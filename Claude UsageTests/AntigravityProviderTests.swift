import XCTest
@testable import Claude_Usage

/// Antigravity provider: `agy /usage` JSON decoding tolerance, pool mapping,
/// not-started window handling, CLI output interpretation, the shared fetch
/// cache, the process runner, and the profile's pool field.
@MainActor
final class AntigravityProviderTests: XCTestCase {

    // MARK: - Fixtures

    /// Real output of `agy --print /usage --output-format json` (2026-11-27),
    /// after one Claude prompt. The email-bearing `response` text is trimmed.
    static let realSample = """
    {"conversation_id":"","status":"SUCCESS","response":"…","duration_seconds":0,"num_turns":0,
     "usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},
     "command":{"name":"usage","data":{"description":"Within each group, models share a weekly limit and a 5-hour limit.",
      "groups":[
       {"name":"Gemini Models","description":"Models within this group: Gemini 4 Hydrogen, Gemini 3.8 Flash",
        "buckets":[{"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":1,"reset_time":"2026-12-04T06:11:47Z"}]},
       {"name":"Claude and GPT models","description":"Models within this group: Claude Sonnet 4.6, Claude Opus 4.6, GPT-OSS 120B",
        "buckets":[
         {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly","remaining_fraction":0.9755905270576477,"reset_time":"2026-12-04T06:11:45Z"},
         {"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h","remaining_fraction":0.9755905270576477,"reset_time":"2026-11-27T11:11:45Z"}]}]}}}
    """

    /// A moment between the sample's 5h reset and its weekly reset.
    static let sampleNow = AntigravityDecoding.parseDate("2026-11-27T08:00:00Z")!

    private func decode(_ json: String) throws -> AntigravityUsageResponse {
        try JSONDecoder().decode(AntigravityUsageResponse.self, from: Data(json.utf8))
    }

    private func date(_ iso: String) -> Date { AntigravityDecoding.parseDate(iso)! }

    // MARK: - Decoding

    func testDecodeRealSample() throws {
        let response = try decode(Self.realSample)
        XCTAssertTrue(response.isSuccess)
        XCTAssertEqual(response.groups.count, 2)
        let ids = response.groups.flatMap(\.buckets).compactMap(\.id)
        XCTAssertEqual(ids, ["gemini-weekly", "3p-weekly", "3p-5h"])
        let fiveHour = try XCTUnwrap(response.groups[1].buckets.last)
        XCTAssertEqual(fiveHour.window, "5h")
        XCTAssertEqual(try XCTUnwrap(fiveHour.remainingFraction), 0.97559, accuracy: 0.0001)
        XCTAssertEqual(fiveHour.resetTime, date("2026-11-27T11:11:45Z"))
    }

    func testDecodeToleratesMissingAndMalformedFields() throws {
        let json = """
        {"status":"SUCCESS","command":{"data":{"groups":[
          {"name":42,"buckets":[
            {"id":"3p-5h","window":"5h","remaining_fraction":"lots","reset_time":"not a date"},
            {"id":"3p-weekly","window":"weekly","remaining_fraction":0.5},
            "garbage",
            {"window":"fortnightly","remaining_fraction":0.1,"extra":{"nested":true}}
          ]},
          {"buckets":"not an array"}
        ]}}}
        """
        let response = try decode(json)
        XCTAssertEqual(response.groups.count, 2)
        let buckets = response.groups[0].buckets
        XCTAssertNil(response.groups[0].name, "a malformed name becomes nil")
        XCTAssertEqual(buckets.count, 3, "an element that isn't an object is skipped, not fatal")
        XCTAssertEqual(buckets[0].id, "3p-5h")
        XCTAssertNil(buckets[0].remainingFraction)
        XCTAssertNil(buckets[0].resetTime)
        XCTAssertEqual(buckets[1].remainingFraction, 0.5)
        XCTAssertEqual(buckets[2].window, "fortnightly", "unknown window values pass through")
        XCTAssertTrue(response.groups[1].buckets.isEmpty)
    }

