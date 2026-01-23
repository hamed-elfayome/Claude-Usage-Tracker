import SwiftUI
import AppKit

// MARK: - Simplified Setup Wizard

enum SetupMode {
    case loading
    case cliDetected
    case manualSetup
}

struct SetupWizardState {
    var sessionKey: String = ""
    var validationState: ValidationState = .idle
    var testedOrganizations: [ClaudeAPIService.AccountInfo] = []
    var selectedOrgId: String? = nil
    var showInstructions: Bool = false
}

/// Simplified setup wizard - auto-detects CLI credentials
struct SetupWizardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var setupMode: SetupMode = .loading
    @State private var wizardState = SetupWizardState()
    @State private var isStarting = false
    @State private var errorMessage: String?
    private let apiService = ClaudeAPIService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image("WizardLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                Text("Welcome to Claude Usage Tracker")
                    .font(.system(size: 24, weight: .semibold))

                Text("Track your Claude API usage from the menu bar")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 30)

            Divider()

            // Content based on setup mode
            switch setupMode {
            case .loading:
                loadingView
            case .cliDetected:
                cliDetectedView
            case .manualSetup:
                manualSetupView
            }
        }
        .frame(width: 480, height: setupMode == .manualSetup ? 520 : 420)
        .onAppear {
            checkForCLICredentials()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Checking for Claude Code CLI...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - CLI Detected View (Simple One-Click)

    private var cliDetectedView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Claude Code CLI Detected!")
                    .font(.system(size: 18, weight: .semibold))

                Text("Your CLI credentials will be used automatically.\nNo additional setup required.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            // Single action button
            Button(action: startWithCLI) {
                if isStarting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 200, height: 20)
                } else {
                    Text("Start Tracking")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 200)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isStarting)

            // Option to use manual setup instead
            Button("Set up manually instead") {
                setupMode = .manualSetup
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundColor(.secondary)

            Spacer()
        }
        .padding(30)
    }

    // MARK: - Manual Setup View

    private var manualSetupView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Enter your Claude.ai session key")
                        .font(.system(size: 14, weight: .medium))

                    // Instructions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To get your session key:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        ForEach(["Go to claude.ai and log in",
                                 "Open Developer Tools (Cmd+Option+I)",
                                 "Go to Application → Cookies → claude.ai",
                                 "Copy the 'sessionKey' value"], id: \.self) { step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(step)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    // Open Claude.ai button
                    Button(action: {
                        if let url = URL(string: "https://claude.ai") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open claude.ai")
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)

                    // Session key input
                    TextField("sk-ant-sid-...", text: $wizardState.sessionKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        )

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }

                    // Success message
                    if case .success(let message) = wizardState.validationState {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(message)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: testAndSaveSessionKey) {
                    if case .validating = wizardState.validationState {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 80)
                    } else {
                        Text("Connect")
                            .frame(width: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(wizardState.sessionKey.isEmpty || wizardState.validationState == .validating)
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func checkForCLICredentials() {
        Task {
            do {
                LoggingService.shared.log("SetupWizard: Checking for CLI credentials...")

                let credentials = try ClaudeCodeSyncService.shared.readSystemCredentials()

                if let creds = credentials {
                    LoggingService.shared.log("SetupWizard: Found CLI credentials, checking expiry...")
                    let isExpired = ClaudeCodeSyncService.shared.isTokenExpired(creds)
                    LoggingService.shared.log("SetupWizard: Token expired = \(isExpired)")

                    if !isExpired {
                        LoggingService.shared.log("SetupWizard: Valid CLI credentials found!")
                        await MainActor.run {
                            setupMode = .cliDetected
                        }
                    } else {
                        LoggingService.shared.log("SetupWizard: CLI credentials expired, showing manual setup")
                        await MainActor.run {
                            setupMode = .manualSetup
                        }
                    }
                } else {
                    LoggingService.shared.log("SetupWizard: No CLI credentials found (nil)")
                    await MainActor.run {
                        setupMode = .manualSetup
                    }
                }
            } catch {
                LoggingService.shared.logError("SetupWizard: Failed to check CLI credentials", error: error)
                await MainActor.run {
                    setupMode = .manualSetup
                }
            }
        }
    }

    private func startWithCLI() {
        isStarting = true
        errorMessage = nil

        Task {
            do {
                // Mark setup as completed
                SharedDataStore.shared.saveHasCompletedSetup(true)
                SharedDataStore.shared.markWizardShown()

                await MainActor.run {
                    isStarting = false
                    dismiss()
                }
            }
        }
    }

    private func testAndSaveSessionKey() {
        errorMessage = nil
        wizardState.validationState = .validating

        Task {
            do {
                // Test the session key
                let organizations = try await apiService.testSessionKey(wizardState.sessionKey)

                guard let firstOrg = organizations.first else {
                    throw NSError(domain: "Setup", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No organizations found"
                    ])
                }

                // Save to profile
                guard let profileId = ProfileManager.shared.activeProfile?.id else {
                    throw NSError(domain: "Setup", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "No active profile"
                    ])
                }

                var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
                creds.claudeSessionKey = wizardState.sessionKey
                creds.organizationId = firstOrg.uuid
                try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

                // Update profile model
                if var profile = ProfileManager.shared.activeProfile {
                    profile.claudeSessionKey = wizardState.sessionKey
                    profile.organizationId = firstOrg.uuid
                    ProfileManager.shared.updateProfile(profile)
                }

                // Mark setup complete
                SharedDataStore.shared.saveHasCompletedSetup(true)
                SharedDataStore.shared.markWizardShown()

                await MainActor.run {
                    wizardState.validationState = .success("Connected!")
                    NotificationCenter.default.post(name: .credentialsChanged, object: nil)

                    // Dismiss after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }

            } catch {
                await MainActor.run {
                    wizardState.validationState = .error(error.localizedDescription)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    SetupWizardView()
}
