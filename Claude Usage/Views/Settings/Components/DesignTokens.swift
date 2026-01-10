//
//  DesignTokens.swift
//  Claude Usage - Centralized Design System
//
//  Centralized styling constants for consistent design across all settings views
//

import SwiftUI

/// Centralized design tokens for Settings UI
enum DesignTokens {

    // MARK: - Typography

    enum Typography {
        /// Main page title (18px, semibold)
        static let pageTitle = Font.system(size: 18, weight: .semibold)

        /// Page subtitle (13px, regular)
        static let pageSubtitle = Font.system(size: 13)

        /// Section header (13px, medium) - e.g. "Refresh Interval"
        static let sectionTitle = Font.system(size: 13, weight: .medium)

        /// Section subtitle (12px, regular)
        static let sectionSubtitle = Font.system(size: 12)

        /// Body text (12-13px)
        static let body = Font.system(size: 12)
        static let bodyMedium = Font.system(size: 13, weight: .medium)

        /// Small text (11px) - helper text, captions
        static let caption = Font.system(size: 11)

        /// Tiny text (10px) - very small labels
        static let tiny = Font.system(size: 10)

        /// Monospaced for keys/tokens
        static let monospaced = Font.system(size: 12, design: .monospaced)
        static let monospacedSmall = Font.system(size: 11, design: .monospaced)
        static let captionMono = Font.system(size: 11, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        /// Main sections spacing (24px)
        static let section: CGFloat = 24

        /// Card padding (16px)
        static let cardPadding: CGFloat = 16

        /// Small padding (12px)
        static let medium: CGFloat = 12

        /// Tiny padding (8px)
        static let small: CGFloat = 8

        /// Extra small (4px)
        static let extraSmall: CGFloat = 4

        /// Icon-text spacing (10px)
        static let iconText: CGFloat = 10

        /// Icon frame width (20px)
        static let iconFrame: CGFloat = 20
    }

    // MARK: - Corner Radius

    enum Radius {
        /// Main card radius (8px)
        static let card: CGFloat = 8

        /// Small radius (6px)
        static let small: CGFloat = 6

        /// Tiny radius (4px)
        static let tiny: CGFloat = 4
    }

    // MARK: - Icons

    enum Icons {
        /// Standard icon size (14px)
        static let standard: CGFloat = 14

        /// Small icon size (12px)
        static let small: CGFloat = 12

        /// Tiny icon size (10px)
        static let tiny: CGFloat = 10
    }

    // MARK: - Status Indicators

    enum StatusDot {
        /// Standard status dot size (8px)
        static let standard: CGFloat = 8

        /// Small status dot (6px)
        static let small: CGFloat = 6
    }

    // MARK: - Colors

    enum Colors {
        /// Card background
        static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)

        /// Card border
        static let cardBorder = Color.secondary.opacity(0.15)

        /// Text field background
        static let inputBackground = Color(nsColor: .textBackgroundColor)

        /// Success/connected state
        static let success = Color.green

        /// Error state
        static let error = Color.red

        /// Warning state
        static let warning = Color.orange

        /// Info/accent
        static let accent = Color.accentColor
    }
}
