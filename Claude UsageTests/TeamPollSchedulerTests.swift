import XCTest
@testable import Claude_Usage

final class TeamPollSchedulerTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_000_000)
    private func make(_ r: Double = 0.5) -> TeamPollScheduler { TeamPollScheduler(random: { r }) }

    func testRoundTiming() {
        var s = make()
        s.start(now: t)
        XCTAssertFalse(s.isRoundDue(now: t.addingTimeInterval(14)))
        XCTAssertTrue(s.isRoundDue(now: t.addingTimeInterval(15)))
        s.roundStarted(now: t.addingTimeInterval(15))
        XCTAssertFalse(s.isRoundDue(now: t.addingTimeInterval(314)))
        XCTAssertTrue(s.isRoundDue(now: t.addingTimeInterval(315)))
    }

    func testListStartSpreadAndInterval() {
        var s = make(0.5); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        XCTAssertEqual(s.dueLists(now: t.addingTimeInterval(4.9)), [])
        XCTAssertEqual(s.dueLists(now: t.addingTimeInterval(5)), [a])
        let f = t.addingTimeInterval(100)
        s.listFinished(accountId: a, outcome: .success, now: f)
        XCTAssertEqual(s.dueLists(now: f.addingTimeInterval(899)), [])
        XCTAssertEqual(s.dueLists(now: f.addingTimeInterval(900)), [a])
    }

    func testNoOrgListNeverDue() {
        var s = make(); let a = UUID()
        s.register(accountId: a, hasOrgList: false, now: t)
        XCTAssertEqual(s.dueLists(now: t.addingTimeInterval(10_000)), [])
        s.listFinished(accountId: a, outcome: .success, now: t)
        s.listFinished(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
        XCTAssertEqual(s.dueLists(now: t.addingTimeInterval(10_000)), [])
    }

    func testForceListDebounceBoundary() {
        var s = make(); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        XCTAssertTrue(s.forceList(accountId: a, now: t))
        XCTAssertFalse(s.forceList(accountId: a, now: t.addingTimeInterval(59.9)))
        XCTAssertTrue(s.forceList(accountId: a, now: t.addingTimeInterval(60)))
    }

    func testBackoffSequence() {
        var s = make(0.5); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        for expected in [60.0, 120, 240, 480, 900, 900] {
            s.record(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
            XCTAssertEqual(s.backoffUntil(a)!.timeIntervalSince(t), expected, accuracy: 0.001)
        }
    }

    func testJitterBounds() {
        for (r, lo, hi) in [(0.0, 48.0, 48.0), (0.999, 71.9, 72.0)] {
            var s = make(r); let a = UUID()
            s.register(accountId: a, hasOrgList: true, now: t)
            s.record(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
            let d = s.backoffUntil(a)!.timeIntervalSince(t)
            XCTAssertGreaterThanOrEqual(d, lo); XCTAssertLessThanOrEqual(d, hi)
        }
    }

    func testRetryAfter() {
        var s = make(); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        s.record(accountId: a, outcome: .rateLimited(retryAfter: 1800), now: t)
        XCTAssertEqual(s.backoffUntil(a)!.timeIntervalSince(t), 1800, accuracy: 0.001)
        s.record(accountId: a, outcome: .success, now: t)
        s.record(accountId: a, outcome: .rateLimited(retryAfter: 7200), now: t)
        XCTAssertEqual(s.backoffUntil(a)!.timeIntervalSince(t), 3600, accuracy: 0.001)
    }

    func testBackingOffExcludedAndOthersUnaffected() {
        var s = make(0); let a = UUID(), b = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        s.register(accountId: b, hasOrgList: true, now: t)
        s.record(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
        XCTAssertTrue(s.isBackingOff(a, now: t))
        XCTAssertEqual(s.dueLists(now: t), [b])
        XCTAssertFalse(s.forceList(accountId: a, now: t))
        XCTAssertTrue(s.forceList(accountId: b, now: t))
    }

    func testSuccessClearsBackoff() {
        var s = make(); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        s.record(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
        s.record(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
        s.record(accountId: a, outcome: .failed, now: t)
        XCTAssertTrue(s.isBackingOff(a, now: t))
        s.record(accountId: a, outcome: .success, now: t)
        XCTAssertFalse(s.isBackingOff(a, now: t))
        s.record(accountId: a, outcome: .rateLimited(retryAfter: nil), now: t)
        XCTAssertEqual(s.backoffUntil(a)!.timeIntervalSince(t), 60, accuracy: 0.001)
    }

    func testForceListDebounce() {
        var s = make(); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        XCTAssertTrue(s.forceList(accountId: a, now: t))
        XCTAssertFalse(s.forceList(accountId: a, now: t.addingTimeInterval(30)))
        XCTAssertTrue(s.forceList(accountId: a, now: t.addingTimeInterval(30), bypassDebounce: true))
        XCTAssertTrue(s.forceList(accountId: a, now: t.addingTimeInterval(91)))
    }

    func testUnregisterAndUnknown() {
        var s = make(); let a = UUID(), u = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        s.unregister(accountId: a)
        XCTAssertEqual(s.dueLists(now: t.addingTimeInterval(1000)), [])
        XCTAssertTrue(s.registeredAccounts.isEmpty)
        s.record(accountId: u, outcome: .rateLimited(retryAfter: nil), now: t)
        s.listFinished(accountId: a, outcome: .success, now: t)
        XCTAssertTrue(s.registeredAccounts.isEmpty)
    }

    func testRegisterTwiceKeepsDueTime() {
        var s = make(0.5); let a = UUID()
        s.register(accountId: a, hasOrgList: true, now: t)
        s.register(accountId: a, hasOrgList: true, now: t.addingTimeInterval(500))
        XCTAssertEqual(s.dueLists(now: t.addingTimeInterval(5)), [a])
    }
}
