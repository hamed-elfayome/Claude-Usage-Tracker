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
                title: "settings.session_management".localized,
                subtitle: "session.subtitle".localized
            )

            Divider()

            // Auto-Start Session Toggle
            SettingToggle(
                title: "session.auto_start".localized,
                description: "session.auto_start.description".localized,
                badge: .beta,
                isOn: $autoStartSessionEnabled
            )
            .onChange(of: autoStartSessionEnabled) { _, newValue in
                DataStore.shared.saveAutoStartSessionEnabled(newValue)
            }

            if autoStartSessionEnabled {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("ui.how_it_works".localized)
                        .font(Typography.sectionHeader)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("session.auto_description_line1".localized)
                        Text("session.auto_description_line2".localized)
                        Text("session.auto_description_line3".localized)
                        Text("session.auto_description_line4".localized)
                    }
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
