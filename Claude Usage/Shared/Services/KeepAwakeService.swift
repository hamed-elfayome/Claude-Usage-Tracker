//
//  KeepAwakeService.swift
//  Claude Usage
//
//  Amphetamine-style sleep prevention. Holds a single named IOKit power
//  assertion while either the manual toggle is on (optionally time-limited)
//  or auto mode detects an active Claude Code session (with a configurable
//  grace period after activity stops). Assertion lifecycle is centralized
//  in reconcile() so create/release stays idempotent, and the kernel drops
//  the assertion automatically if the process exits.
//
//  Idle-sleep assertions do NOT prevent sleep when the lid is closed; the
//  settings UI documents this.
//

import Foundation
import Combine
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    enum SleepMode: String, CaseIterable {
        /// System stays awake, display may sleep (default — long Claude Code
        /// runs keep going with the screen off).
        case allowDisplaySleep
        /// Display and system both stay awake.
        case preventDisplaySleep

        var assertionType: String {
            switch self {
            case .allowDisplaySleep:
                return kIOPMAssertionTypePreventUserIdleSystemSleep as String
            case .preventDisplaySleep:
                return kIOPMAssertionTypePreventUserIdleDisplaySleep as String
            }
        }
    }

    // ASCII-only: pmset renders non-ASCII assertion names as mojibake.
    static let assertionName = "Claude Usage - Keep Awake"

    // MARK: - Published state

    @Published private(set) var isManualOn = false
    /// Wall-clock instant the manual hold auto-disables; nil = indefinite/off.
    @Published private(set) var manualExpiry: Date?
    @Published private(set) var isAssertionHeld = false
    /// True while the auto branch (active session or grace period) holds the assertion.
    @Published private(set) var isAutoHolding = false
    /// When the auto branch is in its grace window, the instant it will let go;
    /// nil while sessions are actively working (or auto isn't holding).
    @Published private(set) var autoGraceExpiry: Date?

    // MARK: - Settings (reloaded via settingsChanged())

    private(set) var autoEnabled = false
    private(set) var sleepMode: SleepMode = .allowDisplaySleep
    /// Manual duration in seconds; 0 = indefinite.
    private(set) var defaultDuration: TimeInterval = 0
    /// Auto mode keeps the assertion this long after sessions go idle; 0 = release immediately.
    private(set) var gracePeriod: TimeInterval = 30 * 60

    // MARK: - Test seams

    /// Injectable clock for tests.
    var now: () -> Date = { Date() }
    var createAssertion: (SleepMode) -> IOPMAssertionID? = { mode in
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            mode.assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            KeepAwakeService.assertionName as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }
    var releaseAssertion: (IOPMAssertionID) -> Void = { id in
        IOPMAssertionRelease(id)
    }
    var loadSettings: () -> (autoEnabled: Bool, sleepMode: SleepMode, defaultDuration: TimeInterval, gracePeriod: TimeInterval) = {
        let store = SharedDataStore.shared
        let mode = store.loadKeepAwakeSleepMode().flatMap(SleepMode.init(rawValue:)) ?? .allowDisplaySleep
        return (
            autoEnabled: store.loadKeepAwakeAutoEnabled(),
            sleepMode: mode,
            defaultDuration: store.loadKeepAwakeDefaultDuration(),
            gracePeriod: store.loadKeepAwakeAutoGracePeriod()
        )
    }

    // MARK: - Private state

    private let sessionStore: NotchSessionStore
    private var assertionID: IOPMAssertionID?
    private var heldMode: SleepMode?
    /// Last instant a Claude Code session was seen actively working.
    private var lastActiveDate: Date?
    /// Set by smartToggle() while an auto hold is dismissed; cleared when
    /// activity next resumes so auto mode picks the following task back up.
    private var autoSuppressed = false
    private var wereSessionsActive = false
    private var deadlineTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    init(sessionStore: NotchSessionStore = .shared) {
        self.sessionStore = sessionStore
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        reloadSettings()
        sessionStore.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.reconcile(sessions: sessions)
            }
            .store(in: &cancellables)
        reconcile()
    }

    func stop() {
        cancellables.removeAll()
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        isManualOn = false
        manualExpiry = nil
        releaseIfHeld()
        isAssertionHeld = false
        isAutoHolding = false
        started = false
    }

    // MARK: - Manual control

    func toggleManual() {
        setManual(on: !isManualOn)
    }

    /// One-click mental model for the popover button: lit means "your Mac is
    /// being kept awake", and clicking always flips that. On → end whatever is
    /// holding, including dismissing a current auto hold (the setting stays
    /// on). Off → resume the dismissed auto hold if it would still be holding;
    /// only start a manual hold when auto has nothing to hold right now.
    func smartToggle() {
        if isAssertionHeld {
            isManualOn = false
            manualExpiry = nil
            if isAutoHolding {
                autoSuppressed = true
            }
            reconcile()
        } else {
            if autoEnabled, autoSuppressed {
                autoSuppressed = false
                reconcile()
                if isAssertionHeld { return }
            }
            setManual(on: true)
        }
    }

    /// `duration` overrides the persisted default (menu quick-picks); 0 = indefinite.
    func setManual(on: Bool, duration: TimeInterval? = nil) {
        if on {
            isManualOn = true
            let holdDuration = duration ?? defaultDuration
            manualExpiry = holdDuration > 0 ? now().addingTimeInterval(holdDuration) : nil
        } else {
            isManualOn = false
            manualExpiry = nil
        }
        reconcile()
    }

    /// Single entry point for flipping auto mode (settings pane and the
    /// button's context menu): persists, manages the shared hooks, and
    /// notifies AppDelegate to re-gate the hook server.
    func setAutoEnabled(_ enabled: Bool) {
        SharedDataStore.shared.saveKeepAwakeAutoEnabled(enabled)
        if enabled {
            NotchHookInstaller.shared.install()
        } else if !SharedDataStore.shared.loadNotchHUDEnabled() {
            NotchHookInstaller.shared.uninstall()
        }
        NotificationCenter.default.post(name: .keepAwakeSettingChanged, object: nil)
    }

    /// Re-reads persisted settings and reapplies them (sleep-mode changes
    /// release + re-acquire the assertion with the new type).
    func settingsChanged() {
        reloadSettings()
        reconcile()
    }

    // MARK: - Reconcile

    /// Single idempotent sync point between desired state and the held
    /// assertion. `sessions` overrides the store's array when delivered via
    /// the Combine sink (whose values arrive before the store property updates).
    func reconcile(sessions: [ClaudeCodeSession]? = nil) {
        let reference = now()
        let currentSessions = sessions ?? sessionStore.sessions

        // Manual branch, expiring the timed hold if its deadline passed.
        if isManualOn, let expiry = manualExpiry, reference >= expiry {
            isManualOn = false
            manualExpiry = nil
        }
        let manualActive = isManualOn

        // Auto branch: active sessions hold; after they stop, the grace
        // period keeps holding until it elapses or activity resumes.
        let sessionsActive = !currentSessions.isEmpty
            && !currentSessions.allSatisfy { $0.status == .idle }
        if sessionsActive, !wereSessionsActive {
            // A fresh burst of activity lifts any smartToggle dismissal.
            autoSuppressed = false
        }
        wereSessionsActive = sessionsActive
        if sessionsActive {
            lastActiveDate = reference
        }
        let inGrace: Bool = {
            guard !sessionsActive, gracePeriod > 0, let last = lastActiveDate else { return false }
            return reference.timeIntervalSince(last) < gracePeriod
        }()
        let autoActive = autoEnabled && !autoSuppressed && (sessionsActive || inGrace)

        // Apply: at most one assertion, re-acquired when the mode changed.
        let desired = manualActive || autoActive
        if desired {
            if assertionID == nil || heldMode != sleepMode {
                releaseIfHeld()
                if let id = createAssertion(sleepMode) {
                    assertionID = id
                    heldMode = sleepMode
                }
            }
        } else {
            releaseIfHeld()
        }

        isAssertionHeld = assertionID != nil
        isAutoHolding = autoActive && isAssertionHeld
        autoGraceExpiry = (isAutoHolding && !sessionsActive && gracePeriod > 0)
            ? lastActiveDate?.addingTimeInterval(gracePeriod)
            : nil
        scheduleDeadlineCheck(sessionsActive: sessionsActive, reference: reference)
    }

    // MARK: - Private

    private func reloadSettings() {
        let settings = loadSettings()
        autoEnabled = settings.autoEnabled
        sleepMode = settings.sleepMode
        defaultDuration = settings.defaultDuration
        gracePeriod = settings.gracePeriod
    }

    private func releaseIfHeld() {
        if let id = assertionID {
            releaseAssertion(id)
            assertionID = nil
            heldMode = nil
        }
    }

    /// Timers only exist to revisit wall-clock deadlines (manual expiry,
    /// grace-period end); session events re-reconcile via the Combine sink.
    private func scheduleDeadlineCheck(sessionsActive: Bool, reference: Date) {
        deadlineTimer?.invalidate()
        deadlineTimer = nil

        var deadlines: [Date] = []
        if isManualOn, let expiry = manualExpiry {
            deadlines.append(expiry)
        }
        if autoEnabled, !sessionsActive, gracePeriod > 0, let last = lastActiveDate {
            let graceEnd = last.addingTimeInterval(gracePeriod)
            if graceEnd > reference { deadlines.append(graceEnd) }
        }
        guard let fireDate = deadlines.min() else { return }

        // Small pad so the check runs just after the deadline passes.
        let interval = max(0.5, fireDate.timeIntervalSince(reference) + 0.1)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }
}
