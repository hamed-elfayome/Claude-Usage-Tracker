import AppKit
import SwiftUI

struct CodexSettingsView: View {
    var body: some View {
        if let manager = MenuBarManager.current {
            CodexSettingsContentView(manager: manager)
        } else {
            ContentUnavailableView(
                "Codex integration unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Restart Claude Usage Tracker and try again.")
            )
        }
    }
}

@MainActor
private struct CodexSettingsContentView: View {
    @ObservedObject var manager: MenuBarManager

    @State private var settings = CodexSettings()
    @State private var executablePath = ""
    @State private var diagnostics: CodexInstallationDiagnostics?
    @State private var isCheckingInstallation = false
    @State private var copiedCommand: String?

    private let store = SharedDataStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "codex.settings.title".localized,
                    subtitle: "codex.settings.subtitle".localized
                )

                monitoringCard
                connectionCard

                if diagnostics?.isInstalled != true || diagnostics?.isSignedIn != true {
                    setupGuideCard
                }

                trayCard
                notificationsCard
                dataCard

                Text("codex.settings.experimental_note".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .onAppear {
            settings = store.loadCodexSettings(
                legacyMetric: ProfileManager.shared.activeProfile?.iconConfig.config(for: .codex)
            )
            executablePath = settings.executablePath ?? ""
            inspectInstallation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .codexSettingsChanged)) { _ in
            settings = store.loadCodexSettings()
            executablePath = settings.executablePath ?? ""
        }
    }

    private var monitoringCard: some View {
        SettingsSectionCard(
            title: "codex.settings.monitoring_title".localized,
            subtitle: "codex.settings.monitoring_desc".localized
        ) {
            SettingToggle(
                title: "codex.settings.monitoring_toggle".localized,
                description: "codex.settings.monitoring_toggle_desc".localized,
                isOn: Binding(
                    get: { settings.monitoringEnabled },
                    set: { value in
                        settings.monitoringEnabled = value
                        saveSettings()
                    }
                )
            )
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
                    if isCheckingInstallation || manager.isCodexRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("codex.settings.executable".localized)
                        .font(.system(size: 11, weight: .medium))

                    HStack(spacing: 8) {
                        TextField("codex.settings.executable_auto".localized, text: $executablePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10, design: .monospaced))
                            .onSubmit { applyExecutablePath() }

                        SettingsButton(title: "codex.settings.choose".localized, icon: "folder") {
                            chooseExecutable()
                        }
                        if settings.executablePath != nil {
                            SettingsButton(title: "codex.settings.auto".localized) {
                                executablePath = ""
                                applyExecutablePath()
                            }
                        }
                    }
                }

                if let account = manager.codexUsage?.account {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("codex.settings.account".localized)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            if settings.showAccountEmail, let email = account.email {
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
                            get: { settings.showAccountEmail },
                            set: { settings.showAccountEmail = $0; saveSettings(refresh: false) }
                        )
                    )
                }

                if let updated = manager.codexUsage?.lastUpdated {
                    infoRow(label: "codex.settings.last_refresh".localized, value: updated.formatted(date: .abbreviated, time: .standard))
                }
                if let error = manager.codexRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    SettingsButton(title: "codex.settings.recheck".localized, icon: "stethoscope") {
                        inspectInstallation()
                    }
                    SettingsButton(title: "codex.settings.refresh".localized, icon: "arrow.clockwise") {
                        manager.refreshCodexUsageNow()
                    }
                    .disabled(!settings.monitoringEnabled || diagnostics?.isInstalled != true)
                }
            }
        }
    }

    private var setupGuideCard: some View {
        SettingsSectionCard(
            title: "codex.settings.setup_title".localized,
            subtitle: "codex.settings.setup_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 10) {
                commandRow(command: "npm install --global @openai/codex")
                commandRow(command: "codex login")
                commandRow(command: "codex login status")

                SettingsButton(title: "codex.settings.open_docs".localized, icon: "arrow.up.right.square") {
                    if let url = URL(string: "https://developers.openai.com/codex/cli/") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private var trayCard: some View {
        SettingsSectionCard(
            title: "codex.settings.tray_title".localized,
            subtitle: "codex.settings.tray_desc".localized
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                MetricIconCard(
                    metricType: .codex,
                    config: Binding(
                        get: { settings.menuBarMetric },
                        set: { settings.menuBarMetric = $0 }
                    ),
                    onConfigChanged: { saveSettings(refresh: false) }
                )

                if let usage = manager.codexUsage, !usage.rateLimits.isEmpty {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("codex.settings.bucket".localized)
                                .font(.system(size: 11, weight: .medium))
                            Text("codex.settings.bucket_desc".localized)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.selectedRateLimitID ?? "" },
                            set: { value in
                                settings.selectedRateLimitID = value.isEmpty ? nil : value
                                saveSettings(refresh: false)
                            }
                        )) {
                            Text("codex.settings.automatic".localized).tag("")
                            ForEach(usage.rateLimits) { limit in
                                Text(limit.displayName).tag(limit.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
            }
        }
        .disabled(!settings.monitoringEnabled)
        .opacity(settings.monitoringEnabled ? 1 : 0.55)
    }

    private var notificationsCard: some View {
        SettingsSectionCard(
            title: "codex.settings.notifications_title".localized,
            subtitle: "codex.settings.notifications_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggle(
                    title: "codex.settings.notifications_toggle".localized,
                    description: "codex.settings.notifications_toggle_desc".localized,
                    isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { settings.notificationsEnabled = $0; saveSettings(refresh: false) }
                    )
                )

                HStack(spacing: 18) {
                    ForEach([75, 90, 95], id: \.self) { threshold in
                        Toggle("\(threshold)%", isOn: thresholdBinding(threshold))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                    }
                }
                .disabled(!settings.notificationsEnabled)
                .opacity(settings.notificationsEnabled ? 1 : 0.55)
            }
        }
        .disabled(!settings.monitoringEnabled)
        .opacity(settings.monitoringEnabled ? 1 : 0.55)
    }

    private var dataCard: some View {
        SettingsSectionCard(
            title: "codex.settings.usage_title".localized,
            subtitle: "codex.settings.usage_desc".localized
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let usage = manager.codexUsage {
                    if let limit = usage.rateLimit(preferredID: settings.selectedRateLimitID),
                       let credits = limit.credits {
                        infoRow(
                            label: "codex.settings.credits".localized,
                            value: credits.unlimited ? "codex.settings.unlimited".localized : (credits.balance ?? "codex.settings.available".localized)
                        )
                    }
                    if let tokens = usage.tokenUsage?.lifetimeTokens {
                        infoRow(label: "codex.settings.lifetime_tokens".localized, value: tokens.formatted(.number.notation(.compactName)))
                    }
                    Text("codex.settings.privacy".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("codex.settings.no_usage".localized)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var connectionColor: Color {
        guard let diagnostics else { return .secondary }
        if !diagnostics.isInstalled { return .red }
        if !diagnostics.isSignedIn { return .orange }
        return manager.codexRefreshError == nil ? .green : .orange
    }

    private var connectionTitle: String {
        guard let diagnostics else { return "codex.settings.checking".localized }
        if !diagnostics.isInstalled { return "codex.settings.not_installed".localized }
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

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).textSelection(.enabled)
        }
    }

    private func commandRow(command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copiedCommand = command
            } label: {
                Image(systemName: copiedCommand == command ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("codex.settings.copy".localized)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    private func thresholdBinding(_ threshold: Int) -> Binding<Bool> {
        Binding(
            get: { settings.notificationThresholds.contains(threshold) },
            set: { enabled in
                if enabled {
                    settings.notificationThresholds.append(threshold)
                } else {
                    settings.notificationThresholds.removeAll { $0 == threshold }
                }
                settings.notificationThresholds = Array(Set(settings.notificationThresholds)).sorted()
                saveSettings(refresh: false)
            }
        )
    }

    private func saveSettings(refresh: Bool = true) {
        store.saveCodexSettings(settings)
        NotificationCenter.default.post(name: .codexSettingsChanged, object: nil)
        if refresh { inspectInstallation() }
    }

    private func applyExecutablePath() {
        let trimmed = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.executablePath = trimmed.isEmpty ? nil : trimmed
        executablePath = settings.executablePath ?? ""
        saveSettings()
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
            applyExecutablePath()
        }
    }

    private func inspectInstallation() {
        guard !isCheckingInstallation else { return }
        isCheckingInstallation = true
        let selectedPath = settings.executablePath
        Task {
            let result = await CodexAppServerService.inspectInstallation(customExecutablePath: selectedPath)
            await MainActor.run {
                diagnostics = result
                isCheckingInstallation = false
            }
        }
    }
}

#Preview {
    CodexSettingsView().frame(width: 530, height: 750)
}
