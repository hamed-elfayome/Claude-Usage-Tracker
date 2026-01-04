//
//  AppearanceSettingsView.swift
//  Claude Usage - Menu Bar Appearance Settings
//
//  Created by Claude Code on 2025-12-27.
//

import SwiftUI

/// Menu bar icon appearance and customization with multi-metric support
struct AppearanceSettingsView: View {
    @State private var configuration: MenuBarIconConfiguration = DataStore.shared.loadMenuBarIconConfiguration()
    @State private var saveDebounceTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
                // Header
                SettingsHeader(
                    title: "appearance.title".localized,
                    subtitle: "appearance.subtitle".localized
                )

                Divider()

                // Global Settings
                Text("appearance.global_settings".localized)
                    .font(Typography.sectionHeader)

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

                Divider()

                // Metrics Configuration
                Text("appearance.menu_bar_metrics".localized)
                    .font(Typography.sectionHeader)

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
                        onConfigChanged: { saveConfiguration() },
                        isLastEnabled: isLastEnabledMetric(.session)
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
                        onConfigChanged: { saveConfiguration() },
                        isLastEnabled: isLastEnabledMetric(.week)
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
                        onConfigChanged: { saveConfiguration() },
                        isLastEnabled: isLastEnabledMetric(.api)
                    )
                }

                Spacer()
            }
            .contentPadding()
        }
    }

    // MARK: - Helper Methods

    private func saveConfiguration() {
        let enabledCount = configuration.metrics.filter { $0.isEnabled }.count
        if enabledCount == 0 {
            if let sessionIndex = configuration.metrics.firstIndex(where: { $0.metricType == .session }) {
                configuration.metrics[sessionIndex].isEnabled = true
            }
        }

        DataStore.shared.saveMenuBarIconConfiguration(configuration)
        NotificationCenter.default.post(name: .menuBarIconConfigChanged, object: nil)
    }

    private func isLastEnabledMetric(_ metricType: MenuBarMetricType) -> Bool {
        let enabledMetrics = configuration.metrics.filter { $0.isEnabled }
        return enabledMetrics.count == 1 && enabledMetrics.first?.metricType == metricType
    }
}

// MARK: - Previews

#Preview {
    AppearanceSettingsView()
        .frame(width: 520, height: 600)
}
