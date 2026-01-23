//
//  MenuBarSettingsView.swift
//  Claude Usage - Menu Bar Metrics Configuration
//
//  Configure which metrics appear in the menu bar
//

import SwiftUI

/// Menu bar metrics configuration
struct MenuBarSettingsView: View {
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var configuration: MenuBarIconConfiguration?

    var body: some View {
        ScrollView {
            if let config = configuration {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                    // Page Header
                    SettingsPageHeader(
                        title: "Menu Bar",
                        subtitle: "Configure which metrics appear in your menu bar"
                    )

                    // Menu Bar Appearance
                    SettingsSectionCard(
                        title: "Appearance Style",
                        subtitle: "Choose appearance settings for the menu bar"
                    ) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                            SettingToggle(
                                title: "appearance.monochrome_title".localized,
                                description: "appearance.monochrome_description".localized,
                                isOn: Binding(
                                    get: { config.monochromeMode },
                                    set: { newValue in
                                        configuration?.monochromeMode = newValue
                                        saveConfiguration()
                                    }
                                )
                            )

                            SettingToggle(
                                title: "appearance.show_labels_title".localized,
                                description: "appearance.show_labels_description".localized,
                                isOn: Binding(
                                    get: { config.showIconNames },
                                    set: { newValue in
                                        configuration?.showIconNames = newValue
                                        saveConfiguration()
                                    }
                                )
                            )
                        }
                    }

                    // Metrics Configuration
                    SettingsSectionCard(
                        title: "Menu Bar Metrics",
                        subtitle: "Choose which metrics to display"
                    ) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            // Info message when all metrics are disabled
                            if config.metrics.filter({ $0.isEnabled }).isEmpty {
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
                            if let sessionIndex = config.metrics.firstIndex(where: { $0.metricType == .session }) {
                                MetricIconCard(
                                    metricType: .session,
                                    config: Binding(
                                        get: { config.metrics[sessionIndex] },
                                        set: { newValue in
                                            configuration?.metrics[sessionIndex] = newValue
                                        }
                                    ),
                                    onConfigChanged: { saveConfiguration() }
                                )
                            }

                            // Week Usage
                            if let weekIndex = config.metrics.firstIndex(where: { $0.metricType == .week }) {
                                MetricIconCard(
                                    metricType: .week,
                                    config: Binding(
                                        get: { config.metrics[weekIndex] },
                                        set: { newValue in
                                            configuration?.metrics[weekIndex] = newValue
                                        }
                                    ),
                                    onConfigChanged: { saveConfiguration() }
                                )
                            }

                            // API Credits
                            if let apiIndex = config.metrics.firstIndex(where: { $0.metricType == .api }) {
                                MetricIconCard(
                                    metricType: .api,
                                    config: Binding(
                                        get: { config.metrics[apiIndex] },
                                        set: { newValue in
                                            configuration?.metrics[apiIndex] = newValue
                                        }
                                    ),
                                    onConfigChanged: { saveConfiguration() }
                                )
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
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
        // Save to active profile
        guard let profileId = profileManager.activeProfile?.id else {
            LoggingService.shared.logError("Cannot save menu bar config: no active profile")
            return
        }

        guard let config = configuration else {
            LoggingService.shared.logError("Cannot save menu bar config: configuration not loaded")
            return
        }

        profileManager.updateIconConfig(config, for: profileId)

        // Notify that config changed (for MenuBarManager to update)
        NotificationCenter.default.post(name: .menuBarIconConfigChanged, object: nil)

        let enabledCount = config.metrics.filter { $0.isEnabled }.count
        LoggingService.shared.log("Saved menu bar configuration to profile (enabled: \(enabledCount))")
    }
}

// MARK: - Previews

#Preview {
    MenuBarSettingsView()
        .frame(width: 520, height: 600)
}
