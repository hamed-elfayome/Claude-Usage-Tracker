import XCTest
import CryptoKit
@testable import Claude_Usage

final class ClaudeUsageTests: XCTestCase {

    // MARK: - Status Level Tests (Deprecated Property - uses remaining-based thresholds)

    func testStatusLevelSafe() {
        // statusLevel uses remaining-based thresholds: safe when remaining >= 20%
        let usage = createUsage(sessionPercentage: 0)  // 100% remaining
        XCTAssertEqual(usage.statusLevel, .safe)

        let usage25 = createUsage(sessionPercentage: 25)  // 75% remaining
        XCTAssertEqual(usage.statusLevel, .safe)

        let usage80 = createUsage(sessionPercentage: 80)  // 20% remaining (exact boundary)
        XCTAssertEqual(usage.statusLevel, .safe)
    }

    func testStatusLevelModerate() {
        // statusLevel uses remaining-based thresholds: moderate when 10% <= remaining < 20%
        let usage81 = createUsage(sessionPercentage: 81)  // 19% remaining
        XCTAssertEqual(usage81.statusLevel, .moderate)

        let usage85 = createUsage(sessionPercentage: 85)  // 15% remaining
        XCTAssertEqual(usage85.statusLevel, .moderate)

        let usage90 = createUsage(sessionPercentage: 90)  // 10% remaining (exact boundary)
        XCTAssertEqual(usage90.statusLevel, .moderate)
    }

    func testStatusLevelCritical() {
        // statusLevel uses remaining-based thresholds: critical when remaining < 10%
        let usage91 = createUsage(sessionPercentage: 91)  // 9% remaining
        XCTAssertEqual(usage91.statusLevel, .critical)

        let usage95 = createUsage(sessionPercentage: 95)  // 5% remaining
        XCTAssertEqual(usage95.statusLevel, .critical)

        let usage100 = createUsage(sessionPercentage: 100)  // 0% remaining
        XCTAssertEqual(usage100.statusLevel, .critical)
    }

    // MARK: - Empty Usage Tests

    func testEmptyUsage() {
        let empty = ClaudeUsage.empty

        XCTAssertEqual(empty.sessionTokensUsed, 0)
        XCTAssertEqual(empty.sessionPercentage, 0)
        XCTAssertEqual(empty.weeklyTokensUsed, 0)
        XCTAssertEqual(empty.weeklyPercentage, 0)
        XCTAssertEqual(empty.statusLevel, .safe)
        XCTAssertNil(empty.costUsed)
        XCTAssertNil(empty.costLimit)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = createUsage(sessionPercentage: 45.5)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClaudeUsage.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - Helpers

    private func createUsage(sessionPercentage: Double) -> ClaudeUsage {
        ClaudeUsage(
            sessionTokensUsed: Int(sessionPercentage * 1000),
            sessionLimit: 100000,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 500000,
            weeklyLimit: 1000000,
            weeklyPercentage: 50,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }
}

// MARK: - Profile custom keychain field

final class ProfileCustomKeychainTests: XCTestCase {
    func testDecodesOldPlistWithoutCustomKeychainField() throws {
        // Simulate an older-shape plist by encoding then stripping the new key.
        let original = Profile(id: UUID(), name: "AccountA")
        let data = try JSONEncoder().encode(original)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "customKeychainServiceName")
        let pruned = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(Profile.self, from: pruned)
        XCTAssertNil(decoded.customKeychainServiceName)
    }

    func testHasAnyCredentialsRecognizesCustomKeychainPin() {
        let bare = Profile(id: UUID(), name: "AccountA")
        XCTAssertFalse(bare.hasAnyCredentials)

        let pinned = Profile(
            id: UUID(),
            name: "AccountA",
            customKeychainServiceName: "Claude Code-credentials-abcd1234"
        )
        XCTAssertTrue(pinned.hasAnyCredentials)
    }
}

// MARK: - ClaudeCodeSyncService logic helpers

final class ClaudeCodeSyncServiceLogicTests: XCTestCase {
    private var service: ClaudeCodeSyncService { ClaudeCodeSyncService.shared }

    // Locks the hash algorithm Claude Code uses to derive
    // `Claude Code-credentials-<HASH>` from a CLAUDE_CONFIG_DIR path so a future
    // change in either side is caught immediately.
    func testSha256HexPrefixMatchesClaudeCodeKeychainHashAlgorithm() {
        let path = "/tmp/fixture-config-dir"
        let expected = SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(8)
        XCTAssertEqual(service.sha256HexPrefix(path, length: 8), String(expected))
    }

