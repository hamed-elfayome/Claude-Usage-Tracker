//
//  AntigravityAccountView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//
//  Settings view for Google Antigravity profiles: shows whether the `agy`
//  CLI is installed, lets the profile pick which quota pool its menu bar shows (the popover
//  lists every pool), and
//  tests the connection by running `agy /usage`. The CLI owns the Google
//  login, so there is nothing to paste or store here.
//

import SwiftUI

struct AntigravityAccountView: View {
    @StateObject private var profileManager = ProfileManager.shared

    @State private var executable: URL?
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult {
        case success([BucketLine])
        case failure(String)
    }

    private struct BucketLine: Identifiable {
        let id: String
        let text: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "antigravity.title".localized,
                    subtitle: "antigravity.subtitle".localized
                )

                if let profile = profileManager.activeProfile {
                    statusCard(for: profile)
                    poolCard(for: profile)
                }
            }
            .padding()
        }
        .onAppear { refreshDetection(resetShellLookup: false) }
    }

    // MARK: - Status

    private func statusCard(for profile: Profile) -> some View {
        let installed = executable != nil

        return SettingsSectionCard(
            title: "antigravity.cli_title".localized,
            subtitle: "antigravity.cli_subtitle".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                HStack(spacing: DesignTokens.Spacing.iconText) {
                    Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: DesignTokens.Icons.standard))
                        .foregroundColor(installed ? .green : .orange)
                        .frame(width: DesignTokens.Spacing.iconFrame)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                        Text(installed ? "antigravity.cli_found".localized : "antigravity.cli_not_found".localized)
                            .font(DesignTokens.Typography.body)
                        if let executable {
                            Text(executable.path)
                                .font(DesignTokens.Typography.monospaced)
                                .foregroundColor(.secondary)
                        } else {
                            Text("antigravity.cli_not_found_hint".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text("antigravity.one_account_note".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("antigravity.rescan".localized) {
                        refreshDetection(resetShellLookup: true)
                    }

                    Button {
                        testConnection(for: profile)
                    } label: {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("antigravity.test_connection".localized)
                        }
                    }
                    .disabled(isTesting || !installed)
                }

                if let result = testResult {
                    switch result {
                    case .success(let lines):
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                            Label("antigravity.test_success".localized, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            ForEach(lines) { line in
                                Text(line.text)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(DesignTokens.Typography.caption)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.red)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    // MARK: - Pool

    private func poolCard(for profile: Profile) -> some View {
        SettingsSectionCard(
            title: "antigravity.pool_title".localized,
            subtitle: "antigravity.pool_subtitle".localized
        ) {
            Picker("", selection: poolBinding(for: profile)) {
                ForEach(AntigravityPool.allCases, id: \.self) { pool in
                    Text(Self.poolName(pool)).tag(pool)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
    }

    static func poolName(_ pool: AntigravityPool) -> String {
        switch pool {
        case .thirdParty: return "antigravity.pool.third_party".localized
        case .gemini: return "antigravity.pool.gemini".localized
        }
    }

    private func poolBinding(for profile: Profile) -> Binding<AntigravityPool> {
        Binding(
            get: { profileManager.activeProfile?.antigravityPool ?? .thirdParty },
            set: { profileManager.setActiveAntigravityPool($0) }
        )
    }

    // MARK: - Actions

    private func refreshDetection(resetShellLookup: Bool) {
        if resetShellLookup { AntigravityCLILocator.shared.resetShellLookup() }
        executable = AntigravityCLILocator.shared.cachedExecutable()
        Task {
            let resolved = await AntigravityCLILocator.shared.resolve()
            await MainActor.run { executable = resolved }
        }
    }

    private func testConnection(for profile: Profile) {
        isTesting = true
        testResult = nil
        Task {
            do {
                let response = try await AntigravityUsageProvider.shared.fetchRawResponse(forceRefresh: true)
                let lines = Self.describe(response)
                await MainActor.run {
                    testResult = .success(lines)
                    isTesting = false
                }
            } catch {
                let message = (error as? AppError)?.message ?? error.localizedDescription
                await MainActor.run {
                    testResult = .failure(message)
                    isTesting = false
                }
            }
        }
    }

    /// "Claude and GPT models · 5h: 97% left"
    private static func describe(_ response: AntigravityUsageResponse) -> [BucketLine] {
        response.groups.flatMap { group in
            group.buckets.map { bucket in
                let left = Int(((bucket.remainingFraction ?? 0) * 100).rounded())
                let window = bucket.window ?? "?"
                let text = "\(group.name ?? "?") · \(window): " + "antigravity.percent_left".localized(with: left)
                return BucketLine(id: "\(group.name ?? "")/\(bucket.id ?? window)", text: text)
            }
        }
    }
}
