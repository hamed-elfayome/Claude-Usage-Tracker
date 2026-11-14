import Foundation
import XCTest
@testable import Claude_Usage

@MainActor
final class AutoStartSessionParsingTests: XCTestCase {
    func test_usageParsingPreservesModelMetricsAndResetTimes() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let service = AutoStartSessionService(
            session: session, profiles: { [] }, saveUsage: { _, _ in },
            notify: { _, _, _ in XCTFail("Parsing must not notify") },
            logError: { XCTFail($0) }
        )
        let data = Data("""
        {
          "five_hour": {"utilization": 12.5, "resets_at": "2099-01-01T00:00:00.000Z"},
          "seven_day": {"utilization": 25, "resets_at": "2099-01-02T00:00:00.000Z"},
          "seven_day_opus": {"utilization": 10},
          "seven_day_sonnet": {"utilization": 20, "resets_at": "2099-01-03T00:00:00.000Z"}
        }
        """.utf8)

        let (usage, hasOpenWindow) = try service.parseUsageResponse(data)

        XCTAssertTrue(hasOpenWindow)
        XCTAssertEqual(usage.sessionLimit, 0)
        XCTAssertEqual(usage.sessionPercentage, 12.5)
        XCTAssertEqual(usage.sessionResetTime.timeIntervalSince1970, 4_070_908_800)
        XCTAssertEqual(usage.weeklyLimit, 1_000_000)
        XCTAssertEqual(usage.weeklyPercentage, 25)
        XCTAssertEqual(usage.weeklyTokensUsed, 250_000)
        XCTAssertEqual(usage.weeklyResetTime.timeIntervalSince1970, 4_070_995_200)
        XCTAssertEqual(usage.opusWeeklyPercentage, 10)
        XCTAssertEqual(usage.opusWeeklyTokensUsed, 100_000)
        XCTAssertEqual(usage.sonnetWeeklyPercentage, 20)
        XCTAssertEqual(usage.sonnetWeeklyTokensUsed, 200_000)
        XCTAssertEqual(usage.sonnetWeeklyResetTime?.timeIntervalSince1970, 4_071_081_600)
        XCTAssertNil(usage.costUsed)
        XCTAssertNil(usage.costLimit)
    }
}