    func testMergeRefreshedCredentialsUpdatesAccessTokenAndExpiresAt() throws {
        let cliJSON = #"""
        {
            "claudeAiOauth": {
                "accessToken": "OLD",
                "refreshToken": "OLD-RT",
                "expiresAt": 1000,
                "scopes": ["a", "b"],
                "subscriptionType": "max"
            },
            "organizationUuid": "org-1"
        }
        """#
        let refreshed = ClaudeCodeSyncService.OAuthRefreshResponse(
            access_token: "NEW",
            refresh_token: nil,
            expires_in: 3600,
            token_type: "Bearer"
        )
        let merged = try XCTUnwrap(service.mergeRefreshedCredentials(into: cliJSON, refreshed: refreshed))
        let obj = try JSONSerialization.jsonObject(with: Data(merged.utf8)) as! [String: Any]
        let oauth = obj["claudeAiOauth"] as! [String: Any]
        XCTAssertEqual(oauth["accessToken"] as? String, "NEW")
        // Refresh token preserved when response omits it
        XCTAssertEqual(oauth["refreshToken"] as? String, "OLD-RT")
        // expiresAt persisted as ms-since-epoch, ~now()+3600s
        let exp = (oauth["expiresAt"] as? NSNumber)?.int64Value ?? 0
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertGreaterThan(exp, nowMs + 3500 * 1000)
        XCTAssertLessThan(exp, nowMs + 3700 * 1000)
        // Untouched fields preserved
        XCTAssertEqual(obj["organizationUuid"] as? String, "org-1")
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
        XCTAssertEqual(oauth["scopes"] as? [String], ["a", "b"])
    }

    func testMergeRefreshedCredentialsRotatesRefreshTokenWhenProvided() throws {
        let cliJSON = #"{"claudeAiOauth":{"accessToken":"old","refreshToken":"old-rt","expiresAt":0}}"#
        let refreshed = ClaudeCodeSyncService.OAuthRefreshResponse(
            access_token: "new",
            refresh_token: "new-rt",
            expires_in: 60,
            token_type: nil
        )
        let merged = try XCTUnwrap(service.mergeRefreshedCredentials(into: cliJSON, refreshed: refreshed))
        let obj = try JSONSerialization.jsonObject(with: Data(merged.utf8)) as! [String: Any]
        let oauth = obj["claudeAiOauth"] as! [String: Any]
        XCTAssertEqual(oauth["refreshToken"] as? String, "new-rt")
    }

    func testMergeRefreshedCredentialsRejectsInputWithoutClaudeAiOauth() {
        let cliJSON = #"{"unknownRoot": {}}"#
        let refreshed = ClaudeCodeSyncService.OAuthRefreshResponse(
            access_token: "x", refresh_token: nil, expires_in: 60, token_type: nil
        )
        XCTAssertNil(service.mergeRefreshedCredentials(into: cliJSON, refreshed: refreshed))
    }

    func testDisplayLabelEmailAndOrg() {
        let d = ClaudeCodeSyncService.KeychainEntryDescription(
            serviceName: "Claude Code-credentials-abcd1234",
            emailAddress: "user@example.com",
            organizationName: "ExampleOrg",
            subscriptionType: "max"
        )
        XCTAssertEqual(d.displayLabel, "user@example.com — ExampleOrg · abcd1234")
    }

    func testDisplayLabelEmailOnly() {
        let d = ClaudeCodeSyncService.KeychainEntryDescription(
            serviceName: "Claude Code-credentials-abcd1234",
            emailAddress: "user@example.com",
            organizationName: nil,
            subscriptionType: nil
        )
        XCTAssertEqual(d.displayLabel, "user@example.com · abcd1234")
    }

    func testDisplayLabelDefaultShorthand() {
        let d = ClaudeCodeSyncService.KeychainEntryDescription(
            serviceName: "Claude Code-credentials",
            emailAddress: "user@example.com",
            organizationName: nil,
            subscriptionType: nil
        )
        XCTAssertEqual(d.displayLabel, "user@example.com · default")
    }

    func testDisplayLabelSubscriptionFallback() {
        let d = ClaudeCodeSyncService.KeychainEntryDescription(
            serviceName: "Claude Code-credentials-abcd1234",
            emailAddress: nil,
            organizationName: nil,
            subscriptionType: "team"
        )
        XCTAssertEqual(d.displayLabel, "abcd1234 — team")
    }

    func testDisplayLabelRawSvcFallback() {
        let d = ClaudeCodeSyncService.KeychainEntryDescription(
            serviceName: "Claude Code-credentials-abcd1234",
            emailAddress: nil,
            organizationName: nil,
            subscriptionType: nil
        )
        XCTAssertEqual(d.displayLabel, "Claude Code-credentials-abcd1234")
    }
}

