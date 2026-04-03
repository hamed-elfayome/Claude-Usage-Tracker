import Foundation

struct OpenAIUsage: Codable, Equatable {
    let currentSpendCents: Int
    let currency: String
    let resetsAt: Date
    let dailyCostCents: [String: Double]
    let tokensByModel: [String: OpenAIModelTokens]?
    let lastUpdated: Date

    var usedAmount: Double {
        Double(currentSpendCents) / 100.0
    }

    var formattedUsed: String {
        formatCurrency(usedAmount)
    }

    var sortedDailyCosts: [(date: Date, cents: Double)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return dailyCostCents.compactMap { key, value in
            guard let date = formatter.date(from: key) else { return nil }
            return (date: date, cents: value)
        }.sorted { $0.date < $1.date }
    }

    var sortedModelTokens: [(model: String, tokens: OpenAIModelTokens)] {
        guard let byModel = tokensByModel else { return [] }
        return byModel.sorted { $0.value.totalTokens > $1.value.totalTokens }
            .map { (model: $0.key, tokens: $0.value) }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(currency) \(String(format: "%.2f", amount))"
    }
}

struct OpenAIModelTokens: Codable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}
