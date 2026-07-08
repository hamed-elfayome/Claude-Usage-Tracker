import XCTest
@testable import Claude_Usage

/// Tests for #267 (GHSA-mfxh-xpwm-23c7): profile credentials must not be
/// serialized into the profiles plist, and legacy plaintext values must
/// survive the migration to the Keychain.
final class ProfileKeychainMigrationTests: XCTestCase {

    private let testProfileId = UUID()

    override func tearDown() {
        KeychainService.shared.deleteAllProfileSecrets(profileId: testProfileId)
        super.tearDown()
    }

    // MARK: - Codable exclusion

    func testEncodeExcludesSecretsByDefault() throws {
        let profile = Profile(
            name: "Test",
            claudeSessionKey: "sk-ant-sid01-SECRET",
            organizationId: "org-123",
            apiSessionKey: "sk-ant-api03-SECRET",
            cliCredentialsJSON: "{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-SECRET\"}}"
        )

        let data = try JSONEncoder().encode(profile)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertFalse(json.contains("SECRET"), "encoded profile must not contain credentials")
        XCTAssertFalse(json.contains("claudeSessionKey"))
        XCTAssertFalse(json.contains("apiSessionKey"))
        XCTAssertFalse(json.contains("cliCredentialsJSON"))
        // Non-secret fields still present
        XCTAssertTrue(json.contains("org-123"), "organizationId is not a secret and must persist")
    }

    func testEncodeIncludesSecretsWithUserInfoFlag() throws {
        let profile = Profile(name: "Test", claudeSessionKey: "sk-ant-sid01-SECRET")

        let encoder = JSONEncoder()
        encoder.userInfo[Profile.includeSecretsKey] = true
        let json = String(data: try encoder.encode(profile), encoding: .utf8)!

        XCTAssertTrue(json.contains("sk-ant-sid01-SECRET"),
                      "fallback encoding must retain credentials to avoid data loss")
    }

    func testDecodeLegacyPlistWithSecrets() throws {
        // Simulates a pre-migration profiles_v3 entry with plaintext credentials.
        let legacyJSON = """
        {
            "id": "\(testProfileId.uuidString)",
            "name": "Legacy",
            "claudeSessionKey": "sk-ant-sid01-LEGACY",
            "organizationId": "org-legacy",
            "cliCredentialsJSON": "{\\"claudeAiOauth\\":{\\"accessToken\\":\\"tok\\"}}",
            "hasCliAccount": true,
            "refreshInterval": 30,
            "createdAt": 700000000,
            "lastUsedAt": 700000000
        }
        """
        let profile = try JSONDecoder().decode(Profile.self, from: legacyJSON.data(using: .utf8)!)

        XCTAssertEqual(profile.claudeSessionKey, "sk-ant-sid01-LEGACY")
        XCTAssertEqual(profile.organizationId, "org-legacy")
        XCTAssertNotNil(profile.cliCredentialsJSON)
        XCTAssertTrue(profile.hasCliAccount)
    }

    func testDecodeMinimalLegacyProfileAppliesDefaults() throws {
        // Very old / partial plist entries must not fail to decode.
        let minimalJSON = """
        {"id": "\(UUID().uuidString)", "name": "Minimal"}
        """
        let profile = try JSONDecoder().decode(Profile.self, from: minimalJSON.data(using: .utf8)!)

        XCTAssertEqual(profile.name, "Minimal")
        XCTAssertFalse(profile.hasCliAccount)
        XCTAssertEqual(profile.refreshInterval, 30.0)
        XCTAssertTrue(profile.checkOverageLimitEnabled)
        XCTAssertTrue(profile.isSelectedForDisplay)
        XCTAssertNil(profile.claudeSessionKey)
    }

    // MARK: - Keychain round trip
    // These use the data-protection keychain, which requires an application
    // identifier (real signing). Ad-hoc-signed test runners skip them — the app
    // falls back to legacy plist storage in that configuration by design.

    func testProfileSecretRoundTrip() throws {
        try XCTSkipUnless(KeychainService.shared.isProfileSecretStorageAvailable,
                          "data-protection keychain unavailable under ad-hoc signing")
        let saved = KeychainService.shared.saveProfileSecret(
            "round-trip-value", profileId: testProfileId, field: .claudeSessionKey)
        XCTAssertTrue(saved)

        let loaded = KeychainService.shared.loadProfileSecret(
            profileId: testProfileId, field: .claudeSessionKey)
        XCTAssertEqual(loaded, "round-trip-value")

        // Overwrite
        XCTAssertTrue(KeychainService.shared.saveProfileSecret(
            "updated-value", profileId: testProfileId, field: .claudeSessionKey))
        XCTAssertEqual(KeychainService.shared.loadProfileSecret(
            profileId: testProfileId, field: .claudeSessionKey), "updated-value")

        // nil deletes
        XCTAssertTrue(KeychainService.shared.saveProfileSecret(
            nil, profileId: testProfileId, field: .claudeSessionKey))
        XCTAssertNil(KeychainService.shared.loadProfileSecret(
            profileId: testProfileId, field: .claudeSessionKey))
    }

    func testFieldsAreIsolatedPerProfileAndField() throws {
        try XCTSkipUnless(KeychainService.shared.isProfileSecretStorageAvailable,
                          "data-protection keychain unavailable under ad-hoc signing")
        let otherId = UUID()
        defer { KeychainService.shared.deleteAllProfileSecrets(profileId: otherId) }

        KeychainService.shared.saveProfileSecret("A", profileId: testProfileId, field: .claudeSessionKey)
        KeychainService.shared.saveProfileSecret("B", profileId: testProfileId, field: .apiSessionKey)
        KeychainService.shared.saveProfileSecret("C", profileId: otherId, field: .claudeSessionKey)

        XCTAssertEqual(KeychainService.shared.loadProfileSecret(profileId: testProfileId, field: .claudeSessionKey), "A")
        XCTAssertEqual(KeychainService.shared.loadProfileSecret(profileId: testProfileId, field: .apiSessionKey), "B")
        XCTAssertEqual(KeychainService.shared.loadProfileSecret(profileId: otherId, field: .claudeSessionKey), "C")

        KeychainService.shared.deleteAllProfileSecrets(profileId: testProfileId)
        XCTAssertNil(KeychainService.shared.loadProfileSecret(profileId: testProfileId, field: .claudeSessionKey))
        XCTAssertNil(KeychainService.shared.loadProfileSecret(profileId: testProfileId, field: .apiSessionKey))
        // Other profile untouched
        XCTAssertEqual(KeychainService.shared.loadProfileSecret(profileId: otherId, field: .claudeSessionKey), "C")
    }
}
