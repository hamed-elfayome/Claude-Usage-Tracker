//
//  MenuBarAppearanceTrackerTests.swift
//  Claude UsageTests
//
//  Covers the redraw decision that lets StatusBarUIManager observe each
//  status bar button's effectiveAppearance without re-entering the redraw
//  loop that originally forced that observation to be removed.
//

import XCTest
@testable import Claude_Usage

final class MenuBarAppearanceTrackerTests: XCTestCase {
    private final class Token {}

    private func id(_ t: Token) -> ObjectIdentifier { ObjectIdentifier(t) }

    func testUnrenderedButtonNeverNeedsRedraw() {
        let tracker = MenuBarAppearanceTracker()
        let b = Token()
        XCTAssertFalse(tracker.needsRedraw(for: id(b), currentIsDark: true))
        XCTAssertFalse(tracker.needsRedraw(for: id(b), currentIsDark: false))
        XCTAssertFalse(tracker.isTracking(id(b)))
    }

    func testSettledAppearanceMatchingLastRenderIsIgnored() {
        // Assigning button.image fires effectiveAppearance KVO; once settled the
        // appearance is the one we just drew, so no redraw may be scheduled.
        var tracker = MenuBarAppearanceTracker()
        let b = Token()
        tracker.recordRender(for: id(b), isDark: true)
        XCTAssertFalse(tracker.needsRedraw(for: id(b), currentIsDark: true))
        tracker.recordRender(for: id(b), isDark: false)
        XCTAssertFalse(tracker.needsRedraw(for: id(b), currentIsDark: false))
    }

    func testFlippedAppearanceNeedsRedraw() {
        var tracker = MenuBarAppearanceTracker()
        let b = Token()
        tracker.recordRender(for: id(b), isDark: false)   // black digits on a light menu bar
        XCTAssertTrue(tracker.needsRedraw(for: id(b), currentIsDark: true)) // Space with a dark wallpaper
        tracker.recordRender(for: id(b), isDark: true)
        XCTAssertFalse(tracker.needsRedraw(for: id(b), currentIsDark: true))
        XCTAssertTrue(tracker.needsRedraw(for: id(b), currentIsDark: false))
    }

    func testRedrawCycleConverges() {
        // flip -> redraw (records new value) -> KVO echoes from image set -> no-op.
        var tracker = MenuBarAppearanceTracker()
        let b = Token()
        tracker.recordRender(for: id(b), isDark: false)
        var redraws = 0
        for _ in 0..<10 where tracker.needsRedraw(for: id(b), currentIsDark: true) {
            redraws += 1
            tracker.recordRender(for: id(b), isDark: true)
        }
        XCTAssertEqual(redraws, 1)
    }

    func testButtonsAreTrackedIndependently() {
        var tracker = MenuBarAppearanceTracker()
        let a = Token(), b = Token()
        tracker.recordRender(for: id(a), isDark: false)
        tracker.recordRender(for: id(b), isDark: true)
        XCTAssertTrue(tracker.needsRedraw(for: id(a), currentIsDark: true))
        XCTAssertFalse(tracker.needsRedraw(for: id(b), currentIsDark: true))
    }

    func testRetainOnlyDropsStaleButtons() {
        var tracker = MenuBarAppearanceTracker()
        let live = Token(), gone = Token()
        tracker.recordRender(for: id(live), isDark: true)
        tracker.recordRender(for: id(gone), isDark: true)
        XCTAssertEqual(tracker.trackedCount, 2)
        tracker.retain(only: [id(live)])
        XCTAssertEqual(tracker.trackedCount, 1)
        XCTAssertTrue(tracker.isTracking(id(live)))
        XCTAssertFalse(tracker.isTracking(id(gone)))
        XCTAssertFalse(tracker.needsRedraw(for: id(gone), currentIsDark: false))
    }
}
