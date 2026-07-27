import AppKit
import SwiftUI

/// Connection settings for the active Codex profile. Appearance, refresh
/// interval, notifications, and multi-profile selection intentionally remain
/// in the same shared profile settings used by Claude profiles.
struct CodexSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared

    var body: some View {
        if let profile = profileManager.activeProfile, profile.provider == .codex {
            CodexProfileSettingsContent(profileID: profile.id)
        } else {
            ContentUnavailableView(
                "Select a Codex profile",
                systemImage: ProfileProvider.codex.icon,
                description: Text("Create or select an OpenAI Codex profile under Manage Profiles.")
            )
        }
    }
}

@MainActor
private struct CodexProfileSettingsContent: View {
    let profileID: UUID

    @StateObject private var profileManager = ProfileManager.shared
    @State private var configuration = CodexProfileConfiguration()
    @State private var executablePath = ""
    @State private var codexHome = ""
    @State private var sshHost = ""
    @State private var diagnostics: CodexInstallationDiagnostics?
    @State private var isChecking = false
    @State private var diagnosticsTask: Task<Void, Never>?

    private var profile: Profile? {
        profileManager.profiles.first { $0.id == profileID }
    }

    private var usage: CodexUsage? {
        profile?.codexUsage
    }

    private var manager: MenuBarManager? {
        MenuBarManager.current
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "codex.settings.title".localized,
                    subtitle: "codex.settings.subtitle".localized
                )

                connectionCard

                if diagnostics?.isInstalled != true || diagnostics?.isSignedIn != true {
                    setupGuideCard
                }

                if let usage, !usage.rateLimits.isEmpty {
                    rateLimitCard(usage)
                }

                usageCard

                Text("codex.settings.privacy".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("codex.settings.experimental_note".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .onAppear(perform: load)
        .onChange(of: profileID) { _, _ in load() }
        .onChange(of: executablePath) { _, value in
            configuration.executablePath = value.nilIfBlank
        }
        .onChange(of: codexHome) { _, value in
            configuration.codexHome = value.nilIfBlank
        }
        .onChange(of: sshHost) { _, value in
            // Keep validation current while the user types. Persistence still
            // happens on submit, refresh/recheck, or when leaving the view.
            configuration.sshHost = value.nilIfBlank
        }
        .onDisappear {
            persistFields()
            diagnosticsTask?.cancel()
            diagnosticsTask = nil
        }
    }

    private var connectionCard: some View {
        SettingsSectionCard(
            title: "codex.settings.connection_title".localized,
            subtitle: "codex.settings.connection_desc".localized
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
                    if isChecking || manager?.isCodexRefreshing == true {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider()

                Picker("Connection", selection: Binding(
                    get: { configuration.connectionType },
                    set: {
                        configuration.connectionType = $0
                        save()
                    }
                )) {
                    ForEach(CodexConnectionType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if configuration.connectionType == .ssh {
                    field(
                        title: "SSH host alias",
                        value: $sshHost,
                        placeholder: "codex-vm",
                        help: "Uses a Host entry from ~/.ssh/config. Key-based, agent, and macOS Keychain authentication are supported by /usr/bin/ssh."
                    )
                }

                field(
                    title: configuration.connectionType == .local
                        ? "Codex executable"
                        : "Remote Codex executable",
                    value: $executablePath,
                    placeholder: configuration.connectionType == .local
                        ? "Automatically detected"
                        : "codex",
                    help: configuration.connectionType == .local
                        ? "Leave blank to search common install locations and PATH."
                        : "Leave blank to run codex from the remote shell PATH."
                )

                field(
                    title: configuration.connectionType == .local
                        ? "CODEX_HOME"
                        : "Remote CODEX_HOME",
                    value: $codexHome,
                    placeholder: "Default Codex home",
                    help: "Optional. Use an existing Codex home to monitor another signed-in Codex account. The setup commands below create it when needed."
                )

                if configuration.connectionType == .local {
                    SettingsButton(title: "codex.settings.choose".localized, icon: "folder") {
                        chooseExecutable()
                    }
                }

                if let validationError = configuration.validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }

                if let account = usage?.account {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("codex.settings.account".localized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            if configuration.showAccountEmail, let email = account.email {
                                Text(email).font(.system(size: 11)).textSelection(.enabled)
                            }
                        }
                        Spacer()
                        if let plan = account.planType {
                            Text(plan.capitalized)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }

                    SettingToggle(
                        title: "codex.settings.show_email".localized,
                        description: "codex.settings.show_email_desc".localized,
                        isOn: Binding(
                            get: { configuration.showAccountEmail },
                            set: {
                                configuration.showAccountEmail = $0
                                save(inspect: false)
                            }
                        )
                    )
                }

                if let error = manager?.codexRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    SettingsButton(title: "codex.settings.recheck".localized, icon: "stethoscope") {
                        persistFields()
                        inspectInstallation()
                    }
                    SettingsButton(title: "codex.settings.refresh".localized, icon: "arrow.clockwise") {
                        persistFields()
                        manager?.refreshCodexUsageNow()
                    }
                    .disabled(configuration.validationError != nil)
                }
            }
        }
    }

    private var setupGuideCard: some View {
        SettingsSectionCard(
            title: "codex.settings.setup_title".localized,
            subtitle: "codex.settings.setup_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(setupCommands)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))

                HStack {
                    SettingsButton(title: "codex.settings.open_docs".localized, icon: "arrow.up.right.square") {
                        NSWorkspace.shared.open(URL(string: "https://developers.openai.com/codex/cli/")!)
                    }
                    if configuration.connectionType == .ssh {
                        SettingsButton(title: "Remote connection guide", icon: "network") {
                            NSWorkspace.shared.open(URL(string: "https://learn.chatgpt.com/docs/remote-connections")!)
                        }
                    }
                }
            }
        }
    }

