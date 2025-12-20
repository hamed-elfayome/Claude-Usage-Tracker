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
        VStack(alignment: .leading, spacing: 16) {
            // Data Refresh
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Refresh Interval")
                        .font(Typography.body)

                    Spacer()

                    Text("\(Int(refreshInterval))s")
                        .font(Typography.monospacedValue)
                        .foregroundColor(.secondary)
                }

                Slider(value: $refreshInterval, in: 5...120, step: 1)
                    .onChange(of: refreshInterval) { _, newValue in
                        DataStore.shared.saveRefreshInterval(newValue)
                    }

                Text("Shorter intervals provide more real-time data but may impact battery life")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

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
        .padding(28)
    }
}

// MARK: - Previews

#Preview {
    GeneralSettingsView(refreshInterval: .constant(30))
        .frame(width: 520, height: 600)
}
