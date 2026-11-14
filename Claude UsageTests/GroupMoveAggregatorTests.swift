import XCTest
@testable import Claude_Usage

final class GroupMoveAggregatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let p = UUID(), q = UUID(), r = UUID(), s = UUID()
    private let names = ["org-a": "A", "org-b": "B"]

    func testMixedOutcomes() {
        let e = GroupMoveAggregator.event(from: "org-a", trigger: p, triggerTarget: "org-b",
                                          peers: [q: .moved(to: "org-b"), r: .notMoved, s: .unchecked], names: names, now: now)
        guard case let .groupMove(from, to, moves, notMoved, unchecked) = e.kind else { return XCTFail("kind") }
        XCTAssertEqual(from, "org-a")
        XCTAssertEqual(to, "org-b")
        XCTAssertEqual(Set(moves.keys), [p, q])
        XCTAssertEqual(notMoved, [r])
        XCTAssertEqual(unchecked, [s])
        XCTAssertEqual(e.date, now)
        XCTAssertEqual(e.title, "2 accounts moved: A → B")
    }

    func testAllRemovedTitle() {
        let e = GroupMoveAggregator.event(from: "org-a", trigger: p, triggerTarget: nil,
                                          peers: [q: .moved(to: nil)], names: names, now: now)
        guard case let .groupMove(_, to, _, _, _) = e.kind else { return XCTFail("kind") }
        XCTAssertNil(to)
        XCTAssertEqual(e.title, "2 accounts removed from A")
    }

    func testMostCommonTargetTieGoesToTrigger() {
        XCTAssertEqual(GroupMoveAggregator.mostCommonTarget([p: "x", q: "y"], trigger: p), "x")
        XCTAssertEqual(GroupMoveAggregator.mostCommonTarget([p: "x", q: "y"], trigger: q), "y")
        XCTAssertEqual(GroupMoveAggregator.mostCommonTarget([p: "x", q: "y", r: "y"], trigger: p), "y")
        XCTAssertNil(GroupMoveAggregator.mostCommonTarget([p: nil], trigger: p))
    }
}
