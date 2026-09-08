import XCTest
@testable import Claude_Usage

/// The gateway's field limits, enforced at construction so a long label
/// shortens rather than failing the whole publish.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifyLimitsTests: XCTestCase {

    // MARK: - Text

    func testShortensRatherThanFailing() {
        let long = String(repeating: "a", count: 40)
        XCTAssertEqual(NotifyLimits.text(long, maximum: 24)?.count, 24)
    }

    func testReportsAnEmptyResultAsNil() {
        XCTAssertNil(NotifyLimits.text("", maximum: 24))
        XCTAssertNil(NotifyLimits.text("   ", maximum: 24))
        XCTAssertNil(NotifyLimits.text(nil, maximum: 24))
    }

    func testTrimsAndDropsNul() {
        XCTAssertEqual(NotifyLimits.text("  5h  ", maximum: 24), "5h")
        XCTAssertEqual(NotifyLimits.text("5\0h", maximum: 24), "5h")
    }

    func testLeavesTextInsideTheLimitAlone() {
        XCTAssertEqual(NotifyLimits.text("Opus 7d", maximum: 24), "Opus 7d")
    }

    // MARK: - Progress

    /// A quota can legitimately report a negative remainder when the user is
    /// over the limit, and that reads as an empty bar rather than an error.
    func testClampsRatherThanRejecting() {
        XCTAssertEqual(NotifyLimits.progress(-15), 0)
        XCTAssertEqual(NotifyLimits.progress(140), 100)
        XCTAssertEqual(NotifyLimits.progress(42), 42)
    }

    func testDropsNonFiniteProgress() {
        XCTAssertNil(NotifyLimits.progress(.nan))
        XCTAssertNil(NotifyLimits.progress(.infinity))
        XCTAssertNil(NotifyLimits.progress(nil))
    }

    // MARK: - Tint

    func testNormalizesBothHexLengths() {
        XCTAssertEqual(NotifyLimits.tint("34c759"), "#34C759")
        XCTAssertEqual(NotifyLimits.tint("#34c759"), "#34C759")
        XCTAssertEqual(NotifyLimits.tint("ff34c759"), "#FF34C759")
    }

    /// A bad color is dropped rather than failing the publish: a tile with the
    /// wrong accent still tells the user their percentage.
    func testDropsAnythingThatIsNotSixOrEightHexDigits() {
        XCTAssertNil(NotifyLimits.tint("34c75"))
        XCTAssertNil(NotifyLimits.tint("nothex"))
        XCTAssertNil(NotifyLimits.tint("#zzzzzz"))
        XCTAssertNil(NotifyLimits.tint(nil))
    }

    // MARK: - Values built on the limits

    func testAMetricNeedsALabelAndAValue() {
        XCTAssertNil(NotifyMetric(label: "", value: "42"))
        XCTAssertNil(NotifyMetric(label: "5h", value: "  "))
        XCTAssertNotNil(NotifyMetric(label: "5h", value: "42"))
    }

    func testATileKeepsAtMostSixMetrics() {
        let metrics = (0..<9).compactMap { NotifyMetric(label: "w\($0)", value: "\($0)") }
        let tile = NotifyTile(title: "Claude Usage", metrics: metrics)
        XCTAssertEqual(tile?.metrics.count, 6)
    }

    func testATileNeedsATitle() {
        XCTAssertNil(NotifyTile(title: "   "))
        XCTAssertNotNil(NotifyTile(title: "Claude Usage"))
    }

    func testAGaugeNeedsATitle() {
        XCTAssertNil(NotifyGauge(title: ""))
        XCTAssertNotNil(NotifyGauge(title: "Claude Usage"))
    }
}
