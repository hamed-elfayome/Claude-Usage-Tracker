import XCTest
@testable import Claude_Usage

/// SuperGrok weekly quota: the CLI billing payload maps to used percent and
/// reset time, and a missing or non-weekly reading is not stored as zero.
final class GrokProviderTests: XCTestCase {

    func testWeeklyUsedPercentAndReset() throws {
        let usage = try usage(from: """
        {
          "config": {
            "creditUsagePercent": 37,
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "start": "2026-11-20T00:45:02.245+00:00",
              "end": "2026-11-27T00:45:02.245+00:00"
            },
            "prepaidBalance": { "val": 0 }
          },
          "subscription_tier": "SuperGrok Plus"
        }
        """)

        XCTAssertEqual(usage.weeklyPercentage, 37)
        XCTAssertEqual(100 - usage.weeklyPercentage, 63)
        XCTAssertEqual(usage.weeklyResetTime, date("2026-11-27T00:45:02.245+00:00"))
        XCTAssertTrue(usage.weeklyResetKnown)
        XCTAssertFalse(usage.hasSessionLimit)
        XCTAssertTrue(usage.hasWeeklyLimit)
        XCTAssertEqual(usage.weeklyTokensUsed, 0)
        XCTAssertEqual(usage.weeklyLimit, 0)
        XCTAssertEqual(usage.planType, "SuperGrok Plus")
    }

    func testExplicitZeroIsNotMissing() throws {
        let usage = try usage(from: weekly(percent: "0"))
        XCTAssertEqual(usage.weeklyPercentage, 0)
        XCTAssertTrue(usage.hasWeeklyLimit)
    }

    func testFullyUsed() throws {
        let usage = try usage(from: weekly(percent: "100"))
        XCTAssertEqual(usage.weeklyPercentage, 100)
    }

    func testMissingPercentIsUnavailable() {
        XCTAssertNil(GrokBillingParser.quota(from: data("""
        {"config":{"prepaidBalance":{"val":1200},"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-11-27T00:00:00Z"}}}
        """)))
    }

    func testMalformedPercentIsUnavailable() {
        XCTAssertNil(GrokBillingParser.quota(from: data(weekly(percent: "\"17\""))))
        XCTAssertNil(GrokBillingParser.quota(from: data(weekly(percent: "-1"))))
        XCTAssertNil(GrokBillingParser.quota(from: data(weekly(percent: "101"))))
    }

    func testNonWeeklyPeriodIsUnavailable() {
        XCTAssertNil(GrokBillingParser.quota(from: data("""
        {"config":{"creditUsagePercent":10,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY","end":"2026-12-01T00:00:00Z"}}}
        """)))
    }

    func testMissingResetKeepsPercentWithoutCountdown() throws {
        let quota = try XCTUnwrap(GrokBillingParser.quota(from: data("""
        {"config":{"creditUsagePercent":12,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}
        """)))
        let usage = GrokBillingParser.usage(from: quota)
        XCTAssertEqual(usage.weeklyPercentage, 12)
        XCTAssertFalse(usage.weeklyResetKnown)
    }

    func testJSONRPCWrapper() throws {
        let usage = try usage(from: """
        {"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":17,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-11-27T00:45:02.245+00:00"}},"subscription_tier":"SuperGrok Plus"}}
        """)
        XCTAssertEqual(usage.weeklyPercentage, 17)
    }

    func testCLIOutputIgnoresNotificationsAndReadsBilling() throws {
        let lines = [
            #"{"jsonrpc":"2.0","method":"_x.ai/mcp/servers_updated","params":{"mcpServers":[]}}"#,
            #"{"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":17,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-11-27T00:45:02Z"}}}}"#,
        ]
        let payload = try XCTUnwrap(GrokCLIProtocol.billingPayload(from: lines))
        let quota = try XCTUnwrap(GrokBillingParser.quota(from: payload))
        XCTAssertEqual(quota.usedPercent, 17)
    }

    func testCLIAuthErrorIsNotAQuota() {
        let lines = [
            #"{"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"Authentication required to fetch billing data. Run 'grok login' to authenticate."}}"#,
        ]
        XCTAssertEqual(GrokCLIProtocol.failure(from: lines), .authenticationRequired)
    }

    func testSharedCLIIsNotWrittenToAnotherGrokProfile() {
        let active = Profile(name: "Active", provider: .grok)
        let other = Profile(name: "Other", provider: .grok)
        XCTAssertTrue(GrokUsageProvider.mayUseSharedCLI(active, activeProfileId: active.id, profiles: [active, other]))
        XCTAssertFalse(GrokUsageProvider.mayUseSharedCLI(other, activeProfileId: active.id, profiles: [active, other]))
        XCTAssertTrue(GrokUsageProvider.mayUseSharedCLI(other, activeProfileId: active.id, profiles: [other]))
    }

    private func usage(from json: String) throws -> ClaudeUsage {
        let quota = try XCTUnwrap(GrokBillingParser.quota(from: data(json)))
        return GrokBillingParser.usage(from: quota, now: date("2026-11-21T00:00:00Z"))
    }

    private func weekly(percent: String) -> String {
        """
        {"config":{"creditUsagePercent":\(percent),"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-11-27T00:45:02.245+00:00"}}}
        """
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)!
    }
}
