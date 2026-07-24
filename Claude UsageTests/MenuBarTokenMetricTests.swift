import XCTest
@testable import Claude_Usage

final class MenuBarTokenMetricTests: XCTestCase {

    func testTokenMetricCasesExist() {
        XCTAssertEqual(MenuBarMetricType(rawValue: "tokensAllTime"), .tokensAllTime)
        XCTAssertEqual(MenuBarMetricType(rawValue: "tokens7Days"), .tokens7Days)
        XCTAssertEqual(MenuBarMetricType(rawValue: "tokens30Days"), .tokens30Days)
    }

    func testTokenMetricProperties() {
        XCTAssertEqual(MenuBarMetricType.tokensAllTime.prefixText, "∑")
        XCTAssertEqual(MenuBarMetricType.tokens7Days.prefixText, "7d")
        XCTAssertEqual(MenuBarMetricType.tokens30Days.prefixText, "30d")
        XCTAssertTrue(MenuBarMetricType.tokensAllTime.isTokenMetric)
        XCTAssertFalse(MenuBarMetricType.session.isTokenMetric)
    }

    func testTokenTopLabel() {
        XCTAssertEqual(MenuBarMetricType.tokensAllTime.tokenTopLabel, "ALL")
        XCTAssertEqual(MenuBarMetricType.tokens7Days.tokenTopLabel, "7D")
        XCTAssertEqual(MenuBarMetricType.tokens30Days.tokenTopLabel, "30D")
    }

    func testTokenStatsValueSelection() {
        let s = TokenStats(allTime: 100, last7Days: 20, last30Days: 30, isAvailable: true)
        XCTAssertEqual(s.value(for: .tokensAllTime), 100)
        XCTAssertEqual(s.value(for: .tokens7Days), 20)
        XCTAssertEqual(s.value(for: .tokens30Days), 30)
        XCTAssertNil(s.value(for: .session))
    }

    func testDefaultConfigurationContainsTokenMetricsDisabled() {
        let config = MenuBarIconConfiguration.default
        for t in [MenuBarMetricType.tokensAllTime, .tokens7Days, .tokens30Days] {
            let mc = config.config(for: t)
            XCTAssertNotNil(mc, "default metrics missing \(t.rawValue)")
            XCTAssertEqual(mc?.isEnabled, false)
        }
    }

    func testDecodingLegacyConfigBackfillsTokenMetrics() throws {
        // Legacy config JSON with only session/week/api metrics
        let legacy = """
        {
          "colorMode": "multiColor",
          "singleColorHex": "#00BFFF",
          "showIconNames": true,
          "metrics": [
            { "metricType": "session", "isEnabled": true, "iconStyle": "battery", "order": 0,
              "weekDisplayMode": "percentage", "apiDisplayMode": "remaining", "showNextSessionTime": false }
          ]
        }
        """
        let config = try JSONDecoder().decode(MenuBarIconConfiguration.self, from: Data(legacy.utf8))
        XCTAssertNotNil(config.config(for: .tokensAllTime))
        XCTAssertNotNil(config.config(for: .tokens7Days))
        XCTAssertNotNil(config.config(for: .tokens30Days))
    }
}
