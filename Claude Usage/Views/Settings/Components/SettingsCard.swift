//
//  SettingsCard.swift
//  Claude Usage - Card Container Component
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Modern card container for grouping related settings
/// Provides consistent card styling with optional header and footer
struct SettingsCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let footer: String?
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                    if let title = title {
                        Text(title)
                            .font(DesignTokens.Typography.sectionTitle)
                            .foregroundColor(.primary)
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.cardPadding)
                .padding(.top, DesignTokens.Spacing.cardPadding)
                .padding(.bottom, DesignTokens.Spacing.medium)
            }

            // Content
            content
                .padding(.horizontal, DesignTokens.Spacing.cardPadding)
                .padding(.bottom, footer == nil ? DesignTokens.Spacing.cardPadding : DesignTokens.Spacing.medium)

            // Footer
            if let footer = footer {
                Text(footer)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignTokens.Spacing.cardPadding)
                    .padding(.bottom, DesignTokens.Spacing.cardPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Convenience Modifiers

extension SettingsCard {
    /// Create a card with just a title
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: nil, footer: nil, content: content)
    }

    /// Create a card with title and footer
    init(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, subtitle: nil, footer: footer, content: content)
    }
}

// MARK: - Previews

#Preview("Cards") {
    VStack(spacing: DesignTokens.Spacing.cardPadding) {
        SettingsCard(title: "Settings") {
            SettingToggle(title: "Enable", isOn: .constant(true))
        }
        SettingsCard(title: "Advanced", footer: "For advanced users") {
            SettingToggle(title: "Debug", badge: .beta, isOn: .constant(false))
        }
    }
    .padding()
}
