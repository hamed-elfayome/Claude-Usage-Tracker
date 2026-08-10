import XCTest
@testable import Claude_Usage

final class TokenStatsServiceTests: XCTestCase {

    // MARK: - Fixture helpers

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenStatsServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    /// referenceDate is pinned to "now" (not a hardcoded historic date). This matters for the
    /// JSONL scan's mtime-based skip optimization: fixture files are written with mtime = real
    /// "now", so as long as `referenceDate` is also real "now", `scanFrom` (always <= today)
    /// can never be later than the fixture's mtime, and the optimization never spuriously skips
    /// a fixture file. All fixture calendar dates below are computed as offsets from this
    /// reference (via `day(offsetFromToday:)`) rather than hardcoded literals, so window math
    /// stays deterministic regardless of which real-world day the suite runs on.
    private let referenceDate = Date()

    private lazy var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "yyyy-MM-dd" string for `referenceDate + offset` days (offset may be negative).
    private func day(offsetFromToday offset: Int) -> String {
        let today = calendar.startOfDay(for: referenceDate)
        let d = calendar.date(byAdding: .day, value: offset, to: today)!
        return dayFormatter.string(from: d)
    }

    private func writeStatsCache(_ json: String) -> URL {
        let url = tempDir.appendingPathComponent("stats-cache.json")
        try! json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes a single JSONL session file containing one assistant line per token tuple.
    /// `projectsDir` layout mirrors `~/.claude/projects/<slug>/<session>.jsonl`.
    ///
    /// All four token kinds are spelled out per line because the delta sum must include cache
    /// tokens (see `testCacheTokensCountTowardEveryFrame`), so a fixture that left them implicit
    /// would hide exactly the arithmetic these tests exist to pin down.
    private func writeJSONL(_ lines: [(day: String, input: Int, output: Int, cacheRead: Int, cacheCreate: Int)]) -> URL {
        let projectsDir = tempDir.appendingPathComponent("projects/my-project")
        try! FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let sessionFile = projectsDir.appendingPathComponent("session.jsonl")

        let body = lines.map { line in
            """
            {"type":"assistant","timestamp":"\(line.day)T12:00:00.000Z","message":{"usage":{"input_tokens":\(line.input),"output_tokens":\(line.output),"cache_read_input_tokens":\(line.cacheRead),"cache_creation_input_tokens":\(line.cacheCreate)}}}
            """
        }.joined(separator: "\n")

        try! body.write(to: sessionFile, atomically: true, encoding: .utf8)
        return projectsDir.deletingLastPathComponent() // return the `projects` dir itself
    }

    private func emptyProjectsDir() -> URL {
        let dir = tempDir.appendingPathComponent("projects-empty")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func missingStatsURL() -> URL {
        tempDir.appendingPathComponent("no-such-stats-cache.json")
    }

    // MARK: - Tests

    func testHybridAllTimeAddsCacheAndPostCutoffJSONL() {
        // Cache lifetime total = 700 + 300 + 4000 + 200 = 5200, authoritative through "today - 3".
        // A JSONL line 2 days after the cutoff (100 + 50 + 800 + 40 = 990) is added on top.
        let cutoff = day(offsetFromToday: -3)
        let json = """
        {
          "modelUsage": {
            "claude-sonnet-4-5": {
              "inputTokens": 700, "outputTokens": 300,
              "cacheReadInputTokens": 4000, "cacheCreationInputTokens": 200
            }
          },
          "dailyModelTokens": [],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -1), input: 100, output: 50, cacheRead: 800, cacheCreate: 40)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 6190)
        XCTAssertEqual(stats.last7Days, 0, "disabled frame should not be computed")
        XCTAssertEqual(stats.last30Days, 0, "disabled frame should not be computed")
    }

    /// Regression guard for the CLI 2.1.221 accounting change: `dailyModelTokens` (which feeds the
    /// 7D/30D windows) counts input + output + cache_read + cache_creation. If the all-time
    /// aggregate or the post-cutoff JSONL delta counted only input + output, the frames would
    /// report mutually inconsistent quantities - a 7D window larger than all-time.
    func testCacheTokensCountTowardEveryFrame() {
        // A pure cache-read line: zero input, zero output. Under the old accounting it contributed
        // nothing at all; it must now contribute its full 1000 to both all-time and the 7D window.
        let cutoff = day(offsetFromToday: -2)
        let json = """
        {
          "modelUsage": {
            "m": {
              "inputTokens": 0, "outputTokens": 0,
              "cacheReadInputTokens": 60, "cacheCreationInputTokens": 15
            }
          },
          "dailyModelTokens": [ { "date": "\(cutoff)", "tokensByModel": { "m": 75 } } ],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -1), input: 0, output: 0, cacheRead: 1000, cacheCreate: 0)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime, .tokens7Days, .tokens30Days],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 1075, "cache-only lines must count: 60 + 15 cached + 1000 from JSONL")
        XCTAssertEqual(stats.last7Days, 1075, "75 from the cached day + 1000 from the post-cutoff day")
        XCTAssertGreaterThanOrEqual(
            stats.allTime, stats.last7Days,
            "all-time and the windows must measure the same quantity, so all-time can never be smaller"
        )
    }

    func testWindowMergesCacheDayAndJSONLDayWithinRange() {
        // Cache authoritative through "today - 3"; a dailyModelTokens entry that day (50 tokens)
        // plus a JSONL line 1 day after the cutoff (30 tokens), both within the 7-day window,
        // must sum together.
        let cutoff = day(offsetFromToday: -3)
        let json = """
        {
          "modelUsage": {},
          "dailyModelTokens": [
            { "date": "\(cutoff)", "tokensByModel": { "a": 50 } }
          ],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -2), input: 20, output: 10, cacheRead: 500, cacheCreate: 5)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokens7Days],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.last7Days, 585, "50 cached + (20 + 10 + 500 + 5) from JSONL")
        XCTAssertEqual(stats.allTime, 0, "disabled frame should not be computed")
    }

    func testJSONLLinesOnOrBeforeCutoffAreIgnored() {
        // A JSONL line dated exactly on lastComputedDate duplicates data already folded into the
        // cache and must NOT be double-counted.
        let cutoff = day(offsetFromToday: -1)
        let json = """
        {
          "modelUsage": {
            "m": {
              "inputTokens": 500, "outputTokens": 0,
              "cacheReadInputTokens": 1500, "cacheCreationInputTokens": 0
            }
          },
          "dailyModelTokens": [],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([
            (day: cutoff, input: 9999, output: 9999, cacheRead: 9999, cacheCreate: 9999)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 2000, "on-cutoff JSONL line already counted in cache; must be ignored")
    }

    func testDisabledFrameIsNotComputed() {
        let cutoff = day(offsetFromToday: -2)
        let json = """
        {
          "modelUsage": { "m": { "inputTokens": 1000, "outputTokens": 0 } },
          "dailyModelTokens": [ { "date": "\(cutoff)", "tokensByModel": { "a": 40 } } ],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -1), input: 10, output: 5, cacheRead: 100, cacheCreate: 0)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokens7Days],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 0, "only enabled frames are computed")
        XCTAssertEqual(stats.last30Days, 0, "only enabled frames are computed")
        XCTAssertEqual(stats.last7Days, 155, "40 cached + (10 + 5 + 100) from JSONL")
    }

    func testMissingCacheFallsBackToFullJSONLSum() {
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -10), input: 100, output: 50, cacheRead: 200, cacheCreate: 10),
            (day: day(offsetFromToday: -1), input: 20, output: 5, cacheRead: 30, cacheCreate: 1)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: missingStatsURL(),
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 416, "360 + 56")
    }

    func testDecodedCacheWithoutLastComputedDateFallsBackToFullJSONLSum() {
        // Cache decodes fine and has real aggregates (modelUsage summing to 1000, plus a
        // dailyModelTokens entry), but lastComputedDate is absent. Without a valid cutoff we
        // cannot safely combine the cache's totals with a JSONL delta (that would either double-
        // count the cache's lifetime total on top of the full JSONL history, or silently ignore
        // the cache's daily entries in window sums). The fix must fall back to pure JSONL: only
        // the JSONL line's 470 tokens should count, not 1000, and not 1470.
        let json = """
        {
          "modelUsage": {
            "claude-sonnet-4-5": { "inputTokens": 700, "outputTokens": 300 }
          },
          "dailyModelTokens": [
            { "date": "\(day(offsetFromToday: -5))", "tokensByModel": { "a": 40 } }
          ]
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -1), input: 100, output: 50, cacheRead: 300, cacheCreate: 20)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 470, "no valid cutoff -> pure JSONL, not 1470 (double-count) or 1000 (cache-only)")
    }

    func testNothingAvailableReturnsUnavailable() {
        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: missingStatsURL(),
            projectsDir: emptyProjectsDir(),
            referenceDate: referenceDate
        )

        XCTAssertEqual(stats, .unavailable)
        XCTAssertFalse(stats.isAvailable)
    }

    func testNoTokenFramesEnabledReturnsUnavailable() {
        // Only non-token metrics enabled -> nothing to compute, even with valid data present.
        let json = """
        { "modelUsage": { "m": { "inputTokens": 10, "outputTokens": 10 } }, "dailyModelTokens": [] }
        """
        let statsURL = writeStatsCache(json)

        let stats = TokenStatsService().load(
            enabledFrames: [.session, .week, .api],
            statsURL: statsURL,
            projectsDir: emptyProjectsDir(),
            referenceDate: referenceDate
        )

        XCTAssertEqual(stats, .unavailable)
    }

    func testMalformedJSONLLineIsSkippedButGoodLinesStillCount() {
        let projectsDir = tempDir.appendingPathComponent("projects/bad-project")
        try! FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let sessionFile = projectsDir.appendingPathComponent("session.jsonl")

        let goodDay = day(offsetFromToday: -1)
        let content = """
        { this is not valid json at all "usage"
        {"type":"assistant","timestamp":"\(goodDay)T09:00:00.000Z","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100}}}
        {"type":"assistant","timestamp":"not-a-real-timestamp","message":{"usage":{"input_tokens":1,"output_tokens":1}}}
        {"type":"user","timestamp":"\(goodDay)T09:01:00.000Z"}
        """
        try! content.write(to: sessionFile, atomically: true, encoding: .utf8)

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: missingStatsURL(),
            projectsDir: projectsDir.deletingLastPathComponent(),
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(
            stats.allTime, 115,
            "malformed/unusable lines are skipped; the one good line still counts, cache included. "
            + "A line omitting cache_creation_input_tokens entirely must decode as 0, not fail."
        )
    }
}
