//
//  NotifyPublishDriver.swift
//  Claude Usage
//
//  Keeps a linked Notify! device in sync with the active profile's usage.
//

import Combine
import Foundation

/// Keeps a linked Notify! device in sync with the active profile's usage.
///
/// Mirrors `NotchHUDController`: a singleton the app delegate brings up and
/// down with a setting, holding a Combine subscription on the state it renders
/// and a timer for the changes that happen on a clock rather than on state.
/// SwiftUI is not involved, because the surface being driven is on the user's
/// phone and has no view here to invalidate.
///
/// Deliberately free of judgement. Everything about what to show and when to
/// send it lives in `NotifyPayloadBuilder` and `NotifyPublishGate`, which are
/// pure and tested; anything decided here would be decided untested. This
/// driver only gathers state, asks those two, and performs the writes the
/// answer implies.
@MainActor
final class NotifyPublishDriver {
    static let shared = NotifyPublishDriver()

    private let settings: NotifySettingsStore
    private let publisher: NotifyPublishing
    private let builder: NotifyPayloadBuilder
    private let gate: NotifyPublishGate

    private var cancellables: Set<AnyCancellable> = []
    private var settingsObserver: NSObjectProtocol?

    /// Offers the current payload to the gate on a clock. See `startTick` for
    /// why state changes alone are not enough.
    private var tickTimer: Timer?

    /// Whether `start()` has run. Kept separately from the timer so a stop
    /// followed by a start cannot leave half of the subscriptions live.
    private var isRunning = false

    /// The publish in flight. Exactly one at a time: two overlapping writes to
    /// the same tile can land out of order, which leaves an older reading
    /// standing on the Lock Screen with nothing to correct it.
    ///
    /// A publish already running is never cancelled to make room for a newer
    /// one. Cancelling a start mid-flight is the one way this driver could
    /// leave two tiles on a phone: the gateway may already have created the
    /// tile, and losing the activity id it was about to return means the next
    /// start opens a second one beside it. A skipped payload costs nothing,
    /// because the tick re-offers it within the minute.
    private var publishTask: Task<String?, Never>?

    /// What the phone is believed to be showing, and when each surface last
    /// received a write. The gate needs both to decide anything.
    private var record: NotifyPublishRecord?

    /// While set, tile writes are skipped: the gateway is in push to start
    /// backoff and every attempt inside the wait lengthens it.
    private var tileSuppressedUntil: Date?

    /// While set, Home Screen tile writes are skipped: the gateway has that
    /// surface switched off server side. Separate from the tile's wait because
    /// the two mean opposite things. Backoff is the gateway asking us to stop
    /// doing something; the kill switch is a feature Notify! has not started
    /// serving yet, and nothing on this Mac shortens it.
    private var screenTileSuppressedUntil: Date?

    /// How often the payload is re-offered to the gate. A minute is the tile's
    /// own minimum interval, so this is the finest cadence that can ever change
    /// an answer.
    private static let tickInterval: TimeInterval = 60

    /// How long the Home Screen tile goes quiet after the gateway says it is
    /// not serving that surface. Deliberately hours: the switch is thrown by
    /// Notify! on Notify!'s own schedule, so asking again on the next tick is a
    /// poll against a decision that will not have moved, once a minute forever.
    private static let switchedOffSuppression: TimeInterval = 6 * 60 * 60

    /// Everything this driver leans on, supplied explicitly.
    ///
    /// None of these are parameter defaults, which is deliberate. A default
    /// argument expression is evaluated in a nonisolated context, and this
    /// target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every
    /// one of these values is main-actor isolated and naming it as a default
    /// warns at the declaration. The convenience initializer below supplies
    /// them from a main-actor body instead, where reaching them is ordinary.
    init(
        settings: NotifySettingsStore,
        publisher: NotifyPublishing,
        builder: NotifyPayloadBuilder,
        gate: NotifyPublishGate
    ) {
        self.settings = settings
        self.publisher = publisher
        self.builder = builder
        self.gate = gate
    }

    /// The driver as the app runs it. `publisher` is the one seam a test needs,
    /// and nil rather than a real default because nil is a literal and costs no
    /// isolation to write down.
    convenience init(publisher: NotifyPublishing? = nil) {
        self.init(
            settings: .shared,
            publisher: publisher ?? NotifyGatewayClient(),
            builder: NotifyPayloadBuilder(),
            gate: NotifyPublishGate()
        )
    }

