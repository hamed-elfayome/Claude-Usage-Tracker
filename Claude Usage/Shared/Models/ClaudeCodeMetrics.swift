//
//  ClaudeCodeMetrics.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-23.
//

import Foundation

/// Represents Claude Code team metrics for a specific user
/// Data sourced from platform.claude.com/api/claude_code/metrics_aggs/users
struct ClaudeCodeMetrics: Codable, Equatable {
    /// Total cost in dollars for the period
    let totalCost: Double

    /// Average cost per day in dollars
    let avgCostPerDay: Double

    /// Total number of coding sessions
    let totalSessions: Int

    /// Total lines of code accepted
    let totalLinesAccepted: Int

    /// Date of last activity
    let lastActive: Date?

    /// Start of the metrics period
    let periodStart: Date

    /// End of the metrics period
    let periodEnd: Date

    /// User email associated with these metrics
    let userEmail: String?

    // MARK: - PR Stats

    /// Number of PRs with Claude Code involvement
    let prsWithCc: Int?

    /// Total number of PRs
    let totalPrs: Int?

    /// Percentage of PRs with Claude Code (0.0 - 100.0)
    let prsWithCcPercentage: Double?

    // MARK: - Team Comparison Data

    /// Team average cost per day
    let teamAvgCostPerDay: Double?

    /// Total number of users in the team
    let teamTotalUsers: Int?

    /// User's rank by cost (1 = highest spender)
    let userRankByCost: Int?

    // MARK: - Daily Cost Data (for sparkline)

    /// Daily costs for the period (for sparkline display)
    var dailyCosts: [DailyCost]?

    /// Model breakdown summary
    var modelBreakdown: ModelBreakdownSummary?

    // MARK: - Budget Settings (from profile)

    /// Monthly budget amount (optional, from profile)
    var monthlyBudget: Double?

    // MARK: - Computed Properties

    /// Formatted total cost as currency string
    var formattedTotalCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: totalCost)) ?? "$\(String(format: "%.2f", totalCost))"
    }

    /// Formatted average daily cost
    var formattedAvgCostPerDay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: avgCostPerDay)) ?? "$\(String(format: "%.2f", avgCostPerDay))"
    }

    /// Formatted lines accepted (e.g., "118.7K")
    var formattedLinesAccepted: String {
        if totalLinesAccepted >= 1_000_000 {
            return String(format: "%.1fM", Double(totalLinesAccepted) / 1_000_000.0)
        } else if totalLinesAccepted >= 1_000 {
            return String(format: "%.1fK", Double(totalLinesAccepted) / 1_000.0)
        } else {
            return "\(totalLinesAccepted)"
        }
    }

    /// Short display text for menu bar (e.g., "$432")
    var menuBarDisplayText: String {
        if totalCost >= 1000 {
            return String(format: "$%.1fK", totalCost / 1000.0)
        } else if totalCost >= 100 {
            return String(format: "$%.0f", totalCost)
        } else {
            return String(format: "$%.2f", totalCost)
        }
    }

    /// Short display text showing daily average (e.g., "~$27/day")
    var menuBarAvgDisplayText: String {
        if avgCostPerDay >= 100 {
            return String(format: "~$%.0f/day", avgCostPerDay)
        } else {
            return String(format: "~$%.2f/day", avgCostPerDay)
        }
    }

    /// Period description (e.g., "Jan 1 - Jan 23")
    var periodDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: periodStart)) - \(formatter.string(from: periodEnd))"
    }

    /// Days in the period
    var periodDays: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: periodStart, to: periodEnd)
        return (components.day ?? 0) + 1
    }

    // MARK: - PR Stats Computed Properties

    /// Whether PR stats are available
    var hasPRStats: Bool {
        prsWithCc != nil && totalPrs != nil
    }

    /// Formatted PR stats (e.g., "2/5")
    var formattedPRStats: String {
        guard let withCc = prsWithCc, let total = totalPrs else { return "-" }
        return "\(withCc)/\(total)"
    }

    /// Formatted PR percentage (e.g., "40%")
    var formattedPRPercentage: String? {
        guard let percentage = prsWithCcPercentage else { return nil }
        return String(format: "%.0f%%", percentage)
    }

    // MARK: - Team Comparison Computed Properties

    /// Whether team comparison data is available
    var hasTeamComparison: Bool {
        teamAvgCostPerDay != nil && teamAvgCostPerDay! > 0
    }

    /// Percentage difference from team average (positive = above average)
    var costComparedToTeam: Double? {
        guard let teamAvg = teamAvgCostPerDay, teamAvg > 0 else { return nil }
        return ((avgCostPerDay - teamAvg) / teamAvg) * 100
    }

    /// Formatted team comparison (e.g., "+15%" or "-20%")
    var formattedTeamComparison: String? {
        guard let diff = costComparedToTeam else { return nil }
        let sign = diff >= 0 ? "+" : ""
        return String(format: "%@%.0f%%", sign, diff)
    }

    /// Whether user is above team average
    var isAboveTeamAverage: Bool {
        guard let diff = costComparedToTeam else { return false }
        return diff > 0
    }

    /// Formatted rank (e.g., "#2/36")
    var formattedRank: String? {
        guard let rank = userRankByCost, let total = teamTotalUsers else { return nil }
        return "#\(rank)/\(total)"
    }

    // MARK: - Budget Computed Properties

    /// Budget usage percentage (0-100)
    var budgetUsagePercentage: Double? {
        guard let budget = monthlyBudget, budget > 0 else { return nil }
        return min((totalCost / budget) * 100, 100)
    }

    /// Whether budget is available
    var hasBudget: Bool {
        monthlyBudget != nil && monthlyBudget! > 0
    }

    /// Formatted budget (e.g., "$750")
    var formattedBudget: String? {
        guard let budget = monthlyBudget else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: budget))
    }

    /// Budget alert level based on usage
    var budgetAlertLevel: BudgetAlertLevel {
        guard let percentage = budgetUsagePercentage else { return .safe }
        if percentage >= 90 { return .critical }
        if percentage >= 75 { return .warning }
        if percentage >= 50 { return .caution }
        return .safe
    }

    // MARK: - Sparkline Data

    /// Daily cost values for sparkline (last 14 days or available data)
    var sparklineData: [Double] {
        guard let costs = dailyCosts else { return [] }
        return costs.suffix(14).map { $0.cost }
    }

    /// Trend direction based on recent data
    var trendDirection: TrendDirection {
        guard sparklineData.count >= 3 else { return .stable }

        let recent = Array(sparklineData.suffix(3))
        let earlier = Array(sparklineData.prefix(3))

        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let earlierAvg = earlier.reduce(0, +) / Double(earlier.count)

        let percentChange = earlierAvg > 0 ? ((recentAvg - earlierAvg) / earlierAvg) * 100 : 0

        if percentChange > 10 { return .up }
        if percentChange < -10 { return .down }
        return .stable
    }

    // MARK: - Model Breakdown Computed Properties

    /// Whether model breakdown is available
    var hasModelBreakdown: Bool {
        modelBreakdown != nil
    }
}

