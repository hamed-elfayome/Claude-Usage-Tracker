import XCTest
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

    func testDecodeLegacyJSONWithoutDesignAndFableKeys() throws {
        // Persisted data from v3.1.1 and earlier has no design/fable keys.
        // Decoding it must succeed (defaulting to 0/nil), otherwise
        // ProfileStore.loadProfiles() wipes every profile on upgrade.
        let legacyJSON = """
        {
          "sessionTokensUsed": 100, "sessionLimit": 1000,
          "sessionPercentage": 10, "sessionResetTime": 700000000,
          "weeklyTokensUsed": 200, "weeklyLimit": 1000000,
          "weeklyPercentage": 20, "weeklyResetTime": 700000000,
          "opusWeeklyTokensUsed": 5, "opusWeeklyPercentage": 5,
          "sonnetWeeklyTokensUsed": 6, "sonnetWeeklyPercentage": 6,
          "lastUpdated": 700000000,
          "userTimezone": {"identifier": "Europe/Moscow"}
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: legacyJSON)

        XCTAssertEqual(decoded.sessionTokensUsed, 100)
        XCTAssertEqual(decoded.opusWeeklyPercentage, 5)
        XCTAssertEqual(decoded.designWeeklyTokensUsed, 0)
        XCTAssertEqual(decoded.designWeeklyPercentage, 0)
        XCTAssertNil(decoded.designWeeklyResetTime)
        XCTAssertEqual(decoded.fableWeeklyTokensUsed, 0)
        XCTAssertEqual(decoded.fableWeeklyPercentage, 0)
        XCTAssertNil(decoded.fableWeeklyResetTime)
    }

    func testEncodeDecodeFableFields() throws {
        var original = createUsage(sessionPercentage: 10)
        original.fableWeeklyTokensUsed = 123_456
        original.fableWeeklyPercentage = 42.5
        original.fableWeeklyResetTime = Date(timeIntervalSince1970: 1_800_000_000)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: data)

        XCTAssertEqual(decoded.fableWeeklyTokensUsed, 123_456)
        XCTAssertEqual(decoded.fableWeeklyPercentage, 42.5)
        XCTAssertEqual(decoded.fableWeeklyResetTime, original.fableWeeklyResetTime)
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
            designWeeklyTokensUsed: 0,
            designWeeklyPercentage: 0,
            designWeeklyResetTime: nil,
            fableWeeklyTokensUsed: 0,
            fableWeeklyPercentage: 0,
            fableWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }
}
