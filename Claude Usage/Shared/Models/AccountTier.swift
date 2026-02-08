//
//  AccountTier.swift
//  Claude Usage
//

import Foundation

/// Represents the subscription tier for a Claude account, derived from organization capabilities
enum AccountTier: String, Codable, Equatable {
    case free
    case pro
    case max5x
    case max20x
    case team
    case enterprise

    /// Relative capacity weight compared to Pro (1x baseline)
    var weight: Double {
        switch self {
        case .free: return 0.2
        case .pro: return 1.0
        case .max5x: return 5.0
        case .max20x: return 20.0
        case .team: return 5.0
        case .enterprise: return 10.0
        }
    }

    /// Detects account tier from the capabilities array returned by /organizations
    static func from(capabilities: [String]) -> AccountTier {
        let lowered = capabilities.map { $0.lowercased() }

        // Check each capability individually to avoid cross-element false matches
        for cap in lowered {
            if cap.contains("max") && cap.contains("20") {
                return .max20x
            }
            if cap.contains("max") && cap.contains("5") {
                return .max5x
            }
        }
        for cap in lowered {
            if cap.contains("max") {
                return .max5x
            }
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
}
