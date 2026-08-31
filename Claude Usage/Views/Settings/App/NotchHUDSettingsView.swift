//
//  NotchHUDSettingsView.swift
//  Claude Usage
//
//  Settings for the Claude Code notch HUD: master toggle (installs hooks and
//  starts the local listener), auto-hide, hook install status, server status.
//

import SwiftUI

struct NotchHUDSettingsView: View {
    @State private var enabled: Bool = SharedDataStore.shared.loadNotchHUDEnabled()
    @State private var autoHide: Bool = SharedDataStore.shared.loadNotchHUDAutoHide()
    @State private var hookStatus: NotchHookInstaller.InstallStatus = .notInstalled
    @ObservedObject private var store = NotchSessionStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "notch.hud.section_title".localized,
                    subtitle: "notch.hud.section_desc".localized
                )

                SettingsSectionCard(
                    title: "notch.hud.section_title".localized,
                    subtitle: "notch.hud.section_desc".localized
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                        SettingToggle(
                            title: "notch.hud.enable".localized,
                            description: "notch.hud.enable_desc".localized,
                            badge: .beta,
                            isOn: $enabled
                        )

                        SettingToggle(
                            title: "notch.hud.auto_hide".localized,
                            description: "notch.hud.auto_hide_desc".localized,
                            isOn: $autoHide
                        )
                        .disabled(!enabled)
                        .opacity(enabled ? 1.0 : 0.5)
                        .padding(.leading, 16)
                    }
                }

                SettingsSectionCard(
                    title: "notch.hooks.title".localized,
                    subtitle: "notch.hooks.desc".localized
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.cardPadding) {
                        hookStatusRow
                        if enabled {
                            serverStatusRow
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear { hookStatus = NotchHookInstaller.shared.checkStatus() }
        .onChange(of: enabled) { _, newValue in
            SharedDataStore.shared.saveNotchHUDEnabled(newValue)
            if newValue {
                NotchHookInstaller.shared.install()
            } else if !SharedDataStore.shared.loadKeepAwakeAutoEnabled() {
                // Keep Awake's auto mode shares the hooks — only remove them
                // when no feature needs session events anymore.
                NotchHookInstaller.shared.uninstall()
            }
            hookStatus = NotchHookInstaller.shared.checkStatus()
            NotificationCenter.default.post(name: .notchHUDSettingChanged, object: nil)
        }
        .onChange(of: autoHide) { _, newValue in
            SharedDataStore.shared.saveNotchHUDAutoHide(newValue)
            NotificationCenter.default.post(name: .notchHUDSettingChanged, object: nil)
        }
    }

    // MARK: - Hook status

    private var hookStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hookStatusColor)
                .frame(width: 8, height: 8)
            Text(hookStatusText)
                .font(DesignTokens.Typography.body)
                .foregroundColor(SettingsColors.secondary)
            Spacer()
            switch hookStatus {
            case .installed:
                Button("notch.hooks.remove".localized) {
                    NotchHookInstaller.shared.uninstall()
                    hookStatus = NotchHookInstaller.shared.checkStatus()
                }
            case .partial, .legacyDetected:
                Button("notch.hooks.repair".localized) {
                    NotchHookInstaller.shared.install()
                    hookStatus = NotchHookInstaller.shared.checkStatus()
                }
            case .notInstalled, .error:
                Button("notch.hooks.install".localized) {
                    NotchHookInstaller.shared.install()
                    hookStatus = NotchHookInstaller.shared.checkStatus()
                }
            }
        }
    }

    private var hookStatusColor: Color {
        switch hookStatus {
        case .installed: return .green
        case .partial, .legacyDetected: return .orange
        case .notInstalled: return .secondary
        case .error: return .red
        }
    }

    private var hookStatusText: String {
        switch hookStatus {
        case .installed: return "notch.hooks.status_installed".localized
        case .partial: return "notch.hooks.status_partial".localized
        case .legacyDetected: return "notch.hooks.status_legacy".localized
        case .notInstalled: return "notch.hooks.status_not_installed".localized
        case .error(let message): return message
        }
    }

    // MARK: - Server status

    private var serverStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.serverStatus == .running ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(serverStatusText)
                .font(DesignTokens.Typography.body)
                .foregroundColor(SettingsColors.secondary)
            Spacer()
            if store.serverStatus == .portBusy {
                Button("notch.server.retry".localized) {
                    NotchHookServer.shared.retry()
                }
            }
        }
    }

    private var serverStatusText: String {
        switch store.serverStatus {
        case .running:
            return "notch.server.listening".localized(with: "\(Constants.NotchHUD.host):\(Constants.NotchHUD.port)")
        case .portBusy:
            return "notch.server.port_busy".localized(with: "\(Constants.NotchHUD.port)")
        case .stopped:
            return "notch.hooks.status_not_installed".localized
        }
    }
}

#Preview {
    NotchHUDSettingsView()
        .frame(width: 520, height: 420)
}
