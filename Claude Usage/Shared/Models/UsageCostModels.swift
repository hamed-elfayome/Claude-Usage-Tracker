//
//  UsageCostModels.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import Foundation

// MARK: - Daily Cost Model

/// Represents daily cost data with model breakdown
struct DailyCost: Codable, Identifiable, Equatable {
    var id: String { date }
    let date: String
    let cost: Double
    let modelBreakdown: [ModelCost]

    init(date: String, cost: Double, modelBreakdown: [ModelCost] = []) {
        self.date = date
        self.cost = cost
        self.modelBreakdown = modelBreakdown
    }
}

// MARK: - Model Cost

/// Represents cost for a specific model
struct ModelCost: Codable, Equatable {
    let modelName: String
    let total: Double

    /// Normalized model category (Opus, Sonnet, Haiku)
    var modelCategory: ModelCategory {
        let lowercased = modelName.lowercased()
        if lowercased.contains("opus") {
            return .opus
        } else if lowercased.contains("sonnet") {
            return .sonnet
        } else if lowercased.contains("haiku") {
            return .haiku
        } else {
            return .other
        }
    }
}

/// Model category for breakdown display
enum ModelCategory: String, CaseIterable, Codable {
    case opus = "Opus"
    case sonnet = "Sonnet"
    case haiku = "Haiku"
    case other = "Other"

    var displayName: String { rawValue }

    var color: String {
        switch self {
        case .opus: return "purple"
        case .sonnet: return "blue"
        case .haiku: return "green"
        case .other: return "gray"
        }
    }
}

// MARK: - Usage Cost API Response

/// Response structure for /workspaces/{id}/usage_cost API
struct UsageCostResponse: Codable {
    let costs: [String: [CostEntry]]

    /// Parse the raw response into structured daily costs
    func toDailyCosts(filterByApiKeyId: String? = nil) -> [DailyCost] {
        var result: [DailyCost] = []

        for (date, entries) in costs {
            // Filter by API key if specified
            let filteredEntries = filterByApiKeyId != nil
                ? entries.filter { $0.keyId == filterByApiKeyId }
                : entries

            // Group by model
            var modelCosts: [String: Double] = [:]
            for entry in filteredEntries {
                let modelName = entry.modelName ?? "Unknown"
                modelCosts[modelName, default: 0] += entry.total
            }

            let totalCost = modelCosts.values.reduce(0, +)
            let breakdown = modelCosts.map { ModelCost(modelName: $0.key, total: $0.value) }

            result.append(DailyCost(date: date, cost: totalCost, modelBreakdown: breakdown))
        }

        // Sort by date ascending
        return result.sorted { $0.date < $1.date }
    }
}

/// Individual cost entry from the API
struct CostEntry: Codable {
    let workspaceId: String?
    let keyId: String?
    let modelName: String?
    let total: Double
    let tokenType: String?
    let promptTokenCountTier: String?
    let usageType: String?

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case keyId = "key_id"
        case modelName = "model_name"
        case total
        case tokenType = "token_type"
        case promptTokenCountTier = "prompt_token_count_tier"
        case usageType = "usage_type"
    }
}

// MARK: - Model Breakdown Summary

/// Aggregated model breakdown for display
struct ModelBreakdownSummary: Codable, Equatable {
    let opusCost: Double
    let sonnetCost: Double
    let haikuCost: Double
    let otherCost: Double

    var totalCost: Double {
        opusCost + sonnetCost + haikuCost + otherCost
    }

    var opusPercentage: Double {
        totalCost > 0 ? (opusCost / totalCost) * 100 : 0
    }

    var sonnetPercentage: Double {
        totalCost > 0 ? (sonnetCost / totalCost) * 100 : 0
    }

    var haikuPercentage: Double {
        totalCost > 0 ? (haikuCost / totalCost) * 100 : 0
    }

    var otherPercentage: Double {
        totalCost > 0 ? (otherCost / totalCost) * 100 : 0
    }

    /// Creates a summary from daily costs
    static func from(dailyCosts: [DailyCost]) -> ModelBreakdownSummary {
        var opus: Double = 0
        var sonnet: Double = 0
        var haiku: Double = 0
        var other: Double = 0

        for dailyCost in dailyCosts {
            for modelCost in dailyCost.modelBreakdown {
                switch modelCost.modelCategory {
                case .opus: opus += modelCost.total
                case .sonnet: sonnet += modelCost.total
                case .haiku: haiku += modelCost.total
                case .other: other += modelCost.total
                }
            }
        }

        return ModelBreakdownSummary(
            opusCost: opus,
            sonnetCost: sonnet,
            haikuCost: haiku,
            otherCost: other
        )
    }
}

// MARK: - API Key Info

/// Information about an API key
struct APIKeyInfo: Codable, Identifiable {
    let id: String
    let name: String?
    let createdAt: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case status
    }
}
