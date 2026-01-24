//
//  WidgetStyle.swift
//  Claude Usage
//
//  Widget and statusline appearance style options
//

import Foundation

// MARK: - Statusline Color Mode

/// Statusline color mode for Claude Code integration
enum StatuslineColorMode: String, Codable, CaseIterable {
    /// Multi-colored elements (default terminal colors)
    case colored = "colored"

    /// Monochrome/adaptive (uses terminal's default text color)
    case monochrome = "monochrome"

    /// Single user-selected color for all elements
    case singleColor = "singleColor"

    var displayName: String {
        switch self {
        case .colored:
            return "Multi-Color"
        case .monochrome:
            return "Monochrome"
        case .singleColor:
            return "Single Color"
        }
    }

    var description: String {
        switch self {
        case .colored:
            return "Threshold-based colors by usage level"
        case .monochrome:
            return "Adapts to system theme"
        case .singleColor:
            return "Custom color for all elements"
        }
    }

    var icon: String {
        switch self {
        case .colored:
            return "paintpalette.fill"
        case .monochrome:
            return "circle.lefthalf.filled"
        case .singleColor:
            return "eyedropper.halffull"
        }
    }
}

// MARK: - Widget Color Mode

/// Widget color display mode
enum WidgetColorMode: String, Codable, CaseIterable {
    /// Multi-colored elements (threshold-based)
    case multiColor = "multiColor"

    /// Monochrome/adaptive (uses system theme)
    case monochrome = "monochrome"

    /// Single user-selected color for all elements
    case singleColor = "singleColor"

    var displayName: String {
        switch self {
        case .multiColor:
            return "Multi-Color"
        case .monochrome:
            return "Monochrome"
        case .singleColor:
            return "Single Color"
        }
    }

    var description: String {
        switch self {
        case .multiColor:
            return "Threshold-based colors by usage level"
        case .monochrome:
            return "Adapts to system theme"
        case .singleColor:
            return "Custom color for all elements"
        }
    }

    var icon: String {
        switch self {
        case .multiColor:
            return "paintpalette.fill"
        case .monochrome:
            return "circle.lefthalf.filled"
        case .singleColor:
            return "eyedropper.halffull"
        }
    }
}

// MARK: - Small Widget Metric

/// Small widget metric selection - determines which single metric is displayed
enum SmallWidgetMetric: String, Codable, CaseIterable {
    case session = "session"
    case weekly = "weekly"
    case opus = "opus"
    case sonnet = "sonnet"
    case extra = "extra"

    var displayName: String {
        switch self {
        case .session:
            return "Session"
        case .weekly:
            return "Weekly"
        case .opus:
            return "Opus"
        case .sonnet:
            return "Sonnet"
        case .extra:
            return "Extra"
        }
    }

    var icon: String {
        switch self {
        case .session:
            return "clock.fill"
        case .weekly:
            return "calendar"
        case .opus:
            return "star.fill"
        case .sonnet:
            return "bolt.fill"
        case .extra:
            return "dollarsign.circle.fill"
        }
    }
}

// MARK: - Extra Usage Display Format

/// Extra usage display format - determines how extra usage is shown
enum ExtraUsageDisplayFormat: String, Codable, CaseIterable {
    case percentage = "percentage"
    case currency = "currency"
    case both = "both"

    var displayName: String {
        switch self {
        case .percentage:
            return "Percentage"
        case .currency:
            return "Currency Amount"
        case .both:
            return "Both"
        }
    }

    var description: String {
        switch self {
        case .percentage:
            return "Show as percentage (e.g., 22%)"
        case .currency:
            return "Show as currency amount (e.g., $2.25)"
        case .both:
            return "Show both values"
        }
    }
}

