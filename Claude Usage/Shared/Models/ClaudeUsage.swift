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

    // Weekly data (Fable only)
    var fableWeeklyTokensUsed: Int
    var fableWeeklyPercentage: Double
    var fableWeeklyResetTime: Date?

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
            fableWeeklyTokensUsed: 0,
            fableWeeklyPercentage: 0,
            fableWeeklyResetTime: nil,
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

// Custom decoding lives in an extension so the memberwise initializer is
// preserved. Fields added after v3.1.1 (design/fable) use decodeIfPresent:
// pre-upgrade persisted JSON lacks those keys, and synthesized decoding
// would throw keyNotFound — ProfileStore.loadProfiles() catches that and
// returns [], wiping every profile on upgrade.
extension ClaudeUsage {
    private enum CodingKeys: String, CodingKey {
        case sessionTokensUsed, sessionLimit, sessionPercentage, sessionResetTime
        case weeklyTokensUsed, weeklyLimit, weeklyPercentage, weeklyResetTime
        case opusWeeklyTokensUsed, opusWeeklyPercentage
        case sonnetWeeklyTokensUsed, sonnetWeeklyPercentage, sonnetWeeklyResetTime
        case designWeeklyTokensUsed, designWeeklyPercentage, designWeeklyResetTime
        case fableWeeklyTokensUsed, fableWeeklyPercentage, fableWeeklyResetTime
        case costUsed, costLimit, costCurrency
        case overageBalance, overageBalanceCurrency
        case lastUpdated, userTimezone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionTokensUsed = try c.decode(Int.self, forKey: .sessionTokensUsed)
        sessionLimit = try c.decode(Int.self, forKey: .sessionLimit)
        sessionPercentage = try c.decode(Double.self, forKey: .sessionPercentage)
        sessionResetTime = try c.decode(Date.self, forKey: .sessionResetTime)
        weeklyTokensUsed = try c.decode(Int.self, forKey: .weeklyTokensUsed)
        weeklyLimit = try c.decode(Int.self, forKey: .weeklyLimit)
        weeklyPercentage = try c.decode(Double.self, forKey: .weeklyPercentage)
        weeklyResetTime = try c.decode(Date.self, forKey: .weeklyResetTime)
        opusWeeklyTokensUsed = try c.decode(Int.self, forKey: .opusWeeklyTokensUsed)
        opusWeeklyPercentage = try c.decode(Double.self, forKey: .opusWeeklyPercentage)
        sonnetWeeklyTokensUsed = try c.decode(Int.self, forKey: .sonnetWeeklyTokensUsed)
        sonnetWeeklyPercentage = try c.decode(Double.self, forKey: .sonnetWeeklyPercentage)
        sonnetWeeklyResetTime = try c.decodeIfPresent(Date.self, forKey: .sonnetWeeklyResetTime)
        designWeeklyTokensUsed = try c.decodeIfPresent(Int.self, forKey: .designWeeklyTokensUsed) ?? 0
        designWeeklyPercentage = try c.decodeIfPresent(Double.self, forKey: .designWeeklyPercentage) ?? 0
        designWeeklyResetTime = try c.decodeIfPresent(Date.self, forKey: .designWeeklyResetTime)
        fableWeeklyTokensUsed = try c.decodeIfPresent(Int.self, forKey: .fableWeeklyTokensUsed) ?? 0
        fableWeeklyPercentage = try c.decodeIfPresent(Double.self, forKey: .fableWeeklyPercentage) ?? 0
        fableWeeklyResetTime = try c.decodeIfPresent(Date.self, forKey: .fableWeeklyResetTime)
        costUsed = try c.decodeIfPresent(Double.self, forKey: .costUsed)
        costLimit = try c.decodeIfPresent(Double.self, forKey: .costLimit)
        costCurrency = try c.decodeIfPresent(String.self, forKey: .costCurrency)
        overageBalance = try c.decodeIfPresent(Double.self, forKey: .overageBalance)
        overageBalanceCurrency = try c.decodeIfPresent(String.self, forKey: .overageBalanceCurrency)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        userTimezone = try c.decode(TimeZone.self, forKey: .userTimezone)
    }
}

/// Usage status level for color coding
/// Thresholds depend on display mode (used vs remaining percentage)
enum UsageStatusLevel {
    case safe       // Used mode: 0-50% used | Remaining mode: >20% remaining
    case moderate   // Used mode: 50-80% used | Remaining mode: 10-20% remaining
    case critical   // Used mode: 80-100% used | Remaining mode: <10% remaining
}
