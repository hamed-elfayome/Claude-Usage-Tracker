//
//  UsageSpendResponseTests.swift
//  Claude Usage Tests
//
//  Created on 2026-07-21.
//

import XCTest
@testable import Claude_Usage

/// Decoding tests for the `/organizations/{org}/usage/spend` response, which
/// backs the Monthly Spend row in the popover.
@MainActor
final class UsageSpendResponseTests: XCTestCase {

    private func decode(_ json: String) throws -> ClaudeAPIService.UsageSpendResponse {
        try JSONDecoder().decode(ClaudeAPIService.UsageSpendResponse.self, from: Data(json.utf8))
    }

    // MARK: - Decoding Tests

    func testDecodesCurrencyAndTotals() throws {
        let response = try decode("""
        {
            "currency": "usd",
            "totals": [
                { "product_surface": "claude_ai", "cost_minor_units": 123456.78 },
                { "product_surface": "claude_code", "cost_minor_units": 100 }
            ]
        }
        """)

        XCTAssertEqual(response.currency, "usd")
        XCTAssertEqual(response.totals?.count, 2)

        let grandTotal = response.totals?.reduce(0.0) { $0 + ($1.costMinorUnits ?? 0) } ?? 0
        XCTAssertEqual(grandTotal, 123556.78, accuracy: 0.001)
    }

    func testToleratesUnknownFieldsAndMissingCost() throws {
        let response = try decode("""
        {
            "currency": "usd",
            "totals": [
                { "product_surface": "claude_ai", "unexpected_field": true }
            ]
        }
        """)

        XCTAssertEqual(response.totals?.count, 1)
        XCTAssertNil(response.totals?.first?.costMinorUnits)
    }

    func testDecodesEmptyResponse() throws {
        let response = try decode("{}")

        XCTAssertNil(response.currency)
        XCTAssertNil(response.totals)
    }
}
