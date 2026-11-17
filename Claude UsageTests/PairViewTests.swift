import XCTest
@testable import Claude_Usage

final class PairViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSessionProjectedAfterReset() throws {
        let reset = now.addingTimeInterval(-60)
        let u = try TeamFixtures.usage(session: 80, weekly: 30, sessionReset: reset, weeklyReset: now.addingTimeInterval(86_400))
        let v = PairView.make(usage: u, sampledAt: reset.addingTimeInterval(-600), now: now)
        XCTAssertEqual(v.sessionPercent, 0)
        XCTAssertTrue(v.sessionProjected)
        XCTAssertEqual(v.sessionLeft, 100)
        XCTAssertFalse(v.weeklyProjected)
        let after = PairView.make(usage: u, sampledAt: reset.addingTimeInterval(10), now: now)
        XCTAssertFalse(after.sessionProjected)
        XCTAssertEqual(after.sessionPercent, 80)
    }

    func testWeeklyProjectedZeroesModelsAndHeadroom() throws {
        let u = try TeamFixtures.usage(session: 40, weekly: 90, sessionReset: now.addingTimeInterval(3600),
                                       weeklyReset: now.addingTimeInterval(-5), opus: 70)
        let v = PairView.make(usage: u, sampledAt: now.addingTimeInterval(-100), now: now)
        XCTAssertEqual(v.weeklyPercent, 0)
        XCTAssertTrue(v.weeklyProjected)
        XCTAssertEqual(v.opusPercent, 0)
        XCTAssertEqual(v.headroom, 60)   // min(60, 100)
    }

    func testOverHundredClampedAndNoSessionWindow() throws {
        var u = try TeamFixtures.usage(session: 120, weekly: 130, sessionReset: now.addingTimeInterval(60), weeklyReset: now.addingTimeInterval(60))
        var v = PairView.make(usage: u, sampledAt: now, now: now)
        XCTAssertEqual(v.sessionLeft, 0)
        XCTAssertEqual(v.weeklyLeft, 0)
        XCTAssertEqual(v.headroom, 0)
        u.hasSessionLimit = false
        v = PairView.make(usage: u, sampledAt: now, now: now)
        XCTAssertNil(v.sessionPercent)
        XCTAssertEqual(PairView.make(usage: nil, sampledAt: nil, now: now), PairView())
    }
}
