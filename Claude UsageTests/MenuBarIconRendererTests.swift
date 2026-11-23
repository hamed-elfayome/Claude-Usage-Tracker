import AppKit
import XCTest
@testable import Claude_Usage

@MainActor
final class MenuBarIconRendererTests: XCTestCase {
    func testUnreadWeekIsNotRenderedAsZeroUsedOrFullRemaining() throws {
        let renderer = MenuBarIconRenderer()
        var reading = ClaudeUsage.empty
        reading.weeklyPercentage = 0
        reading.weeklyResetKnown = false
        for remaining in [false, true] {
            let config = MenuBarIconConfiguration(showRemainingPercentage: remaining)
            var metric = MetricIconConfig.weekDefault
            metric.iconStyle = .percentageOnly
            func render(_ usage: ClaudeUsage?) -> NSImage {
                renderer.createImage(for: .week, config: metric, globalConfig: config, usage: usage,
                                     apiUsage: nil, isDarkMode: false, colorMode: .monochrome,
                                     singleColorHex: "", showIconName: false, showNextSessionTime: false)
            }
            let unread = render(nil)
            XCTAssertEqual(unread.accessibilityDescription, "popover.no_usage_data".localized)
            XCTAssertNotEqual(try XCTUnwrap(unread.tiffRepresentation), try XCTUnwrap(render(reading).tiffRepresentation))
        }
    }
}
