import XCTest
import AppKit
@testable import Claude_Usage

final class NSWindowFullScreenSpacesTests: XCTestCase {

    // MARK: - Space Membership

    func testEnableDisplayJoinsAllSpacesAndFullScreenSpaces() {
        let window = makeWindow()
        window.collectionBehavior = []

        window.enableDisplayOnFullScreenSpaces()

        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testEnableDisplayClearsMoveToActiveSpace() {
        let window = makeWindow()
        window.collectionBehavior = [.moveToActiveSpace]

        // Guards an AppKit exception, not a preference: inserting .canJoinAllSpaces
        // alongside .moveToActiveSpace raises NSInternalInconsistencyException, so
        // dropping the remove() aborts this test rather than failing it.
        window.enableDisplayOnFullScreenSpaces()

        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testEnableDisplayPreservesUnrelatedCollectionBehavior() {
        let window = makeWindow()
        window.collectionBehavior = [.ignoresCycle, .stationary]

        window.enableDisplayOnFullScreenSpaces()

        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
    }

    // MARK: - Helpers

    private func makeWindow() -> NSWindow {
        // defer: true keeps the window device from being created — these tests only
        // exercise the window's Spaces behavior.
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
    }
}
