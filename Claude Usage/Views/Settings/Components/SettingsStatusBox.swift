//
//  SettingsStatusBox.swift
//  Claude Usage - Unified Status/Feedback Component
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Unified status feedback component
/// Replaces: StatusBox, APIStatusBox, and wizard status boxes
struct SettingsStatusBox: View {
    let message: String
    let type: StatusType

    enum StatusType {
        case success
        case error
        case info
        case warning

        var color: Color {
            switch self {
            case .success: return SettingsColors.success
            case .error: return SettingsColors.error
            case .info: return SettingsColors.info
            case .warning: return SettingsColors.warning
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.iconTextSpacing) {
            Image(systemName: type.icon)
                .font(.system(size: 14))
                .foregroundColor(type.color)
                .accessibilityHidden(true)

            Text(message)
                .font(Typography.label)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                .fill(SettingsColors.lightOverlay(type.color, opacity: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                        .strokeBorder(SettingsColors.borderColor(type.color, opacity: 0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(type.accessibilityLabel): \(message)"))
    }
}

private extension SettingsStatusBox.StatusType {
    var accessibilityLabel: String {
        switch self {
        case .success: return "Success"
        case .error: return "Error"
        case .info: return "Information"
        case .warning: return "Warning"
        }
    }
}

// MARK: - Previews

#Preview("Success") {
    SettingsStatusBox(message: "Settings saved successfully!", type: .success)
        .padding()
}

#Preview("Error") {
    SettingsStatusBox(message: "Failed to connect to server", type: .error)
        .padding()
}

#Preview("Info") {
    SettingsStatusBox(message: "Claude Code integration requires restart", type: .info)
        .padding()
}

#Preview("Warning") {
    SettingsStatusBox(message: "Session key will expire in 7 days", type: .warning)
        .padding()
}
