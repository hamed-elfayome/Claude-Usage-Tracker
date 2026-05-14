//
//  ClaudeAPIServiceTests.swift
//  Claude Usage Tests
//
//  Tests for ClaudeAPIService response type decoding.
//  Uses inline JSON Data fixtures (no external files) following the
//  existing pattern in ClaudeUsageTests.swift and URLBuilderTests.swift.
//

import XCTest
@testable import Claude_Usage

final class ClaudeAPIServiceTests: XCTestCase {

    // MARK: - RunBudgetResponse Decoding

    /// Happy-path decode using the exact HAR fixture body.
    func testRunBudgetResponseDecodeHappyPath() throws {
        let json = #"{"limit":"25","unified_billing_enabled":true,"used":"0"}"#
        let data = Data(json.utf8)

        let response = try JSONDecoder().decode(ClaudeAPIService.RunBudgetResponse.self, from: data)

        XCTAssertEqual(response.limit, "25")
        XCTAssertEqual(response.used, "0")
        XCTAssertTrue(response.unifiedBillingEnabled)
    }

    /// Integer run counts: limitRuns and usedRuns parse the string fields as Int.
    func testRunBudgetResponseRunCounts() throws {
        let json = #"{"limit":"25","unified_billing_enabled":true,"used":"0"}"#
        let response = try JSONDecoder().decode(
            ClaudeAPIService.RunBudgetResponse.self, from: Data(json.utf8)
        )

        XCTAssertEqual(response.limitRuns, 25)
        XCTAssertEqual(response.usedRuns,  0)
    }

    /// Non-integer used value (decimal string): Int("12.50") returns nil, so usedRuns falls back to 0.
    func testRunBudgetResponseNonIntegerUsedFallsBackToZero() throws {
        let json = #"{"limit":"25","unified_billing_enabled":true,"used":"12.50"}"#
        let response = try JSONDecoder().decode(
            ClaudeAPIService.RunBudgetResponse.self, from: Data(json.utf8)
        )

        XCTAssertEqual(response.usedRuns,  0)   // Int("12.50") == nil → 0
        XCTAssertEqual(response.limitRuns, 25)
    }

    /// When unified_billing_enabled is false, budget should not be applied (caller checks).
    func testRunBudgetResponseUnifiedBillingDisabled() throws {
        let json = #"{"limit":"25","unified_billing_enabled":false,"used":"0"}"#
        let response = try JSONDecoder().decode(
            ClaudeAPIService.RunBudgetResponse.self, from: Data(json.utf8)
        )

        XCTAssertFalse(response.unifiedBillingEnabled)
        XCTAssertEqual(response.limitRuns, 25)
    }

    /// Malformed string (non-numeric) gracefully falls back to 0.
    func testRunBudgetResponseMalformedValues() throws {
        let json = #"{"limit":"abc","unified_billing_enabled":true,"used":"xyz"}"#
        let response = try JSONDecoder().decode(
            ClaudeAPIService.RunBudgetResponse.self, from: Data(json.utf8)
        )

        // Int("abc") = nil → defaults to 0
        XCTAssertEqual(response.usedRuns,  0)
        XCTAssertEqual(response.limitRuns, 0)
    }

    /// Missing fields should throw (all three fields are non-optional in the struct).
    func testRunBudgetResponseMissingFieldsThrows() {
        let json = #"{"limit":"25","unified_billing_enabled":true}"# // missing "used"
        XCTAssertThrowsError(
            try JSONDecoder().decode(ClaudeAPIService.RunBudgetResponse.self, from: Data(json.utf8))
        )
    }

    // MARK: - extra_usage Parsing (Fix #219)

    func testExtraUsageFromHARParsesToCostFields() throws {
        let harJSON = """
        {
            "five_hour": null,
            "seven_day": null,
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": null,
            "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 25000,
                "used_credits": 1504.0,
                "utilization": 6.016,
                "currency": "USD"
            }
        }
        """.data(using: .utf8)!

        let service = ClaudeAPIService()
        let usage = try service.parseUsageResponse(harJSON)

        XCTAssertEqual(usage.costUsed ?? 0,        1504.0,  accuracy: 0.001)
        XCTAssertEqual(usage.costLimit ?? 0,       25000.0, accuracy: 0.001)
        XCTAssertEqual(usage.costCurrency,         "USD")
        XCTAssertEqual(usage.costUtilization ?? 0, 6.016,   accuracy: 0.001)
    }

    // MARK: - ClaudeUsage Routine Runs Fields

    /// New fields default to nil in ClaudeUsage.empty.
    func testClaudeUsageEmptyHasNilRoutineRuns() {
        let empty = ClaudeUsage.empty
        XCTAssertNil(empty.routineRunsUsed)
        XCTAssertNil(empty.routineRunsLimit)
    }

    /// ClaudeUsage round-trips through Codable with routine runs fields populated.
    func testClaudeUsageRoutineRunsCodableRoundTrip() throws {
        var usage = ClaudeUsage.empty
        usage.routineRunsUsed  = 3
        usage.routineRunsLimit = 25

        let data    = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: data)

        XCTAssertEqual(decoded.routineRunsUsed,  3)
        XCTAssertEqual(decoded.routineRunsLimit, 25)
    }
}
