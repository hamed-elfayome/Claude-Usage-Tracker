import Foundation

/// Aggregated Claude Code CLI token totals (input + output, excluding cache).
struct TokenStats: Codable, Equatable {
    let allTime: Int
    let last7Days: Int
    let last30Days: Int
    /// False when the local stats cache is absent or unreadable.
    let isAvailable: Bool

    static let unavailable = TokenStats(allTime: 0, last7Days: 0, last30Days: 0, isAvailable: false)

    /// Token count for a token metric type, or nil for non-token metrics.
    func value(for metricType: MenuBarMetricType) -> Int? {
        switch metricType {
        case .tokensAllTime: return allTime
        case .tokens7Days: return last7Days
        case .tokens30Days: return last30Days
        case .session, .week, .api: return nil
        }
    }
}
