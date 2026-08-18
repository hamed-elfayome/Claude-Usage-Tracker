//
//  AppSettingsView.swift
//  Claude Usage
//
//  App-wide settings (launch at login, etc.)
//

import SwiftUI

struct AppSettingsView: View {
    @State private var launchAtLogin = LaunchAtLoginManager.shared.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "section.app_settings_title".localized,
                    subtitle: "section.app_settings_desc".localized
                )

                SettingsSectionCard(
                    title: "general.launch_at_login".localized,
                    subtitle: "general.launch_at_login.description".localized
                ) {
                    SettingToggle(
                        title: "general.launch_at_login".localized,
                        description: "general.launch_at_login.description".localized,
                        isOn: $launchAtLogin
                    )
                }
            }
            .padding()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginManager.shared.setEnabled(newValue)
        }
    }
}

#Preview {
    AppSettingsView()
        .frame(width: 520, height: 400)
}
