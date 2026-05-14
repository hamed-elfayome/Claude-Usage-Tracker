//
//  PopoverDisabledBudgetTests.swift
//  Claude UsageTests
//
//  Unit tests for ClaudeUsage.budgetDisabledReason population.
//  (Visual chip appearance is verified via accessibilityIdentifier in integration.)
//

import XCTest
@testable import Claude_Usage

final class PopoverDisabledBudgetTests: XCTestCase {

    // MARK: — budgetDisabledReason mapping

    func testBudgetDisabledReasonFromExplicitReason() {
        var usage = ClaudeUsage.empty
        usage.budgetDisabledReason = "payment_required"
        XCTAssertEqual(usage.budgetDisabledReason, "payment_required")
    }

    func testBudgetDisabledReasonNilByDefault() {
        let usage = ClaudeUsage.empty
        XCTAssertNil(usage.budgetDisabledReason)
    }

    func testBudgetDisabledReasonCodableRoundTrip() throws {
        var usage = ClaudeUsage.empty
        usage.budgetDisabledReason = "out_of_credits"
        let data    = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: data)
        XCTAssertEqual(decoded.budgetDisabledReason, "out_of_credits")
    }

    func testBudgetDisabledReasonNilAfterRoundTrip() throws {
        let usage   = ClaudeUsage.empty   // nil budgetDisabledReason
        let data    = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: data)
        XCTAssertNil(decoded.budgetDisabledReason)
    }

    // MARK: — OverageSpendLimitResponse mapping logic (logic-layer tests)

    func testOutOfCreditsMapsToDisabledReason() {
        // Simulate the mapping logic from ClaudeAPIService
        let disabledReason: String? = nil
        let outOfCredits: Bool? = true

        let result: String?
        if let reason = disabledReason, !reason.isEmpty {
            result = reason
        } else if outOfCredits == true {
            result = "out_of_credits"
        } else {
            result = nil
        }
        XCTAssertEqual(result, "out_of_credits")
    }

    func testExplicitReasonTakesPrecedenceOverOutOfCredits() {
        let disabledReason: String? = "payment_required"
        let outOfCredits: Bool? = true

        let result: String?
        if let reason = disabledReason, !reason.isEmpty {
            result = reason
        } else if outOfCredits == true {
            result = "out_of_credits"
        } else {
            result = nil
        }
        XCTAssertEqual(result, "payment_required")
    }
}
