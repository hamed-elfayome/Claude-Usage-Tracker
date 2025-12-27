//
//  SessionManagementView.swift
//  Claude Usage - Automatic Session Management
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Automatic session management settings
struct SessionManagementView: View {
    @Binding var autoStartSessionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "Session Management",
                subtitle: "Automatic session initialization and maintenance"
            )

            Divider()

            // Auto-Start Session Toggle
            SettingToggle(
                title: "Auto-start session on reset",
                description: "Automatically initialize a new 5-hour session when the current one expires",
                badge: .beta,
                isOn: $autoStartSessionEnabled
            )
            .onChange(of: autoStartSessionEnabled) { _, newValue in
                DataStore.shared.saveAutoStartSessionEnabled(newValue)
            }

            if autoStartSessionEnabled {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("How it works")
                        .font(Typography.sectionHeader)

                    Text(
                        """
                        • Detects when your session resets to 0%
                        • Sends 'Hi' to Claude 3.5 Haiku (cheapest model)
                        • Uses a temporary chat that won't appear in your history
                        • New 5-hour session is ready instantly
                        """
                    )
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .contentPadding()
    }
}

// MARK: - Previews

#Preview {
    SessionManagementView(autoStartSessionEnabled: .constant(true))
        .frame(width: 520, height: 600)
}
