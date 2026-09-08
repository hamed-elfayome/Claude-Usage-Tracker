//
//  NotifyPublishGate.swift
//  Claude Usage
//
//  Decides when a payload is worth a request.
//

import Foundation

/// What the last publish sent, and when each surface was last written.
struct NotifyPublishRecord: Sendable, Equatable {
    let payload: NotifyPayload
    let tileAt: Date?
    let gaugeAt: Date?
    let screenTileAt: Date?

    init(
        payload: NotifyPayload,
        tileAt: Date? = nil,
        gaugeAt: Date? = nil,
        screenTileAt: Date? = nil
    ) {
        self.payload = payload
        self.tileAt = tileAt
        self.gaugeAt = gaugeAt
        self.screenTileAt = screenTileAt
    }

    /// The record after a publish, carrying forward both the timestamp and the
    /// content of whichever surface was not written this time.
    ///
    /// Merging per surface rather than storing the payload wholesale is what
    /// keeps a held back change from being lost. A tile-only publish that
    /// recorded the whole payload would file the new gauge as already sent, and
    /// the gate would then see no change when the gauge's own interval finally
    /// came round, leaving a stale value on the phone until something else
    /// happened to move it. The record has to remember what each surface is
    /// actually showing, which is not the same as the last payload built.
    func updated(with payload: NotifyPayload, decision: NotifyPublishDecision, at now: Date) -> NotifyPublishRecord {
        NotifyPublishRecord(
            payload: NotifyPayload(
                tile: decision.publishesTile ? payload.tile : self.payload.tile,
                gauge: decision.publishesGauge ? payload.gauge : self.payload.gauge,
                screenTile: decision.publishesScreenTile ? payload.screenTile : self.payload.screenTile
            ),
            tileAt: decision.publishesTile ? now : tileAt,
            gaugeAt: decision.publishesGauge ? now : gaugeAt,
            screenTileAt: decision.publishesScreenTile ? now : screenTileAt
        )
    }
}

/// Which surfaces a publish should actually write.
struct NotifyPublishDecision: Sendable, Equatable {
    let publishesTile: Bool
    let publishesGauge: Bool
    let publishesScreenTile: Bool

    init(
        publishesTile: Bool,
        publishesGauge: Bool,
        publishesScreenTile: Bool = false
    ) {
        self.publishesTile = publishesTile
        self.publishesGauge = publishesGauge
        self.publishesScreenTile = publishesScreenTile
    }

    var publishesNothing: Bool {
        !publishesTile && !publishesGauge && !publishesScreenTile
    }

    static let nothing = NotifyPublishDecision(
        publishesTile: false,
        publishesGauge: false,
        publishesScreenTile: false
    )
}

/// Decides when a payload is worth a request.
///
/// Quota numbers move on every refresh, and the reset countdown in the detail
/// line moves every minute, so "publish whenever the payload differs" would
/// mean a request per refresh forever. The gate adds two rules on top of that
/// difference:
///
/// - a minimum gap per surface, because iOS redraws a widget roughly every
///   fifteen minutes no matter how often the value is pushed, so pushing faster
///   buys nothing;
/// - a keep alive for the tile, because the gateway ends a progress-only Live
///   Activity that has gone two hours without an update, on the grounds that a
///   frozen percentage is worse than no tile at all. Republishing every ninety
///   minutes keeps it alive with room to spare.
///
/// Pure and clock free: `now` is a parameter, so every rule is directly testable.
struct NotifyPublishGate: Sendable {
    /// The tile is a push, so it can afford to be prompt.
    static let defaultTileInterval: TimeInterval = 60

    /// The widget is a poll. iOS decides when it redraws, roughly every quarter
    /// hour, so there is nothing to gain from writing it more often.
    static let defaultGaugeInterval: TimeInterval = 15 * 60

    /// The Home Screen tile is a poll like the gauge, on the same quarter hour.
    static let defaultScreenTileInterval: TimeInterval = 15 * 60

    /// Comfortably inside both deadlines it has to beat: the gateway ends a
    /// progress-only Live Activity after two hours without an update, and a
    /// screen widget's `staleAt` falls two hours after its last write, past
    /// which the phone dims the tile and says how long ago it was current.
    static let defaultKeepAliveInterval: TimeInterval = 90 * 60

    private let tileInterval: TimeInterval
    private let gaugeInterval: TimeInterval
    private let screenTileInterval: TimeInterval
    private let keepAliveInterval: TimeInterval

    init(
        tileInterval: TimeInterval = NotifyPublishGate.defaultTileInterval,
        gaugeInterval: TimeInterval = NotifyPublishGate.defaultGaugeInterval,
        screenTileInterval: TimeInterval = NotifyPublishGate.defaultScreenTileInterval,
        keepAliveInterval: TimeInterval = NotifyPublishGate.defaultKeepAliveInterval
    ) {
        self.tileInterval = tileInterval
        self.gaugeInterval = gaugeInterval
        self.screenTileInterval = screenTileInterval
        self.keepAliveInterval = keepAliveInterval
    }

    func decide(
        payload: NotifyPayload,
        since record: NotifyPublishRecord?,
        now: Date
    ) -> NotifyPublishDecision {
        NotifyPublishDecision(
            publishesTile: publishesTile(payload: payload, record: record, now: now),
            publishesGauge: publishesGauge(payload: payload, record: record, now: now),
            publishesScreenTile: publishesScreenTile(payload: payload, record: record, now: now)
        )
    }

    private func publishesTile(payload: NotifyPayload, record: NotifyPublishRecord?, now: Date) -> Bool {
        guard let tile = payload.tile else { return false }
        guard let record, let lastAt = record.tileAt else { return true }

        let elapsed = now.timeIntervalSince(lastAt)
        if elapsed >= keepAliveInterval { return true }
        return tile != record.payload.tile && elapsed >= tileInterval
    }

    /// The Home Screen tile takes the keep alive as well as its interval,
    /// because its freshness deadline is a real one: two hours after the last
    /// write the phone stops presenting the content as current and dims it.
    private func publishesScreenTile(payload: NotifyPayload, record: NotifyPublishRecord?, now: Date) -> Bool {
        guard let screenTile = payload.screenTile else { return false }
        guard let record, let lastAt = record.screenTileAt else { return true }

        let elapsed = now.timeIntervalSince(lastAt)
        if elapsed >= keepAliveInterval { return true }
        return screenTile != record.payload.screenTile && elapsed >= screenTileInterval
    }

    private func publishesGauge(payload: NotifyPayload, record: NotifyPublishRecord?, now: Date) -> Bool {
        guard let gauge = payload.gauge else { return false }
        guard let record, let lastAt = record.gaugeAt else { return true }

        let elapsed = now.timeIntervalSince(lastAt)
        return gauge != record.payload.gauge && elapsed >= gaugeInterval
    }
}
