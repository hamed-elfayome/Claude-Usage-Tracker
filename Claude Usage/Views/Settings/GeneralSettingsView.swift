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
    @State private var initialLanguage: LanguageManager.SupportedLanguage?
    @State private var showRestartButton = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
                // Header
                SettingsHeader(
                    title: "settings.general".localized,
                    subtitle: "settings.general.description".localized
                )

                Divider()

                // App Behavior Section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("ui.app_behavior".localized)
                        .font(Typography.sectionHeader)

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
                }

                Divider()

                // Data Refresh Section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("general.refresh_interval".localized)
                        .font(Typography.sectionHeader)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Current value display
                        HStack(spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentColor)

                                    Text("\(Int(refreshInterval))s")
                                        .font(Typography.monospacedValue)
                                        .foregroundColor(.primary)
                                }

                                Text(refreshIntervalDescription)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                        // Slider
                        VStack(spacing: 4) {
                            Slider(value: $refreshInterval, in: 5...120, step: 5)
                                .onChange(of: refreshInterval) { _, newValue in
                                    DataStore.shared.saveRefreshInterval(newValue)
                                }

                            HStack {
                                Text("5s")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("general.slider_fast".localized)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("general.slider_balanced_label".localized)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("general.slider_battery_saver_label".localized)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("120s")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("general.refresh_interval.description".localized)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                // Usage Tracking Section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("ui.usage_tracking".localized)
                        .font(Typography.sectionHeader)

                    SettingToggle(
                        title: "general.check_overage_limit".localized,
                        description: "general.check_overage_limit.description".localized,
                        isOn: $checkOverageLimitEnabled
                    )
                    .onChange(of: checkOverageLimitEnabled) { _, newValue in
                        DataStore.shared.saveCheckOverageLimitEnabled(newValue)
                    }
                }

                Divider()

                // Language Selection
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("general.language.title".localized)
                        .font(Typography.sectionHeader)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("general.language.select".localized)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)

                        // Language grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: Spacing.sm),
                            GridItem(.flexible(), spacing: Spacing.sm),
                            GridItem(.flexible(), spacing: Spacing.sm)
                        ], spacing: Spacing.sm) {
                            ForEach(availableLanguages) { language in
                                Button(action: {
                                    languageManager.currentLanguage = language
                                    if let initial = initialLanguage, initial != language {
                                        showRestartButton = true
                                    } else if initialLanguage == language {
                                        showRestartButton = false
                                    }
                                }) {
                                    VStack(spacing: 6) {
                                        Text(language.flag)
                                            .font(.system(size: 28))

                                        Text(language.displayName)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(language == languageManager.currentLanguage ?
                                                  Color.accentColor.opacity(0.12) :
                                                  Color(nsColor: .controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                language == languageManager.currentLanguage ?
                                                Color.accentColor : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Restart button (appears when language changed)
                        if showRestartButton {
                            Button(action: restartApp) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13, weight: .semibold))

                                    Text("general.language.restart_app".localized)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, Spacing.sm)
                        } else {
                            // Restart notice
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)

                                Text("general.language.restart_note".localized)
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .padding(.top, Spacing.xs)
                        }
                    }
                }

                Spacer()
            }
            .contentPadding()
        }
        .onAppear {
            // Refresh the launch at login state when view appears
            launchAtLogin = LaunchAtLoginManager.shared.isEnabled
            // Store initial language to detect changes
            initialLanguage = languageManager.currentLanguage
        }
    }

    // MARK: - Actions

    private func restartApp() {
        // Relaunch the app
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [Bundle.main.bundlePath]
        task.launch()

        // Quit current instance
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helper Properties

    /// Only show languages that have translation files
    private var availableLanguages: [LanguageManager.SupportedLanguage] {
        [.english, .spanish, .french, .german, .italian, .portuguese]
    }

    private var refreshIntervalDescription: String {
        switch refreshInterval {
        case 0..<20:
            return "general.slider_realtime".localized
        case 20..<40:
            return "general.slider_frequent".localized
        case 40..<70:
            return "general.slider_balanced".localized
        case 70..<100:
            return "general.slider_efficient".localized
        default:
            return "general.slider_battery_saver".localized
        }
    }
}

// MARK: - Previews

#Preview {
    GeneralSettingsView(refreshInterval: .constant(30))
        .frame(width: 520, height: 600)
}
