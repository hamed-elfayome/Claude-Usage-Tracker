import XCTest
@testable import Claude_Usage

final class PollingSchedulerTests: XCTestCase {

    private func makeUsage(sessionPercentage: Double = 50.0, weeklyPercentage: Double = 30.0) -> ClaudeUsage {
        ClaudeUsage(
            sessionTokensUsed: 500,
            sessionLimit: 1000,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date().addingTimeInterval(5 * 60 * 60),
            weeklyTokensUsed: 300,
            weeklyLimit: 1_000_000,
            weeklyPercentage: weeklyPercentage,
            weeklyResetTime: Date().addingTimeInterval(7 * 24 * 60 * 60),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }

    // MARK: - Initial State

    func testInitialIntervalEqualsBaseRate() {
        var scheduler = PollingScheduler(baseInterval: 30)
        XCTAssertEqual(scheduler.currentInterval, 30)
    }

    // MARK: - Rate-Limit Backoff

    func testRateLimitErrorDoublesInterval() {
        var scheduler = PollingScheduler(baseInterval: 30)

        scheduler.recordRateLimitError()
        XCTAssertEqual(scheduler.currentInterval, 60)  // 30 * 2^1

        scheduler.recordRateLimitError()
        XCTAssertEqual(scheduler.currentInterval, 120) // 30 * 2^2

        scheduler.recordRateLimitError()
        XCTAssertEqual(scheduler.currentInterval, 240) // 30 * 2^3
    }

    func testBackoffCapsAtMaxInterval() {
        var scheduler = PollingScheduler(baseInterval: 30, maxBackoffInterval: 300)

        // 30 -> 60 -> 120 -> 240 -> 300 (cap)
        scheduler.recordRateLimitError() // 60
        scheduler.recordRateLimitError() // 120
        scheduler.recordRateLimitError() // 240
        scheduler.recordRateLimitError() // 480 -> capped to 300

        XCTAssertEqual(scheduler.currentInterval, 300)
    }

    func testSuccessAfterBackoffResetsToBaseRate() {
        var scheduler = PollingScheduler(baseInterval: 30)

        scheduler.recordRateLimitError()
        scheduler.recordRateLimitError()
        XCTAssertEqual(scheduler.currentInterval, 120)

        scheduler.recordSuccess(usage: makeUsage())
        XCTAssertEqual(scheduler.currentInterval, 30)
    }

    // MARK: - Adaptive Polling (Stability)

    func testFiveSimilarResponsesTriggersStableTier() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 5, idleThreshold: 10)
        let usage = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)

        for _ in 0..<5 {
            scheduler.recordSuccess(usage: usage)
        }

        XCTAssertEqual(scheduler.currentInterval, 60) // 30 * 2x
    }

    func testTenSimilarResponsesTriggersIdleTier() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 5, idleThreshold: 10)
        let usage = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)

        for _ in 0..<10 {
            scheduler.recordSuccess(usage: usage)
        }

        XCTAssertEqual(scheduler.currentInterval, 120) // 30 * 4x
    }

    func testChangedDataResetsStabilityStreak() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 5, idleThreshold: 10)
        let usage1 = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)
        let usage2 = makeUsage(sessionPercentage: 55.0, weeklyPercentage: 30.0) // >1pp diff

        // Build up stability
        for _ in 0..<5 {
            scheduler.recordSuccess(usage: usage1)
        }
        XCTAssertEqual(scheduler.currentInterval, 60) // stable

        // Changed data resets streak
        scheduler.recordSuccess(usage: usage2)
        XCTAssertEqual(scheduler.currentInterval, 30) // back to normal
    }

    // MARK: - Backoff Overrides Adaptive

    func testBackoffOverridesAdaptiveMultiplier() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 5, idleThreshold: 10)
        let usage = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)

        // Build up idle tier
        for _ in 0..<10 {
            scheduler.recordSuccess(usage: usage)
        }
        XCTAssertEqual(scheduler.currentInterval, 120) // idle tier

        // Rate limit overrides adaptive
        scheduler.recordRateLimitError()
        XCTAssertEqual(scheduler.currentInterval, 60) // backoff: 30 * 2^1
    }

    // MARK: - resetBaseInterval

    func testResetBaseIntervalUpdatesComputedInterval() {
        var scheduler = PollingScheduler(baseInterval: 30)
        XCTAssertEqual(scheduler.currentInterval, 30)

        scheduler.resetBaseInterval(60)
        XCTAssertEqual(scheduler.currentInterval, 60)
    }

    func testResetBaseIntervalAffectsAdaptiveMultiplier() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 5, idleThreshold: 10)
        let usage = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)

        for _ in 0..<5 {
            scheduler.recordSuccess(usage: usage)
        }
        XCTAssertEqual(scheduler.currentInterval, 60) // 30 * 2x

        scheduler.resetBaseInterval(45)
        XCTAssertEqual(scheduler.currentInterval, 90) // 45 * 2x
    }

    // MARK: - Similarity Tolerance

    func testSimilarityWithinToleranceIsSimilar() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 2, similarityTolerance: 1.0)
        let usage1 = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)
        let usage2 = makeUsage(sessionPercentage: 50.5, weeklyPercentage: 30.3) // within 1pp

        scheduler.recordSuccess(usage: usage1)
        scheduler.recordSuccess(usage: usage2)
        XCTAssertEqual(scheduler.currentInterval, 60) // stable (2 similar = threshold)
    }

    func testSimilarityExceedingToleranceResetsStreak() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 2, similarityTolerance: 1.0)
        let usage1 = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)
        let usage2 = makeUsage(sessionPercentage: 51.5, weeklyPercentage: 30.0) // >1pp diff

        scheduler.recordSuccess(usage: usage1)
        scheduler.recordSuccess(usage: usage2)
        XCTAssertEqual(scheduler.currentInterval, 30) // streak reset, back to normal
    }

    // MARK: - Other Errors

    func testOtherErrorsDoNotTriggerBackoff() {
        var scheduler = PollingScheduler(baseInterval: 30)

        scheduler.recordOtherError()
        XCTAssertEqual(scheduler.currentInterval, 30) // unchanged
    }

    // MARK: - Full Cycle

    func testFullCycleBackoffRecoveryStabilityChange() {
        var scheduler = PollingScheduler(baseInterval: 30, stableThreshold: 3, idleThreshold: 6)
        let stableUsage = makeUsage(sessionPercentage: 50.0, weeklyPercentage: 30.0)
        let changedUsage = makeUsage(sessionPercentage: 60.0, weeklyPercentage: 35.0)

        // Phase 1: Backoff
        scheduler.recordRateLimitError()
        scheduler.recordRateLimitError()
        XCTAssertEqual(scheduler.currentInterval, 120) // 30 * 2^2

        // Phase 2: Recovery
        scheduler.recordSuccess(usage: stableUsage)
        XCTAssertEqual(scheduler.currentInterval, 30) // reset to base

        // Phase 3: Stability
        scheduler.recordSuccess(usage: stableUsage) // streak = 2
        scheduler.recordSuccess(usage: stableUsage) // streak = 3
        XCTAssertEqual(scheduler.currentInterval, 60) // stable tier

        // Phase 4: Change resets
        scheduler.recordSuccess(usage: changedUsage)
        XCTAssertEqual(scheduler.currentInterval, 30) // back to normal
    }
}
