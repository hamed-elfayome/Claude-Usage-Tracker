//
//  MenuBarIconConfig.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation

/// Types of metrics that can be displayed in the menu bar
enum MenuBarMetricType: String, Codable, CaseIterable, Identifiable {
    case session
    case week
    case api

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session:
            return "Session Usage"
        case .week:
            return "Week Usage"
        case .api:
            return "API Credits"
        }
    }

    var prefixText: String {
        switch self {
        case .session:
            return "S:"
        case .week:
            return "W:"
        case .api:
            return "API:"
        }
    }

    var description: String {
        switch self {
        case .session:
            return "5-hour rolling window usage"
        case .week:
            return "Weekly token usage (all models)"
        case .api:
            return "API Console billing credits"
        }
    }

    var icon: String {
        switch self {
        case .session:
            return "clock.fill"
        case .week:
            return "calendar.badge.clock"
        case .api:
            return "dollarsign.circle.fill"
        }
    }
}

/// Display mode for API usage
enum APIDisplayMode: String, Codable, CaseIterable {
    case remaining
    case used
    case both

    var displayName: String {
        switch self {
        case .remaining:
            return "Remaining Credits"
        case .used:
            return "Used Amount"
        case .both:
            return "Both (Used / Total)"
        }
    }

    var description: String {
        switch self {
        case .remaining:
            return "Show only remaining credits"
        case .used:
            return "Show only amount spent"
        case .both:
            return "Show both used and total"
        }
    }
}

/// Display mode for week usage
enum WeekDisplayMode: String, Codable, CaseIterable {
    case percentage
    case tokens

    var displayName: String {
        switch self {
        case .percentage:
            return "Percentage"
        case .tokens:
            return "Token Count"
        }
    }

    var description: String {
        switch self {
        case .percentage:
            return "Show as percentage (e.g., 60%)"
        case .tokens:
            return "Show token numbers (e.g., 600K/1M)"
        }
    }
}

/// Configuration for a single metric icon
struct MetricIconConfig: Codable, Equatable {
    var metricType: MenuBarMetricType
    var isEnabled: Bool
    var iconStyle: MenuBarIconStyle
    var order: Int

    /// Week-specific configuration
    var weekDisplayMode: WeekDisplayMode

    /// API-specific configuration
    var apiDisplayMode: APIDisplayMode

    /// Session-specific configuration
    var showNextSessionTime: Bool

    init(
        metricType: MenuBarMetricType,
        isEnabled: Bool = false,
        iconStyle: MenuBarIconStyle = .battery,
        order: Int = 0,
        weekDisplayMode: WeekDisplayMode = .percentage,
        apiDisplayMode: APIDisplayMode = .remaining,
        showNextSessionTime: Bool = false
    ) {
        self.metricType = metricType
        self.isEnabled = isEnabled
        self.iconStyle = iconStyle
        self.order = order
        self.weekDisplayMode = weekDisplayMode
        self.apiDisplayMode = apiDisplayMode
        self.showNextSessionTime = showNextSessionTime
    }

    /// Default config for session (enabled by default)
    static var sessionDefault: MetricIconConfig {
        MetricIconConfig(
            metricType: .session,
            isEnabled: true,
            iconStyle: .battery,
            order: 0,
            showNextSessionTime: false
        )
    }

    /// Default config for week (disabled by default)
    static var weekDefault: MetricIconConfig {
        MetricIconConfig(
            metricType: .week,
            isEnabled: false,
            iconStyle: .battery,
            order: 1,
            weekDisplayMode: .percentage
        )
    }

    /// Default config for API (disabled by default)
    static var apiDefault: MetricIconConfig {
        MetricIconConfig(
            metricType: .api,
            isEnabled: false,
            iconStyle: .battery,
            order: 2,
            apiDisplayMode: .remaining
        )
    }
}

/// Icon style for multi-profile display
enum MultiProfileIconStyle: String, Codable, CaseIterable {
    case concentric   // Concentric circles (session inner, week outer)
    case progressBar  // Horizontal progress bars stacked
    case compact      // Minimal dot indicators

    var displayName: String {
        switch self {
        case .concentric:
            return "Concentric Circles"
        case .progressBar:
            return "Progress Bars"
        case .compact:
            return "Compact Dots"
        }
    }

    var description: String {
        switch self {
        case .concentric:
            return "Session inside, week outside ring"
        case .progressBar:
            return "Horizontal bars stacked vertically"
        case .compact:
            return "Minimal colored dots"
        }
    }

    var icon: String {
        switch self {
        case .concentric:
            return "circle.circle"
        case .progressBar:
            return "chart.bar.fill"
        case .compact:
            return "circle.fill"
        }
    }
}

/// Configuration for multi-profile display mode
struct MultiProfileDisplayConfig: Codable, Equatable {
    var iconStyle: MultiProfileIconStyle
    var showWeek: Bool        // If false, only show session
    var showProfileLabel: Bool // Show profile name below icon

    init(
        iconStyle: MultiProfileIconStyle = .concentric,
        showWeek: Bool = true,
        showProfileLabel: Bool = true
    ) {
        self.iconStyle = iconStyle
        self.showWeek = showWeek
        self.showProfileLabel = showProfileLabel
    }

    static var `default`: MultiProfileDisplayConfig {
        MultiProfileDisplayConfig()
    }
}

/// Global menu bar icon configuration
struct MenuBarIconConfiguration: Codable, Equatable {
    var monochromeMode: Bool
    var showIconNames: Bool
    var showRemainingPercentage: Bool
    var metrics: [MetricIconConfig]

    init(
        monochromeMode: Bool = false,
        showIconNames: Bool = true,
        showRemainingPercentage: Bool = false,
        metrics: [MetricIconConfig] = [
            .sessionDefault,
            .weekDefault,
            .apiDefault
        ]
    ) {
        self.monochromeMode = monochromeMode
        self.showIconNames = showIconNames
        self.showRemainingPercentage = showRemainingPercentage
        self.metrics = metrics
    }

    // MARK: - Codable (Custom decoder for backwards compatibility)

    enum CodingKeys: String, CodingKey {
        case monochromeMode
        case showIconNames
        case showRemainingPercentage
        case metrics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        monochromeMode = try container.decode(Bool.self, forKey: .monochromeMode)
        showIconNames = try container.decode(Bool.self, forKey: .showIconNames)

        // New property - provide default value if missing (backwards compatibility)
        showRemainingPercentage = try container.decodeIfPresent(Bool.self, forKey: .showRemainingPercentage) ?? false

        metrics = try container.decode([MetricIconConfig].self, forKey: .metrics)
    }

    /// Get enabled metrics sorted by order
    var enabledMetrics: [MetricIconConfig] {
        metrics
            .filter { $0.isEnabled }
            .sorted { $0.order < $1.order }
    }

    /// Get config for specific metric type
    func config(for metricType: MenuBarMetricType) -> MetricIconConfig? {
        metrics.first { $0.metricType == metricType }
    }

    /// Update config for specific metric
    mutating func updateConfig(_ config: MetricIconConfig) {
        if let index = metrics.firstIndex(where: { $0.metricType == config.metricType }) {
            metrics[index] = config
        }
    }

    /// Default configuration (session only, like current behavior)
    static var `default`: MenuBarIconConfiguration {
        MenuBarIconConfiguration()
    }
}
