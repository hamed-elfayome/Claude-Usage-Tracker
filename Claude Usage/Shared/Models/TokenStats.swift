import Foundation

/// Aggregated Claude Code CLI token totals (input + output, excluding cache).
struct TokenStats: Codable, Equatable {
    let allTime: Int
    let last7Days: Int
    let last30Days: Int
    /// False when the local stats cache is absent or unreadable.
    let isAvailable: Bool

    static let unavailable = TokenStats(allTime: 0, last7Days: 0, last30Days: 0, isAvailable: false)
}
