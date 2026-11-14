import XCTest

struct SelfError: Error {}
nonisolated(unsafe) var selfEvents: [String] = []

final class SelfOrderTests: XCTestCase {
    override func setUp() async throws { selfEvents.append("setUpAsync") }
    override func setUpWithError() throws { selfEvents.append("setUpWithError") }
    override func setUp() { selfEvents.append("setUp") }
    override func tearDown() { selfEvents.append("tearDown") }
    override func tearDownWithError() throws { selfEvents.append("tearDownWithError") }
    override func tearDown() async throws {
        selfEvents.append("tearDownAsync")
        print("ORDER:" + selfEvents.joined(separator: ","))
    }
    func testOrder() async throws {
        selfEvents.append("body")
        addTeardownBlock { selfEvents.append("block1") }
        addTeardownBlock { selfEvents.append("block2") }
    }
}

final class SelfOutcomeTests: XCTestCase {
    func testFailEqual() { XCTAssertEqual(1, 2) }
    func testListedSkip() { XCTFail("must not run: listed skip") }
    func testSkipUnless() throws { try XCTSkipUnless(false, "selftest reason") }
    func testThrows() throws { throw SelfError() }
}

nonisolated(unsafe) var selfPaused = false

@MainActor final class SelfPauseTests: XCTestCase {
    override func setUp() async throws {}
    override func tearDown() async throws { Task { @MainActor in selfPaused = true } }
    func testA() {}
    func testB() { XCTAssertTrue(selfPaused, "previous tearDown's main-actor Task had not run") }
}

final class SelfSetUpThrowTests: XCTestCase {
    override func setUpWithError() throws { throw SelfError() }
    override func tearDown() { print("TEARDOWN-RAN") }
    func testSetUpThrows() { XCTFail("body must not run") }
}

final class SelfZHangTests: XCTestCase {
    func testZZHang() { Thread.sleep(forTimeInterval: 10) }
}
