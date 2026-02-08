//
//  AccountTier.swift
//  Claude Usage
//

import Foundation

/// Represents the subscription tier for a Claude account, derived from organization capabilities
enum AccountTier: String, Codable, Equatable {
    case free
    case pro
    case max
    case team
    case enterprise

    // Legacy cases decoded as .max
    case max5x
    case max20x

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "max5x", "max20x", "max": self = .max
        default: self = AccountTier(rawValue: raw) ?? .pro
        }
    }

    /// Human-readable label for display in the UI
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max, .max5x, .max20x: return "Max"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        }
    }

    /// Relative capacity weight compared to Pro (1x baseline).
    /// Max uses 5x as a conservative estimate since we can't distinguish 5x from 20x.
    var weight: Double {
        switch self {
        case .free: return 0.2
        case .pro: return 1.0
        case .max, .max5x, .max20x: return 5.0
        case .team: return 5.0
        case .enterprise: return 10.0
        }
    }

    /// Detects account tier from the capabilities array returned by /organizations
    static func from(capabilities: [String]) -> AccountTier {
        let lowered = capabilities.map { $0.lowercased() }

        for cap in lowered {
            if cap.contains("max") { return .max }
        }
        for cap in lowered {
            if cap.contains("enterprise") { return .enterprise }
            if cap.contains("team") { return .team }
            if cap.contains("pro") || cap.contains("raven") { return .pro }
        }
        if !capabilities.isEmpty {
            return .pro
        }
        return .free
    }

    /// Detects account tier from the subscriptionType string in CLI OAuth credentials.
    /// Returns nil if the string doesn't map to a known tier.
    static func from(subscriptionType: String) -> AccountTier? {
        let lowered = subscriptionType.lowercased()
        if lowered.contains("max") { return .max }
        if lowered.contains("enterprise") { return .enterprise }
        if lowered.contains("team") { return .team }
        if lowered.contains("pro") || lowered.contains("raven") { return .pro }
        if lowered.contains("free") { return .free }
        return nil
    }
}