    private func rateLimitCard(_ usage: CodexUsage) -> some View {
        SettingsSectionCard(
            title: "codex.settings.bucket".localized,
            subtitle: "codex.settings.bucket_desc".localized
        ) {
            Picker("", selection: Binding(
                get: { configuration.selectedRateLimitID ?? "" },
                set: {
                    configuration.selectedRateLimitID = $0.isEmpty ? nil : $0
                    save(inspect: false)
                }
            )) {
                Text("codex.settings.automatic".localized).tag("")
                ForEach(usage.rateLimits) { limit in
                    Text(limit.displayName).tag(limit.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var usageCard: some View {
        SettingsSectionCard(
            title: "codex.settings.usage_title".localized,
            subtitle: "codex.settings.usage_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let usage {
                    if let updated = usage.lastUpdated as Date? {
                        infoRow("codex.settings.last_refresh".localized, updated.formatted(date: .abbreviated, time: .standard))
                    }
                    if let tokens = usage.tokenUsage?.lifetimeTokens {
                        infoRow("codex.settings.lifetime_tokens".localized, tokens.formatted(.number.notation(.compactName)))
                    }
                } else {
                    Text("codex.settings.no_usage".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var setupCommands: String {
        let authentication = configuration.setupCommands
        guard configuration.connectionType == .local,
              diagnostics?.isInstalled == false else {
            return authentication
        }
        return "npm install --global @openai/codex\n\(authentication)"
    }

    private func field(
        title: String,
        value: Binding<String>,
        placeholder: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium))
            TextField(placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .onSubmit { persistFields() }
            Text(help)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).textSelection(.enabled)
        }
    }

    private var connectionColor: Color {
        guard let diagnostics else { return .secondary }
        if !diagnostics.isInstalled { return .red }
        if !diagnostics.isSignedIn { return .orange }
        return manager?.codexRefreshError == nil ? .green : .orange
    }

    private var connectionTitle: String {
        guard let diagnostics else { return "codex.settings.checking".localized }
        if !diagnostics.isInstalled {
            return configuration.connectionType == .ssh
                ? "SSH connection failed"
                : "codex.settings.not_installed".localized
        }
        if !diagnostics.isSignedIn { return "codex.settings.signed_out".localized }
        return "codex.settings.connected".localized
    }

    private var connectionDetail: String? {
        if diagnostics?.isInstalled == true, diagnostics?.isSignedIn == false {
            return diagnostics?.loginStatus ?? diagnostics?.error
        }
        if let version = diagnostics?.version, let path = diagnostics?.executablePath {
            return "\(version) · \(path)"
        }
        return diagnostics?.loginStatus ?? diagnostics?.error
    }

    private func load() {
        guard let profile else { return }
        configuration = profile.codexConfiguration
        executablePath = configuration.executablePath ?? ""
        codexHome = configuration.codexHome ?? ""
        sshHost = configuration.sshHost ?? ""
        inspectInstallation()
    }

    private func persistFields() {
        configuration.executablePath = executablePath.nilIfBlank
        configuration.codexHome = codexHome.nilIfBlank
        configuration.sshHost = sshHost.nilIfBlank
        save()
    }

    private func save(inspect: Bool = true) {
        guard var updated = profile else { return }
        if !updated.codexConfiguration.targetsSameInstallation(as: configuration) {
            // Never present one machine/account's cached limits under a newly
            // selected connection if that connection cannot refresh.
            updated.codexUsage = nil
            diagnostics = nil
        }
        updated.codexConfiguration = configuration
        profileManager.updateProfile(updated)
        NotificationCenter.default.post(name: .codexSettingsChanged, object: profileID)
        if inspect { inspectInstallation() }
    }

    private func inspectInstallation() {
        diagnosticsTask?.cancel()
        isChecking = true
        let current = configuration
        diagnosticsTask = Task {
            let result = await CodexAppServerService.inspectInstallation(configuration: current)
            guard !Task.isCancelled,
                  current.targetsSameInstallation(as: configuration) else { return }
            diagnostics = result
            isChecking = false
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "codex.settings.choose_title".localized
        panel.message = "codex.settings.choose_message".localized
        panel.prompt = "codex.settings.choose".localized
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            executablePath = url.path
            persistFields()
        }
    }
}

#Preview {
    CodexSettingsView().frame(width: 530, height: 750)
}
