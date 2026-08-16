import AppKit
import SwiftUI

/// Connection settings for the active z.ai (GLM Coding Plan) profile.
/// Appearance, refresh interval, notifications, and multi-profile selection
/// intentionally remain in the same shared profile settings used by Claude
/// profiles.
struct ZAISettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared

    var body: some View {
        if let profile = profileManager.activeProfile, profile.provider == .zai {
            ZAIProfileSettingsContent(profileID: profile.id)
        } else {
            ContentUnavailableView(
                "Select a Z.ai profile",
                systemImage: ProfileProvider.zai.icon,
                description: Text("Create or select a Z.ai GLM profile under Manage Profiles.")
            )
        }
    }
}

@MainActor
private struct ZAIProfileSettingsContent: View {
    let profileID: UUID

    @StateObject private var profileManager = ProfileManager.shared
    @State private var configuration = ZAIProfileConfiguration()
    @State private var apiKey = ""
    @State private var isEditingKey = false

    private var profile: Profile? {
        profileManager.profiles.first { $0.id == profileID }
    }

    private var usage: ZAIUsage? {
        profile?.zaiUsage
    }

    private var manager: MenuBarManager? {
        MenuBarManager.current
    }

    private var hasStoredKey: Bool {
        profile?.zaiAPIKey != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "zai.settings.title".localized,
                    subtitle: "zai.settings.subtitle".localized
                )

                connectionCard

                if !hasStoredKey {
                    setupGuideCard
                }

                if let usage, !usage.rateLimits.isEmpty {
                    rateLimitCard(usage)
                }

                usageCard

                Text("zai.settings.privacy".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .onAppear(perform: load)
        .onChange(of: profileID) { _, _ in load() }
        .onDisappear {
            persistConfiguration()
        }
    }

