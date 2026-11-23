import SwiftUI

/// Shows how to sign the Grok CLI in and checks the weekly quota. The app
/// does not read or store the CLI token.
struct GrokAccountView: View {
    private let setupProfileID: UUID?
    private let onDone: ((String?) -> Void)?
    private let onBack: (() -> Void)?
    @ObservedObject private var profileManager = ProfileManager.shared
    @State private var draftPath: String
    @State private var testTask: Task<Void, Never>?
    @State private var message: String?
    @State private var verified: Target?

    private struct Target: Equatable {
        let profileID: UUID
        let home: URL
    }

    init(
        setupProfileID: UUID? = nil, initialHomePath: String = "",
        onDone: ((String?) -> Void)? = nil, onBack: (() -> Void)? = nil
    ) {
        self.setupProfileID = setupProfileID
        self.onDone = onDone
        self.onBack = onBack
        _draftPath = State(initialValue: initialHomePath)
    }

    private var editingHome: Bool {
        guard let profile = profileManager.activeProfile else { return false }
        return profile.id == setupProfileID && profile.provider != .grok
    }

    private var homePath: String? {
        editingHome ? draftPath : profileManager.activeProfile?.grokHomePath
    }

    private var target: Target? {
        guard let profile = profileManager.activeProfile,
              setupProfileID.map({ $0 == profile.id }) ?? (profile.provider == .grok),
              let home = GrokHome.resolve(homePath),
              GrokUsageProvider.canConfigure(
                profileID: profile.id, homePath: homePath, profiles: profileManager.profiles
              ) else { return nil }
        return Target(profileID: profile.id, home: home)
    }

    var body: some View {
        let cliPresent = GrokCLIClient.locateExecutable() != nil
        let target = self.target
        let connected = target != nil && verified == target
        let loginDetected = cliPresent && message == nil && target.map { GrokCLIClient.authFileExists(in: $0.home) } == true
        let disconnectedStatus = loginDetected ? "grok.login_detected".localized : "codex.not_connected".localized
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "grok.title".localized,
                    subtitle: "grok.subtitle".localized
                )

                if editingHome {
                    GrokHomeField(path: Binding(get: { draftPath }, set: { newPath in
                        invalidateTest()
                        draftPath = newPath
                    }), available: target != nil)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("grok.home_label".localized)
                            .font(DesignTokens.Typography.bodyMedium)
                        Text(verbatim: GrokHome.resolve(homePath)?.path ?? homePath ?? "")
                            .textSelection(.enabled)
                        Text("grok.home_fixed".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if target == nil {
                            Text("grok.ambiguous".localized)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                HStack(spacing: DesignTokens.Spacing.medium) {
                    Circle()
                        .fill(connected ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)
                    Text(connected ? "codex.connected".localized : disconnectedStatus)
                        .font(DesignTokens.Typography.bodyMedium)
                    Spacer()
                    Button("codex.test_connection".localized) {
                        testConnection()
                    }
                    .disabled(testTask != nil || target == nil)
                }
                .padding(DesignTokens.Spacing.medium)
                .background(DesignTokens.Colors.cardBackground)
                .cornerRadius(DesignTokens.Radius.card)

                if let target {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(cliPresent ? "grok.login_needed".localized : "grok.cli_missing".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: Self.loginCommand(for: target.home))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let message, target != nil {
                    Text(message)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(connected ? .green : .red)
                }

                if setupProfileID != nil {
                    HStack {
                        Button("common.back".localized) { onBack?() }
                            .buttonStyle(.plain)
                        Spacer()
                        Button("common.done".localized) {
                            guard let verified, verified == self.target else { return }
                            onDone?(editingHome ? verified.home.path : homePath)
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(!connected)
                    }
                }
            }
            .padding()
        }
        .onChange(of: target) { _ in invalidateTest() }
        .onDisappear { invalidateTest() }
    }

    private static func loginCommand(for home: URL) -> String {
        let quotedPath = home.path.replacingOccurrences(of: "'", with: "'\\''")
        return "GROK_HOME='\(quotedPath)' grok login"
    }

    private func invalidateTest() {
        testTask?.cancel()
        testTask = nil
        message = nil
        verified = nil
    }

    private func testConnection() {
        guard let profile = profileManager.activeProfile, let target else { return }
        invalidateTest()
        testTask = Task { @MainActor in
            defer { if !Task.isCancelled { testTask = nil } }
            do {
                let usage: ClaudeUsage
                if let setupProfileID {
                    usage = try await GrokUsageProvider.shared.fetchSetupUsage(for: setupProfileID, homePath: target.home.path)
                } else {
                    usage = try await GrokUsageProvider.shared.fetchUsage(for: profile)
                }
                guard !Task.isCancelled, target == self.target else { return }
                let remaining = Int((100 - usage.weeklyPercentage).rounded())
                verified = target
                message = String(format: "grok.test_success".localized, usage.planType ?? "SuperGrok", remaining)
            } catch {
                guard !Task.isCancelled, target == self.target else { return }
                message = error.localizedDescription
            }
        }
    }
}

struct GrokHomeField: View {
    @Binding var path: String
    let available: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("grok.home_label".localized)
                .font(.callout)
            TextField(GrokHome.resolve(nil)?.path ?? "", text: $path)
                .accessibilityLabel("grok.home_label".localized)
                .textFieldStyle(.roundedBorder)
            Text("grok.home_hint".localized)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !available {
                Text(GrokHome.resolve(path) == nil ? "grok.home_invalid".localized : "grok.home_taken".localized)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}
