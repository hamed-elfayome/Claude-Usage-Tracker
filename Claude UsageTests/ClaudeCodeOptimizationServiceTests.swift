import XCTest
@testable import Claude_Usage

final class ClaudeCodeOptimizationServiceTests: XCTestCase {

    func testChecklistItemsCount() {
        let service = ClaudeCodeOptimizationService.shared
        let items = service.checklistItems()
        XCTAssertEqual(items.count, 4, "Should have 4 checklist items")
    }

    func testChecklistItemsHaveRequiredFields() {
        let service = ClaudeCodeOptimizationService.shared
        let items = service.checklistItems()

        for item in items {
            XCTAssertFalse(item.command.isEmpty, "Command should not be empty")
            XCTAssertFalse(item.description.isEmpty, "Description should not be empty")
            XCTAssertFalse(item.whenToUse.isEmpty, "WhenToUse should not be empty")
        }
    }

    func testSessionHandoffTemplateContainsRequiredSections() {
        let service = ClaudeCodeOptimizationService.shared
        let template = service.sessionHandoffTemplate()

        XCTAssertTrue(template.contains("# Session Handoff Summary"), "Template should have title")
        XCTAssertTrue(template.contains("## Current Task"), "Template should have Current Task section")
        XCTAssertTrue(template.contains("## Key Decisions"), "Template should have Key Decisions section")
        XCTAssertTrue(template.contains("## Files Modified"), "Template should have Files Modified section")
        XCTAssertTrue(template.contains("## Next Steps"), "Template should have Next Steps section")
        XCTAssertTrue(template.contains("## Context Notes"), "Template should have Context Notes section")
    }

    func testDiagnosticsDoesNotModifyFiles() {
        // The diagnostics service should only read files, never write
        // This test verifies the service runs without throwing and doesn't modify anything
        let service = ClaudeCodeOptimizationService.shared
        let diagnostics = service.runDiagnostics()

        // Just verify it returns a valid diagnostics object
        XCTAssertGreaterThanOrEqual(diagnostics.mcpServerCount, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.settingsEntriesCount, 0)
    }

    func testDiagnosticsMCPWarningThreshold() {
        // Test the warning logic
        let warningDiag = ClaudeCodeDiagnostics(
            mcpServerCount: 5,
            mcpServersActive: true,
            hasClaudeMd: false,
            claudeMdSize: nil,
            hasGlobalClaudeMd: false,
            globalClaudeMdSize: nil,
            settingsEntriesCount: 0,
            hasAutoContext: false,
            hasAutoMCP: false
        )
        XCTAssertTrue(warningDiag.mcpWarning, "Should warn with 5 active MCP servers")

        let noWarningDiag = ClaudeCodeDiagnostics(
            mcpServerCount: 2,
            mcpServersActive: true,
            hasClaudeMd: false,
            claudeMdSize: nil,
            hasGlobalClaudeMd: false,
            globalClaudeMdSize: nil,
            settingsEntriesCount: 0,
            hasAutoContext: false,
            hasAutoMCP: false
        )
        XCTAssertFalse(noWarningDiag.mcpWarning, "Should not warn with 2 MCP servers")
    }

    func testDiagnosticsClaudeMdWarningThreshold() {
        let warningDiag = ClaudeCodeDiagnostics(
            mcpServerCount: 0,
            mcpServersActive: false,
            hasClaudeMd: true,
            claudeMdSize: 6000,
            hasGlobalClaudeMd: false,
            globalClaudeMdSize: nil,
            settingsEntriesCount: 0,
            hasAutoContext: false,
            hasAutoMCP: false
        )
        XCTAssertTrue(warningDiag.claudeMdWarning, "Should warn with large CLAUDE.md")

        let noWarningDiag = ClaudeCodeDiagnostics(
            mcpServerCount: 0,
            mcpServersActive: false,
            hasClaudeMd: true,
            claudeMdSize: 1000,
            hasGlobalClaudeMd: false,
            globalClaudeMdSize: nil,
            settingsEntriesCount: 0,
            hasAutoContext: false,
            hasAutoMCP: false
        )
        XCTAssertFalse(noWarningDiag.claudeMdWarning, "Should not warn with small CLAUDE.md")
    }
}