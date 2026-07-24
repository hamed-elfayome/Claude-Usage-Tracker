import XCTest
@testable import Claude_Usage

final class TokenStatsServiceTests: XCTestCase {

    private func writeFixture(_ json: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-\(UUID().uuidString).json")
        try! json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // referenceDate 2026-07-23; windows anchored to that day
    private let ref: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 23
        return Calendar.current.date(from: c)!
    }()

    func testMissingFileIsUnavailable() {
        let missing = URL(fileURLWithPath: "/nonexistent/stats-cache.json")
        let stats = TokenStatsService().load(from: missing, referenceDate: ref)
        XCTAssertFalse(stats.isAvailable)
        XCTAssertEqual(stats, .unavailable)
    }

    func testAllTimeSumsInputPlusOutputExcludingCache() {
        let json = """
        {
          "modelUsage": {
            "claude-sonnet-4-5": { "inputTokens": 1000, "outputTokens": 500,
              "cacheReadInputTokens": 9000000, "cacheCreationInputTokens": 8000000 },
            "claude-opus-4-8": { "inputTokens": 200, "outputTokens": 300 }
          },
          "dailyModelTokens": []
        }
        """
        let stats = TokenStatsService().load(from: writeFixture(json), referenceDate: ref)
        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 2000) // 1000+500+200+300, cache ignored
    }

    func testWindowsSumDailyTokensWithinRange() {
        // ref day = 2026-07-23. 7d window includes 07-17..07-23; 30d includes 06-24..07-23.
        let json = """
        {
          "modelUsage": {},
          "dailyModelTokens": [
            { "date": "2026-07-23", "tokensByModel": { "a": 100, "b": 50 } },
            { "date": "2026-07-17", "tokensByModel": { "a": 10 } },
            { "date": "2026-07-16", "tokensByModel": { "a": 7 } },
            { "date": "2026-06-24", "tokensByModel": { "a": 3 } },
            { "date": "2026-06-23", "tokensByModel": { "a": 999 } }
          ]
        }
        """
        let stats = TokenStatsService().load(from: writeFixture(json), referenceDate: ref)
        XCTAssertEqual(stats.last7Days, 160)   // 150 + 10 (07-16 excluded)
        XCTAssertEqual(stats.last30Days, 170)  // 150 + 10 + 7 + 3 (06-23 excluded)
    }

    func testMalformedJsonIsUnavailable() {
        let stats = TokenStatsService().load(from: writeFixture("{ not json "), referenceDate: ref)
        XCTAssertFalse(stats.isAvailable)
    }
}
