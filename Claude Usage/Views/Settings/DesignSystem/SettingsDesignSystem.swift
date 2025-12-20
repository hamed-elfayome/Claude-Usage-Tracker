//
//  SettingsDesignSystem.swift
//  Claude Usage - Settings Design System
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Centralized design system for Settings UI
/// Provides access to all design tokens and styles
enum SettingsDesignSystem {
    // Design system components are available as:
    // - Typography (direct import)
    // - SettingsColors
    // - Spacing (direct import)

    // MARK: - Common Styles

    /// Standard card style with shadow and border
    static func cardStyle() -> some ShapeStyle {
        return Color(nsColor: .controlBackgroundColor)
    }

    /// Standard card shape
    static func cardShape() -> some Shape {
        return RoundedRectangle(cornerRadius: Spacing.radiusLarge)
    }

    /// Input field style
    static func inputFieldStyle() -> some ShapeStyle {
        return Color(nsColor: .textBackgroundColor)
    }

    /// Input field shape
    static func inputFieldShape() -> some Shape {
        return RoundedRectangle(cornerRadius: Spacing.radiusMedium)
    }
}

/// View modifier for standard card appearance
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusLarge)
                    .fill(SettingsColors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusLarge)
                    .strokeBorder(SettingsColors.border, lineWidth: 0.5)
            )
    }
}

extension View {
    /// Apply standard card styling
    func settingsCard() -> some View {
        self.modifier(CardModifier())
    }
}
