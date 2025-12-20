//
//  Spacing.swift
//  Claude Usage - Settings Design System
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Spacing system for Settings UI
/// Follows 4px grid system for consistent spacing
enum Spacing {
    // MARK: - Core Spacing (4px grid)

    /// 4px - Minimal spacing
    static let xs: CGFloat = 4

    /// 8px - Small spacing between related elements
    static let sm: CGFloat = 8

    /// 12px - Medium spacing within components
    static let md: CGFloat = 12

    /// 16px - Standard spacing between components
    static let lg: CGFloat = 16

    /// 20px - Large spacing for section separation
    static let xl: CGFloat = 20

    /// 24px - Extra large spacing
    static let xxl: CGFloat = 24

    /// 32px - Maximum spacing for major sections
    static let xxxl: CGFloat = 32

    // MARK: - Semantic Spacing

    /// Spacing between settings sections (32px)
    static let sectionSpacing: CGFloat = 32

    /// Spacing between cards (16px)
    static let cardSpacing: CGFloat = 16

    /// Spacing within cards (20px)
    static let cardPadding: CGFloat = 20

    /// Spacing for input fields (12px)
    static let inputSpacing: CGFloat = 12

    /// Padding for input fields (12px)
    static let inputPadding: CGFloat = 12

    /// Content padding from edges (28px)
    static let contentPadding: CGFloat = 28

    /// Compact content padding (16px)
    static let compactPadding: CGFloat = 16

    // MARK: - Component Spacing

    /// Spacing between toggle and description (4px)
    static let toggleDescriptionSpacing: CGFloat = 4

    /// Spacing between icon and text (8px)
    static let iconTextSpacing: CGFloat = 8

    /// Spacing between buttons in a row (10px)
    static let buttonRowSpacing: CGFloat = 10

    /// Spacing in form rows (12px)
    static let formRowSpacing: CGFloat = 12

    // MARK: - Radius

    /// Small corner radius (4px)
    static let radiusSmall: CGFloat = 4

    /// Medium corner radius (6px)
    static let radiusMedium: CGFloat = 6

    /// Standard corner radius (8px)
    static let radiusStandard: CGFloat = 8

    /// Large corner radius for cards (12px)
    static let radiusLarge: CGFloat = 12

    /// Extra large radius (16px)
    static let radiusXLarge: CGFloat = 16
}

/// View modifiers for consistent spacing
extension View {
    /// Apply standard card padding
    func cardPadding() -> some View {
        self.padding(Spacing.cardPadding)
    }

    /// Apply content padding
    func contentPadding() -> some View {
        self.padding(Spacing.contentPadding)
    }

    /// Apply compact padding
    func compactPadding() -> some View {
        self.padding(Spacing.compactPadding)
    }
}
