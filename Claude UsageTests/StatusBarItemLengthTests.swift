import XCTest
@testable import Claude_Usage

/// Covers the length pinned on each multi-profile status item.
///
/// Two properties matter and pull against each other:
/// - the length must not change on an ordinary refresh (macOS 26 NSISEngine recursion), and
/// - it must not reserve menu bar width the icon does not need, or the last profile's item
///   gets laid out into the notch where macOS never draws it (#328).
final class StatusBarItemLengthTests: XCTestCase {

    // MARK: - No over-reserving

    func testPinnedLengthStaysCloseToTheRenderedWidth() {
        // The concentric-with-label icon renders 22pt wide; the item used to reserve 32.
        XCTAssertEqual(StatusBarUIManager.pinnedLength(forImageWidth: 22, previous: nil), 24)
        // The compact dot renders 16pt wide; the item used to reserve 32.
        XCTAssertEqual(StatusBarUIManager.pinnedLength(forImageWidth: 16, previous: nil), 16)
        // The concentric icon renders 20pt wide.
        XCTAssertEqual(StatusBarUIManager.pinnedLength(forImageWidth: 20, previous: nil), 20)
    }

    func testPinnedLengthNeverReservesMoreThanAGridStep() {
        for width in stride(from: CGFloat(1), through: CGFloat(120), by: 0.5) {
            let length = StatusBarUIManager.pinnedLength(forImageWidth: width, previous: nil)
            XCTAssertGreaterThanOrEqual(length, width, "width \(width) would be clipped")
            XCTAssertLessThan(length - width, 4, "width \(width) reserves a whole grid step of dead space")
        }
    }

    // MARK: - Stability across refreshes

    func testOrdinaryDataChangesDoNotMoveThePinnedLength() {
        // Percentage style, "5%" → "45%" → "5%": the width varies with the digits, the
        // pinned length must not follow it back down.
        let narrow = StatusBarUIManager.pinnedLength(forImageWidth: 25, previous: nil)
        let wide = StatusBarUIManager.pinnedLength(forImageWidth: 31, previous: narrow)
        let narrowAgain = StatusBarUIManager.pinnedLength(forImageWidth: 25, previous: wide)

        XCTAssertEqual(wide, narrowAgain, "length shrank back after the value shrank")
        XCTAssertGreaterThanOrEqual(wide, narrow)
    }

    func testRepeatedUpdatesAtTheSameWidthAreIdempotent() {
        var length = StatusBarUIManager.pinnedLength(forImageWidth: 22, previous: nil)
        for _ in 0..<10 {
            let next = StatusBarUIManager.pinnedLength(forImageWidth: 22, previous: length)
            XCTAssertEqual(next, length)
            length = next
        }
    }

    func testSubPointRenderingDifferencesAreAbsorbed() {
        let a = StatusBarUIManager.pinnedLength(forImageWidth: 21.4, previous: nil)
        let b = StatusBarUIManager.pinnedLength(forImageWidth: 21.9, previous: a)
        XCTAssertEqual(a, b)
    }

    func testDegenerateWidthsStayPositive() {
        XCTAssertGreaterThan(StatusBarUIManager.pinnedLength(forImageWidth: 0, previous: nil), 0)
        XCTAssertGreaterThan(StatusBarUIManager.pinnedLength(forImageWidth: -5, previous: nil), 0)
    }

    // MARK: - Config signature

    func testSignatureChangesWithEveryWidthAffectingSetting() {
        let base = MultiProfileDisplayConfig()
        let baseSignature = StatusBarUIManager.lengthPinSignature(for: base)

        var style = base
        style.iconStyle = base.iconStyle == .compact ? .percentage : .compact
        XCTAssertNotEqual(StatusBarUIManager.lengthPinSignature(for: style), baseSignature)

        var label = base
        label.showProfileLabel.toggle()
        XCTAssertNotEqual(StatusBarUIManager.lengthPinSignature(for: label), baseSignature)

        var week = base
        week.showWeek.toggle()
        XCTAssertNotEqual(StatusBarUIManager.lengthPinSignature(for: week), baseSignature)

        var pace = base
        pace.showPaceMarker.toggle()
        XCTAssertNotEqual(StatusBarUIManager.lengthPinSignature(for: pace), baseSignature)
    }

    func testSignatureIgnoresSettingsThatDoNotChangeWidth() {
        let base = MultiProfileDisplayConfig()
        var colored = base
        colored.useSystemColor.toggle()
        XCTAssertEqual(
            StatusBarUIManager.lengthPinSignature(for: colored),
            StatusBarUIManager.lengthPinSignature(for: base)
        )
    }
}
