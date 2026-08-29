//
//  CodexAPIService+Types.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//
//  DTOs for chatgpt.com/backend-api/wham/usage. Every field decodes
//  tolerantly (per-field try?) — a new or malformed field must never fail
//  the whole response, mirroring both the Codex CLI's own tolerance and this
//  app's ClaudeUsage convention. Response shape verified against the
//  MIT-licensed CodexBar project (github.com/steipete/codexbar).
//

import Foundation

/// Response of GET wham/usage.
/// Known plan_type values: guest, free, go, plus, pro, free_workspace, team,
/// business, education, quorum, k12, enterprise, edu — stored as the raw
/// string so unknown future plans pass through.
struct CodexUsageResponse: Decodable {
    let planType: String?
    let rateLimit: CodexRateLimitDetails?
    let credits: CodexCreditDetails?
    // `individual_limit` (spend controls) and `additional_rate_limits`
    // (named model-specific limits) also exist in the payload; v1 ignores
    // them, and the per-field tolerant decoding below means their presence
    // can never break the primary/weekly mapping.

    private enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? c.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try? c.decodeIfPresent(CodexRateLimitDetails.self, forKey: .rateLimit)
        credits = try? c.decodeIfPresent(CodexCreditDetails.self, forKey: .credits)
    }

    init(planType: String?, rateLimit: CodexRateLimitDetails?, credits: CodexCreditDetails?) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.credits = credits
    }
}

struct CodexRateLimitDetails: Decodable {
    let primaryWindow: CodexRateWindow?
    let secondaryWindow: CodexRateWindow?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryWindow = try? c.decodeIfPresent(CodexRateWindow.self, forKey: .primaryWindow)
        secondaryWindow = try? c.decodeIfPresent(CodexRateWindow.self, forKey: .secondaryWindow)
    }

    init(primaryWindow: CodexRateWindow?, secondaryWindow: CodexRateWindow?) {
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}

struct CodexRateWindow: Decodable {
    /// Percent of the window consumed (integer in the API).
    let usedPercent: Double
    /// Unix timestamp (seconds) when the window resets.
    let resetAt: Int?
    /// Window length in seconds (e.g. 18000 = 5h, 604800 = 7d).
    let limitWindowSeconds: Int?

    var resetDate: Date? {
        resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var windowMinutes: Int? {
        limitWindowSeconds.map { $0 / 60 }
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // used_percent is documented as Int but tolerate doubles/strings
        if let value = try? c.decodeIfPresent(Double.self, forKey: .usedPercent) {
            usedPercent = value
        } else if let value = try? c.decodeIfPresent(Int.self, forKey: .usedPercent) {
            usedPercent = Double(value)
        } else if let value = try? c.decodeIfPresent(String.self, forKey: .usedPercent), let parsed = Double(value) {
            usedPercent = parsed
        } else {
            usedPercent = 0
        }
        resetAt = try? c.decodeIfPresent(Int.self, forKey: .resetAt)
        limitWindowSeconds = try? c.decodeIfPresent(Int.self, forKey: .limitWindowSeconds)
    }

    init(usedPercent: Double, resetAt: Int?, limitWindowSeconds: Int?) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.limitWindowSeconds = limitWindowSeconds
    }
}

struct CodexCreditDetails: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    /// Balance may arrive as a number or a string.
    let balance: Double?

    private enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = (try? c.decodeIfPresent(Bool.self, forKey: .hasCredits)) ?? false
        unlimited = (try? c.decodeIfPresent(Bool.self, forKey: .unlimited)) ?? false
        if let value = try? c.decodeIfPresent(Double.self, forKey: .balance) {
            balance = value
        } else if let value = try? c.decodeIfPresent(String.self, forKey: .balance) {
            balance = Double(value)
        } else {
            balance = nil
        }
    }

    init(hasCredits: Bool, unlimited: Bool, balance: Double?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

// MARK: - Window normalization

/// The API's primary/secondary windows are NOT guaranteed to be
/// session/weekly in that order — classify by duration and swap when
/// reversed. Ported from CodexBar's CodexRateWindowNormalizer (MIT).
enum CodexRateWindowNormalizer {
    private enum Role {
        case session   // 300 minutes (5h)
        case weekly    // 10080 minutes (7d)
        case unknown
    }

    private static func role(for window: CodexRateWindow) -> Role {
        switch window.windowMinutes {
        case 300: return .session
        case 10080: return .weekly
        default: return .unknown
        }
    }

    /// Returns (session, weekly). Unknown-duration windows default to the
    /// session slot; a lone weekly window leaves session empty.
    static func normalize(
        primary: CodexRateWindow?,
        secondary: CodexRateWindow?
    ) -> (session: CodexRateWindow?, weekly: CodexRateWindow?) {
        switch (primary, secondary) {
        case let (.some(p), .some(s)):
            switch (role(for: p), role(for: s)) {
            case (.session, .weekly), (.session, .unknown), (.unknown, .weekly):
                return (p, s)
            case (.weekly, .session), (.weekly, .unknown), (.unknown, .session):
                // A recognized session window always wins the session slot,
                // even when its counterpart has an unrecognized duration.
                return (s, p)
            default:
                return (p, s)
            }
        case let (.some(p), .none):
            return role(for: p) == .weekly ? (nil, p) : (p, nil)
        case let (.none, .some(s)):
            return role(for: s) == .weekly ? (nil, s) : (s, nil)
        case (.none, .none):
            return (nil, nil)
        }
    }
}