// MARK: - Supporting Types

/// Budget alert level
enum BudgetAlertLevel: String, Codable {
    case safe
    case caution
    case warning
    case critical

    var color: String {
        switch self {
        case .safe: return "green"
        case .caution: return "yellow"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
}

/// Trend direction for sparkline
enum TrendDirection: String, Codable {
    case up
    case down
    case stable

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
}

// MARK: - API Response Models

/// Response structure for Claude Code metrics API
struct ClaudeCodeMetricsResponse: Codable {
    let organizationId: String?
    let startDate: String?
    let endDate: String?
    let totalUsers: Int?
    let users: [ClaudeCodeUserMetrics]
    let pagination: ClaudeCodeMetricsPagination?

    enum CodingKeys: String, CodingKey {
        case organizationId = "organization_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case totalUsers = "total_users"
        case users
        case pagination
    }
}

/// Individual user metrics from the API
struct ClaudeCodeUserMetrics: Codable {
    let email: String?  // Can be null for service accounts or deleted users
    let apiKeyName: String?
    let status: String?
    let avgCostPerDay: String?
    let avgLinesAcceptedPerDay: Int?
    let totalCost: String?
    let totalLinesAccepted: Int?
    let totalSessions: Int?
    let lastActive: String?
    let prsWithCc: Int?
    let totalPrs: Int?
    let prsWithCcPercentage: Double?  // API returns float (e.g., 0.0)

    enum CodingKeys: String, CodingKey {
        case email
        case apiKeyName = "api_key_name"
        case status
        case avgCostPerDay = "avg_cost_per_day"
        case avgLinesAcceptedPerDay = "avg_lines_accepted_per_day"
        case totalCost = "total_cost"
        case totalLinesAccepted = "total_lines_accepted"
        case totalSessions = "total_sessions"
        case lastActive = "last_active"
        case prsWithCc = "prs_with_cc"
        case totalPrs = "total_prs"
        case prsWithCcPercentage = "prs_with_cc_percentage"
    }
}

/// Pagination info from the API
struct ClaudeCodeMetricsPagination: Codable {
    let limit: Int
    let offset: Int
    let total: Int
    let hasNext: Bool

    enum CodingKeys: String, CodingKey {
        case limit
        case offset
        case total
        case hasNext = "has_next"
    }
}
