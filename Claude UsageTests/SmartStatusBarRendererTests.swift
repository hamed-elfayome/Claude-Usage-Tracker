import XCTest
@testable import Claude_Usage

final class SmartStatusBarRendererTests: XCTestCase {

    func testNoProfilesAboveThresholdReturnsEmpty() {
        let profiles = [
            makeClaudeMaxProfile(name: "Low", percentage: 30),
            makeClaudeMaxProfile(name: "Medium", percentage: 55)
        ]
        let result = SmartStatusBarRenderer.profilesForStatusBar(profiles, threshold: 60, maxItems: 4)
        XCTAssertTrue(result.isEmpty)
    }

    func testProfilesAboveThresholdReturned() {
        let profiles = [
            makeClaudeMaxProfile(name: "High", percentage: 85),
            makeClaudeMaxProfile(name: "Low", percentage: 30),
            makeClaudeMaxProfile(name: "Critical", percentage: 95)
        ]
        let result = SmartStatusBarRenderer.profilesForStatusBar(profiles, threshold: 60, maxItems: 4)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Critical")
        XCTAssertEqual(result[1].name, "High")
    }

    func testMaxItemsRespected() {
        let profiles = (1...6).map { i in
            makeClaudeMaxProfile(name: "P\(i)", percentage: Double(60 + i * 5))
        }
        let result = SmartStatusBarRenderer.profilesForStatusBar(profiles, threshold: 60, maxItems: 3)
        XCTAssertEqual(result.count, 3)
    }

    func testColorForPercentage() {
        XCTAssertEqual(SmartStatusBarRenderer.alertLevel(for: 50), .none)
        XCTAssertEqual(SmartStatusBarRenderer.alertLevel(for: 72), .warning)
        XCTAssertEqual(SmartStatusBarRenderer.alertLevel(for: 95), .critical)
    }

    func testAPIProfileWithNoBudgetExcluded() {
        var profile = Profile(name: "API", providerType: .claudeAPI)
        profile.apiUsage = APIUsage(
            currentSpendCents: 5000,
            resetsAt: Date(),
            prepaidCreditsCents: 10000,
            currency: "usd",
            apiTokenCostCents: nil,
            apiCostByModel: nil,
            costBySource: nil,
            dailyCostCents: nil
        )
        XCTAssertNil(profile.effectivePercentageForThreshold)
    }

    // MARK: - Helpers

    private func makeClaudeMaxProfile(name: String, percentage: Double) -> Profile {
        var profile = Profile(name: name, providerType: .claudeMax)
        profile.claudeUsage = ClaudeUsage(
            sessionTokensUsed: 0, sessionLimit: 0,
            sessionPercentage: percentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 0, weeklyLimit: 0,
            weeklyPercentage: percentage,
            weeklyResetTime: Date(),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: percentage,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            lastUpdated: Date(),
            userTimezone: .current
        )
        return profile
    }
}
