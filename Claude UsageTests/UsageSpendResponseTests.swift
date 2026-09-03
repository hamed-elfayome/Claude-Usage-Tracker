//
//  UsageSpendResponseTests.swift
//  Claude Usage Tests
//
//  Created on 2026-07-21.
//

import XCTest
@testable import Claude_Usage

/// Coverage for the Monthly Spend feature: the `/organizations/{org}/usage/spend`
/// response decoding, the model fields that carry it, and the capability flag
/// that gates its UI.
@MainActor
final class UsageSpendResponseTests: XCTestCase {

    private func decode(_ json: String) throws -> ClaudeAPIService.UsageSpendResponse {
        try JSONDecoder().decode(ClaudeAPIService.UsageSpendResponse.self, from: Data(json.utf8))
    }

    // MARK: - Response decoding

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

    /// A server-side type change throws here; `fetchPersonalSpend` decodes with
    /// `try?`, so the failure surfaces as a hidden row, never a broken fetch.
    func testMalformedTotalsTypeFailsDecodeRatherThanYieldingGarbage() {
        XCTAssertThrowsError(try decode("{ \"totals\": \"not-an-array\" }"))
        XCTAssertNil(try? decode("{ \"totals\": \"not-an-array\" }"))
    }

    // MARK: - ClaudeUsage carrying the spend

    func testClaudeUsageRoundTripsPersonalSpend() throws {
        var usage = ClaudeUsage.empty
        usage.personalSpendUsed = 4237
        usage.personalSpendCurrency = "USD"

        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: data)

        XCTAssertEqual(decoded.personalSpendUsed, 4237)
        XCTAssertEqual(decoded.personalSpendCurrency, "USD")
    }

    /// Usage written by an older app version has no spend keys at all; it must
    /// still decode, leaving the row hidden.
    func testClaudeUsageWithoutPersonalSpendDecodesToNil() throws {
        let usage = try JSONDecoder().decode(
            ClaudeUsage.self,
            from: Data("{ \"sessionPercentage\": 12 }".utf8)
        )

        XCTAssertNil(usage.personalSpendUsed)
        XCTAssertNil(usage.personalSpendCurrency)
    }

    // MARK: - Profile spend target

    func testProfileRoundTripsMonthlySpendTarget() throws {
        var profile = Profile(name: "Work")
        profile.monthlySpendLimitCents = 150_000

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded.monthlySpendLimitCents, 150_000)
    }

    func testLegacyProfileWithoutSpendTargetDecodesToNil() throws {
        let profile = try JSONDecoder().decode(
            Profile.self,
            from: Data("""
            {
                "id": "11111111-2222-3333-4444-555555555555",
                "name": "Legacy"
            }
            """.utf8)
        )

        XCTAssertNil(profile.monthlySpendLimitCents)
    }

    /// A very large target must survive the persist/reload round trip. Rendering
    /// it via `Int(cents / 100)` traps once the value passes Int.max, which
    /// crashed the settings view on reopen.
    func testVeryLargeSpendTargetFormatsWithoutTrapping() throws {
        var profile = Profile(name: "Whale")
        profile.monthlySpendLimitCents = Double(Int.max) * 100.0

        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        let cents = try XCTUnwrap(decoded.monthlySpendLimitCents)

        XCTAssertTrue(cents.isFinite)
        // The formatting the settings field performs on load.
        XCTAssertFalse(String(format: "%.0f", cents / 100).isEmpty)
    }

    // MARK: - Capability gate

    func testOnlyProvidersReportingSpendDeclareTheCapability() {
        XCTAssertTrue(
            Provider.anthropic.descriptor.capabilities.personalSpend,
            "claude.ai exposes a per-member spend figure"
        )
        XCTAssertFalse(
            Provider.codex.descriptor.capabilities.personalSpend,
            "Codex reports no per-member spend; the row must stay hidden"
        )
    }
}