    private var connectionCard: some View {
        SettingsSectionCard(
            title: "zai.settings.connection_title".localized,
            subtitle: "zai.settings.connection_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionTitle)
                            .font(.system(size: 12, weight: .semibold))
                        if let detail = connectionDetail {
                            Text(detail)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                    if manager?.isZAIRefreshing == true {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider()

                if isEditingKey || !hasStoredKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("zai.settings.api_key".localized)
                            .font(.system(size: 11, weight: .medium))
                        SecureField(
                            hasStoredKey ? "zai.settings.api_key_placeholder_keep".localized : "zai.settings.api_key_placeholder".localized,
                            text: $apiKey
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .onSubmit { saveAPIKey() }
                        Text("zai.settings.api_key_help".localized)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            SettingsButton(title: "zai.settings.save_key".localized, icon: "key.fill") {
                                saveAPIKey()
                            }
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if hasStoredKey {
                                SettingsButton(title: "common.cancel".localized, icon: "xmark") {
                                    isEditingKey = false
                                    apiKey = ""
                                }
                            }
                        }
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("zai.settings.api_key".localized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(maskedKey)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        Spacer()
                        SettingsButton(title: "zai.settings.replace_key".localized, icon: "pencil") {
                            isEditingKey = true
                            apiKey = ""
                        }
                        SettingsButton(title: "zai.settings.remove_key".localized, icon: "trash") {
                            removeAPIKey()
                        }
                    }
                }

                if let error = manager?.zaiRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    SettingsButton(title: "zai.settings.refresh".localized, icon: "arrow.clockwise") {
                        persistConfiguration()
                        manager?.refreshZAIUsageNow()
                    }
                    .disabled(!hasStoredKey)
                }
            }
        }
    }

    private var setupGuideCard: some View {
        SettingsSectionCard(
            title: "zai.settings.setup_title".localized,
            subtitle: "zai.settings.setup_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("zai.settings.setup_steps".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    SettingsButton(title: "zai.settings.open_docs".localized, icon: "arrow.up.right.square") {
                        NSWorkspace.shared.open(URL(string: "https://docs.z.ai/devpack/overview")!)
                    }
                    SettingsButton(title: "zai.settings.open_console".localized, icon: "key") {
                        NSWorkspace.shared.open(URL(string: "https://z.ai/manage-apikey/apikey")!)
                    }
                }
            }
        }
    }

    private func rateLimitCard(_ usage: ZAIUsage) -> some View {
        SettingsSectionCard(
            title: "zai.settings.bucket".localized,
            subtitle: "zai.settings.bucket_desc".localized
        ) {
            Picker("", selection: Binding(
                get: { configuration.selectedLimitID ?? "" },
                set: {
                    configuration.selectedLimitID = $0.isEmpty ? nil : $0
                    persistConfiguration()
                }
            )) {
                Text("codex.settings.automatic".localized).tag("")
                ForEach(usage.rateLimits) { limit in
                    Text(bucketName(for: limit)).tag(limit.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Bucket names in the same terms the popover uses, so "Session" in the
    /// tray settings matches the "Session Usage" row it drives.
    private func bucketName(for limit: ZAIRateLimit) -> String {
        if limit.isFiveHourSessionWindow { return "menubar.session_usage".localized }
        if limit.isWeeklyWindow { return "menubar.weekly_usage".localized }
        if limit.kind == .toolCalls { return "zai.window.tools_title".localized }
        return limit.displayName
    }

    private var usageCard: some View {
        SettingsSectionCard(
            title: "zai.settings.usage_title".localized,
            subtitle: "zai.settings.usage_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let usage {
                    infoRow(
                        "codex.settings.last_refresh".localized,
                        usage.lastUpdated.formatted(date: .abbreviated, time: .standard)
                    )
                    if let plan = usage.account?.planType {
                        infoRow("zai.settings.plan".localized, plan.capitalized)
                    }
                } else {
                    Text("zai.settings.no_usage".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).textSelection(.enabled)
        }
    }

    private var maskedKey: String {
        guard let key = profile?.zaiAPIKey, !key.isEmpty else { return "—" }
        let prefix = key.prefix(6)
        let suffix = key.suffix(4)
        return "\(prefix)••••••\(suffix)"
    }

    private var connectionColor: Color {
        guard hasStoredKey else { return .orange }
        return manager?.zaiRefreshError == nil ? .green : .orange
    }

    private var connectionTitle: String {
        guard hasStoredKey else { return "zai.settings.no_key".localized }
        if manager?.zaiRefreshError != nil { return "zai.settings.error_state".localized }
        return usage == nil ? "zai.settings.checking".localized : "zai.settings.connected".localized
    }

    private var connectionDetail: String? {
        if let plan = usage?.account?.planType {
            return "GLM Coding Plan · \(plan.capitalized)"
        }
        return manager?.zaiRefreshError
    }

    private func load() {
        guard let profile else { return }
        configuration = profile.zaiConfiguration
        apiKey = ""
        isEditingKey = false
    }

    private func persistConfiguration() {
        guard var updated = profile else { return }
        updated.zaiConfiguration = configuration
        profileManager.updateProfile(updated)
        NotificationCenter.default.post(name: .zaiSettingsChanged, object: profileID)
    }

    private func saveAPIKey() {
        guard var updated = profile else { return }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Never present one account's cached quota under a different key.
        updated.zaiAPIKey = trimmed
        updated.zaiUsage = nil
        updated.zaiConfiguration = configuration
        profileManager.updateProfile(updated)
        apiKey = ""
        isEditingKey = false
        NotificationCenter.default.post(name: .zaiSettingsChanged, object: profileID)
        manager?.refreshZAIUsageNow()
    }

    private func removeAPIKey() {
        guard var updated = profile else { return }
        updated.zaiAPIKey = nil
        updated.zaiUsage = nil
        profileManager.updateProfile(updated)
        NotificationCenter.default.post(name: .zaiSettingsChanged, object: profileID)
    }
}

#Preview {
    ZAISettingsView().frame(width: 530, height: 750)
}
