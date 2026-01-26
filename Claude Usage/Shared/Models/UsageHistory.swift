//
//  UsageHistory.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-01-26.
//

import Foundation

/// Reset type that triggers a usage snapshot
enum ResetType: String, Codable, CaseIterable {
    case sessionReset     // Session reset (every 5 hours)
    case weeklyReset      // Weekly usage reset (every Monday)
    case billingCycle     // API billing cycle reset (monthly)

    var localizedName: String {
        switch self {
        case .sessionReset:
            return "history.reset_type.session".localized
        case .weeklyReset:
            return "history.reset_type.weekly".localized
        case .billingCycle:
            return "history.reset_type.billing".localized
        }
    }
}

/// Usage snapshot - records usage data at the moment of reset
struct UsageSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date           // When the snapshot was recorded
    let resetType: ResetType      // Type of reset that triggered this snapshot

    // Claude.ai session usage data (captured before reset)
    let sessionTokensUsed: Int?
    let sessionPercentage: Double?

    // Claude.ai weekly usage data (captured before reset)
    let weeklyTokensUsed: Int?
    let weeklyPercentage: Double?
    let opusWeeklyTokensUsed: Int?
    let opusWeeklyPercentage: Double?
    let sonnetWeeklyTokensUsed: Int?
    let sonnetWeeklyPercentage: Double?

    // API billing data (captured before reset)
    let apiSpendCents: Int?
    let apiPrepaidCreditsCents: Int?
    let apiCurrency: String?

    // The reset time that triggered this snapshot
    let triggeringResetTime: Date

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        resetType: ResetType,
        sessionTokensUsed: Int? = nil,
        sessionPercentage: Double? = nil,
        weeklyTokensUsed: Int? = nil,
        weeklyPercentage: Double? = nil,
        opusWeeklyTokensUsed: Int? = nil,
        opusWeeklyPercentage: Double? = nil,
        sonnetWeeklyTokensUsed: Int? = nil,
        sonnetWeeklyPercentage: Double? = nil,
        apiSpendCents: Int? = nil,
        apiPrepaidCreditsCents: Int? = nil,
        apiCurrency: String? = nil,
        triggeringResetTime: Date
    ) {
        self.id = id
        self.timestamp = timestamp
        self.resetType = resetType
        self.sessionTokensUsed = sessionTokensUsed
        self.sessionPercentage = sessionPercentage
        self.weeklyTokensUsed = weeklyTokensUsed
        self.weeklyPercentage = weeklyPercentage
        self.opusWeeklyTokensUsed = opusWeeklyTokensUsed
        self.opusWeeklyPercentage = opusWeeklyPercentage
        self.sonnetWeeklyTokensUsed = sonnetWeeklyTokensUsed
        self.sonnetWeeklyPercentage = sonnetWeeklyPercentage
        self.apiSpendCents = apiSpendCents
        self.apiPrepaidCreditsCents = apiPrepaidCreditsCents
        self.apiCurrency = apiCurrency
        self.triggeringResetTime = triggeringResetTime
    }

    /// Creates a snapshot from ClaudeUsage data (for session reset)
    static func fromSessionReset(_ usage: ClaudeUsage, resetTime: Date) -> UsageSnapshot {
        UsageSnapshot(
            resetType: .sessionReset,
            sessionTokensUsed: usage.sessionTokensUsed,
            sessionPercentage: usage.sessionPercentage,
            triggeringResetTime: resetTime
        )
    }

    /// Creates a snapshot from ClaudeUsage data (for weekly reset)
    static func fromWeeklyReset(_ usage: ClaudeUsage, resetTime: Date) -> UsageSnapshot {
        UsageSnapshot(
            resetType: .weeklyReset,
            weeklyTokensUsed: usage.weeklyTokensUsed,
            weeklyPercentage: usage.weeklyPercentage,
            opusWeeklyTokensUsed: usage.opusWeeklyTokensUsed,
            opusWeeklyPercentage: usage.opusWeeklyPercentage,
            sonnetWeeklyTokensUsed: usage.sonnetWeeklyTokensUsed,
            sonnetWeeklyPercentage: usage.sonnetWeeklyPercentage,
            triggeringResetTime: resetTime
        )
    }

    /// Creates a snapshot from APIUsage data (for billing cycle reset)
    static func fromBillingCycleReset(_ usage: APIUsage, resetTime: Date) -> UsageSnapshot {
        UsageSnapshot(
            resetType: .billingCycle,
            apiSpendCents: usage.currentSpendCents,
            apiPrepaidCreditsCents: usage.prepaidCreditsCents,
            apiCurrency: usage.currency,
            triggeringResetTime: resetTime
        )
    }

    /// Formatted API spend amount
    var formattedApiSpend: String? {
        guard let cents = apiSpendCents, let currency = apiCurrency else { return nil }
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
    }

    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Short date string (for weekly chart labels - shows date and hour)
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }

    /// Short time string (for session chart labels - shows hour and minute)
    var shortTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

/// Container for a profile's usage history
struct UsageHistoryData: Codable, Equatable {
    var snapshots: [UsageSnapshot]

    init(snapshots: [UsageSnapshot] = []) {
        self.snapshots = snapshots
    }

    /// Snapshots filtered by reset type
    func snapshots(for resetType: ResetType) -> [UsageSnapshot] {
        snapshots.filter { $0.resetType == resetType }
    }

    /// Session reset snapshots sorted by date (newest first), filtered for valid data
    var sessionSnapshots: [UsageSnapshot] {
        snapshots(for: .sessionReset)
            .filter { $0.triggeringResetTime <= $0.timestamp.addingTimeInterval(60) } // Allow 1 min tolerance
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Weekly reset snapshots sorted by date (newest first), filtered for valid data
    var weeklySnapshots: [UsageSnapshot] {
        snapshots(for: .weeklyReset)
            .filter { $0.triggeringResetTime <= $0.timestamp.addingTimeInterval(60) } // Allow 1 min tolerance
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Billing cycle snapshots sorted by date (newest first), filtered for valid data
    var billingCycleSnapshots: [UsageSnapshot] {
        snapshots(for: .billingCycle)
            .filter { $0.triggeringResetTime <= $0.timestamp.addingTimeInterval(60) } // Allow 1 min tolerance
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Total number of snapshots
    var count: Int {
        snapshots.count
    }

    /// Whether there are any snapshots
    var isEmpty: Bool {
        snapshots.isEmpty
    }

    /// Add a new snapshot
    mutating func addSnapshot(_ snapshot: UsageSnapshot) {
        snapshots.append(snapshot)
    }

    /// Export to JSON string
    func exportToJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Export specific reset type to JSON
    func exportToJSON(for resetType: ResetType) -> String? {
        let filtered = UsageHistoryData(snapshots: snapshots(for: resetType))
        return filtered.exportToJSON()
    }
}
