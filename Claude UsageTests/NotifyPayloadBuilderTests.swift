import XCTest
@testable import Claude_Usage

/// The whole decision layer of the Notify! feature: what to show, in what
/// order, in what words, and in what color.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifyPayloadBuilderTests: XCTestCase {

    /// Fixed on purpose, so every countdown below is an explicit arithmetic
    /// answer rather than whatever the machine's clock happened to say.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let builder = NotifyPayloadBuilder(title: "Claude Usage")

    private func reading(
        provider: String = "anthropic",
        name: String = "Anthropic",
        key: String,
        label: String,
        remaining: Double? = nil,
        dollars: Double? = nil,
        resetsIn: TimeInterval? = nil
    ) -> NotifyQuotaReading {
        NotifyQuotaReading(
            providerId: provider,
            providerName: name,
            quota: NotifyQuota(
                key: key,
                label: label,
                percentRemaining: remaining,
                dollarRemaining: dollars,
                currencyCode: dollars == nil ? nil : "USD",
                resetsAt: resetsIn.map { now.addingTimeInterval($0) }
            )
        )
    }

    // MARK: - Ordering

    /// The worst quota leads, and the tile takes its tint and countdown from
    /// that one.
    func testTheWorstQuotaLeads() {
        let payload = builder.payload(
            readings: [
                reading(key: "weekly", label: "7d", remaining: 80),
                reading(key: "session", label: "5h", remaining: 5, resetsIn: 3600),
            ],
            now: now
        )

        XCTAssertEqual(payload.tile?.metrics.first?.label, "5h")
        XCTAssertEqual(payload.tile?.tintHex, NotifyQuotaStatus.critical.notifyTintHex)
        XCTAssertEqual(payload.tile?.trailing, "1:00")
    }

    /// Two payloads built from the same readings must compare equal, or the
    /// driver would republish forever.
    func testOrderingIsDeterministicDownToTheLastTieBreak() {
        let readings = [
            reading(provider: "b", name: "Same", key: "weekly", label: "7d", remaining: 50),
            reading(provider: "a", name: "Same", key: "weekly", label: "7d", remaining: 50),
        ]

        let first = NotifyPayloadBuilder.ordered(readings)
        let second = NotifyPayloadBuilder.ordered(readings.reversed())

        XCTAssertEqual(first.map { $0.providerId }, ["a", "b"])
        XCTAssertEqual(second.map { $0.providerId }, ["a", "b"])
    }

    /// A seventh reading is dropped rather than failing the whole tile.
    func testAtMostSixMetricsReachTheTile() {
        let readings = (0..<9).map {
            reading(key: "w\($0)", label: "w\($0)", remaining: Double($0 * 10))
        }
        let payload = builder.payload(readings: readings, now: now)
        XCTAssertEqual(payload.tile?.metrics.count, 6)
    }

    // MARK: - Labels

    func testLabelsOmitTheProviderNameWhenEveryReadingSharesOne() {
        let payload = builder.payload(
            readings: [
                reading(key: "session", label: "5h", remaining: 20),
                reading(key: "weekly", label: "7d", remaining: 60),
            ],
            now: now
        )
        XCTAssertEqual(payload.tile?.metrics.map { $0.label }, ["5h", "7d"])
    }

    func testLabelsRegainTheProviderNameWhenASecondAppears() {
        let payload = builder.payload(
            readings: [
                reading(key: "session", label: "5h", remaining: 20),
                reading(provider: "codex", name: "OpenAI Codex", key: "session", label: "5h", remaining: 60),
            ],
            now: now
        )
        XCTAssertEqual(
            payload.tile?.metrics.map { $0.label },
            ["Anthropic 5h", "OpenAI Codex 5h"]
        )
    }

    // MARK: - Numbers

    /// A 42% quota publishes 42, never 58. Every surface in this app reads as
    /// remaining, and a full bar meaning a full quota is the only intuitive
    /// mapping a gauge has.
    func testAPercentageIsRemainingNotUsed() {
        let payload = builder.payload(
            readings: [reading(key: "session", label: "5h", remaining: 42)],
            now: now
        )
        XCTAssertEqual(payload.tile?.progress, 42)
        XCTAssertEqual(payload.gauge?.progress, 42)
        XCTAssertEqual(payload.tile?.metrics.first?.value, "42")
        XCTAssertEqual(payload.tile?.metrics.first?.unit, "%")
    }

    func testAMoneyQuotaPublishesItsBalanceAndNoUnit() {
        let payload = builder.payload(
            readings: [reading(key: "credits", label: "Credits", dollars: 12.5)],
            now: now
        )
        XCTAssertEqual(payload.gauge?.value, NotifyQuota.formatCurrency(12.5, code: "USD"))
        XCTAssertNil(payload.gauge?.unit)
        XCTAssertNil(payload.gauge?.progress)
    }

    /// A whole balance drops its cents: the widget has forty characters and
    /// "$120" reads faster than "$120.00".
    ///
    /// Asserted on the digits rather than on a whole formatted string, because
    /// the balance is written in the user's own locale and the CI runner's is
    /// not something to pin a test to.
    func testAWholeBalanceDropsItsCentsAndAFractionalOneKeepsThem() {
        let locale = Locale(identifier: "en_US")
        let whole = NotifyQuota.formatCurrency(120, code: "USD", locale: locale)
        let fractional = NotifyQuota.formatCurrency(120.5, code: "USD", locale: locale)

        XCTAssertEqual(whole, "$120")
        XCTAssertEqual(fractional, "$120.50")
    }

    /// The tile's bar falls through to the worst quota that has a percentage,
    /// rather than vanishing whenever a credit balance is the headline.
    func testTheBarFallsThroughPastAMoneyHeadline() {
        let payload = builder.payload(
            readings: [
                reading(key: "credits", label: "Credits", dollars: 0),
                reading(key: "session", label: "5h", remaining: 65),
            ],
            now: now
        )
        // The depleted balance leads and colors the tile...
        XCTAssertEqual(payload.tile?.tintHex, NotifyQuotaStatus.depleted.notifyTintHex)
        // ...but the bar comes from the window that actually has a percentage.
        XCTAssertEqual(payload.tile?.progress, 65)
    }

    // MARK: - Countdown

    func testTheCountdownUsesTheGatewaysCompactShapes() {
        XCTAssertEqual(
            NotifyQuota(key: "k", label: "l", resetsAt: now.addingTimeInterval(3 * 86400)).compactResetTime(now: now),
            "3d"
        )
        XCTAssertEqual(
            NotifyQuota(key: "k", label: "l", resetsAt: now.addingTimeInterval(4 * 3600 + 40 * 60)).compactResetTime(now: now),
            "4:40"
        )
        XCTAssertEqual(
            NotifyQuota(key: "k", label: "l", resetsAt: now.addingTimeInterval(12 * 60)).compactResetTime(now: now),
            "12m"
        )
        XCTAssertEqual(
            NotifyQuota(key: "k", label: "l", resetsAt: now.addingTimeInterval(30)).compactResetTime(now: now),
            "soon"
        )
        XCTAssertNil(NotifyQuota(key: "k", label: "l").compactResetTime(now: now))
    }

    // MARK: - Gauge selection

    func testTheGaugeShowsTheWindowTheUserPicked() {
        let payload = builder.payload(
            readings: [
                reading(key: "session", label: "5h", remaining: 12),
                reading(key: "weekly", label: "7d", remaining: 88),
            ],
            gaugeSelection: NotifyGaugeSelection(providerId: "anthropic", quotaKey: "weekly"),
            now: now
        )
        XCTAssertEqual(payload.gauge?.progress, 88)
    }

    /// A selection naming a window that has stopped reporting falls back to the
    /// worst quota rather than publishing nothing.
    func testAStaleSelectionFallsBackToTheWorstQuota() {
        let payload = builder.payload(
            readings: [reading(key: "session", label: "5h", remaining: 12)],
            gaugeSelection: NotifyGaugeSelection(providerId: "anthropic", quotaKey: "opus_weekly"),
            now: now
        )
        XCTAssertEqual(payload.gauge?.progress, 12)
    }

    func testAnEmptySelectionIsAutomatic() {
        XCTAssertTrue(NotifyGaugeSelection().isAutomatic)
        XCTAssertTrue(NotifyGaugeSelection(providerId: "anthropic", quotaKey: "").isAutomatic)
        XCTAssertFalse(NotifyGaugeSelection(providerId: "anthropic", quotaKey: "session").isAutomatic)
    }

    // MARK: - Surfaces

    /// The Live Activity and the Home Screen tile are one built value, so the
    /// two can never disagree about the same quota.
    func testBothTilesCarryTheIdenticalValue() {
        let payload = builder.payload(
            readings: [reading(key: "session", label: "5h", remaining: 42, resetsIn: 3600)],
            now: now
        )
        XCTAssertNotNil(payload.tile)
        XCTAssertEqual(payload.tile, payload.screenTile)
    }

    func testASwitchedOffSurfaceIsNil() {
        let payload = builder.payload(
            readings: [reading(key: "session", label: "5h", remaining: 42)],
            includesTile: false,
            includesGauge: true,
            includesScreenTile: false,
            now: now
        )
        XCTAssertNil(payload.tile)
        XCTAssertNil(payload.screenTile)
        XCTAssertNotNil(payload.gauge)
    }

    func testNoReadingsMeansAnEmptyPayload() {
        XCTAssertTrue(builder.payload(readings: [], now: now).isEmpty)
    }

    // MARK: - Status

    func testStatusThresholdsMatchTheMenuBarsRemainingMode() {
        XCTAssertEqual(NotifyQuotaStatus.forRemaining(100), .healthy)
        XCTAssertEqual(NotifyQuotaStatus.forRemaining(30), .healthy)
        XCTAssertEqual(NotifyQuotaStatus.forRemaining(29), .warning)
        XCTAssertEqual(NotifyQuotaStatus.forRemaining(10), .warning)
        XCTAssertEqual(NotifyQuotaStatus.forRemaining(9), .critical)
        XCTAssertEqual(NotifyQuotaStatus.forRemaining(0), .depleted)
    }
}
