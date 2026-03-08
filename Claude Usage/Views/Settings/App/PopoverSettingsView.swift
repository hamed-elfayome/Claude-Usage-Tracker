//
//  PopoverSettingsView.swift
//  Claude Usage
//
//  Popover display settings (app-wide, applies to both single and multi-profile)
//

import SwiftUI

struct PopoverSettingsView: View {
    @State private var showRemainingTime: Bool = SharedDataStore.shared.loadPopoverShowRemainingTime()

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
                }
            }
            .padding()
        }
        .onChange(of: showRemainingTime) { newValue in
            SharedDataStore.shared.savePopoverShowRemainingTime(newValue)
        }
    }
}
