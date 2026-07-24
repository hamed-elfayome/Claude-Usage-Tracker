import Foundation

/// Reads and aggregates Claude Code CLI token usage from `~/.claude/stats-cache.json`.
struct TokenStatsService {

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
    }

    /// Loads token stats. Returns `.unavailable` if the file is missing or unreadable.
    func load(from url: URL = Constants.ClaudePaths.statsCacheFile, referenceDate: Date = Date()) -> TokenStats {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return .unavailable
        }

        // All-time: sum input + output across models (exclude cache tokens).
        let allTime = (cache.modelUsage ?? [:]).values.reduce(0) {
            $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0)
        }

        // Windows from daily per-model token sums.
        let daily = cache.dailyModelTokens ?? []
        let last7Days = sumWindow(daily, days: 7, referenceDate: referenceDate)
        let last30Days = sumWindow(daily, days: 30, referenceDate: referenceDate)

        return TokenStats(allTime: allTime, last7Days: last7Days, last30Days: last30Days, isAvailable: true)
    }

    private func sumWindow(_ daily: [Cache.Daily], days: Int, referenceDate: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let today = calendar.startOfDay(for: referenceDate)
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }

        return daily.reduce(0) { acc, entry in
            guard let d = formatter.date(from: entry.date) else { return acc }
            let day = calendar.startOfDay(for: d)
            guard day >= cutoff && day <= today else { return acc }
            return acc + entry.tokensByModel.values.reduce(0, +)
        }
    }
}
