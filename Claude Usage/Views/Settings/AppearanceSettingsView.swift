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

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu Bar Appearance")
                    .font(.system(size: 18, weight: .semibold))

                Text("Choose your preferred icon style")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            // Icon Style Picker - Row of cards
            IconStylePicker(selectedStyle: $iconStyle)
                .onChange(of: iconStyle) { _, newValue in
                    DataStore.shared.saveMenuBarIconStyle(newValue)
                    NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
                }

            Spacer()
        }
        .padding(28)
    }
}

// MARK: - Previews

#Preview {
    AppearanceSettingsView()
        .frame(width: 520, height: 600)
}
