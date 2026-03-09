//
//  APIUsage.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

// MARK: - Cost Source Types

enum APICostSourceType: String, Codable, Equatable {
    case cli
    case api
    case unknown

    var localizationKey: String {
        switch self {
        case .cli: return "menubar.cost_source.cli"
        case .api: return "menubar.cost_source.api"
        case .unknown: return "menubar.cost_source.unknown"
        }
    }

    var icon: String {
        switch self {
        case .cli: return "terminal.fill"
        case .api: return "chevron.left.forwardslash.chevron.right"
        case .unknown: return "key.fill"
        }
    }

    static func detect(from keyName: String) -> APICostSourceType {
        let lower = keyName.lowercased()
        if lower.contains("claude code") || lower.contains("claude-code") || lower.contains("cli") {
            return .cli
        }
        if lower.contains("api") || lower.contains("sdk") || lower.contains("server")
            || lower.contains("bot") || lower.contains("app") || lower.contains("prod")
            || lower.contains("dev") || lower.contains("staging") || lower.contains("test") {
            return .api
        }
        return .unknown
    }
}

struct APICostSource: Codable, Equatable, Identifiable {
    let keyId: String
    let keyName: String
    let sourceType: APICostSourceType
    let totalCents: Double
    let costByModel: [String: Double]

    var id: String { keyId }

    func formattedTotal(currency: String) -> String {
        APICostSource.formatCents(totalCents, currency: currency)
    }

    func sortedModelCosts(currency: String) -> [(model: String, cost: String)] {
        costByModel
            .sorted { $0.value > $1.value }
            .map { (model: $0.key, cost: APICostSource.formatCents($0.value, currency: currency)) }
    }

    static func formatCents(_ cents: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amount = cents / 100.0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }
}

// MARK: - API Usage

struct APIUsage: Codable, Equatable {
    let currentSpendCents: Int
    let resetsAt: Date
    let prepaidCreditsCents: Int
    let currency: String
    let apiTokenCostCents: Double?
    let apiCostByModel: [String: Double]?
    let costBySource: [APICostSource]?
    let dailyCostCents: [String: Double]?

    /// Daily costs sorted chronologically, parsing "yyyy-MM-dd" date strings
    var sortedDailyCosts: [(date: Date, cents: Double)] {
        guard let daily = dailyCostCents, !daily.isEmpty else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return daily.compactMap { key, value in
            guard let date = formatter.date(from: key) else { return nil }
            return (date: date, cents: value)
        }.sorted { $0.date < $1.date }
    }

    var usedAmount: Double {
        Double(currentSpendCents) / 100.0
    }

    var remainingAmount: Double {
        Double(prepaidCreditsCents) / 100.0
    }

    var totalCredits: Double {
        usedAmount + remainingAmount
    }

    var usagePercentage: Double {
        guard totalCredits > 0 else { return 0 }
        return (usedAmount / totalCredits) * 100.0
    }

    var formattedUsed: String {
        formatCurrency(usedAmount)
    }

    var formattedRemaining: String {
        formatCurrency(remainingAmount)
    }

    var formattedTotal: String {
        formatCurrency(totalCredits)
    }

    var formattedAPICost: String? {
        guard let cents = apiTokenCostCents, cents > 0 else { return nil }
        return formatCurrency(cents / 100.0)
    }

    var sortedModelCosts: [(model: String, cost: String)] {
        guard let costs = apiCostByModel, !costs.isEmpty else { return [] }
        return costs
            .sorted { $0.value > $1.value }
            .map { (model: $0.key, cost: formatCurrency($0.value / 100.0)) }
    }

    var sortedCostSources: [APICostSource] {
        guard let sources = costBySource else { return [] }
        return sources.sorted { $0.totalCents > $1.totalCents }
    }

    var hasMultipleSources: Bool {
        guard let sources = costBySource else { return false }
        return sources.count > 1
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }

    static func == (lhs: APIUsage, rhs: APIUsage) -> Bool {
        lhs.currentSpendCents == rhs.currentSpendCents &&
        lhs.prepaidCreditsCents == rhs.prepaidCreditsCents &&
        lhs.currency == rhs.currency &&
        lhs.resetsAt == rhs.resetsAt &&
        lhs.apiTokenCostCents == rhs.apiTokenCostCents &&
        lhs.apiCostByModel == rhs.apiCostByModel &&
        lhs.costBySource == rhs.costBySource &&
        lhs.dailyCostCents == rhs.dailyCostCents
    }
}

struct APIOrganization: Codable, Identifiable, Equatable {
    let id: String
    let name: String

    var displayName: String {
        name.isEmpty ? id : name
    }
}
