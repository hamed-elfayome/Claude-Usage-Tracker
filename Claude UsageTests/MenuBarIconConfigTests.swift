import XCTest
@testable import Claude_Usage

@MainActor
final class MenuBarIconConfigTests: XCTestCase {

    // MARK: - Exclude Weekends from Weekly Pace

    func testExcludeWeekendsIsOffByDefault() {
        XCTAssertFalse(MenuBarIconConfiguration.default.excludeWeekendsFromWeeklyPace)
        XCTAssertFalse(MultiProfileDisplayConfig.default.excludeWeekendsFromWeeklyPace)
    }

    func testExcludeWeekendsSurvivesEncodeDecode() throws {
        var config = MenuBarIconConfiguration.default
        config.excludeWeekendsFromWeeklyPace = true
        let decodedConfig = try JSONDecoder().decode(
            MenuBarIconConfiguration.self,
            from: JSONEncoder().encode(config)
        )
        XCTAssertTrue(decodedConfig.excludeWeekendsFromWeeklyPace)

        var multiProfileConfig = MultiProfileDisplayConfig.default
        multiProfileConfig.excludeWeekendsFromWeeklyPace = true
        let decodedMultiProfileConfig = try JSONDecoder().decode(
            MultiProfileDisplayConfig.self,
            from: JSONEncoder().encode(multiProfileConfig)
        )
        XCTAssertTrue(decodedMultiProfileConfig.excludeWeekendsFromWeeklyPace)
    }

    func testDecodesSettingsSavedBeforeExcludeWeekendsExisted() throws {
        // Settings persisted by earlier versions have no excludeWeekendsFromWeeklyPace key.
        // They must still decode (with the option off) rather than fail and reset the configuration.
        let legacyConfig = try removingKey(
            "excludeWeekendsFromWeeklyPace",
            from: JSONEncoder().encode(MenuBarIconConfiguration.default)
        )
        let decodedConfig = try JSONDecoder().decode(MenuBarIconConfiguration.self, from: legacyConfig)
        XCTAssertFalse(decodedConfig.excludeWeekendsFromWeeklyPace)

        let legacyMultiProfileConfig = try removingKey(
            "excludeWeekendsFromWeeklyPace",
            from: JSONEncoder().encode(MultiProfileDisplayConfig.default)
        )
        let decodedMultiProfileConfig = try JSONDecoder().decode(
            MultiProfileDisplayConfig.self,
            from: legacyMultiProfileConfig
        )
        XCTAssertFalse(decodedMultiProfileConfig.excludeWeekendsFromWeeklyPace)
    }

    // MARK: - Helpers

    /// Re-encodes JSON without `key`, asserting the key was present to begin with
    private func removingKey(_ key: String, from data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: key), "\(key) should be encoded")
        return try JSONSerialization.data(withJSONObject: object)
    }
}
