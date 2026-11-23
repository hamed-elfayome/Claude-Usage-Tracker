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

    @MainActor
    func testSetupChecksProspectiveProfileWithoutChangingTheSavedProfile() async throws {
        let billing = APIUsage(
            currentSpendCents: 920, resetsAt: Date(timeIntervalSince1970: 0), prepaidCreditsCents: 0,
            currency: "USD", apiTokenCostCents: nil, apiCostByModel: nil, costBySource: nil, dailyCostCents: nil
        )
        let current = Profile(name: "First launch", claudeSessionKey: "saved", claudeUsage: .empty, apiUsage: billing)
        let profiles = [current]
        let payload = data(weekly(percent: "37"))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let provider = GrokUsageProvider(profileContext: { (current.id, profiles) }, billingPayload: { requested in
            XCTAssertEqual(requested.path, GrokHome.resolve(home.path)?.path)
            return payload
        })

        let live = try await provider.fetchSetupUsage(for: current.id, homePath: home.path)
        XCTAssertEqual(live.weeklyPercentage, 37)
        let candidate = try XCTUnwrap(GrokUsageProvider.setupProfile(for: current.id, activeID: current.id, profiles: profiles, homePath: home.path))
        XCTAssertEqual(candidate.grokHomePath, GrokHome.resolve(home.path)?.path)
        XCTAssertEqual(candidate.id, current.id)
        XCTAssertEqual(candidate.provider, .grok)
        XCTAssertNil(candidate.apiUsage)
        XCTAssertNil(candidate.claudeUsage)
        XCTAssertEqual(candidate.claudeSessionKey, "saved")
        XCTAssertEqual(profiles[0].provider, .anthropic)
        XCTAssertNotNil(profiles[0].claudeUsage)
        XCTAssertEqual(profiles[0].apiUsage, billing)
        XCTAssertNil(GrokUsageProvider.setupProfile(for: current.id, activeID: UUID(), profiles: profiles, homePath: home.path))
    }

    @MainActor
    func testDuplicateGrokProfilesCannotUseTheCLIOrClaimItDuringSetup() async {
        let active = Profile(name: "Active", provider: .grok)
        let other = Profile(name: "Other", provider: .grok)
        let profiles = [active, other]
        let provider = GrokUsageProvider(profileContext: { (active.id, profiles) }, billingPayload: { _ in
            XCTFail("An ambiguous profile must not start the CLI")
            return Data()
        })
        for profile in profiles {
            do {
                _ = try await provider.fetchUsage(for: profile)
                XCTFail("Expected an ownership error")
            } catch {
                XCTAssertEqual((error as? AppError)?.code, .providerCredentialsNotFound)
            }
        }
        let claude = Profile(name: "Claude")
        XCTAssertFalse(GrokUsageProvider.canConfigure(profileID: nil, homePath: nil, profiles: [other]))
        XCTAssertNil(GrokUsageProvider.setupProfile(for: claude.id, activeID: claude.id, profiles: [claude, other], homePath: nil))
    }

    @MainActor
    func testSoleInactiveGrokProfileReadsLiveDataAndNeverReturnsCachedUsageOnFailure() async throws {
        let active = Profile(name: "Active")
        let owner = Profile(name: "Grok", provider: .grok, claudeUsage: .empty)
        let profiles = [active, owner]
        let payload = data(weekly(percent: "12"))
        let provider = GrokUsageProvider(profileContext: { (active.id, profiles) }, billingPayload: { _ in payload })
        let live = try await provider.fetchUsage(for: owner)
        XCTAssertEqual(live.weeklyPercentage, 12)

        for code in [ErrorCode.apiServerError, .apiParsingFailed] {
            let failing = GrokUsageProvider(profileContext: { (active.id, profiles) }, billingPayload: { _ in
                if code == .apiServerError { throw GrokCLIError.unavailable }
                return Data("{}".utf8)
            })
            do {
                _ = try await failing.fetchUsage(for: owner)
                XCTFail("A failed live request must not return a cached reading")
            } catch {
                XCTAssertEqual((error as? AppError)?.code, code)
            }
        }
    }

    @MainActor
    func testLegacyAndCustomProfilesRouteToDistinctHomesAfterReload() async throws {
        let legacy = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","provider":"grok"}"#.utf8))
        let suggested = GrokHome.suggestedPath(in: [legacy])
        let workHome = try XCTUnwrap(GrokHome.resolve(suggested))
        let work = Profile(name: "Work", provider: .grok, grokHomePath: workHome.path)
        let profiles = try PropertyListDecoder().decode([Profile].self, from: PropertyListEncoder().encode([legacy, work]))
        XCTAssertNil(profiles[0].grokHomePath)
        XCTAssertEqual(profiles[1].grokHomePath, workHome.path)
        let defaultHome = try XCTUnwrap(GrokHome.resolve(nil))
        XCTAssertNotEqual(workHome.path, defaultHome.path)
        let readings = [defaultHome.path: data(weekly(percent: "0")), workHome.path: data(weekly(percent: "87"))]
        let provider = GrokUsageProvider(profileContext: { (legacy.id, profiles) }, billingPayload: { try XCTUnwrap(readings[$0.path]) })
        let personalReading = try await provider.fetchUsage(for: profiles[0])
        let workReading = try await provider.fetchUsage(for: profiles[1])
        XCTAssertEqual(personalReading.weeklyPercentage, 0)
        XCTAssertEqual(workReading.weeklyPercentage, 87)
        XCTAssertNil(GrokUsageProvider.setupProfile(for: work.id, activeID: work.id, profiles: [work], homePath: nil))
    }

    @MainActor
    func testHomeAliasesCannotClaimAnotherProfilesDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let real = root.appendingPathComponent("real", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(at: alias, withDestinationURL: real)
        let owner = Profile(name: "Owner", provider: .grok, grokHomePath: real.path + "/work")
        XCTAssertFalse(GrokUsageProvider.canConfigure(profileID: nil, homePath: alias.path + "/./work/", profiles: [owner]))
        XCTAssertTrue(GrokUsageProvider.canConfigure(profileID: nil, homePath: alias.path + "/personal", profiles: [owner]))
        XCTAssertFalse(GrokUsageProvider.canConfigure(profileID: nil, homePath: "relative/work", profiles: []))
        let file = real.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        XCTAssertNil(GrokHome.resolve(file.path))
        XCTAssertNil(GrokHome.resolve(file.path + "/work"))
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
