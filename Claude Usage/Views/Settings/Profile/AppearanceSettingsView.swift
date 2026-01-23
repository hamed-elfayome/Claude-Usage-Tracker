//
//  AppearanceSettingsView.swift
//  Claude Usage - Menu Bar Appearance Settings
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI

/// Menu bar icon appearance and customization with multi-metric support
struct AppearanceSettingsView: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var configuration: MenuBarIconConfiguration = .default
    @State private var saveDebounceTimer: Timer?

    private var isMultiProfileMode: Bool {
        profileManager.displayMode == .multi
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "appearance.title".localized,
                    subtitle: "appearance.subtitle".localized
                )

                // Multi-profile mode warning
                if isMultiProfileMode {
                    MultiProfileModeWarningCard(
                        onDisableMultiProfile: {
                            profileManager.updateDisplayMode(.single)
                            NotificationCenter.default.post(name: .displayModeChanged, object: nil)
                        }
                    )
                }

                // Global Settings
                SettingsSectionCard(
                    title: "appearance.global_settings".localized,
                    subtitle: "appearance.global_subtitle".localized
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                        SettingToggle(
                            title: "appearance.monochrome_title".localized,
                            description: "appearance.monochrome_description".localized,
                            isOn: Binding(
                                get: { configuration.monochromeMode },
                                set: { newValue in
                                    configuration.monochromeMode = newValue
                                    saveConfiguration()
                                }
                            )
                        )

                        SettingToggle(
                            title: "appearance.show_labels_title".localized,
                            description: "appearance.show_labels_description".localized,
                            isOn: Binding(
                                get: { configuration.showIconNames },
                                set: { newValue in
                                    configuration.showIconNames = newValue
                                    saveConfiguration()
                                }
                            )
                        )

                        SettingToggle(
                            title: "appearance.show_remaining_title".localized,
                            description: "appearance.show_remaining_description".localized,
                            isOn: Binding(
                                get: { configuration.showRemainingPercentage },
                                set: { newValue in
                                    configuration.showRemainingPercentage = newValue
                                    saveConfiguration()
                                }
                            )
                        )
                    }
                }
                .disabled(isMultiProfileMode)
                .opacity(isMultiProfileMode ? 0.5 : 1.0)

                // Metrics Configuration
                SettingsSectionCard(
                    title: "appearance.menu_bar_metrics".localized,
                    subtitle: "appearance.metrics_subtitle".localized
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        // Info message when all metrics are disabled
                        if configuration.metrics.filter({ $0.isEnabled }).isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("appearance.all_metrics_off_title".localized)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.primary)

                                    Text("appearance.all_metrics_off_description".localized)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(DesignTokens.Spacing.small)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }

                        // Session Usage
                        if let sessionIndex = configuration.metrics.firstIndex(where: { $0.metricType == .session }) {
                            MetricIconCard(
                                metricType: .session,
                                config: Binding(
                                    get: { configuration.metrics[sessionIndex] },
                                    set: { newValue in
                                        configuration.metrics[sessionIndex] = newValue
                                    }
                                ),
                                onConfigChanged: { saveConfiguration() }
                            )
                        }

                        // Week Usage
                        if let weekIndex = configuration.metrics.firstIndex(where: { $0.metricType == .week }) {
                            MetricIconCard(
                                metricType: .week,
                                config: Binding(
                                    get: { configuration.metrics[weekIndex] },
                                    set: { newValue in
                                        configuration.metrics[weekIndex] = newValue
                                    }
                                ),
                                onConfigChanged: { saveConfiguration() }
                            )
                        }

                        // API Credits
                        if let apiIndex = configuration.metrics.firstIndex(where: { $0.metricType == .api }) {
                            MetricIconCard(
                                metricType: .api,
                                config: Binding(
                                    get: { configuration.metrics[apiIndex] },
                                    set: { newValue in
                                        configuration.metrics[apiIndex] = newValue
                                    }
                                ),
                                onConfigChanged: { saveConfiguration() }
                            )
                        }

                        // Claude Code Cost
                        if let claudeCodeIndex = configuration.metrics.firstIndex(where: { $0.metricType == .claudeCode }) {
                            MetricIconCard(
                                metricType: .claudeCode,
                                config: Binding(
                                    get: { configuration.metrics[claudeCodeIndex] },
                                    set: { newValue in
                                        configuration.metrics[claudeCodeIndex] = newValue
                                    }
                                ),
                                onConfigChanged: { saveConfiguration() }
                            )
                        }
                    }
                }
                .disabled(isMultiProfileMode)
                .opacity(isMultiProfileMode ? 0.5 : 1.0)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            // Load configuration from active profile
            if let activeProfile = profileManager.activeProfile {
                configuration = activeProfile.iconConfig
            }
        }
        .onChange(of: profileManager.activeProfile?.id) { _, newProfileId in
            // Reload configuration when profile changes
            if let activeProfile = profileManager.activeProfile {
                configuration = activeProfile.iconConfig
            }
        }
    }

    // MARK: - Helper Methods

    private func saveConfiguration() {
        // Allow all metrics to be disabled - will show default app logo
        // No minimum enforcement needed

        // Save to active profile
        guard let profileId = profileManager.activeProfile?.id else {
            LoggingService.shared.logError("Cannot save appearance: no active profile")
            return
        }

        profileManager.updateIconConfig(configuration, for: profileId)

        // Notify that config changed (for MenuBarManager to update)
        NotificationCenter.default.post(name: .menuBarIconConfigChanged, object: nil)

        let enabledCount = configuration.metrics.filter { $0.isEnabled }.count
        LoggingService.shared.log("Saved icon configuration to profile (enabled: \(enabledCount))")
    }
}

// MARK: - Multi-Profile Mode Warning Card

struct MultiProfileModeWarningCard: View {
    let onDisableMultiProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("appearance.multiprofile_locked_title".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("appearance.multiprofile_locked_description".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button(action: onDisableMultiProfile) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                    Text("appearance.disable_multiprofile".localized)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.orange, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview {
    AppearanceSettingsView()
        .frame(width: 520, height: 600)
}