    // MARK: - Lifecycle

    /// Starts publishing. Idempotent, so the app delegate can call it from the
    /// settings observer without checking whether it is already up.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        LoggingService.shared.logInfo("Notify!: publishing on")

        // Usage lands on the active profile, and `activeProfile` is republished
        // every time a refresh saves one, so this fires on exactly the events
        // that can change what the phone should show. Switching profile fires
        // it too, which is right: the phone follows the profile the Mac is on.
        ProfileManager.shared.$activeProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.schedule(payload: self.currentPayload())
            }
            .store(in: &cancellables)

        // Credentials, the surface switches and the surface handles all live
        // outside the profile, so a save in the pane changes nothing the
        // subscription above can see. The pane posts instead.
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(
                forName: .notifySettingsChanged, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in
                    _ = await NotifyPublishDriver.shared.publishNow()
                }
            }
        }

        startTick()
        schedule(payload: currentPayload())
    }

    /// Stops publishing and releases everything held.
    ///
    /// Nothing is torn down on the device. Ending the tile and deleting the
    /// widgets would need a network call at the exact moment the user said
    /// stop, and would fail silently when they are offline; leaving the last
    /// reading standing is the honest outcome of "stop sending", and the pane
    /// offers an explicit way to remove it.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        LoggingService.shared.logInfo("Notify!: publishing off, leaving the last published state on the device")

        cancellables.removeAll()
        stopTick()
        publishTask?.cancel()
        publishTask = nil

        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }

    // MARK: - Forced publish

    /// Publishes the current payload whether the gate would have allowed it or
    /// not, for the moment the user saves new credentials or presses publish in
    /// the pane. Waiting a quarter of an hour to find out whether a token works
    /// is not an answer.
    ///
    /// This is the only forced path, and the settings pane goes through it
    /// rather than opening a second one of its own. Two publishers writing the
    /// same handles is exactly how a phone ends up with two Live Activities:
    /// both read a nil activity id, both start a tile, and only one of the two
    /// ids can be stored.
    ///
    /// - Returns: nil when everything the payload asked for was written, or a
    ///   message fit to show the user when it was not.
    @discardableResult
    func publishNow() async -> String? {
        guard settings.isEnabled() else {
            return "notify.status.switched_off".localized
        }

        // Said before the payload is built, because an empty payload cannot
        // tell these two apart afterwards: every surface switched off and no
        // usage reported yet produce exactly the same nothing, and blaming the
        // providers for a switch the user turned off themselves is the more
        // annoying of the two wrong answers.
        guard settings.isLiveActivityEnabled()
            || settings.isWidgetEnabled()
            || settings.isScreenWidgetEnabled() else {
            return "notify.status.all_surfaces_off".localized
        }

        // Let any publish already running finish first, rather than cancelling
        // it. A cancelled start may already have created a tile whose id is then
        // lost, and the next start would put a second one beside it.
        while let inFlight = publishTask {
            _ = await inFlight.value
        }

        // Clearing the record is what forces the write: the gate holds a
        // surface back on elapsed time since its last write, and with nothing
        // recorded every surface the payload carries is due. The gateway's own
        // backoff is left in place, since ignoring that earns a longer one.
        record = nil

        // The background tick stays quiet about a device that shows no surface,
        // because saying so once a minute forever is noise. A forced publish is
        // the opposite case: somebody asked for this one, now, and is owed the
        // reason it cannot happen rather than a cheerful nil.
        if let link = settings.deviceLink(), !link.kind.supportsAnySurface {
            return link.kind.widgetUnsupportedReason ?? link.kind.liveActivityUnsupportedReason
        }

        let now = Date()
        let payload = currentPayload(now: now)
        guard !payload.isEmpty else {
            return "notify.status.no_usage_yet".localized
        }

        let decision = withoutSuppressedSurfaces(gate.decide(payload: payload, since: nil, now: now), at: now)
        guard !decision.publishesNothing else {
            // Every surface the payload carried is inside a wait the gateway
            // asked for, and the two waits are different news. A backoff is the
            // app being told to slow down, which the user can sometimes clear
            // from their phone; the kill switch is a surface Notify! has not
            // started serving, where waiting is the only move either of us has.
            // The backoff is named first because it is the one with a remedy.
            if tileSuppressedUntil != nil {
                return "notify.status.holding_off".localized
            }
            return "notify.status.home_screen_not_served".localized
        }

        return await startPublish(payload: payload, decision: decision, at: now).value
    }

    // MARK: - Building

    /// Reads the active profile's usage and asks the builder for a payload.
    ///
    /// The active profile only, which is the whole multi-profile story: the
    /// phone shows what the menu bar shows. Merging every profile into one tile
    /// would need the six metric slots to cover several accounts, and a phone
    /// that disagreed with the Mac is worse than one that shows less.
    private func currentPayload(now: Date = Date()) -> NotifyPayload {
        guard let profile = ProfileManager.shared.activeProfile,
              let usage = profile.claudeUsage else {
            return .empty
        }

        let readings = NotifyUsageReadings.readings(
            from: usage,
            provider: profile.provider,
            now: now
        )

        return builder.payload(
            readings: readings,
            gaugeSelection: settings.gaugeSelection(),
            includesTile: settings.isLiveActivityEnabled(),
            includesGauge: settings.isWidgetEnabled(),
            includesScreenTile: settings.isScreenWidgetEnabled(),
            now: now
        )
    }

    /// Asks the gate whether this payload is worth a request, and if so starts
    /// one, unless a publish is already running.
    ///
    /// Synchronous on purpose: it is called from a Combine sink and from a
    /// timer, neither of which can await, and the decision itself is pure.
    private func schedule(payload: NotifyPayload) {
        guard isRunning, !payload.isEmpty else { return }

        let now = Date()
        let decision = withoutSuppressedSurfaces(gate.decide(payload: payload, since: record, now: now), at: now)
        guard !decision.publishesNothing else { return }
        guard publishTask == nil else { return }

        _ = startPublish(payload: payload, decision: decision, at: now)
    }

    /// Runs one publish as the single in-flight task, and hands the task back so
    /// a caller that wants the outcome can await it.
    private func startPublish(
        payload: NotifyPayload,
        decision: NotifyPublishDecision,
        at now: Date
    ) -> Task<String?, Never> {
        let task = Task { @MainActor [weak self] in
            let message = await self?.publish(payload: payload, decision: decision, at: now)
            self?.publishTask = nil
            return message ?? nil
        }
        publishTask = task
        return task
    }

    // MARK: - Tick

    /// Re-offers the payload to the gate on a clock.
    ///
    /// Both of the gate's time based rules are unreachable without this. A
    /// change it suppressed for arriving inside a surface's minimum interval
    /// has to be offered again once that interval has passed, and the tile has
    /// to be re-sent every ninety minutes or the gateway's two hour abandonment
    /// reaper ends it, on the grounds that a frozen percentage is worse than no
    /// tile. Nothing in published state fires on the mere passage of time.
    private func startTick() {
        guard tickTimer == nil else { return }

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.schedule(payload: self.currentPayload())
            }
        }
        // `.common` rather than the default mode: while a menu tracking loop is
        // up the default mode stops firing, and the popover being open is
        // exactly when the user is watching their usage move.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Narrowing

    /// Drops the surfaces sitting inside a wait the gateway asked for, and
    /// forgets each wait once it has passed.
    ///
    /// The two waits are held apart on purpose. The tile's is push to start
    /// backoff, where every attempt inside it lengthens the wait; the Home
    /// Screen tile's is a server side kill switch, where nothing is wrong and
    /// there is simply nothing serving that route yet. Neither is evidence
    /// about the other, so neither may silence the other, and the gauge is a
    /// poll the gateway rations not at all.
    private func withoutSuppressedSurfaces(
        _ decision: NotifyPublishDecision,
        at now: Date
    ) -> NotifyPublishDecision {
        if let tileSuppressedUntil, now >= tileSuppressedUntil {
            self.tileSuppressedUntil = nil
        }
        if let screenTileSuppressedUntil, now >= screenTileSuppressedUntil {
            self.screenTileSuppressedUntil = nil
        }

        return NotifyPublishDecision(
            publishesTile: decision.publishesTile && tileSuppressedUntil == nil,
            publishesGauge: decision.publishesGauge,
            publishesScreenTile: decision.publishesScreenTile && screenTileSuppressedUntil == nil
        )
    }

    /// Drops whichever surfaces the linked device could never show.
    ///
    /// A Notify! id says what it is, and the three surfaces answer to it
    /// separately. A `GRP`, `MC` or `WB` id cannot show a Live Activity, so a
    /// tile aimed at one is a 400 waiting to happen. Only a group can keep
    /// neither widget, being a fan-out target rather than a device with a
    /// widget list of its own. None of those requests is worth making.
    ///
    /// This is the one narrowing the gate cannot do for itself. The gate is
    /// pure and the payload knows nothing about where it is going; the link is
    /// the only thing that carries the destination, and the driver is the only
    /// place holding one.
    private func withoutUnsupportedSurfaces(
        _ decision: NotifyPublishDecision,
        for link: NotifyDeviceLink
    ) -> NotifyPublishDecision {
        NotifyPublishDecision(
            publishesTile: decision.publishesTile && link.supportsLiveActivity,
            publishesGauge: decision.publishesGauge && link.supportsWidget,
            publishesScreenTile: decision.publishesScreenTile && link.supportsScreenWidget
        )
    }

    // MARK: - Publishing

    /// Which surface a write was for. Each is addressed by its own handle and
    /// fails for its own reasons, so every reaction to a failure has to know
    /// which one it is reacting to.
    private enum Surface {
        case tile
        case gauge
        case screenTile

        var label: String {
            switch self {
            case .tile: return "tile"
            case .gauge: return "Lock Screen widget"
            case .screenTile: return "Home Screen widget"
            }
        }
    }

    /// - Returns: nil when every surface the decision named was written, or the
    ///   first failure as a message fit to show the user.
    private func publish(
        payload: NotifyPayload,
        decision: NotifyPublishDecision,
        at now: Date
    ) async -> String? {
        guard let link = settings.deviceLink() else {
            // No device linked is the state the feature ships in, not a failure,
            // so it stays out of the file log.
            LoggingService.shared.logDebug("Notify!: publish skipped, no device linked")
            return NotifyPublishError.notLinked.errorDescription
        }

        // Now that there is a link, the decision can be narrowed to what this
        // particular device can actually show.
        let supported = withoutUnsupportedSurfaces(decision, for: link)
        guard !supported.publishesNothing else {
            // Debug only, and no message, for the same reason as the unlinked
            // case above. A Mac, a browser or a group takes notifications and
            // nothing else, which is a fact about the user's setup rather than
            // anything going wrong, and the tick would otherwise write the same
            // sentence into the log file every minute and hand the pane a
            // failure to show. The place to explain a device's limits is where
            // the user pastes the link, not once a minute forever.
            LoggingService.shared.logDebug(
                "Notify!: publish skipped, the linked \(link.kind.displayName) shows none of these surfaces"
            )
            return nil
        }

        // Each surface is written independently. A tile the device refuses to
        // start must not cost the user their widgets, which poll happily on a
        // device that cannot do Live Activities at all.
        var sentTile = false
        var sentGauge = false
        var sentScreenTile = false
        var failures: [String] = []

        if supported.publishesTile, let tile = payload.tile {
            if let failure = await sendTile(tile, link: link) {
                failures.append(failure)
            } else {
                sentTile = true
            }
        }
        if supported.publishesGauge, let gauge = payload.gauge {
            if let failure = await sendGauge(gauge, link: link) {
                failures.append(failure)
            } else {
                sentGauge = true
            }
        }
        // Last, and with the same content the Live Activity just carried. The
        // Home Screen route takes the tile body unchanged, which is why the
        // builder hands out one value for both rather than two that agree.
        if supported.publishesScreenTile, let screenTile = payload.screenTile {
            if let failure = await sendScreenTile(screenTile, link: link) {
                failures.append(failure)
            } else {
                sentScreenTile = true
            }
        }

        remember(
            payload: payload,
            sentTile: sentTile,
            sentGauge: sentGauge,
            sentScreenTile: sentScreenTile,
            at: now
        )
        return failures.first
    }

    /// - Returns: nil when the tile was written, or the failure as a message.
    private func sendTile(_ tile: NotifyTile, link: NotifyDeviceLink) async -> String? {
        do {
            let activityId = try await publisher.publishTile(
                tile,
                link: link,
                activityId: settings.activityId()
            )
            store(activityId: activityId, for: link)
            return nil
        } catch NotifyPublishError.tileGone {
            // The handle names a tile the user dismissed, which can never be
            // updated again. Forget it and start one fresh, exactly once: a
            // retry loop here is a retry loop against the gateway.
            LoggingService.shared.logInfo("Notify!: the tile was dismissed on the device, starting a new one")
            settings.setActivityId(nil)
            return await restartTile(tile, link: link)
        } catch {
            report(error, surface: .tile)
            return message(for: error)
        }
    }

    private func restartTile(_ tile: NotifyTile, link: NotifyDeviceLink) async -> String? {
        do {
            let activityId = try await publisher.publishTile(tile, link: link, activityId: nil)
            store(activityId: activityId, for: link)
            return nil
        } catch {
            report(error, surface: .tile)
            return message(for: error)
        }
    }

    /// - Returns: nil when the Lock Screen widget was written, or the failure.
    private func sendGauge(_ gauge: NotifyGauge, link: NotifyDeviceLink) async -> String? {
        do {
            let widgetId = try await publisher.publishGauge(
                gauge,
                link: link,
                widgetId: settings.widgetId()
            )
            store(widgetId: widgetId, for: link)
            return nil
        } catch {
            report(error, surface: .gauge)
            return message(for: error)
        }
    }

    /// - Returns: nil when the Home Screen widget was written, or the failure.
    private func sendScreenTile(_ tile: NotifyTile, link: NotifyDeviceLink) async -> String? {
        do {
            let screenWidgetId = try await publisher.publishScreenTile(
                tile,
                link: link,
                screenWidgetId: settings.screenWidgetId()
            )
            store(screenWidgetId: screenWidgetId, for: link)
            return nil
        } catch {
            report(error, surface: .screenTile)
            return message(for: error)
        }
    }

    // MARK: - Handles

    /// Stores a handle only while it still belongs to the saved link.
    ///
    /// A publish holds the link it started with, and a request can be in flight
    /// for as long as the timeout allows. The user can remove or replace the
    /// link in that window, and the reply, when it lands, carries a handle for a
    /// device that is no longer the one on file. Writing it would leave the next
    /// link inheriting a stranger's tile id, which costs a wasted request and a
    /// 403 before it heals. Comparing first is cheaper than healing.
    private func store(activityId: String, for link: NotifyDeviceLink) {
        guard settings.deviceLink() == link else {
            LoggingService.shared.logInfo("Notify!: the link changed while publishing, discarding the tile handle it returned")
            return
        }
        settings.setActivityId(activityId)
    }

    private func store(widgetId: String, for link: NotifyDeviceLink) {
        guard settings.deviceLink() == link else {
            LoggingService.shared.logInfo("Notify!: the link changed while publishing, discarding the widget handle it returned")
            return
        }
        settings.setWidgetId(widgetId)
    }

    private func store(screenWidgetId: String, for link: NotifyDeviceLink) {
        guard settings.deviceLink() == link else {
            LoggingService.shared.logInfo(
                "Notify!: the link changed while publishing, discarding the Home Screen widget handle it returned"
            )
            return
        }
        settings.setScreenWidgetId(screenWidgetId)
    }

    /// Drops the stored handle for one surface, so the next publish creates its
    /// own replacement rather than writing to something that is gone.
    private func forget(_ surface: Surface) {
        switch surface {
        case .tile: settings.setActivityId(nil)
        case .gauge: settings.setWidgetId(nil)
        case .screenTile: settings.setScreenWidgetId(nil)
        }
    }

    // MARK: - Bookkeeping

    /// Every `NotifyPublishError` already carries a sentence written for a
    /// person, which is the whole reason it is its own error type.
    private func message(for error: Error) -> String {
        (error as? NotifyPublishError)?.errorDescription ?? error.localizedDescription
    }

    /// Records what the phone now shows, per surface.
    ///
    /// What was actually sent, not what was decided: a surface that failed must
    /// not be filed as delivered. `NotifyPublishRecord.updated` does the per
    /// surface merge itself, so a surface that was held back or that failed
    /// keeps the content it is really showing.
    private func remember(
        payload: NotifyPayload,
        sentTile: Bool,
        sentGauge: Bool,
        sentScreenTile: Bool,
        at now: Date
    ) {
        guard sentTile || sentGauge || sentScreenTile else { return }

        let sent = NotifyPublishDecision(
            publishesTile: sentTile,
            publishesGauge: sentGauge,
            publishesScreenTile: sentScreenTile
        )
        record = (record ?? NotifyPublishRecord(payload: .empty))
            .updated(with: payload, decision: sent, at: now)
    }

    /// Turns a failed write into whatever state change it implies, and one log
    /// line. Never a device id and never a token: both are secrets, and the
    /// gateway answers a bad token and an unknown device identically anyway, so
    /// naming the id would not help anyone read the log.
    ///
    /// Every reaction is scoped to the surface that actually failed. The gateway
    /// answers a missing token, a wrong token, an unknown id and somebody else's
    /// id with one identical 403, so a 403 is not evidence the credentials are
    /// bad. The likeliest cause by far is the ordinary one: the user deleted
    /// that one tile or that one widget in the Notify! app, and the handle now
    /// names something that is gone.
    private func report(_ error: Error, surface: Surface) {
        guard let error = error as? NotifyPublishError else {
            // An error from outside this feature's own vocabulary, so its text
            // is not known to be free of a URL, and every URL here carries the
            // device token. The type is enough to find the cause and cannot
            // quote anything.
            LoggingService.shared.logError("Notify!: \(surface.label) publish failed: \(type(of: error))")
            return
        }

        switch error {
        case .rejectedCredentials:
            // Forget only the handle that was refused, and let the next publish
            // create a replacement for it. Clearing the other surfaces' handles
            // as well would abandon a tile or widget that is alive and being
            // written to perfectly happily, and the next write, having no handle
            // for it, would create a second one beside it.
            forget(surface)
            LoggingService.shared.logError(
                "Notify!: refused the stored \(surface.label), forgetting its handle so the next publish creates a new one"
            )

        case .backoff(let retryAfter, let openingTheAppMayHelp):
            // Push to start backoff is a Live Activity rule. Both widgets are
            // polls the gateway does not ration, so a tile's wait must never
            // silence either of them.
            guard surface == .tile else {
                LoggingService.shared.logWarning(
                    "Notify!: the \(surface.label) publish was rate limited, retrying on a later tick"
                )
                return
            }
            tileSuppressedUntil = Date().addingTimeInterval(retryAfter)
            let hint = openingTheAppMayHelp ? ", opening the Notify! app on the device may clear it sooner" : ""
            LoggingService.shared.logWarning(
                "Notify!: holding off Live Activity starts for \(Int(retryAfter.rounded()))s\(hint)"
            )

        case .surfaceSwitchedOff:
            // Not a failure, which is why it is the only branch here that logs
            // at info. Home Screen widgets ship behind a server side kill
            // switch, so a build that can write them meets a gateway that is not
            // serving them yet, and the remedy is entirely Notify!'s. Backing
            // off for hours rather than retrying every tick, because nothing
            // this app does moves that switch and asking once a minute forever
            // would fill the log with a fact that has not changed.
            guard surface == .screenTile else {
                // The 503 belongs to the Home Screen route. Reaching here means
                // the gateway switched off a surface this code did not expect to
                // be switchable, so that write is skipped and offered again on a
                // later tick, and the Home Screen tile's own pause is left alone.
                LoggingService.shared.logInfo(
                    "Notify!: the \(surface.label) is switched off at the moment, retrying on a later tick"
                )
                return
            }
            screenTileSuppressedUntil = Date().addingTimeInterval(Self.switchedOffSuppression)
            LoggingService.shared.logInfo(
                "Notify!: Home Screen widgets are not being served yet, pausing that surface for six hours"
            )

        case .deliveryUnconfirmed(let activityId):
            // Apple never answered, so a tile may already exist. Keeping the id
            // the gateway did hand back means the next update addresses that
            // tile instead of starting a second one beside it.
            if let activityId, !activityId.isEmpty {
                settings.setActivityId(activityId)
            }
            LoggingService.shared.logWarning(
                "Notify!: could not confirm the tile started, updating it on the next tick"
            )

        case .transportFailed:
            // The one error whose text is not ours. It carries a URLError's
            // localized description, which is free to quote the URL it failed
            // on, and every URL in this feature has the device token in its
            // query string. The client already refuses to write that down;
            // logging it here through the error's description would put it in
            // the same file by the back door. The pane still shows it, which is
            // not written down.
            LoggingService.shared.logError("Notify!: the \(surface.label) publish could not reach the gateway")

        default:
            LoggingService.shared.logError("Notify!: the \(surface.label) publish failed: \(error.localizedDescription)")
        }
    }
}
