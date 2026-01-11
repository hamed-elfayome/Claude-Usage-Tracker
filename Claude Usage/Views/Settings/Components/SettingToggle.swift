//
//  SettingToggle.swift
//  Claude Usage - Unified Toggle Component
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Unified toggle component for settings
/// Provides consistent styling with optional description and badges
struct SettingToggle: View {
    let title: String
    let description: String?
    let badge: BadgeType?
    @Binding var isOn: Bool

    enum BadgeType {
        case beta
        case pro
        case new

        var text: String {
            switch self {
            case .beta: return "BETA"
            case .pro: return "PRO"
            case .new: return "NEW"
            }
        }

        var color: Color {
            switch self {
            case .beta: return SettingsColors.betaBadge
            case .pro: return SettingsColors.proBadge
            case .new: return SettingsColors.info
            }
        }
    }

    init(
        title: String,
        description: String? = nil,
        badge: BadgeType? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.description = description
        self.badge = badge
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    Text(title)
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(.primary)

                    if let badge = badge {
                        BadgeView(badge: badge)
                    }
                }

                if let description = description {
                    Text(description)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.cardPadding)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        var label = title
        if let badge = badge {
            label += ", \(badge.text)"
        }
        if let description = description {
            label += ". \(description)"
        }
        return label
    }
}

/// Badge component for toggle labels
private struct BadgeView: View {
    let badge: SettingToggle.BadgeType

    var body: some View {
        Text(badge.text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(badge.color)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Basic Toggle") {
    SettingToggle(
        title: "Enable notifications",
        isOn: .constant(true)
    )
    .padding()
}

#Preview("Toggle with Description") {
    SettingToggle(
        title: "Start at login",
        description: "Automatically launch Claude Usage when you log in to your Mac",
        isOn: .constant(false)
    )
    .padding()
}

#Preview("Toggle with Beta Badge") {
    SettingToggle(
        title: "Advanced features",
        description: "Enable experimental features that may be unstable",
        badge: .beta,
        isOn: .constant(true)
    )
    .padding()
}

#Preview("Toggle with Pro Badge") {
    SettingToggle(
        title: "Export analytics",
        description: "Export detailed usage analytics to CSV",
        badge: .pro,
        isOn: .constant(false)
    )
    .padding()
}

#Preview("Toggle with New Badge") {
    SettingToggle(
        title: "API usage tracking",
        description: "Track your API usage from console.anthropic.com",
        badge: .new,
        isOn: .constant(true)
    )
    .padding()
}
