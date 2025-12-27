//
//  GeneralSettingsView.swift
//  Claude Usage - General App Settings
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// General app behavior and preferences
struct GeneralSettingsView: View {
    @Binding var refreshInterval: Double
    @State private var checkOverageLimitEnabled: Bool = DataStore.shared.loadCheckOverageLimitEnabled()
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    @StateObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "settings.general".localized,
                subtitle: "settings.general.description".localized
            )

            Divider()

            // Launch at Login Toggle
            SettingToggle(
                title: "general.launch_at_login".localized,
                description: "general.launch_at_login.description".localized,
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                let success = LaunchAtLoginManager.shared.setEnabled(newValue)
                if !success {
                    // Revert the toggle if the operation failed
                    launchAtLogin = LaunchAtLoginManager.shared.isEnabled
                }
            }

            Divider()

            // Data Refresh Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("general.refresh_interval".localized)
                    .font(Typography.sectionHeader)

                HStack {
                    Slider(value: $refreshInterval, in: 5...120, step: 1)
                        .onChange(of: refreshInterval) { _, newValue in
                            DataStore.shared.saveRefreshInterval(newValue)
                        }

                    Text("\(Int(refreshInterval))s")
                        .font(Typography.monospacedValue)
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                Text("general.refresh_interval.description".localized)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            // Usage Tracking Options
            SettingToggle(
                title: "general.check_overage_limit".localized,
                description: "general.check_overage_limit.description".localized,
                isOn: $checkOverageLimitEnabled
            )
            .onChange(of: checkOverageLimitEnabled) { _, newValue in
                DataStore.shared.saveCheckOverageLimitEnabled(newValue)
            }

            Divider()

            // Language Selection
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("general.language.title".localized)
                    .font(Typography.sectionHeader)

                Picker("general.language.select".localized, selection: $languageManager.currentLanguage) {
                    ForEach(LanguageManager.SupportedLanguage.allCases) { language in
                        HStack(spacing: 8) {
                            Text(language.flag)
                            Text(language.displayName)
                        }
                        .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)

                Text("general.language.restart_note".localized)
                    .font(Typography.caption)
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .contentPadding()
        .onAppear {
            // Refresh the launch at login state when view appears
            launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        }
    }
}

// MARK: - Previews

#Preview {
    GeneralSettingsView(refreshInterval: .constant(30))
        .frame(width: 520, height: 600)
}
