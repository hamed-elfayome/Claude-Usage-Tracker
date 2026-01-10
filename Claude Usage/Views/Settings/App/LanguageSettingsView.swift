//
//  LanguageSettingsView.swift
//  Claude Usage - App Language Settings
//
//  Created by Claude Code on 2026-01-11.
//

import SwiftUI

/// App-level language settings (not profile-specific)
struct LanguageSettingsView: View {
    @StateObject private var languageManager = LanguageManager.shared
    @State private var showRestartAlert = false
    @State private var pendingLanguage: LanguageManager.SupportedLanguage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "language.title".localized,
                    subtitle: "language.subtitle".localized
                )

                // Current Language
                SettingsSectionCard(
                    title: "language.select_language".localized,
                    subtitle: nil
                ) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        // Language List
                        VStack(spacing: DesignTokens.Spacing.small) {
                            ForEach(LanguageManager.SupportedLanguage.allCases) { language in
                                LanguageRow(
                                    language: language,
                                    isSelected: languageManager.currentLanguage == language,
                                    onSelect: {
                                        selectLanguage(language)
                                    }
                                )
                            }
                        }
                    }
                }

                // Info Card
                HStack(spacing: DesignTokens.Spacing.medium) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: DesignTokens.Icons.standard))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("general.language.restart_note".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DesignTokens.Spacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .fill(Color.blue.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )

                Spacer()
            }
            .padding(28)
        }
        .alert("language.restart_required".localized, isPresented: $showRestartAlert) {
            Button("language.restart_now".localized, role: .destructive) {
                restartApp()
            }
            Button("language.restart_later".localized, role: .cancel) {
                // User chose to restart later, language already changed
            }
        } message: {
            Text("language.restart_message".localized)
        }
    }

    private func selectLanguage(_ language: LanguageManager.SupportedLanguage) {
        guard language != languageManager.currentLanguage else { return }

        languageManager.currentLanguage = language
        pendingLanguage = language

        // Show restart alert
        showRestartAlert = true
    }

    private func restartApp() {
        // Save the current state
        UserDefaults.standard.synchronize()

        // Get the app path
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; open '\(Bundle.main.bundlePath)'"]
        task.launch()

        // Quit the app
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Language Row

struct LanguageRow: View {
    let language: LanguageManager.SupportedLanguage
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.medium) {
                // Flag emoji
                Text(language.flag)
                    .font(.system(size: 24))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .font(DesignTokens.Typography.body)
                        .foregroundColor(.primary)

                    Text(language.englishName)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(DesignTokens.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : DesignTokens.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : DesignTokens.Colors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview {
    LanguageSettingsView()
        .frame(width: 520, height: 600)
}
