import Foundation

/// Main data model representing Claude Code usage statistics
struct ClaudeUsage: Codable, Equatable {
    // Session data (5-hour rolling window)
    var sessionTokensUsed: Int
    var sessionLimit: Int
    var sessionPercentage: Double
    var sessionResetTime: Date

    /// Returns 0% if the 5-hour session window has expired, otherwise the raw percentage.
    var effectiveSessionPercentage: Double {
        sessionResetTime < Date() ? 0.0 : sessionPercentage
    }

    // Weekly data (all models)
    var weeklyTokensUsed: Int
    var weeklyLimit: Int
    var weeklyPercentage: Double
    var weeklyResetTime: Date

    // Weekly data (Opus only)
    var opusWeeklyTokensUsed: Int
    var opusWeeklyPercentage: Double

    // Weekly data (Sonnet only)
    var sonnetWeeklyTokensUsed: Int
    var sonnetWeeklyPercentage: Double
    var sonnetWeeklyResetTime: Date?

    // Weekly data (Design only)
    var designWeeklyTokensUsed: Int
    var designWeeklyPercentage: Double
    var designWeeklyResetTime: Date?

    // Extra usage data
    var costUsed: Double?
    var costLimit: Double?
    var costCurrency: String?

    // Overage credit grant balance
    var overageBalance: Double?
    var overageBalanceCurrency: String?

    // Metadata
    var lastUpdated: Date
    var userTimezone: TimeZone

    /// Remaining percentage (100 - used percentage)
    var remainingPercentage: Double {
        max(0, 100 - effectiveSessionPercentage)
    }

    /// Returns the status level based on remaining percentage (like Mac battery indicator)
    /// DEPRECATED: Use UsageStatusCalculator.calculateStatus() instead for display-aware logic
    /// This property remains for backwards compatibility only
    /// - > 20% remaining: safe (green)
    /// - 10-20% remaining: moderate (orange)
    /// - < 10% remaining: critical (red)
    @available(*, deprecated, message: "Use UsageStatusCalculator.calculateStatus() with showRemaining parameter")
    var statusLevel: UsageStatusLevel {
        switch remainingPercentage {
        case 20...:
            return .safe
        case 10..<20:
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
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            designWeeklyTokensUsed: 0,
            designWeeklyPercentage: 0,
            designWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            overageBalance: nil,
            overageBalanceCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }

}

/// Usage status level for color coding
/// Thresholds depend on display mode (used vs remaining percentage)
enum UsageStatusLevel {
    case safe       // Used mode: 0-50% used | Remaining mode: >20% remaining
    case moderate   // Used mode: 50-80% used | Remaining mode: 10-20% remaining
    case critical   // Used mode: 80-100% used | Remaining mode: <10% remaining
}

// MARK: - Backward-compatible decoding
//
// Synthesized Codable makes every newly added non-optional field a decode
// REQUIREMENT for data written by older app versions. Profiles cache their
// last ClaudeUsage in profiles_v3, so a strict decoder here made
// ProfileStore.loadProfiles() throw on pre-upgrade data and return [] —
// wiping every profile on update (found via PR #271, thanks @yelloduxx).
// Every field decodes tolerantly with a neutral default, so new fields can
// be added without a migration. Lives in an extension so the struct keeps
// its memberwise initializer.
extension ClaudeUsage {
    private enum CodingKeys: String, CodingKey {
        case sessionTokensUsed, sessionLimit, sessionPercentage, sessionResetTime
        case weeklyTokensUsed, weeklyLimit, weeklyPercentage, weeklyResetTime
        case opusWeeklyTokensUsed, opusWeeklyPercentage
        case sonnetWeeklyTokensUsed, sonnetWeeklyPercentage, sonnetWeeklyResetTime
        case designWeeklyTokensUsed, designWeeklyPercentage, designWeeklyResetTime
        case costUsed, costLimit, costCurrency
        case overageBalance, overageBalanceCurrency
        case lastUpdated, userTimezone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionTokensUsed: try c.decodeIfPresent(Int.self, forKey: .sessionTokensUsed) ?? 0,
            sessionLimit: try c.decodeIfPresent(Int.self, forKey: .sessionLimit) ?? 0,
            sessionPercentage: try c.decodeIfPresent(Double.self, forKey: .sessionPercentage) ?? 0,
            sessionResetTime: try c.decodeIfPresent(Date.self, forKey: .sessionResetTime) ?? Date(),
            weeklyTokensUsed: try c.decodeIfPresent(Int.self, forKey: .weeklyTokensUsed) ?? 0,
            weeklyLimit: try c.decodeIfPresent(Int.self, forKey: .weeklyLimit) ?? 0,
            weeklyPercentage: try c.decodeIfPresent(Double.self, forKey: .weeklyPercentage) ?? 0,
            weeklyResetTime: try c.decodeIfPresent(Date.self, forKey: .weeklyResetTime) ?? Date(),
            opusWeeklyTokensUsed: try c.decodeIfPresent(Int.self, forKey: .opusWeeklyTokensUsed) ?? 0,
            opusWeeklyPercentage: try c.decodeIfPresent(Double.self, forKey: .opusWeeklyPercentage) ?? 0,
            sonnetWeeklyTokensUsed: try c.decodeIfPresent(Int.self, forKey: .sonnetWeeklyTokensUsed) ?? 0,
            sonnetWeeklyPercentage: try c.decodeIfPresent(Double.self, forKey: .sonnetWeeklyPercentage) ?? 0,
            sonnetWeeklyResetTime: try c.decodeIfPresent(Date.self, forKey: .sonnetWeeklyResetTime),
            designWeeklyTokensUsed: try c.decodeIfPresent(Int.self, forKey: .designWeeklyTokensUsed) ?? 0,
            designWeeklyPercentage: try c.decodeIfPresent(Double.self, forKey: .designWeeklyPercentage) ?? 0,
            designWeeklyResetTime: try c.decodeIfPresent(Date.self, forKey: .designWeeklyResetTime),
            costUsed: try c.decodeIfPresent(Double.self, forKey: .costUsed),
            costLimit: try c.decodeIfPresent(Double.self, forKey: .costLimit),
            costCurrency: try c.decodeIfPresent(String.self, forKey: .costCurrency),
            overageBalance: try c.decodeIfPresent(Double.self, forKey: .overageBalance),
            overageBalanceCurrency: try c.decodeIfPresent(String.self, forKey: .overageBalanceCurrency),
            lastUpdated: try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date(),
            userTimezone: try c.decodeIfPresent(TimeZone.self, forKey: .userTimezone) ?? .current
        )
    }
}
