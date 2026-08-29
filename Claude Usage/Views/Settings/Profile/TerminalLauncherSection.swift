//
//  TerminalLauncherSection.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-08-29.
//

import SwiftUI

/// Settings card for the per-profile terminal launcher (`claude-<slug>`).
/// Anthropic-provider profiles only (gated by the caller on
/// `capabilities.cliAccountSync`).
struct TerminalLauncherSection: View {
    let profile: Profile

    @StateObject private var profileManager = ProfileManager.shared
    @State private var binDirOnPath = true
    @State private var loginPinned = false
    @State private var installError: String?
    @State private var didCopy = false

    private let launcherService = TerminalLauncherService.shared

    private var isInstalled: Bool {
        launcherService.isInstalled(profile)
    }

    private var launcherCommand: String {
        guard let slug = profile.terminalLauncherSlug else { return "" }
        return launcherService.launcherName(forSlug: slug)
    }

    var body: some View {
        SettingsSectionCard(
            title: "launcher.title".localized,
            subtitle: "launcher.subtitle".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if isInstalled {
                    installedContent
                } else {
                    notInstalledContent
                }

                if let installError {
                    Text(installError)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .onAppear { refreshStatus() }
    }

    // MARK: - Not installed

    private var notInstalledContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            Text(String(format: "launcher.description".localized,
                        launcherService.launcherName(forSlug: launcherService.availableSlug(for: profile))))
                .font(DesignTokens.Typography.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("launcher.install".localized) {
                installLauncher()
            }
        }
    }

    // MARK: - Installed

    private var installedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            HStack(spacing: DesignTokens.Spacing.iconText) {
                Image(systemName: "terminal")
                    .font(.system(size: DesignTokens.Icons.standard))
                    .foregroundColor(DesignTokens.Colors.accent)
                    .frame(width: DesignTokens.Spacing.iconFrame)

                Text(launcherCommand)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(launcherCommand, forType: .string)
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Button("launcher.remove".localized) {
                    removeLauncher()
                }
            }

            if loginPinned {
                Label("launcher.pinned".localized, systemImage: "checkmark.circle.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.adaptiveGreen)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(String(format: "launcher.login_needed".localized, launcherCommand))
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("launcher.verify".localized) {
                        refreshStatus()
                    }
                    .controlSize(.small)
                }
            }

            if !binDirOnPath {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Label("launcher.path_warning".localized, systemImage: "exclamationmark.triangle")
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.orange)

                    Text(launcherService.pathExportLine)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                }
            }
        }
    }

    // MARK: - Actions

    private func installLauncher() {
        installError = nil
        do {
            let slug = try launcherService.install(for: profile)
            var updated = profile
            updated.terminalLauncherSlug = slug
            profileManager.updateProfile(updated)
            refreshStatus()
        } catch {
            installError = String(format: "launcher.install_failed".localized, error.localizedDescription)
        }
    }

    private func removeLauncher() {
        launcherService.uninstall(profile)
        var updated = profile
        updated.terminalLauncherSlug = nil
        profileManager.updateProfile(updated)
    }

    private func refreshStatus() {
        guard isInstalled else { return }
        // Pin the profile as soon as the one-time /login has happened.
        if launcherService.pinIfLoginDetected(profile) {
            loginPinned = true
        } else if let slug = profile.terminalLauncherSlug {
            loginPinned = profile.customKeychainServiceName
                == launcherService.expectedKeychainService(forSlug: slug)
        }
        DispatchQueue.global(qos: .utility).async {
            let onPath = launcherService.isBinDirOnPath()
            DispatchQueue.main.async { binDirOnPath = onPath }
        }
    }
}
