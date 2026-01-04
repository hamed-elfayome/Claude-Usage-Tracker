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
            order: 0
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

/// Global menu bar icon configuration
struct MenuBarIconConfiguration: Codable, Equatable {
    var monochromeMode: Bool
    var showIconNames: Bool
    var metrics: [MetricIconConfig]

    init(
        monochromeMode: Bool = false,
        showIconNames: Bool = true,
        metrics: [MetricIconConfig] = [
            .sessionDefault,
            .weekDefault,
            .apiDefault
        ]
    ) {
        self.monochromeMode = monochromeMode
        self.showIconNames = showIconNames
        self.metrics = metrics
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
