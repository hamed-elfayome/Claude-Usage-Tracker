import XCTest
@testable import Claude_Usage

/// Multi-provider data model: the `provider` field must decode tolerantly so
/// pre-provider profiles (and profiles written by future app versions with
/// unknown providers) never fail to load — a decode throw here wipes the
/// whole profile list (see PR #271 for the ClaudeUsage precedent).
final class ProfileProviderTests: XCTestCase {

    // MARK: - Helpers

    private func decodeProfile(_ json: String) throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
    }

    /// Minimal legacy profile JSON as an older app version would have written it
    /// (every field other than id/name decodes with a default).
    private func legacyProfileJSON(extraFields: String = "") -> String {
        """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Legacy"\(extraFields.isEmpty ? "" : ",")
            \(extraFields)
        }
        """
    }

    // MARK: - Decode tolerance

    func testLegacyProfileWithoutProviderDecodesAsAnthropic() throws {
        let profile = try decodeProfile(legacyProfileJSON())
        XCTAssertEqual(profile.provider, .anthropic)
    }

    func testUnknownProviderRawValueDegradesToAnthropic() throws {
        let profile = try decodeProfile(legacyProfileJSON(extraFields: "\"provider\": \"some-future-provider\""))
        XCTAssertEqual(profile.provider, .anthropic, "unknown provider must degrade, not throw")
    }

    func testNonStringProviderValueDegradesToAnthropic() throws {
        let profile = try decodeProfile(legacyProfileJSON(extraFields: "\"provider\": 42"))
        XCTAssertEqual(profile.provider, .anthropic, "malformed provider must degrade, not throw")
    }

    func testCodexProviderRoundTrips() throws {
        let original = Profile(name: "Codex", provider: .codex)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded.provider, .codex)
    }

    // MARK: - Secret exclusion

    func testCodexCredentialsExcludedFromPlistEncoding() throws {
        let profile = Profile(name: "Codex", provider: .codex, codexCredentialsJSON: "{\"tokens\":{\"access_token\":\"CODEX-SECRET\"}}")
        let data = try JSONEncoder().encode(profile)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("CODEX-SECRET"), "codex credentials must not be serialized into the plist")
    }

    func testCodexCredentialsIncludedWithSecretsUserInfo() throws {
        let profile = Profile(name: "Codex", provider: .codex, codexCredentialsJSON: "{\"tokens\":{\"access_token\":\"CODEX-SECRET\"}}")
        let encoder = JSONEncoder()
        encoder.userInfo[Profile.includeSecretsKey] = true
        let data = try encoder.encode(profile)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("CODEX-SECRET"), "fallback path must preserve codex credentials")
    }

    // MARK: - ClaudeUsage new optional fields

    func testClaudeUsageLegacyJSONDecodesWithNilPlanAndCredits() throws {
        let data = try JSONEncoder().encode(ClaudeUsage.empty)
        // Strip the new keys to simulate data written by an older app version.
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "planType")
        dict.removeValue(forKey: "creditsBalance")
        dict.removeValue(forKey: "creditsUnlimited")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: legacyData)
        XCTAssertNil(decoded.planType)
        XCTAssertNil(decoded.creditsBalance)
        XCTAssertNil(decoded.creditsUnlimited)
    }

    func testClaudeUsagePlanAndCreditsRoundTrip() throws {
        var usage = ClaudeUsage.empty
        usage.planType = "plus"
        usage.creditsBalance = 12.5
        usage.creditsUnlimited = false

        let data = try JSONEncoder().encode(usage)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: data)
        XCTAssertEqual(decoded.planType, "plus")
        XCTAssertEqual(decoded.creditsBalance, 12.5)
        XCTAssertEqual(decoded.creditsUnlimited, false)
    }

    // MARK: - UsageSnapshot provider tag

    func testLegacyUsageSnapshotDecodesWithNilProvider() throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "timestamp": 700000000,
            "resetType": "sessionReset",
            "sessionTokensUsed": 1000,
            "sessionPercentage": 50,
            "triggeringResetTime": 700000000
        }
        """
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.provider)
    }

    func testCodexSnapshotSuppressesTokenCounts() {
        var usage = ClaudeUsage.empty
        usage.sessionTokensUsed = 4242
        usage.sessionPercentage = 42

        let snapshot = UsageSnapshot.fromSessionReset(usage, resetTime: Date(), provider: .codex)
        XCTAssertEqual(snapshot.provider, "codex")
        XCTAssertNil(snapshot.sessionTokensUsed, "percentage-only providers must not record misleading token counts")
        XCTAssertEqual(snapshot.sessionPercentage, 42)
    }

    func testAnthropicSnapshotKeepsTokenCounts() {
        var usage = ClaudeUsage.empty
        usage.sessionTokensUsed = 4242
        usage.sessionPercentage = 42

        let snapshot = UsageSnapshot.fromSessionReset(usage, resetTime: Date(), provider: .anthropic)
        XCTAssertEqual(snapshot.provider, "anthropic")
        XCTAssertEqual(snapshot.sessionTokensUsed, 4242)
    }

    // MARK: - Registry descriptors

    func testEveryProviderHasADescriptor() {
        for provider in Provider.allCases {
            let descriptor = provider.descriptor
            XCTAssertEqual(descriptor.id, provider)
            XCTAssertFalse(descriptor.displayName.isEmpty)
        }
    }

    func testCapabilityExpectations() {
        XCTAssertTrue(Provider.anthropic.descriptor.capabilities.tokenCounts)
        XCTAssertTrue(Provider.anthropic.descriptor.capabilities.cliAccountSync)
        XCTAssertFalse(Provider.codex.descriptor.capabilities.tokenCounts)
        XCTAssertFalse(Provider.codex.descriptor.capabilities.cliAccountSync)
        XCTAssertFalse(Provider.codex.descriptor.capabilities.autoStartSession)
        XCTAssertTrue(Provider.codex.descriptor.capabilities.credits)
    }
}
