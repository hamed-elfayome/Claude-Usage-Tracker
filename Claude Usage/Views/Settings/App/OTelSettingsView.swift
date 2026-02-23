//
//  OTelSettingsView.swift
//  Claude Usage - OTel Collection Settings
//
//  Settings page for enabling/disabling OTel telemetry collection
//  and showing server status + setup instructions.
//

import SwiftUI

struct OTelSettingsView: View {
    @StateObject private var otelManager = OTelManager.shared
    @State private var isEnabled: Bool = SharedDataStore.shared.loadOTelCollectionEnabled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "OTel Collection",
                    subtitle: "Receive per-request telemetry from Claude Code via OpenTelemetry"
                )

                // Enable/Disable Toggle + Status
                SettingsSectionCard(title: "Collection", subtitle: "Start or stop the local OTLP receiver") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        Toggle("Enable OTel collection", isOn: $isEnabled)
                            .font(DesignTokens.Typography.body)
                            .onChange(of: isEnabled) { _, newValue in
                                SharedDataStore.shared.saveOTelCollectionEnabled(newValue)
                                if newValue {
                                    OTelManager.shared.startCollection()
                                } else {
                                    OTelManager.shared.stopCollection()
                                }
                            }

                        // Status indicator
                        HStack(spacing: DesignTokens.Spacing.small) {
                            Circle()
                                .fill(otelManager.isCollecting ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)

                            Text(otelManager.isCollecting
                                 ? "Listening on localhost:\(SharedDataStore.shared.loadOTelPort())"
                                 : "Not running")
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }

                        if otelManager.totalEventsReceived > 0 {
                            HStack(spacing: DesignTokens.Spacing.small) {
                                Image(systemName: "tray.full.fill")
                                    .font(.system(size: DesignTokens.Icons.small))
                                    .foregroundColor(.secondary)
                                Text("\(otelManager.totalEventsReceived) events stored")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Setup Instructions
                SettingsSectionCard(title: "Setup", subtitle: "Add these environment variables before launching Claude Code") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        let commands = """
                            export CLAUDE_CODE_ENABLE_TELEMETRY=1
                            export OTEL_LOGS_EXPORTER=otlp
                            export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
                            export OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://localhost:\(SharedDataStore.shared.loadOTelPort())/v1/logs
                            """

                        Text(commands)
                            .font(DesignTokens.Typography.monospacedSmall)
                            .textSelection(.enabled)
                            .padding(DesignTokens.Spacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                    .fill(Color.accentColor.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                                    )
                            )

                        Button("Copy to Clipboard") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(commands, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .font(DesignTokens.Typography.body)

                        Text("Add these to your shell profile (~/.zshrc) or run them before starting Claude Code.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)

                        Text("Optionally add OTEL_LOG_USER_PROMPTS=1 to also capture prompt text.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    OTelSettingsView()
        .frame(width: 520, height: 600)
}
