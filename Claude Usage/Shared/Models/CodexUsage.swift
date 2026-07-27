import Foundation

/// A cached snapshot for one Codex profile.
///
/// Each profile starts an app-server on its configured local or SSH machine and
/// reuses whichever Codex account is signed in for that connection.
struct CodexUsage: Codable, Equatable {
    var account: CodexAccount?
    var rateLimits: [CodexRateLimit]
    var tokenUsage: CodexTokenUsage?
    var lastUpdated: Date

    /// Prefer the general Codex bucket over model-specific buckets.
    var primaryRateLimit: CodexRateLimit? {
        rateLimits.first(where: { $0.id == "codex" }) ?? rateLimits.first
    }

    func rateLimit(preferredID: String?) -> CodexRateLimit? {
        guard let preferredID else { return primaryRateLimit }
        return rateLimits.first(where: { $0.id == preferredID }) ?? primaryRateLimit
    }
}

struct CodexAccount: Codable, Equatable {
    var email: String?
    var planType: String?
}

struct CodexRateLimit: Codable, Equatable, Identifiable {
    var id: String
    var name: String?
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var credits: CodexCredits?
    var planType: String?
    var reachedType: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return id == "codex" ? "Codex" : id
    }
}

struct CodexRateLimitWindow: Codable, Equatable {
    var usedPercent: Double
    var windowDurationMinutes: Int?
    var resetsAt: Date?

    var duration: TimeInterval? {
        windowDurationMinutes.map { TimeInterval($0 * 60) }
    }
}

struct CodexCredits: Codable, Equatable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}

struct CodexTokenUsage: Codable, Equatable {
    var lifetimeTokens: Int64?
    var peakDailyTokens: Int64?
    var longestRunningTurnSeconds: Int64?
    var currentStreakDays: Int64?
    var longestStreakDays: Int64?
    var dailyBuckets: [CodexDailyTokenUsage]
}

struct CodexDailyTokenUsage: Codable, Equatable, Identifiable {
    var startDate: String
    var tokens: Int64

    var id: String { startDate }
}
