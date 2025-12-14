import Foundation

/// Main data model representing Claude Code usage statistics
struct ClaudeUsage: Codable, Equatable {
    // Session data (5-hour rolling window)
    var sessionTokensUsed: Int
    var sessionLimit: Int
    var sessionPercentage: Double
    var sessionResetTime: Date

    // Weekly data (all models)
    var weeklyTokensUsed: Int
    var weeklyLimit: Int
    var weeklyPercentage: Double
    var weeklyResetTime: Date

    // Weekly data (Opus only)
    var opusWeeklyTokensUsed: Int
    var opusWeeklyPercentage: Double

    // Monthly Cost data
    var costUsed: Double?
    var costLimit: Double?
    var costCurrency: String?

    // Metadata
    var lastUpdated: Date
    var userTimezone: TimeZone

    /// Returns the status color based on session percentage
    var statusLevel: UsageStatusLevel {
        switch sessionPercentage {
        case 0..<50:
            return .safe
        case 50..<80:
            return .moderate
        default:
            return .critical
        }
    }

    /// Empty usage data (used when no data is available)
    static var empty: ClaudeUsage {
        ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 0,
            sessionPercentage: 0,
            sessionResetTime: Date().addingTimeInterval(5 * 60 * 60),
            weeklyTokensUsed: 0,
            weeklyLimit: 1_000_000,
            weeklyPercentage: 0,
            weeklyResetTime: Date().nextMonday1259pm(),
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }
}

/// Usage status level for color coding
enum UsageStatusLevel {
    case safe       // 0-50%: Green
    case moderate   // 51-80%: Yellow
    case critical   // 81-100%: Red
}