    func testDecodeWithoutCommandYieldsNoGroups() throws {
        let response = try decode(#"{"status":"ERROR","error":"authentication failed or timed out"}"#)
        XCTAssertFalse(response.isSuccess)
        XCTAssertEqual(response.error, "authentication failed or timed out")
        XCTAssertTrue(response.groups.isEmpty)
    }

    func testFractionalSecondDatesParse() {
        XCTAssertNotNil(AntigravityDecoding.parseDate("2026-11-27T11:11:45.123Z"))
        XCTAssertNotNil(AntigravityDecoding.parseDate("2026-11-27T11:11:45Z"))
        XCTAssertNil(AntigravityDecoding.parseDate("yesterday"))
    }

    // MARK: - Mapping

    func testThirdPartyPoolMapsBothWindows() throws {
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(
            try decode(Self.realSample), pool: .thirdParty, now: Self.sampleNow))
        XCTAssertTrue(usage.hasSessionLimit)
        XCTAssertTrue(usage.hasWeeklyLimit)
        XCTAssertEqual(usage.sessionPercentage, 2.44, accuracy: 0.01)
        XCTAssertEqual(usage.weeklyPercentage, 2.44, accuracy: 0.01)
        XCTAssertEqual(usage.sessionResetTime, date("2026-11-27T11:11:45Z"))
        XCTAssertEqual(usage.weeklyResetTime, date("2026-12-04T06:11:45Z"))
    }

