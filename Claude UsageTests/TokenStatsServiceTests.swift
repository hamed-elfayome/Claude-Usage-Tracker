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

    /// Writes a single JSONL session file containing one assistant line per (day, input, output)
    /// tuple. `projectsDir` layout mirrors `~/.claude/projects/<slug>/<session>.jsonl`.
    private func writeJSONL(_ lines: [(day: String, input: Int, output: Int)]) -> URL {
        let projectsDir = tempDir.appendingPathComponent("projects/my-project")
        try! FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let sessionFile = projectsDir.appendingPathComponent("session.jsonl")

        let body = lines.map { line in
            """
            {"type":"assistant","timestamp":"\(line.day)T12:00:00.000Z","message":{"usage":{"input_tokens":\(line.input),"output_tokens":\(line.output),"cache_read_input_tokens":999999}}}
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
        // Cache lifetime total = 1000, authoritative through "today - 3".
        // A JSONL line 2 days after the cutoff (input 100 + output 50) should be added on top.
        let cutoff = day(offsetFromToday: -3)
        let json = """
        {
          "modelUsage": {
            "claude-sonnet-4-5": { "inputTokens": 700, "outputTokens": 300 }
          },
          "dailyModelTokens": [],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([(day: day(offsetFromToday: -1), input: 100, output: 50)])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 1150)
        XCTAssertEqual(stats.last7Days, 0, "disabled frame should not be computed")
        XCTAssertEqual(stats.last30Days, 0, "disabled frame should not be computed")
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
        let projectsDir = writeJSONL([(day: day(offsetFromToday: -2), input: 20, output: 10)])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokens7Days],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.last7Days, 80)
        XCTAssertEqual(stats.allTime, 0, "disabled frame should not be computed")
    }

    func testJSONLLinesOnOrBeforeCutoffAreIgnored() {
        // A JSONL line dated exactly on lastComputedDate duplicates data already folded into the
        // cache and must NOT be double-counted.
        let cutoff = day(offsetFromToday: -1)
        let json = """
        {
          "modelUsage": {
            "m": { "inputTokens": 500, "outputTokens": 0 }
          },
          "dailyModelTokens": [],
          "lastComputedDate": "\(cutoff)"
        }
        """
        let statsURL = writeStatsCache(json)
        let projectsDir = writeJSONL([(day: cutoff, input: 9999, output: 9999)])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 500, "on-cutoff JSONL line already counted in cache; must be ignored")
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
        let projectsDir = writeJSONL([(day: day(offsetFromToday: -1), input: 10, output: 5)])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokens7Days],
            statsURL: statsURL,
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 0, "only enabled frames are computed")
        XCTAssertEqual(stats.last30Days, 0, "only enabled frames are computed")
        XCTAssertEqual(stats.last7Days, 55)
    }

    func testMissingCacheFallsBackToFullJSONLSum() {
        let projectsDir = writeJSONL([
            (day: day(offsetFromToday: -10), input: 100, output: 50),
            (day: day(offsetFromToday: -1), input: 20, output: 5)
        ])

        let stats = TokenStatsService().load(
            enabledFrames: [.tokensAllTime],
            statsURL: missingStatsURL(),
            projectsDir: projectsDir,
            referenceDate: referenceDate
        )

        XCTAssertTrue(stats.isAvailable)
        XCTAssertEqual(stats.allTime, 175)
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
        {"type":"assistant","timestamp":"\(goodDay)T09:00:00.000Z","message":{"usage":{"input_tokens":10,"output_tokens":5}}}
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
        XCTAssertEqual(stats.allTime, 15, "malformed/unusable lines are skipped; the one good line still counts")
    }
}
