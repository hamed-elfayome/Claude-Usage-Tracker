//
//  AppearanceSettingsView.swift
//  Claude Usage - Menu Bar Appearance Settings
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Menu bar icon appearance and customization
struct AppearanceSettingsView: View {
    @State private var iconStyle: MenuBarIconStyle = DataStore.shared.loadMenuBarIconStyle()
    @State private var monochromeMode: Bool = DataStore.shared.loadMonochromeMode()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "Menu Bar Appearance",
                subtitle: "Customize your menu bar icon style"
            )

            Divider()

            // Icon Style Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Icon Style")
                    .font(Typography.sectionHeader)

                IconStylePicker(selectedStyle: $iconStyle)
                    .onChange(of: iconStyle) { _, newValue in
                        DataStore.shared.saveMenuBarIconStyle(newValue)
                        NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
                    }
            }

            // Monochrome Mode Toggle
            SettingToggle(
                title: "Monochrome (Adaptive)",
                description: "Remove color coding and adapt to system appearance",
                isOn: $monochromeMode
            )
            .onChange(of: monochromeMode) { _, newValue in
                DataStore.shared.saveMonochromeMode(newValue)
                NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
            }

            Spacer()
        }
        .contentPadding()
    }
}

// MARK: - Previews

#Preview {
    AppearanceSettingsView()
        .frame(width: 520, height: 600)
}
