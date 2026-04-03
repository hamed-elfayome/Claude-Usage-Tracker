import XCTest
@testable import Claude_Usage

final class OpenAIUsageTests: XCTestCase {
    func testUsedAmountConversion() {
        let usage = OpenAIUsage(
            currentSpendCents: 1250,
            currency: "usd",
            resetsAt: Date().addingTimeInterval(86400 * 27),
            dailyCostCents: ["2026-04-01": 500, "2026-04-02": 750],
            tokensByModel: nil,
            lastUpdated: Date()
        )
        XCTAssertEqual(usage.usedAmount, 12.50, accuracy: 0.001)
    }

    func testSortedDailyCosts() {
        let usage = OpenAIUsage(
            currentSpendCents: 1250,
            currency: "usd",
            resetsAt: Date(),
            dailyCostCents: ["2026-04-03": 300, "2026-04-01": 500, "2026-04-02": 450],
            tokensByModel: nil,
            lastUpdated: Date()
        )
        let sorted = usage.sortedDailyCosts
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].cents, 500)
        XCTAssertEqual(sorted[2].cents, 300)
    }

    func testCodableRoundTrip() throws {
        let usage = OpenAIUsage(
            currentSpendCents: 830,
            currency: "usd",
            resetsAt: Date(),
            dailyCostCents: ["2026-04-03": 120],
            tokensByModel: ["gpt-4o": OpenAIModelTokens(inputTokens: 5000, outputTokens: 2000, cachedTokens: 1000)],
            lastUpdated: Date()
        )
        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(OpenAIUsage.self, from: data)
        XCTAssertEqual(usage, decoded)
    }

    func testModelTokensTotalTokens() {
        let tokens = OpenAIModelTokens(inputTokens: 5000, outputTokens: 2000, cachedTokens: 1000)
        XCTAssertEqual(tokens.totalTokens, 7000)
    }
}
