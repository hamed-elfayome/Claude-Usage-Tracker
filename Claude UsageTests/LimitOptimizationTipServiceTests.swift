import XCTest
@testable import Claude_Usage

final class LimitOptimizationTipServiceTests: XCTestCase {

    func testCatalogContainsAll21Tips() {
        let catalog = LimitOptimizationTip.catalog
        XCTAssertEqual(catalog.count, 21, "Catalog should contain exactly 21 tips")

        let claudeAITips = LimitOptimizationTip.tips(for: .claudeAI)
        XCTAssertEqual(claudeAITips.count, 9, "Should have 9 Claude.ai tips")

        let claudeCodeTips = LimitOptimizationTip.tips(for: .claudeCode)
        XCTAssertEqual(claudeCodeTips.count, 8, "Should have 8 Claude Code tips")

        let claudeCoworkTips = LimitOptimizationTip.tips(for: .claudeCowork)
        XCTAssertEqual(claudeCoworkTips.count, 4, "Should have 4 Claude Cowork tips")
    }

    func testTipCategoriesAreCorrect() {
        let allTips = LimitOptimizationTip.catalog

        for tip in allTips {
            XCTAssertFalse(tip.id.isEmpty)
            XCTAssertFalse(tip.titleKey.isEmpty)
            XCTAssertFalse(tip.detailKey.isEmpty)
        }
    }

    func testRecommendationEngineReturnsTipsForHighUsage() {
        let service = LimitOptimizationTipService.shared
        let tips = service.recommendedTips(
            sessionPercentage: 95,
            isPeakHours: false,
            hasClaudeCodeCredentials: true,
            hasMCPServers: true,
            noPlanConfigured: true,
            repeatedNearLimit: true
        )

        XCTAssertFalse(tips.isEmpty, "Should return tips for high usage")
    }

    func testRecommendationEngineReturnsOffPeakTipDuringPeakHours() {
        let service = LimitOptimizationTipService.shared
        let tips = service.recommendedTips(
            sessionPercentage: 50,
            isPeakHours: true,
            hasClaudeCodeCredentials: false,
            hasMCPServers: false,
            noPlanConfigured: false,
            repeatedNearLimit: false
        )

        let offPeakTip = tips.first { $0.id == "claude-ai-off-peak" }
        XCTAssertNotNil(offPeakTip, "Should recommend off-peak tip during peak hours")
    }

    func testRecommendationEngineReturnsMCPForMCPUsers() {
        let service = LimitOptimizationTipService.shared
        let tips = service.recommendedTips(
            sessionPercentage: 50,
            isPeakHours: false,
            hasClaudeCodeCredentials: true,
            hasMCPServers: true,
            noPlanConfigured: false,
            repeatedNearLimit: false
        )

        let mcpTip = tips.first { $0.id == "claude-code-disconnect-mcp" }
        XCTAssertNotNil(mcpTip, "Should recommend MCP disconnection for users with MCPs")
    }

    func testRotatingTipReturnsActionableTip() {
        let service = LimitOptimizationTipService.shared
        let tip = service.rotatingTip(
            sessionPercentage: 85,
            isPeakHours: false,
            lastTipId: nil
        )

        XCTAssertNotNil(tip, "Should return a rotating tip")
        XCTAssertTrue(tip?.actionStyle == .actionable || tip?.actionStyle == .checklist, "Rotating tip should be actionable or checklist")
    }

    func testActionableTipsFiltering() {
        let claudeAIActionable = LimitOptimizationTip.actionableTips(for: .claudeAI)
        let claudeCodeActionable = LimitOptimizationTip.actionableTips(for: .claudeCode)
        let coworkActionable = LimitOptimizationTip.actionableTips(for: .claudeCowork)

        XCTAssertEqual(claudeAIActionable.count, 2, "Claude.ai should have 2 actionable tips")
        XCTAssertEqual(claudeCodeActionable.count, 5, "Claude Code should have 5 actionable/checklist tips")
        XCTAssertEqual(coworkActionable.count, 0, "Cowork should have 0 actionable tips")
    }
}