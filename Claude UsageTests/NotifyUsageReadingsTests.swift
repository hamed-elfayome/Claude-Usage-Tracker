import XCTest
@testable import Claude_Usage

/// The seam between `ClaudeUsage` and the flat readings the payload builder
/// takes: which windows a provider actually reports, and what each one says.
///
/// `@MainActor` because the app target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so everything under test is
/// main-actor isolated while the test target's own default is not. Same
/// reason `NotchHUDCoreTests` and `NotchHookServerTests` carry it.
@MainActor
final class NotifyUsageReadingsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func usage(_ configure: (inout ClaudeUsage) -> Void = { _ in }) -> ClaudeUsage {
        var usage = ClaudeUsage.empty
        usage.sessionResetTime = now.addingTimeInterval(3600)
        usage.weeklyResetTime = now.addingTimeInterval(4 * 86400)
        configure(&usage)
        return usage
    }

    private func keys(_ readings: [NotifyQuotaReading]) -> [String] {
        readings.map { $0.quota.key }
    }

    private func quota(_ readings: [NotifyQuotaReading], _ key: String) -> NotifyQuota? {
        readings.first { $0.quota.key == key }?.quota
    }

    // MARK: - The always-present windows

    func testTheSessionAndWeeklyWindowsAreAlwaysReported() {
        let readings = NotifyUsageReadings.readings(from: usage(), provider: .anthropic, now: now)
        XCTAssertTrue(keys(readings).contains(NotifyUsageReadings.QuotaKey.session))
        XCTAssertTrue(keys(readings).contains(NotifyUsageReadings.QuotaKey.weekly))
    }

    /// The app publishes remaining, not used, so a 30% used window reaches the
    /// phone as 70.
    func testPercentagesArriveAsRemaining() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.sessionPercentage = 30 },
            provider: .anthropic,
            now: now
        )
        XCTAssertEqual(quota(readings, NotifyUsageReadings.QuotaKey.session)?.percentRemaining, 70)
    }

    /// A provider that reports more than 100% used should read as an empty
    /// window rather than as a negative one.
    func testAnOverrunWindowClampsToEmpty() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.sessionPercentage = 130 },
            provider: .anthropic,
            now: now
        )
        XCTAssertEqual(quota(readings, NotifyUsageReadings.QuotaKey.session)?.percentRemaining, 0)
    }

    /// A window that rolled over while the Mac was asleep is full again, and
    /// publishing the stale percentage would put a red ring on a phone for a
    /// limit that no longer applies.
    func testAnExpiredSessionWindowReadsAsFull() {
        let readings = NotifyUsageReadings.readings(
            from: usage {
                $0.sessionPercentage = 95
                $0.sessionResetTime = now.addingTimeInterval(-60)
            },
            provider: .anthropic,
            now: now
        )
        let session = quota(readings, NotifyUsageReadings.QuotaKey.session)
        XCTAssertEqual(session?.percentRemaining, 100)
        XCTAssertNil(session?.resetsAt)
    }

    // MARK: - Per-model windows

    /// A model the account has never used has no window, and a placeholder
    /// 100% would take a slot on the tile away from a number that matters.
    func testAnUnusedModelWindowIsLeftOut() {
        let readings = NotifyUsageReadings.readings(from: usage(), provider: .anthropic, now: now)
        XCTAssertFalse(keys(readings).contains(NotifyUsageReadings.QuotaKey.opusWeekly))
        XCTAssertFalse(keys(readings).contains(NotifyUsageReadings.QuotaKey.sonnetWeekly))
    }

    func testAReportingModelWindowIsIncluded() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.opusWeeklyPercentage = 40 },
            provider: .anthropic,
            now: now
        )
        XCTAssertEqual(quota(readings, NotifyUsageReadings.QuotaKey.opusWeekly)?.percentRemaining, 60)
    }

    /// A provider without per-model reporting never gets those windows, even if
    /// the struct happens to carry numbers in those fields.
    func testAProviderWithoutPerModelReportingGetsNoModelWindows() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.opusWeeklyPercentage = 40 },
            provider: .codex,
            now: now
        )
        XCTAssertFalse(keys(readings).contains(NotifyUsageReadings.QuotaKey.opusWeekly))
    }

    /// A model window with a reset time of its own uses it; one without falls
    /// back to the shared weekly reset.
    func testAModelWindowFallsBackToTheSharedWeeklyReset() {
        let ownReset = now.addingTimeInterval(2 * 86400)
        let readings = NotifyUsageReadings.readings(
            from: usage {
                $0.opusWeeklyPercentage = 10
                $0.sonnetWeeklyPercentage = 10
                $0.sonnetWeeklyResetTime = ownReset
            },
            provider: .anthropic,
            now: now
        )
        XCTAssertEqual(
            quota(readings, NotifyUsageReadings.QuotaKey.opusWeekly)?.resetsAt,
            now.addingTimeInterval(4 * 86400)
        )
        XCTAssertEqual(
            quota(readings, NotifyUsageReadings.QuotaKey.sonnetWeekly)?.resetsAt,
            ownReset
        )
    }

    // MARK: - Money

    /// A spend allowance with a ceiling is a percentage like any other window,
    /// so it draws a bar.
    func testASpendAllowanceWithACeilingIsAPercentage() {
        let readings = NotifyUsageReadings.readings(
            from: usage {
                $0.costUsed = 25
                $0.costLimit = 100
                $0.costCurrency = "USD"
            },
            provider: .anthropic,
            now: now
        )
        XCTAssertEqual(quota(readings, NotifyUsageReadings.QuotaKey.cost)?.percentRemaining, 75)
    }

    /// Without a ceiling there is nothing to divide by, and a bare "spent so
    /// far" number answers no question the user is asking a Lock Screen.
    func testASpendWithNoCeilingIsNotPublished() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.costUsed = 25 },
            provider: .anthropic,
            now: now
        )
        XCTAssertFalse(keys(readings).contains(NotifyUsageReadings.QuotaKey.cost))
    }

    func testAnOverageBalanceIsMoneyWithNoRing() {
        let readings = NotifyUsageReadings.readings(
            from: usage {
                $0.overageBalance = 40
                $0.overageBalanceCurrency = "USD"
            },
            provider: .anthropic,
            now: now
        )
        let overage = quota(readings, NotifyUsageReadings.QuotaKey.overage)
        XCTAssertEqual(overage?.dollarRemaining, 40)
        XCTAssertNil(overage?.percentRemaining)
        XCTAssertTrue(overage?.isDollarBased == true)
    }

    func testACreditsBalanceIsPublishedForProvidersThatReportOne() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.creditsBalance = 18.25 },
            provider: .codex,
            now: now
        )
        XCTAssertEqual(quota(readings, NotifyUsageReadings.QuotaKey.credits)?.dollarRemaining, 18.25)
    }

    /// "Unlimited" on a ring is not a number, so the window is left out.
    func testAnUnlimitedPlanPublishesNoCreditsWindow() {
        let readings = NotifyUsageReadings.readings(
            from: usage {
                $0.creditsBalance = 0
                $0.creditsUnlimited = true
            },
            provider: .codex,
            now: now
        )
        XCTAssertFalse(keys(readings).contains(NotifyUsageReadings.QuotaKey.credits))
    }

    func testCreditsAreNotPublishedForAProviderThatDoesNotReportThem() {
        let readings = NotifyUsageReadings.readings(
            from: usage { $0.creditsBalance = 18.25 },
            provider: .anthropic,
            now: now
        )
        XCTAssertFalse(keys(readings).contains(NotifyUsageReadings.QuotaKey.credits))
    }

    // MARK: - Identity

    func testEveryReadingCarriesTheProvidersIdAndName() {
        let readings = NotifyUsageReadings.readings(from: usage(), provider: .anthropic, now: now)
        XCTAssertTrue(readings.allSatisfy { $0.providerId == "anthropic" })
        XCTAssertTrue(readings.allSatisfy { $0.providerName == "Anthropic" })
    }

    /// The keys are persisted in the gauge selection, so renaming one would
    /// silently drop a user's chosen window back to automatic.
    func testTheQuotaKeysAreTheOnesTheGaugeSelectionStores() {
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.session, "session")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.weekly, "weekly")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.opusWeekly, "opus_weekly")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.sonnetWeekly, "sonnet_weekly")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.designWeekly, "design_weekly")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.fableWeekly, "fable_weekly")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.cost, "cost")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.overage, "overage")
        XCTAssertEqual(NotifyUsageReadings.QuotaKey.credits, "credits")
    }
}
