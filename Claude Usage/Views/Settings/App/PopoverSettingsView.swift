//
//  PopoverSettingsView.swift
//  Claude Usage
//
//  Popover display settings (app-wide, applies to both single and multi-profile)
//

import SwiftUI

struct PopoverSettingsView: View {
    @State private var showRemainingTime: Bool = SharedDataStore.shared.loadPopoverShowRemainingTime()
    @State private var timeFormat: TimeFormatPreference = SharedDataStore.shared.loadTimeFormatPreference()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "popover.title".localized,
                    subtitle: "popover.subtitle".localized
                )

                SettingsSectionCard(title: "popover.display_section".localized) {
                    SettingToggle(
                        title: "popover.show_remaining_time".localized,
                        description: "popover.show_remaining_time_desc".localized,
                        isOn: $showRemainingTime
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("popover.time_format".localized)
                            .font(.body)
                            .fontWeight(.medium)
                        Text("popover.time_format_desc".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $timeFormat) {
                            Text("popover.time_format_system".localized).tag(TimeFormatPreference.system)
                            Text("popover.time_format_12h".localized).tag(TimeFormatPreference.twelveHour)
                            Text("popover.time_format_24h".localized).tag(TimeFormatPreference.twentyFourHour)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
            .padding()
        }
        .onChange(of: showRemainingTime) { _, newValue in
            SharedDataStore.shared.savePopoverShowRemainingTime(newValue)
        }
        .onChange(of: timeFormat) { _, newValue in
            SharedDataStore.shared.saveTimeFormatPreference(newValue)
        }
    }
}
