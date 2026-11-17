import XCTest
@testable import Claude_Usage

final class CurrentPairDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_799_990_000)
    private let a = PairRef(profileId: UUID(), orgId: "a")
    private let b = PairRef(profileId: UUID(), orgId: "b")
    private let c = PairRef(profileId: UUID(), orgId: "c")
    private let reset = TeamFixtures.defaultSessionReset

    private func reading(_ pct: Double, ageSeconds: TimeInterval = 300, reset: Date? = nil) -> RoundReading {
        RoundReading(percent: pct, resetTime: reset ?? self.reset, at: now.addingTimeInterval(-ageSeconds))
    }

    private func cand(_ p: PairRef, prev: Double?, now pct: Double?, ageSeconds: TimeInterval = 300,
                      prevReset: Date? = nil, latestReset: Date? = nil) throws -> RoundCandidate {
        RoundCandidate(pair: p, previous: prev.map { reading($0, ageSeconds: ageSeconds, reset: prevReset) },
                       latest: try pct.map { try TeamFixtures.usage(session: $0, weekly: 10, sessionReset: latestReset ?? reset) },
                       latestAt: now)
    }

    private func run(current: PairRef?, _ cs: [RoundCandidate], manualPickAt: Date? = nil, lastRoundAt: Date? = nil) -> RoundOutput {
        CurrentPairDetector.evaluate(RoundInput(now: now, current: current, manualPickAt: manualPickAt, lastRoundAt: lastRoundAt, candidates: cs))
    }

    func testRiserBecomesCurrent() throws {
        let out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: 13)])
        XCTAssertEqual(out.current, b)
        XCTAssertTrue(out.switched)
    }

    func testLargestRiseWinsAndTiesKeepCurrent() throws {
        var out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: 13), try cand(c, prev: 10, now: 15)])
        XCTAssertEqual(out.current, c)
        out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: 14), try cand(c, prev: 10, now: 14)])
        XCTAssertEqual(out.current, a)
        XCTAssertFalse(out.switched)
        out = run(current: a, [try cand(a, prev: 10, now: 14), try cand(b, prev: 10, now: 14)])
        XCTAssertEqual(out.current, a)
    }

    func testNoRisesUnchanged() throws {
        var out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: 10.5)])
        XCTAssertEqual(out.current, a)
        XCTAssertFalse(out.switched)
        out = run(current: nil, [try cand(a, prev: 10, now: 10)])
        XCTAssertNil(out.current)
        XCTAssertFalse(out.switched)
    }

    func testStalePreviousRebaselinesOnly() throws {
        let out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: 20, ageSeconds: 600)])
        XCTAssertEqual(out.current, a)
        XCTAssertNil(out.rises[b])
        XCTAssertEqual(out.readings[b]?.percent, 20)
    }

    func testDifferentWindowRiseIsLatestPercent() throws {
        let prevReset = reset.addingTimeInterval(-2 * 3600)
        let out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 90, now: 7, prevReset: prevReset)])
        XCTAssertEqual(out.rises[b], 7)
        XCTAssertEqual(out.current, b)
    }

    func testSameWindowLowerIsZeroRise() throws {
        let out = run(current: a, [try cand(b, prev: 50, now: 20)])
        XCTAssertEqual(out.rises[b], 0)
        XCTAssertEqual(out.current, a)
    }

    func testManualPickBlocksSwitchAndClears() throws {
        let cs = [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: 20)]
        var out = run(current: a, cs, manualPickAt: now.addingTimeInterval(-10), lastRoundAt: now.addingTimeInterval(-300))
        XCTAssertEqual(out.current, a)
        XCTAssertFalse(out.switched)
        XCTAssertTrue(out.clearManualPick)
        XCTAssertEqual(out.readings[b]?.percent, 20)
        out = run(current: a, cs, manualPickAt: now.addingTimeInterval(-400), lastRoundAt: now.addingTimeInterval(-300))
        XCTAssertEqual(out.current, b)
        XCTAssertFalse(out.clearManualPick)
    }

    func testWeeklyOnlyUsesWeekly() throws {
        var u = try TeamFixtures.usage(session: 5, weekly: 42)
        u.hasSessionLimit = false
        let m = CurrentPairDetector.metric(u)
        XCTAssertEqual(m.percent, 42)
        XCTAssertEqual(m.reset, u.weeklyResetTime)
    }

    func testNilLatestKeepsNoReadingAndIsNotChosen() throws {
        let out = run(current: a, [try cand(a, prev: 10, now: 10), try cand(b, prev: 10, now: nil)])
        XCTAssertNil(out.readings[b])
        XCTAssertNil(out.rises[b])
        XCTAssertEqual(out.current, a)
    }

    func testEdgeCases() throws {
        let empty = run(current: a, [])
        XCTAssertEqual(empty.current, a)
        XCTAssertTrue(empty.readings.isEmpty)
        // current not among candidates: a unique riser still takes over
        XCTAssertEqual(run(current: a, [try cand(b, prev: 10, now: 15)]).current, b)
        // three-way tie, no current: first in order
        let tie = run(current: nil, [try cand(c, prev: 1, now: 6), try cand(a, prev: 1, now: 6), try cand(b, prev: 1, now: 6)])
        XCTAssertEqual(tie.current, c)
    }
}
