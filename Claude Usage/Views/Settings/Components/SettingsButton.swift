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
    let style: ButtonStyle
    let action: () -> Void

    @State private var isHovered = false

    enum ButtonStyle {
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
        style: ButtonStyle = .secondary,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.iconTextSpacing) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }

                Text(title)
                    .font(Typography.body)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: style == .primary ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                    .fill(style.hoverBackgroundColor(isHovered: isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMedium)
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
        if let icon = icon {
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

#Preview("Primary Button") {
    VStack(spacing: Spacing.md) {
        SettingsButton.primary(title: "Save Changes") {
            print("Save")
        }

        SettingsButton.primary(title: "Connect", icon: "link") {
            print("Connect")
        }
    }
    .padding()
}

#Preview("Secondary Button") {
    VStack(spacing: Spacing.md) {
        SettingsButton(title: "Cancel") {
            print("Cancel")
        }

        SettingsButton(title: "Refresh", icon: "arrow.clockwise") {
            print("Refresh")
        }
    }
    .padding()
}

#Preview("Destructive Button") {
    VStack(spacing: Spacing.md) {
        SettingsButton.destructive(title: "Delete Account") {
            print("Delete")
        }

        SettingsButton.destructive(title: "Remove", icon: "trash") {
            print("Remove")
        }
    }
    .padding()
}

#Preview("Subtle Button") {
    VStack(spacing: Spacing.md) {
        SettingsButton.subtle(title: "Learn More") {
            print("Learn more")
        }

        SettingsButton.subtle(title: "Documentation", icon: "book") {
            print("Docs")
        }
    }
    .padding()
}

#Preview("Button Row") {
    HStack(spacing: Spacing.buttonRowSpacing) {
        SettingsButton(title: "Cancel") {
            print("Cancel")
        }

        SettingsButton.primary(title: "Save", icon: "checkmark") {
            print("Save")
        }
    }
    .padding()
}

#Preview("All Styles") {
    VStack(spacing: Spacing.cardSpacing) {
        SettingsCard(title: "Button Styles") {
            VStack(spacing: Spacing.md) {
                SettingsButton.primary(title: "Primary Button", icon: "star.fill") {
                    print("Primary")
                }

                SettingsButton(title: "Secondary Button", icon: "circle") {
                    print("Secondary")
                }

                SettingsButton.destructive(title: "Destructive Button", icon: "trash") {
                    print("Destructive")
                }

                SettingsButton.subtle(title: "Subtle Button", icon: "info.circle") {
                    print("Subtle")
                }
            }
        }
    }
    .padding()
}
