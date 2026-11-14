import XCTest
@testable import Claude_Usage

private actor Counter {
    var current = 0, peak = 0
    func enter() { current += 1; peak = max(peak, current) }
    func leave() { current -= 1 }
}

final class BoundedTaskRunnerTests: XCTestCase {
    func testGlobalLimit() async {
        let c = Counter()
        let items = (0..<10).map { ($0, UUID()) }
        let r = await BoundedTaskRunner.run(items, key: { $0.1 }, maxConcurrent: 4, maxPerKey: 1) { item in
            await c.enter(); try? await Task.sleep(nanoseconds: 50_000_000); await c.leave(); return item.0
        }
        XCTAssertEqual(r.map { $0.1 }, Array(0..<10))
        let peak = await c.peak
        XCTAssertEqual(peak, 4)
    }

    func testPerKeyLimit() async {
        let c = Counter(); let k = UUID()
        let r = await BoundedTaskRunner.run([1, 2, 3], key: { _ in k }, maxConcurrent: 4, maxPerKey: 1) { i in
            await c.enter(); try? await Task.sleep(nanoseconds: 30_000_000); await c.leave(); return i
        }
        XCTAssertEqual(r.compactMap { $0.1 }, [1, 2, 3])
        let peak = await c.peak
        XCTAssertEqual(peak, 1)
    }

    func testTimeout() async {
        let start = Date()
        let r = await BoundedTaskRunner.run([1, 2], key: { _ in UUID() }, maxConcurrent: 4, maxPerKey: 1, timeout: 0.1) { i in
            if i == 1 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            return i
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertNil(r[0].1)
        XCTAssertEqual(r[1].1, 2)
    }

    func testTimedOutItemStaysNil() async {
        let start = Date()
        let r = await BoundedTaskRunner.run([1, 2], key: { _ in UUID() }, maxConcurrent: 4, maxPerKey: 1, timeout: 0.1) { i in
            if i == 2 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            return i
        }
        XCTAssertEqual(r[0].1, 1)
        XCTAssertNil(r[1].1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testEmpty() async {
        let r = await BoundedTaskRunner.run([Int](), key: { _ in UUID() }, maxConcurrent: 4, maxPerKey: 1) { $0 }
        XCTAssertTrue(r.isEmpty)
    }
}
