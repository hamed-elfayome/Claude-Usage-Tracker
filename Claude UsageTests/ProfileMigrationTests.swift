import XCTest
@testable import Claude_Usage

final class ProfileMigrationTests: XCTestCase {
    func testProfileProviderTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for providerType in ProfileProviderType.allCases {
            let data = try encoder.encode(providerType)
            let decoded = try decoder.decode(ProfileProviderType.self, from: data)
            XCTAssertEqual(providerType, decoded)
        }
    }

    func testProfileProviderTypeDefaultRefreshIntervals() {
        XCTAssertEqual(ProfileProviderType.claudeMax.defaultRefreshInterval, 30)
        XCTAssertEqual(ProfileProviderType.claudeAPI.defaultRefreshInterval, 300)
        XCTAssertEqual(ProfileProviderType.openaiAPI.defaultRefreshInterval, 300)
        XCTAssertEqual(ProfileProviderType.codex.defaultRefreshInterval, 60)
    }

    func testExistingProfileDecodesWithoutNewFields() throws {
        let json = """
        {
            "id": "550E8400-E29B-41D4-A716-446655440000",
            "name": "Test Profile",
            "hasCliAccount": false,
            "iconConfig": {
                "colorMode": "multiColor",
                "singleColorHex": "#FFFFFF",
                "showIconNames": false,
                "showRemainingPercentage": false,
                "showTimeMarker": true,
                "showPaceMarker": false,
                "usePaceColoring": false,
                "metrics": []
            },
            "refreshInterval": 30.0,
            "autoStartSessionEnabled": false,
            "checkOverageLimitEnabled": true,
            "notificationSettings": {
                "enabled": true,
                "threshold75Enabled": true,
                "threshold90Enabled": true,
                "threshold95Enabled": true,
                "soundName": "default",
                "customThresholds": []
            },
            "isSelectedForDisplay": true,
            "createdAt": 0,
            "lastUsedAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let profile = try decoder.decode(Profile.self, from: json)

        XCTAssertEqual(profile.name, "Test Profile")
        XCTAssertEqual(profile.providerType, .claudeMax)
        XCTAssertNil(profile.primaryModel)
        XCTAssertNil(profile.openaiAdminKey)
        XCTAssertNil(profile.openaiApiKey)
        XCTAssertNil(profile.openaiOrganizationId)
        XCTAssertNil(profile.openaiUsage)
        XCTAssertNil(profile.codexUsage)
        XCTAssertNil(profile.spendBudgetCents)
        XCTAssertNil(profile.spendBudgetCurrency)
    }

    func testNewProfileWithOpenAIFields() throws {
        let profile = Profile(
            name: "OpenAI Test",
            providerType: .openaiAPI,
            openaiAdminKey: "sk-admin-test123"
        )
        XCTAssertEqual(profile.providerType, .openaiAPI)
        XCTAssertEqual(profile.openaiAdminKey, "sk-admin-test123")

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded.providerType, .openaiAPI)
        XCTAssertEqual(decoded.openaiAdminKey, "sk-admin-test123")
    }
}
