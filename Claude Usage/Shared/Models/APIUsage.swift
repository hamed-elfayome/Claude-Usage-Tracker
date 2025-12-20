//
//  APIUsage.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

struct APIUsage: Codable, Equatable {
    let currentSpendCents: Int
    let resetsAt: Date
    let prepaidCreditsCents: Int
    let currency: String

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
        lhs.resetsAt == rhs.resetsAt
    }
}

struct APIOrganization: Codable, Identifiable, Equatable {
    let id: String
    let name: String

    var displayName: String {
        name.isEmpty ? id : name
    }
}
