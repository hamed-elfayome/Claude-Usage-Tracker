import Foundation

/// A cached snapshot for one z.ai (GLM Coding Plan) profile.
///
/// The z.ai monitor API reports every quota window (5-hour tokens, weekly
/// tokens, monthly tool calls) as a flat list of limit entries. Each entry is
/// normalized into a rate-limit bucket shaped like the Codex provider's so the
/// tray, popover, widget, and notification pipelines can be reused verbatim.
struct ZAIUsage: Codable, Equatable {
    var account: ZAIAccount?
    var rateLimits: [ZAIRateLimit]
    var lastUpdated: Date

    /// Prefer the 5-hour token window; it is the quota users exhaust first.
    var primaryRateLimit: ZAIRateLimit? {
        rateLimit(preferredID: nil)
    }

    func rateLimit(preferredID: String?) -> ZAIRateLimit? {
        guard let preferredID else { return defaultRateLimit }
        return rateLimits.first(where: { $0.id == preferredID }) ?? defaultRateLimit
    }

    private var defaultRateLimit: ZAIRateLimit? {
        rateLimits.first(where: \.isFiveHourSessionWindow)
            ?? rateLimits.first(where: { $0.kind == .tokens })
            ?? rateLimits.first
    }
}

/// Plan tier reported by the z.ai subscription attached to the API key
/// ("lite", "pro", "max"). z.ai exposes no account email for coding-plan keys.
struct ZAIAccount: Codable, Equatable {
    var planType: String?
}

/// The z.ai window families reported by the quota endpoint.
enum ZAIRateLimitKind: String, Codable {
    case tokens = "TOKENS_LIMIT"
    case toolCalls = "TIME_LIMIT"

    /// z.ai encodes the window family as an opaque `unit` integer:
    /// 3 = hours (5-hour rolling window), 6 = weeks, 5 = month.
    /// The `type` string has shifted between API generations
    /// ("TOKENS_LIMIT" → "CREDIT_LIMIT"), so `unit` is the stable
    /// discriminator; unknown types are classified by it.
    static func kind(type: String, unit: Int?) -> ZAIRateLimitKind? {
        switch type {
        case "TOKENS_LIMIT", "CREDIT_LIMIT": return .tokens
        case "TIME_LIMIT": return .toolCalls
        default:
            switch unit {
            case 3, 6: return .tokens
            case 5: return .toolCalls
            default: return nil
            }
        }
    }
}

struct ZAIRateLimit: Codable, Equatable, Identifiable {
    static let fiveHourTokensID = "TOKENS_LIMIT-3"

    var id: String
    var name: String?
    var kind: ZAIRateLimitKind?
    var primary: ZAIRateLimitWindow?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return id == Self.fiveHourTokensID ? "Z.ai" : id
    }

    /// The 5-hour rolling token/credit quota — z.ai's equivalent of a session
    /// window. Prefer this classifier over id matching: the id embeds the
    /// provider's `type` string, which has changed between API generations.
    var isFiveHourSessionWindow: Bool {
        primary?.windowDurationMinutes == 5 * 60 && isTokenQuota
    }

    /// The 7-day rolling token/credit quota — z.ai's weekly window.
    var isWeeklyWindow: Bool {
        primary?.windowDurationMinutes == 7 * 24 * 60 && isTokenQuota
    }

    private var isTokenQuota: Bool {
        kind != .toolCalls
    }
}

struct ZAIRateLimitWindow: Codable, Equatable {
    var usedPercent: Double
    var windowDurationMinutes: Int?
    var resetsAt: Date?
    /// Credits consumed in this window (z.ai's weighted credit metric).
    var usedCredits: Double?
    /// Total credit budget for the window, when reported.
    var totalCredits: Double?

    var duration: TimeInterval? {
        windowDurationMinutes.map { TimeInterval($0 * 60) }
    }
}
