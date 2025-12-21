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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "General Settings",
                subtitle: "Configure app behavior and preferences"
            )

            Divider()

            // Data Refresh Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Refresh Interval")
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

                Text("Shorter intervals provide more real-time data but may impact battery life")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            // Usage Tracking Options
            SettingToggle(
                title: "Check Extra Usage Limit",
                description: "Fetch and display monthly cost and overage limit information",
                isOn: $checkOverageLimitEnabled
            )
            .onChange(of: checkOverageLimitEnabled) { _, newValue in
                DataStore.shared.saveCheckOverageLimitEnabled(newValue)
            }

            Spacer()
        }
        .contentPadding()
    }
}

// MARK: - Previews

#Preview {
    GeneralSettingsView(refreshInterval: .constant(30))
        .frame(width: 520, height: 600)
}
