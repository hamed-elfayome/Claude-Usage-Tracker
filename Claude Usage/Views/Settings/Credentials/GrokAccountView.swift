import SwiftUI

/// Shows how to sign the Grok CLI in and checks the weekly quota. The app
/// does not read or store the CLI token.
struct GrokAccountView: View {
    var showsDone: Bool = false
    var onDone: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil

    @State private var isTesting = false
    @State private var message: String?
    @State private var succeeded = false

    private var cliPresent: Bool { GrokCLIClient.locateExecutable() != nil }
    private var signedIn: Bool { cliPresent && GrokCLIClient.authFileExists() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                SettingsPageHeader(
                    title: "grok.title".localized,
                    subtitle: "grok.subtitle".localized
                )

                HStack(spacing: DesignTokens.Spacing.medium) {
                    Circle()
                        .fill(signedIn ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)
                    Text(signedIn ? "codex.connected".localized : "codex.not_connected".localized)
                        .font(DesignTokens.Typography.bodyMedium)
                    Spacer()
                    Button("codex.test_connection".localized) {
                        testConnection()
                    }
                    .disabled(isTesting || !signedIn)
                }
                .padding(DesignTokens.Spacing.medium)
                .background(DesignTokens.Colors.cardBackground)
                .cornerRadius(DesignTokens.Radius.card)

                Text(cliPresent ? "grok.login_needed".localized : "grok.cli_missing".localized)
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(succeeded ? .green : .red)
                }

                if showsDone {
                    HStack {
                        Button("common.back".localized) { onBack?() }
                            .buttonStyle(.plain)
                        Spacer()
                        Button("common.done".localized) { onDone?() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!succeeded)
                    }
                }
            }
            .padding()
        }
    }

    private func testConnection() {
        isTesting = true
        message = nil
        succeeded = false
        Task {
            let profile = await MainActor.run { ProfileManager.shared.activeProfile }
            guard let profile else {
                await MainActor.run {
                    message = "grok.unavailable".localized
                    isTesting = false
                }
                return
            }
            do {
                let usage = try await GrokUsageProvider.shared.fetchUsage(for: profile)
                let remaining = Int((100 - usage.weeklyPercentage).rounded())
                await MainActor.run {
                    succeeded = true
                    message = String(format: "grok.test_success".localized, usage.planType ?? "SuperGrok", remaining)
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }
}
