//
//  SettingsButton.swift
//  Claude Usage - Button Component
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Unified button component for settings
/// Provides consistent styling with hover states and variants
struct SettingsButton: View {
    let title: String
    let icon: String?
    let style: SettingsButtonVariant
    let action: () -> Void

    @State private var isHovered = false

    enum SettingsButtonVariant {
        case primary
        case secondary
        case destructive
        case subtle

        var backgroundColor: Color {
            switch self {
            case .primary: return SettingsColors.primary
            case .secondary: return SettingsColors.cardBackground
            case .destructive: return SettingsColors.error
            case .subtle: return Color.clear
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .primary
            case .destructive: return .white
            case .subtle: return .primary
            }
        }

        var borderColor: Color {
            switch self {
            case .primary: return .clear
            case .secondary: return SettingsColors.border
            case .destructive: return .clear
            case .subtle: return .clear
            }
        }

        func hoverBackgroundColor(isHovered: Bool) -> Color {
            guard isHovered else { return backgroundColor }

            switch self {
            case .primary:
                return SettingsColors.primary.opacity(0.85)
            case .secondary:
                return Color(nsColor: .controlBackgroundColor).opacity(1.2)
            case .destructive:
                return SettingsColors.error.opacity(0.85)
            case .subtle:
                return Color.gray.opacity(0.1)
            }
        }
    }

    init(
        title: String,
        icon: String? = nil,
        style: SettingsButtonVariant = .secondary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.iconText) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: DesignTokens.Icons.small))
                }

                Text(title)
                    .font(DesignTokens.Typography.body)
            }
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, DesignTokens.Spacing.small)
            .frame(maxWidth: style == .primary ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                    .fill(style.hoverBackgroundColor(isHovered: isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                    .strokeBorder(style.borderColor, lineWidth: 0.5)
            )
            .foregroundColor(style.foregroundColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        if icon != nil {
            return "\(title) button"
        }
        return title
    }
}

// MARK: - Convenience Initializers

extension SettingsButton {
    /// Create a primary button (full width, accent color)
    static func primary(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> SettingsButton {
        SettingsButton(title: title, icon: icon, style: .primary, action: action)
    }

    /// Create a destructive button (red, for delete actions)
    static func destructive(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> SettingsButton {
        SettingsButton(title: title, icon: icon, style: .destructive, action: action)
    }

    /// Create a subtle button (minimal styling)
    static func subtle(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> SettingsButton {
        SettingsButton(title: title, icon: icon, style: .subtle, action: action)
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: DesignTokens.Spacing.medium) {
        SettingsButton.primary(title: "Save Changes") { }
        SettingsButton(title: "Cancel") { }
        SettingsButton.destructive(title: "Delete", icon: "trash") { }
        SettingsButton.subtle(title: "Learn More") { }
    }
    .padding()
}
