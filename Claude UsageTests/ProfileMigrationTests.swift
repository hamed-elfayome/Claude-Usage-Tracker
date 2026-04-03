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
}
