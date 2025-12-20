//
//  SettingsColors.swift
//  Claude Usage - Settings Design System
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Semantic color palette for Settings UI
/// Provides consistent colors across all settings views
enum SettingsColors {
    // MARK: - Status Colors

    /// Success state (green)
    static let success = Color.green

    /// Error state (red)
    static let error = Color.red

    /// Warning state (orange)
    static let warning = Color.orange

    /// Informational state (blue)
    static let info = Color.blue

    /// Caution state (yellow)
    static let caution = Color.yellow

    // MARK: - Semantic UI Colors

    /// Primary action color (system accent)
    static let primary = Color.accentColor

    /// Secondary elements
    static let secondary = Color.secondary

    /// Card background
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    /// Input field background
    static let inputBackground = Color(nsColor: .textBackgroundColor)

    /// Border color for inputs and cards
    static let border = Color.gray.opacity(0.2)

    // MARK: - Feature-Specific Colors

    /// Icon color for feature highlights
    static let featureIcon = Color.blue

    /// Beta badge color
    static let betaBadge = Color.orange

    /// Pro feature badge
    static let proBadge = Color.purple

    // MARK: - Threshold Colors (for usage indicators)

    /// Low usage (0-50%)
    static let usageLow = Color.green

    /// Medium usage (50-75%)
    static let usageMedium = Color.yellow

    /// High usage (75-90%)
    static let usageHigh = Color.orange

    /// Critical usage (90%+)
    static let usageCritical = Color.red

    // MARK: - Opacity Variants

    /// Light background overlay (for cards on cards)
    static func lightOverlay(_ color: Color, opacity: Double = 0.1) -> Color {
        return color.opacity(opacity)
    }

    /// Border with opacity
    static func borderColor(_ color: Color, opacity: Double = 0.3) -> Color {
        return color.opacity(opacity)
    }
}
