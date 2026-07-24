import Foundation

/// Reads and aggregates Claude Code CLI token usage (input + output tokens, excluding all
/// cache tokens) to match what `claude`'s live "Stats" view reports.
///
/// `~/.claude/stats-cache.json` is only refreshed periodically by the CLI, so reading it alone
/// lags behind the live number by however many days have passed since its `lastComputedDate`.
/// The CLI's live total is effectively:
///
///     cache totals (authoritative through lastComputedDate)
///   + input/output tokens from the raw JSONL session logs for days AFTER lastComputedDate
///
/// This service reproduces that by treating `lastComputedDate` as a cutoff: days on/before it
/// are read from the cache (cheap), and only days after it are recomputed from
/// `~/.claude/projects/**/*.jsonl` (comparatively expensive). To bound that JSONL work, only the
/// time frames present in `enabledFrames` are scanned for; the rest are left at 0.
struct TokenStatsService {

    // MARK: - stats-cache.json decoding

    private struct Cache: Decodable {
        struct Model: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
        }
        struct Daily: Decodable {
            let date: String
            let tokensByModel: [String: Int]
        }
        let modelUsage: [String: Model]?
        let dailyModelTokens: [Daily]?
        /// "yyyy-MM-dd" - the day through which the cache's totals are authoritative.
        let lastComputedDate: String?
    }

    // MARK: - JSONL line decoding

    /// Minimal shape of one assistant line in a `~/.claude/projects/**/*.jsonl` session file.
    /// Decoded with `.convertFromSnakeCase` so `input_tokens`/`output_tokens` map directly.
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let inputTokens: Int?
                let outputTokens: Int?
            }
            let usage: Usage?
        }
        let message: Message?
        let timestamp: String?
    }

    // MARK: - Calendar / date-key helpers

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func startOfDay(_ date: Date) -> Date {
        Self.calendar.startOfDay(for: date)
    }

    private func dayKey(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func dayAfter(_ date: Date) -> Date {
        Self.calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    /// Parses the "yyyy-MM-dd" prefix of an ISO8601 timestamp into a start-of-day `Date`.
    private func dayFromTimestamp(_ timestamp: String) -> Date? {
        guard timestamp.count >= 10 else { return nil }
        guard let date = Self.dayFormatter.date(from: String(timestamp.prefix(10))) else { return nil }
        return startOfDay(date)
    }

    // MARK: - Public API

    /// Loads token stats for exactly the requested frames.
    ///
    /// - Parameters:
    ///   - enabledFrames: Menu-bar metrics currently enabled. Non-token metrics are ignored.
    ///     Frames not present here are left at 0 - this is the load-reduction that keeps the
    ///     JSONL scan bounded to only what's actually displayed.
    /// - Returns: `.unavailable` when neither the cache nor any JSONL file could be read, or
    ///   when no token frame is enabled.
    func load(
        enabledFrames: Set<MenuBarMetricType>,
        statsURL: URL = Constants.ClaudePaths.statsCacheFile,
        projectsDir: URL = Constants.ClaudePaths.projectsDirectory,
        referenceDate: Date = Date()
    ) -> TokenStats {
        let tokenFrames = enabledFrames.filter { $0.isTokenMetric }
        guard !tokenFrames.isEmpty else { return .unavailable }

        let (cacheAllTime, cacheDaily, lastComputed, cacheAvailable) = readCache(from: statsURL)
        let today = startOfDay(referenceDate)

        // Days on/before this are authoritative in the cache; days after it need JSONL.
        // With no usable cache, .distantPast means "nothing is covered - everything from JSONL".
        let cacheCutoff = lastComputed ?? .distantPast

        // Lower bound for the JSONL scan: the earliest day any enabled frame still needs.
        // All-time needs every day after the cutoff (the widest possible need), which also
        // covers any window frame enabled alongside it.
        let scanFrom: Date
        if tokenFrames.contains(.tokensAllTime) {
            scanFrom = dayAfter(cacheCutoff)
        } else {
            let maxWindow = tokenFrames.contains(.tokens30Days) ? 30 : 7
            let windowStart = Self.calendar.date(byAdding: .day, value: -(maxWindow - 1), to: today) ?? today
            scanFrom = max(dayAfter(cacheCutoff), windowStart)
        }

        let (deltaDaily, anyJSONLParsed) = scanJSONL(
            projectsDir: projectsDir,
            cacheCutoff: cacheCutoff,
            scanFrom: scanFrom,
            today: today
        )

        var allTime = 0
        var last7Days = 0
        var last30Days = 0

        if tokenFrames.contains(.tokensAllTime) {
            // deltaDaily only holds days > cacheCutoff (scanFrom = dayAfter(cutoff) above), so
            // its full sum is exactly the "days after the cache" contribution.
            allTime = cacheAllTime + deltaDaily.values.reduce(0, +)
        }
        if tokenFrames.contains(.tokens7Days) {
            last7Days = windowSum(days: 7, today: today, cacheCutoff: cacheCutoff, cacheDaily: cacheDaily, deltaDaily: deltaDaily)
        }
        if tokenFrames.contains(.tokens30Days) {
            last30Days = windowSum(days: 30, today: today, cacheCutoff: cacheCutoff, cacheDaily: cacheDaily, deltaDaily: deltaDaily)
        }

        guard cacheAvailable || anyJSONLParsed else { return .unavailable }

        return TokenStats(allTime: allTime, last7Days: last7Days, last30Days: last30Days, isAvailable: true)
    }

    // MARK: - Cache reading

    private func readCache(from url: URL) -> (allTime: Int, daily: [String: Int], lastComputed: Date?, available: Bool) {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return (0, [:], nil, false)
        }

        let lastComputed = cache.lastComputedDate
            .flatMap { Self.dayFormatter.date(from: $0) }
            .map(startOfDay)

        // Without a valid cutoff we can't safely combine cache aggregates with a JSONL delta
        // (every day would route to JSONL while the cache's lifetime total still got added,
        // double-counting everything). Fail safe to pure JSONL: report no cache aggregates, and
        // let cacheAvailable be false so availability falls through to "did JSONL parse anything."
        guard let lastComputed else {
            return (0, [:], nil, false)
        }

        let allTime = (cache.modelUsage ?? [:]).values.reduce(0) {
            $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0)
        }

        var daily: [String: Int] = [:]
        for entry in cache.dailyModelTokens ?? [] {
            daily[entry.date, default: 0] += entry.tokensByModel.values.reduce(0, +)
        }

        return (allTime, daily, lastComputed, true)
    }

    // MARK: - JSONL scanning

    /// Walks `projectsDir` for `*.jsonl` files and sums input+output tokens per day, restricted
    /// to days strictly after `cacheCutoff`, within `[scanFrom, today]`.
    ///
    /// Perf: files whose content-modification date predates `scanFrom` are skipped without being
    /// opened. A JSONL file only gains lines for a given day when the CLI writes them that day,
    /// so if its mtime is older than `scanFrom` it cannot contain any line we need.
    private func scanJSONL(
        projectsDir: URL,
        cacheCutoff: Date,
        scanFrom: Date,
        today: Date
    ) -> (daily: [String: Int], anyParsed: Bool) {
        var daily: [String: Int] = [:]
        var anyParsed = false

        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (daily, false)
        }

        let lineDecoder = JSONDecoder()
        lineDecoder.keyDecodingStrategy = .convertFromSnakeCase

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Assumes a JSONL file's mtime tracks its latest appended line (true for normal CLI
            // writes); an externally-reset mtime could under-scan.
            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let mtime = values.contentModificationDate,
               mtime < scanFrom {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            anyParsed = true

            for rawLine in content.split(separator: "\n") {
                // Cheap pre-filter before paying for JSON decoding.
                guard rawLine.contains("\"usage\""), let lineData = rawLine.data(using: .utf8) else { continue }

                guard let line = try? lineDecoder.decode(Line.self, from: lineData),
                      let usage = line.message?.usage,
                      let timestamp = line.timestamp,
                      let day = dayFromTimestamp(timestamp) else { continue }

                guard day > cacheCutoff, day >= scanFrom, day <= today else { continue }

                daily[dayKey(day), default: 0] += (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
            }
        }

        return (daily, anyParsed)
    }

    // MARK: - Window aggregation

    /// Sums the trailing `days`-day window ending at `today`, taking each day from the cache
    /// when it's on/before `cacheCutoff`, or from the JSONL delta otherwise.
    private func windowSum(
        days: Int,
        today: Date,
        cacheCutoff: Date,
        cacheDaily: [String: Int],
        deltaDaily: [String: Int]
    ) -> Int {
        var total = 0
        for offset in 0..<days {
            guard let day = Self.calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayKey(day)
            total += day <= cacheCutoff ? (cacheDaily[key] ?? 0) : (deltaDaily[key] ?? 0)
        }
        return total
    }
}
