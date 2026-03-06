import XCTest
@testable import Claude_Usage

final class MenuBarIconRendererTests: XCTestCase {

    private let renderer = MenuBarIconRenderer()

    // MARK: - Smoke Tests

    /// Verifies createImage returns a valid, non-zero-sized image for the circular icon style.
    /// Arc sweep direction (clockwise from 12 o'clock) is validated visually;
    /// this test guards against regressions that crash the renderer.
    func testCreateImage_CircularSession_ReturnsValidImage() {
        let usage = ClaudeUsage(
            sessionTokensUsed: 50_000,
            sessionLimit: 100_000,
            sessionPercentage: 50.0,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 200_000,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 20.0,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
        let config = MetricIconConfig(
            metricType: .session,
            isEnabled: true,
            iconStyle: .icon,
            order: 0
        )
        let globalConfig = MenuBarIconConfiguration.default

        let image = renderer.createImage(
            for: .session,
            config: config,
            globalConfig: globalConfig,
            usage: usage,
            apiUsage: nil,
            isDarkMode: false,
            monochromeMode: false,
            showIconName: false,
            showNextSessionTime: false
        )

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testCreateImage_CircularWeek_ReturnsValidImage() {
        let usage = ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 100_000,
            sessionPercentage: 0,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 800_000,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 80.0,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
        let config = MetricIconConfig(
            metricType: .week,
            isEnabled: true,
            iconStyle: .icon,
            order: 1
        )
        let globalConfig = MenuBarIconConfiguration.default

        let image = renderer.createImage(
            for: .week,
            config: config,
            globalConfig: globalConfig,
            usage: usage,
            apiUsage: nil,
            isDarkMode: false,
            monochromeMode: false,
            showIconName: true,
            showNextSessionTime: false
        )

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    /// Smoke test for all icon styles to ensure none crash after arc direction changes
    func testCreateImage_AllStyles_DoNotCrash() {
        let usage = ClaudeUsage(
            sessionTokensUsed: 75_000,
            sessionLimit: 100_000,
            sessionPercentage: 75.0,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 500_000,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 50.0,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )

        let styles: [MenuBarIconStyle] = [.battery, .progressBar, .percentageOnly, .icon, .compact]
        let globalConfig = MenuBarIconConfiguration.default

        for style in styles {
            let config = MetricIconConfig(
                metricType: .session,
                isEnabled: true,
                iconStyle: style,
                order: 0
            )
            let image = renderer.createImage(
                for: .session,
                config: config,
                globalConfig: globalConfig,
                usage: usage,
                apiUsage: nil,
                isDarkMode: false,
                monochromeMode: false,
                showIconName: false,
                showNextSessionTime: false
            )
            XCTAssertGreaterThan(image.size.width, 0, "Style \(style) produced zero-width image")
        }
    }
}
