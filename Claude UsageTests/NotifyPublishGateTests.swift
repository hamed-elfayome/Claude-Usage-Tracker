import XCTest
@testable import Claude_Usage

/// When a payload is worth a request. Pure and clock free: `now` is a
/// parameter, so every rule is a direct arithmetic assertion.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifyPublishGateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The shipping intervals, spelled out so a test reads as "thirty seconds
    /// is inside the minute" without a lookup elsewhere.
    private let gate = NotifyPublishGate(
        tileInterval: 60,
        gaugeInterval: 900,
        screenTileInterval: 900,
        keepAliveInterval: 5400
    )

    private func payload(
        tile body: String? = nil,
        gauge value: String? = nil,
        screenTile screenBody: String? = nil
    ) -> NotifyPayload {
        NotifyPayload(
            tile: body.flatMap { NotifyTile(title: "Claude Usage", body: $0, progress: 42) },
            gauge: value.flatMap { NotifyGauge(title: "Claude Usage", value: $0, progress: 42) },
            screenTile: screenBody.flatMap { NotifyTile(title: "Claude Usage", body: $0, progress: 42) }
        )
    }

    // MARK: - First publish

    func testWithNoRecordEverySurfaceIsDue() {
        let decision = gate.decide(
            payload: payload(tile: "a", gauge: "42", screenTile: "a"),
            since: nil,
            now: now
        )
        XCTAssertTrue(decision.publishesTile)
        XCTAssertTrue(decision.publishesGauge)
        XCTAssertTrue(decision.publishesScreenTile)
    }

    /// Nil means the user switched that surface off, and the gate must never
    /// write one the payload left out.
    func testASurfaceThePayloadLeftNilIsNeverWritten() {
        let decision = gate.decide(payload: payload(gauge: "42"), since: nil, now: now)
        XCTAssertFalse(decision.publishesTile)
        XCTAssertTrue(decision.publishesGauge)
        XCTAssertFalse(decision.publishesScreenTile)
    }

    func testAnEmptyPayloadPublishesNothing() {
        XCTAssertTrue(gate.decide(payload: .empty, since: nil, now: now).publishesNothing)
    }

    // MARK: - Minimum intervals

    func testAChangedTileIsHeldBackInsideItsMinute() {
        let sent = payload(tile: "a", gauge: "42")
        let record = NotifyPublishRecord(payload: sent, tileAt: now, gaugeAt: now)

        let decision = gate.decide(
            payload: payload(tile: "b", gauge: "42"),
            since: record,
            now: now.addingTimeInterval(30)
        )
        XCTAssertFalse(decision.publishesTile)
    }

    func testAChangedTileGoesOutOnceTheMinuteHasPassed() {
        let sent = payload(tile: "a", gauge: "42")
        let record = NotifyPublishRecord(payload: sent, tileAt: now, gaugeAt: now)

        let decision = gate.decide(
            payload: payload(tile: "b", gauge: "42"),
            since: record,
            now: now.addingTimeInterval(61)
        )
        XCTAssertTrue(decision.publishesTile)
    }

    /// iOS decides when a widget redraws, roughly every quarter hour, so
    /// pushing faster buys nothing.
    func testTheGaugeWaitsItsQuarterHour() {
        let record = NotifyPublishRecord(payload: payload(gauge: "42"), gaugeAt: now)

        XCTAssertFalse(
            gate.decide(payload: payload(gauge: "41"), since: record, now: now.addingTimeInterval(600))
                .publishesGauge
        )
        XCTAssertTrue(
            gate.decide(payload: payload(gauge: "41"), since: record, now: now.addingTimeInterval(901))
                .publishesGauge
        )
    }

    func testAnUnchangedPayloadCostsNoRequest() {
        let sent = payload(tile: "a", gauge: "42", screenTile: "a")
        let record = NotifyPublishRecord(payload: sent, tileAt: now, gaugeAt: now, screenTileAt: now)

        let decision = gate.decide(payload: sent, since: record, now: now.addingTimeInterval(300))
        XCTAssertTrue(decision.publishesNothing)
    }

    // MARK: - Keep alive

    /// The gateway ends a progress-only Live Activity after two hours without
    /// an update, so an unchanged tile still has to be re-sent.
    func testAnUnchangedTileIsRepublishedAfterTheKeepAlive() {
        let sent = payload(tile: "a", gauge: "42", screenTile: "a")
        let record = NotifyPublishRecord(payload: sent, tileAt: now, gaugeAt: now, screenTileAt: now)

        XCTAssertFalse(
            gate.decide(payload: sent, since: record, now: now.addingTimeInterval(5399)).publishesTile
        )
        XCTAssertTrue(
            gate.decide(payload: sent, since: record, now: now.addingTimeInterval(5401)).publishesTile
        )
    }

    /// The Home Screen tile takes the keep alive too: past its `staleAt` the
    /// phone dims the tile rather than presenting old numbers as current.
    func testTheHomeScreenTileTakesTheKeepAliveAsWell() {
        let sent = payload(tile: "a", gauge: "42", screenTile: "a")
        let record = NotifyPublishRecord(payload: sent, tileAt: now, gaugeAt: now, screenTileAt: now)

        XCTAssertTrue(
            gate.decide(payload: sent, since: record, now: now.addingTimeInterval(5401)).publishesScreenTile
        )
    }

    /// The gauge is the one surface with no keep alive: the gateway documents
    /// neither a reaper nor a freshness deadline for it, so a heartbeat there
    /// would prevent nothing.
    func testTheGaugeHasNoKeepAlive() {
        let sent = payload(gauge: "42")
        let record = NotifyPublishRecord(payload: sent, gaugeAt: now)

        XCTAssertFalse(
            gate.decide(payload: sent, since: record, now: now.addingTimeInterval(86_400)).publishesGauge
        )
    }

    // MARK: - The record

    /// The record merges one surface at a time, so a surface the gate held back
    /// still remembers what it is actually showing rather than being filed as
    /// having sent the payload that was built.
    func testTheRecordMergesPerSurface() {
        let first = payload(tile: "a", gauge: "42", screenTile: "a")
        let record = NotifyPublishRecord(payload: first, tileAt: now, gaugeAt: now, screenTileAt: now)

        let second = payload(tile: "b", gauge: "41", screenTile: "b")
        let later = now.addingTimeInterval(61)
        let merged = record.updated(
            with: second,
            decision: NotifyPublishDecision(publishesTile: true, publishesGauge: false, publishesScreenTile: false),
            at: later
        )

        // The tile moved on; the gauge still remembers what the phone shows.
        XCTAssertEqual(merged.payload.tile, second.tile)
        XCTAssertEqual(merged.payload.gauge, first.gauge)
        XCTAssertEqual(merged.tileAt, later)
        XCTAssertEqual(merged.gaugeAt, now)
    }

    /// The gauge held back above must still go out once its own interval
    /// arrives, which is only true because the record kept the old content.
    func testAHeldBackGaugeStillGoesOutLater() {
        let first = payload(tile: "a", gauge: "42")
        var record = NotifyPublishRecord(payload: first, tileAt: now, gaugeAt: now)

        let second = payload(tile: "b", gauge: "41")
        record = record.updated(
            with: second,
            decision: NotifyPublishDecision(publishesTile: true, publishesGauge: false),
            at: now.addingTimeInterval(61)
        )

        let decision = gate.decide(payload: second, since: record, now: now.addingTimeInterval(901))
        XCTAssertTrue(decision.publishesGauge)
    }
}