    func testMappingHasNoTokenCountsOrPlan() throws {
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(
            try decode(Self.realSample), pool: .thirdParty, now: Self.sampleNow))
        XCTAssertEqual(usage.weeklyLimit, 0)
        XCTAssertEqual(usage.sessionLimit, 0)
        XCTAssertEqual(usage.sessionTokensUsed, 0)
        XCTAssertEqual(usage.weeklyTokensUsed, 0)
        XCTAssertNil(usage.planType)
    }

    func testGeminiWeeklyOnlyHidesSession() throws {
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(
            try decode(Self.realSample), pool: .gemini, now: Self.sampleNow))
        XCTAssertFalse(usage.hasSessionLimit, "no gemini-5h bucket → no session metric")
        XCTAssertTrue(usage.hasWeeklyLimit)
        XCTAssertEqual(usage.weeklyPercentage, 0)
    }

    func testGeminiFiveHourBucketMapsToSession() throws {
        let json = """
        {"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[
          {"id":"gemini-5h","window":"5h","remaining_fraction":0.25,"reset_time":"2026-11-27T10:00:00Z"},
          {"id":"gemini-weekly","window":"weekly","remaining_fraction":0.8,"reset_time":"2026-12-01T00:00:00Z"}]}]}}}
        """
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(try decode(json), pool: .gemini, now: Self.sampleNow))
        XCTAssertTrue(usage.hasSessionLimit)
        XCTAssertEqual(usage.sessionPercentage, 75, accuracy: 0.001)
        XCTAssertEqual(usage.weeklyPercentage, 20, accuracy: 0.001)
        XCTAssertEqual(usage.sessionResetTime, date("2026-11-27T10:00:00Z"))
    }

    func testModelSpecificWeeklyBucketIsIgnored() throws {
        let json = """
        {"status":"SUCCESS","command":{"data":{"groups":[{"name":"Gemini Models","buckets":[
          {"id":"gemini-argon-wtu-weekly","window":"weekly","remaining_fraction":0.1,"reset_time":"2026-12-02T00:00:00Z"},
          {"id":"gemini-weekly","window":"weekly","remaining_fraction":0.9,"reset_time":"2026-12-01T00:00:00Z"}]}]}}}
        """
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(try decode(json), pool: .gemini, now: Self.sampleNow))
        XCTAssertEqual(usage.weeklyPercentage, 10, accuracy: 0.001, "the pool's own weekly bucket wins over a model-specific one")
    }

    func testMissingPoolReturnsNil() throws {
        let json = """
        {"status":"SUCCESS","command":{"data":{"groups":[{"name":"Claude and GPT models","buckets":[
          {"id":"3p-5h","window":"5h","remaining_fraction":0.5,"reset_time":"2026-11-27T10:00:00Z"}]}]}}}
        """
        XCTAssertNil(AntigravityUsageMapper.mapToUsage(try decode(json), pool: .gemini, now: Self.sampleNow))
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(try decode(json), pool: .thirdParty, now: Self.sampleNow))
        XCTAssertFalse(usage.hasWeeklyLimit, "a pool without a weekly bucket hides the weekly metric")
    }

    // MARK: - Full quota list (popover)

    func testQuotaListPutsTheMenuBarPoolFirst() throws {
        let response = try decode(Self.realSample)
        let third = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(response, pool: .thirdParty, now: Self.sampleNow))
        let gemini = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(response, pool: .gemini, now: Self.sampleNow))
        XCTAssertEqual(third.quotas.map(\.id), ["3p-5h", "3p-weekly", "gemini-weekly"],
                       "menu bar pool first, session before weekly")
        XCTAssertEqual(gemini.quotas.map(\.id), ["gemini-weekly", "3p-5h", "3p-weekly"])
        XCTAssertEqual(Set(gemini.quotas.map(\.id)), Set(third.quotas.map(\.id)), "every pool is listed either way")
        XCTAssertEqual(third.quotas.map(\.window), [.session, .weekly, .weekly])
        XCTAssertEqual(third.quotas.map(\.titleKey),
                       ["antigravity.quota.third_party", "antigravity.quota.third_party", "antigravity.quota.gemini"])
        XCTAssertEqual(third.quotas[1].usedPercentage, 2.44, accuracy: 0.01)
    }

    func testQuotaListShowsNoResetForWindowsThatHaveNotStarted() throws {
        let response = try decode(Self.realSample)
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(response, pool: .thirdParty, now: Self.sampleNow))
        XCTAssertEqual(usage.quotas[0].resetTime, date("2026-11-27T11:11:45Z"))
        XCTAssertEqual(usage.quotas[1].resetTime, date("2026-12-04T06:11:45Z"))
        XCTAssertNil(usage.quotas[2].resetTime, "gemini-weekly is unused: its rolling reset is not a countdown")
    }

    func testQuotaListSurvivesTheProfileCacheRoundTrip() throws {
        let response = try decode(Self.realSample)
        let usage = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(response, pool: .thirdParty, now: Self.sampleNow))
        let decoded = try JSONDecoder().decode(ClaudeUsage.self, from: JSONEncoder().encode(usage))
        XCTAssertEqual(decoded.quotas, usage.quotas)
    }

    func testUsageSavedWithoutQuotasDecodesToAnEmptyList() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ClaudeUsage.empty)) as? [String: Any])
        json.removeValue(forKey: "quotas")
        XCTAssertTrue(try JSONDecoder().decode(ClaudeUsage.self, from: JSONSerialization.data(withJSONObject: json)).quotas.isEmpty)
        json["quotas"] = "not a list"
        XCTAssertTrue(try JSONDecoder().decode(ClaudeUsage.self, from: JSONSerialization.data(withJSONObject: json)).quotas.isEmpty,
                      "a malformed list degrades to empty instead of dropping the cached usage")
    }

    func testFractionIsClampedAndConverted() {
        func bucket(_ fraction: Double?) -> AntigravityQuotaBucket {
            AntigravityQuotaBucket(id: "3p-5h", window: "5h", remainingFraction: fraction, resetTime: nil)
        }
        XCTAssertEqual(AntigravityUsageMapper.usedPercent(bucket(1)), 0)
        XCTAssertEqual(AntigravityUsageMapper.usedPercent(bucket(0)), 100)
        XCTAssertEqual(AntigravityUsageMapper.usedPercent(bucket(1.7)), 0)
        XCTAssertEqual(AntigravityUsageMapper.usedPercent(bucket(-0.5)), 100)
        XCTAssertEqual(AntigravityUsageMapper.usedPercent(bucket(nil)), 0)
        XCTAssertEqual(AntigravityUsageMapper.usedPercent(bucket(.nan)), 0)
    }

    // MARK: - Not-started windows (reset-time stability)

    func testEpochResetFallsBackToWindowFromNow() {
        let bucket = AntigravityQuotaBucket(id: "3p-5h", window: "5h", remainingFraction: 1,
                                            resetTime: Date(timeIntervalSince1970: 0))
        let reset = AntigravityUsageMapper.resetTime(bucket, previous: nil,
                                                     window: AntigravityUsageMapper.sessionWindow, now: Self.sampleNow)
        XCTAssertEqual(reset, Self.sampleNow.addingTimeInterval(5 * 3600))
    }

    func testNotStartedWindowKeepsPreviousFutureReset() {
        let previous = Self.sampleNow.addingTimeInterval(3 * 86_400)
        // agy reports an unused Gemini weekly window as a rolling "now + 7d".
        let rolling = AntigravityQuotaBucket(id: "gemini-weekly", window: "weekly", remainingFraction: 1,
                                             resetTime: Self.sampleNow.addingTimeInterval(7 * 86_400))
        let reset = AntigravityUsageMapper.resetTime(rolling, previous: previous,
                                                     window: AntigravityUsageMapper.weeklyWindow, now: Self.sampleNow)
        XCTAssertEqual(reset, previous, "an unused window must not move its reset time every refresh")
    }

    func testWindowIdleLongerThanItsLengthGetsANewPlaceholder() {
        // previous placeholder already passed: a fresh one is used. The jump is
        // harmless: history skips 0% reset snapshots and notifications key on
        // the percentage, not the reset time.
        let bucket = AntigravityQuotaBucket(id: "3p-5h", window: "5h", remainingFraction: 1,
                                            resetTime: Date(timeIntervalSince1970: 0))
        let reset = AntigravityUsageMapper.resetTime(bucket, previous: Self.sampleNow.addingTimeInterval(-60),
                                                     window: AntigravityUsageMapper.sessionWindow, now: Self.sampleNow)
        XCTAssertEqual(reset, Self.sampleNow.addingTimeInterval(5 * 3600))
    }

    func testStartedWindowUsesReportedReset() {
        let reported = Self.sampleNow.addingTimeInterval(3600)
        let bucket = AntigravityQuotaBucket(id: "3p-5h", window: "5h", remainingFraction: 0.9, resetTime: reported)
        let reset = AntigravityUsageMapper.resetTime(bucket, previous: Self.sampleNow.addingTimeInterval(7200),
                                                     window: AntigravityUsageMapper.sessionWindow, now: Self.sampleNow)
        XCTAssertEqual(reset, reported)
    }

    func testRepeatedMappingOfUnusedPoolIsStable() throws {
        let first = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(
            try decode(Self.realSample), pool: .gemini, now: Self.sampleNow))
        let later = Self.sampleNow.addingTimeInterval(120)
        let rolled = Self.realSample.replacingOccurrences(of: "2026-12-04T06:11:47Z", with: "2026-12-04T08:02:00Z")
        let second = try XCTUnwrap(AntigravityUsageMapper.mapToUsage(
            try decode(rolled), pool: .gemini, previous: first, now: later))
        XCTAssertFalse(ResetDetection.isReset(from: first.weeklyResetTime, to: second.weeklyResetTime),
                       "a rolling reset on an unused window must not register as a reset")
    }

    // MARK: - CLI output interpretation

    private func result(stdout: String = "", stderr: String = "", exit: Int32? = 0, timedOut: Bool = false) -> AntigravityProcessResult {
        AntigravityProcessResult(exitCode: exit, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8),
                                 timedOut: timedOut, stoppedEarly: false)
    }

    private func assertAppError(_ code: ErrorCode, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual((error as? AppError)?.code, code, file: file, line: line)
        }
    }

    func testInterpretSuccess() throws {
        let response = try AntigravityCLIClient.interpret(result(stdout: Self.realSample))
        XCTAssertEqual(response.groups.count, 2)
    }

    func testInterpretAuthRequiredOnStderrIsAuthExpired() {
        assertAppError(.providerAuthExpired) {
            _ = try AntigravityCLIClient.interpret(result(
                stderr: "Authentication required. Please visit the URL to log in:\n  https://accounts.google.com/…",
                exit: nil))
        }
    }

    func testInterpretAuthErrorStatusIsAuthExpired() {
        assertAppError(.providerAuthExpired) {
            _ = try AntigravityCLIClient.interpret(result(
                stdout: #"{"status":"ERROR","error":"authentication failed or timed out"}"#))
        }
    }

    func testInterpretOtherErrorStatusIsNotACredentialError() {
        assertAppError(.apiGenericError) {
            _ = try AntigravityCLIClient.interpret(result(stdout: #"{"status":"ERROR","error":"backend unavailable"}"#))
        }
    }

    func testInterpretTimeoutWithoutOutput() {
        assertAppError(.networkTimeout) {
            _ = try AntigravityCLIClient.interpret(result(exit: nil, timedOut: true))
        }
    }

    func testInterpretNonJSONOutput() {
        assertAppError(.apiParsingFailed) {
            _ = try AntigravityCLIClient.interpret(result(stdout: "Gemini Models\tWeekly\t100%"))
        }
    }

    func testInterpretSuccessWithoutGroups() {
        assertAppError(.apiParsingFailed) {
            _ = try AntigravityCLIClient.interpret(result(stdout: #"{"status":"SUCCESS","command":{"data":{}}}"#))
        }
    }

    // MARK: - Shared fetch

    private final class CountingFetcher: AntigravityUsageFetching {
        var calls = 0
        var delayNanos: UInt64 = 50_000_000
        var response: AntigravityUsageResponse
        var error: Error?

        init(response: AntigravityUsageResponse) { self.response = response }

        func fetchUsage() async throws -> AntigravityUsageResponse {
            calls += 1
            try await Task.sleep(nanoseconds: delayNanos)
            if let error { throw error }
            return response
        }
    }

    func testConcurrentProfilesShareOneCLICall() async throws {
        let fetcher = CountingFetcher(response: try decode(Self.realSample))
        let provider = AntigravityUsageProvider(fetcher: fetcher, maxAge: 60)
        let claude = Profile(name: "A", provider: .antigravity, antigravityPool: .thirdParty)
        let gemini = Profile(name: "B", provider: .antigravity, antigravityPool: .gemini)

        async let first = provider.fetchUsage(for: claude)
        async let second = provider.fetchUsage(for: gemini)
        let (claudeUsage, geminiUsage) = try await (first, second)

        XCTAssertEqual(fetcher.calls, 1, "concurrent profiles must coalesce into one agy run")
        XCTAssertTrue(claudeUsage.hasSessionLimit)
        XCTAssertFalse(geminiUsage.hasSessionLimit, "each profile maps its own pool")

        _ = try await provider.fetchUsage(for: claude)
        XCTAssertEqual(fetcher.calls, 1, "a fresh result is reused within maxAge")

        _ = try await provider.fetchUsage(for: claude, forceRefresh: true)
        XCTAssertEqual(fetcher.calls, 2, "forceRefresh bypasses the cache")
    }

    func testDefaultPoolIsThirdParty() async throws {
        let fetcher = CountingFetcher(response: try decode(Self.realSample))
        let provider = AntigravityUsageProvider(fetcher: fetcher, maxAge: 60)
        let usage = try await provider.fetchUsage(for: Profile(name: "A", provider: .antigravity))
        XCTAssertTrue(usage.hasSessionLimit, "nil pool → Claude & GPT pool, which has a 5h window")
    }

    func testFailuresAreNotCached() async throws {
        let fetcher = CountingFetcher(response: try decode(Self.realSample))
        fetcher.error = AntigravityCLIClient.authRequiredError()
        let provider = AntigravityUsageProvider(fetcher: fetcher, maxAge: 60)
        let profile = Profile(name: "A", provider: .antigravity)
        do {
            _ = try await provider.fetchUsage(for: profile)
            XCTFail("expected an error")
        } catch {}
        fetcher.error = nil
        _ = try await provider.fetchUsage(for: profile)
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testMissingPoolThrowsParsingError() async throws {
        let json = #"{"status":"SUCCESS","command":{"data":{"groups":[{"buckets":[{"id":"3p-5h","window":"5h","remaining_fraction":1}]}]}}}"#
        let provider = AntigravityUsageProvider(fetcher: CountingFetcher(response: try decode(json)), maxAge: 60)
        do {
            _ = try await provider.fetchUsage(for: Profile(name: "G", provider: .antigravity, antigravityPool: .gemini))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? AppError)?.code, .apiParsingFailed)
        }
    }

    // MARK: - CLI locator

    func testLocatorPrefersOverrideThenKnownPaths() {
        let home = URL(fileURLWithPath: "/Users/test")
        let existing: Set<String> = ["/custom/agy", "/Users/test/.local/bin/agy", "/opt/homebrew/bin/agy"]
        let locator = AntigravityCLILocator(environment: ["AGY_BIN": "/custom/agy"], homeDirectory: home,
                                            isExecutable: { existing.contains($0.path) }, shellLookup: { nil })
        XCTAssertEqual(locator.cachedExecutable()?.path, "/custom/agy")

        let noOverride = AntigravityCLILocator(environment: [:], homeDirectory: home,
                                               isExecutable: { existing.contains($0.path) }, shellLookup: { nil })
        XCTAssertEqual(noOverride.cachedExecutable()?.path, "/Users/test/.local/bin/agy")
    }

    func testLocatorFallsBackToLoginShellOnce() async {
        var lookups = 0
        let locator = AntigravityCLILocator(environment: [:], homeDirectory: URL(fileURLWithPath: "/nowhere"),
                                            isExecutable: { $0.path == "/shell/agy" },
                                            shellLookup: { lookups += 1; return URL(fileURLWithPath: "/shell/agy") })
        XCTAssertNil(locator.cachedExecutable(), "the sync path never runs the shell")
        let resolved = await locator.resolve()
        XCTAssertEqual(resolved?.path, "/shell/agy")
        XCTAssertEqual(locator.cachedExecutable()?.path, "/shell/agy", "the shell result is cached")
        _ = await locator.resolve()
        XCTAssertEqual(lookups, 1)
    }

    func testLocatorWarmsUpInBackgroundWhenAsked() async throws {
        var lookups = 0
        let locator = AntigravityCLILocator(environment: [:], homeDirectory: URL(fileURLWithPath: "/nowhere"),
                                            isExecutable: { $0.path == "/shell/agy" },
                                            shellLookup: { lookups += 1; return URL(fileURLWithPath: "/shell/agy") },
                                            warmUpInBackground: true)
        XCTAssertNil(locator.cachedExecutable(), "the first quick check still answers immediately")
        for _ in 0..<50 where locator.cachedExecutable() == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(locator.cachedExecutable()?.path, "/shell/agy", "a later quick check sees the background result")
        XCTAssertEqual(lookups, 1)
    }

    func testLocatorCachesAFailedShellLookup() async {
        var lookups = 0
        let locator = AntigravityCLILocator(environment: [:], homeDirectory: URL(fileURLWithPath: "/nowhere"),
                                            isExecutable: { _ in false }, shellLookup: { lookups += 1; return nil })
        let first = await locator.resolve()
        let second = await locator.resolve()
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(lookups, 1)
        locator.resetShellLookup()
        _ = await locator.resolve()
        XCTAssertEqual(lookups, 2, "Rescan retries the shell lookup")
    }

    // MARK: - Process runner

    private func script(_ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agy-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fake-agy")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testRunnerCapturesOutputAndExitCode() async throws {
        let result = try await AntigravityProcessRunner.run(
            executable: try script("echo out; echo err >&2; exit 3"), arguments: [], timeout: 10)
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "out\n")
        XCTAssertEqual(String(decoding: result.stderr, as: UTF8.self), "err\n")
        XCTAssertFalse(result.timedOut)
    }

    func testRunnerKillsAProcessThatOutlivesTheDeadline() async throws {
        let start = Date()
        let result = try await AntigravityProcessRunner.run(
            executable: try script("trap '' TERM; sleep 30"), arguments: [], timeout: 0.5)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "SIGKILL follows an ignored SIGTERM")
    }

    func testRunnerDoesNotDeadlockOnLargeOutput() async throws {
        let result = try await AntigravityProcessRunner.run(
            executable: try script("head -c 2000000 /dev/zero"), arguments: [], timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 2_000_000)
        XCTAssertFalse(result.timedOut)
    }

    func testRunnerCapsOutput() async throws {
        let result = try await AntigravityProcessRunner.run(
            executable: try script("head -c 100000 /dev/zero"), arguments: [], timeout: 10, maxOutputBytes: 1000)
        XCTAssertEqual(result.stdout.count, 1000)
    }

    func testRunnerStopsEarlyOnAuthPrompt() async throws {
        // Mirrors a logged-out agy: prints the auth prompt, then waits forever.
        let start = Date()
        let result = try await AntigravityProcessRunner.run(
            executable: try script("echo 'Authentication required. Please visit the URL to log in:' >&2; sleep 30"),
            arguments: [], timeout: 20,
            stopWhen: { _, stderr in AntigravityOutputMarkers.containsAuthRequired(stderr) })
        XCTAssertTrue(result.stoppedEarly)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertThrowsError(try AntigravityCLIClient.interpret(result)) { error in
            XCTAssertEqual((error as? AppError)?.code, .providerAuthExpired)
        }
    }

    func testRunnerReportsLaunchFailure() async {
        do {
            _ = try await AntigravityProcessRunner.run(
                executable: URL(fileURLWithPath: "/nonexistent/agy"), arguments: [], timeout: 5)
            XCTFail("expected a launch failure")
        } catch {
            guard case AntigravityProcessRunner.RunError.launchFailed = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testClientWithoutCLIIsCredentialsNotFound() async {
        let locator = AntigravityCLILocator(environment: [:], homeDirectory: URL(fileURLWithPath: "/nowhere"),
                                            isExecutable: { _ in false }, shellLookup: { nil })
        do {
            _ = try await AntigravityCLIClient(locator: locator).fetchUsage()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? AppError)?.code, .providerCredentialsNotFound)
        }
    }

    func testClientEndToEndWithFakeCLI() async throws {
        let sampleFile = FileManager.default.temporaryDirectory.appendingPathComponent("agy-sample-\(UUID().uuidString).json")
        try Self.realSample.write(to: sampleFile, atomically: true, encoding: .utf8)
        let fake = try script("""
        [ "$1" = "--print" ] && [ "$2" = "/usage" ] && [ "$3" = "--output-format" ] && [ "$4" = "json" ] || exit 9
        cat '\(sampleFile.path)'
        """)
        let locator = AntigravityCLILocator(environment: ["AGY_BIN": fake.path], homeDirectory: URL(fileURLWithPath: "/nowhere"),
                                            shellLookup: { nil })
        let workDir = fake.deletingLastPathComponent().appendingPathComponent("probe")
        let response = try await AntigravityCLIClient(locator: locator, workingDirectory: workDir).fetchUsage()
        XCTAssertEqual(response.groups.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workDir.path), "agy runs in a fixed probe directory")
    }

    // MARK: - Profile codec

    private func decodeProfile(poolField: String?) throws -> Profile {
        var fields = #""id":"6F1C2D3E-0000-4000-8000-000000000001","name":"G","provider":"antigravity""#
        if let poolField { fields += ",\"antigravityPool\":\(poolField)" }
        return try JSONDecoder().decode(Profile.self, from: Data("{\(fields)}".utf8))
    }

    func testPoolMissingDecodesToNil() throws {
        let profile = try decodeProfile(poolField: nil)
        XCTAssertEqual(profile.provider, .antigravity)
        XCTAssertNil(profile.antigravityPool)
    }

    func testPoolUnknownOrMalformedDegradesToNil() throws {
        XCTAssertNil(try decodeProfile(poolField: "\"someFuturePool\"").antigravityPool)
        XCTAssertNil(try decodeProfile(poolField: "42").antigravityPool)
    }

    func testPoolRoundTrips() throws {
        let original = Profile(name: "G", provider: .antigravity, antigravityPool: .gemini)
        let decoded = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded.provider, .antigravity)
        XCTAssertEqual(decoded.antigravityPool, .gemini)
    }

    // MARK: - Registry

    func testDescriptorCapabilities() {
        let descriptor = Provider.antigravity.descriptor
        XCTAssertEqual(descriptor.displayName, "Google Antigravity")
        XCTAssertNil(descriptor.statusPageURL, "no Statuspage feed: the status row is hidden, not Anthropic's shown")
        XCTAssertEqual(descriptor.credentialSections, [.antigravityAccount])
        let c = descriptor.capabilities
        XCTAssertFalse(c.tokenCounts || c.perModelBreakdown || c.consoleBilling || c.cliAccountSync
                       || c.autoStartSession || c.overageChecks || c.personalSpend || c.credits)
        XCTAssertTrue(ProviderRegistry.service(for: .antigravity) is AntigravityUsageProvider)
    }

    func testEveryProviderHasItsOwnSetupHint() {
        let hints = Provider.allCases.map(\.descriptor.setupHintKey)
        XCTAssertEqual(Set(hints).count, hints.count)
    }
}
