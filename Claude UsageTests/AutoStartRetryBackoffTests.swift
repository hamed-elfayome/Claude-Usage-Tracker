import XCTest
@testable import Claude_Usage

final class AutoStartRetryBackoffTests: XCTestCase {
    private let profile = UUID()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNoWaitBeforeAnyFailure() {
        XCTAssertNil(AutoStartRetryBackoff().waitRemaining(for: profile, now: start))
    }

    func testFirstFailureWaitsBaseDelayAndIsReportedAsFirst() {
        var backoff = AutoStartRetryBackoff()
        XCTAssertTrue(backoff.recordFailure(for: profile, now: start))
        XCTAssertEqual(backoff.waitRemaining(for: profile, now: start), AutoStartRetryBackoff.baseDelay)
        XCTAssertNil(backoff.waitRemaining(for: profile, now: start.addingTimeInterval(AutoStartRetryBackoff.baseDelay)))
    }

    func testConsecutiveFailuresDoubleTheWaitUpToTheCap() {
        var backoff = AutoStartRetryBackoff()
        backoff.recordFailure(for: profile, now: start)
        XCTAssertFalse(backoff.recordFailure(for: profile, now: start))
        XCTAssertEqual(backoff.waitRemaining(for: profile, now: start), AutoStartRetryBackoff.baseDelay * 2)
        for _ in 0..<10 { backoff.recordFailure(for: profile, now: start) }
        XCTAssertEqual(backoff.waitRemaining(for: profile, now: start), AutoStartRetryBackoff.maxDelay)
    }

    func testSuccessClearsTheStreak() {
        var backoff = AutoStartRetryBackoff()
        backoff.recordFailure(for: profile, now: start)
        backoff.recordSuccess(for: profile)
        XCTAssertNil(backoff.waitRemaining(for: profile, now: start))
        XCTAssertTrue(backoff.recordFailure(for: profile, now: start))
    }

    func testProfilesAreTrackedSeparately() {
        var backoff = AutoStartRetryBackoff()
        backoff.recordFailure(for: profile, now: start)
        XCTAssertNil(backoff.waitRemaining(for: UUID(), now: start))
    }
}
