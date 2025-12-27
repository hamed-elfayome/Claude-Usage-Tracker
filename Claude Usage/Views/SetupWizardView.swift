import SwiftUI
import AppKit

/// Professional, native macOS setup wizard
struct SetupWizardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var sessionKey = ""
    @State private var validationState: ValidationState = .idle
    @State private var showInstructions = false
    @State private var autoStartSessionEnabled = DataStore.shared.loadAutoStartSessionEnabled()
    @State private var iconStyle: MenuBarIconStyle = DataStore.shared.loadMenuBarIconStyle()
    @State private var monochromeMode: Bool = DataStore.shared.loadMonochromeMode()

    private let apiService = ClaudeAPIService()

    enum ValidationState {
        case idle
        case validating
        case success(String)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 2) {
                // App Logo
                Image("WizardLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                VStack(spacing: 8) {
                    Text("Welcome to Claude Usage Tracker")
                        .font(.system(size: 24, weight: .semibold))

                    Text("Configure your API access to start tracking usage")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 48)
            .padding(.bottom, 32)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Step 1: Get Session Key
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("1")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor))

                            Text("Get Your Session Key")
                                .font(.system(size: 16, weight: .semibold))
                        }

                        Text("You'll need to extract your session key from claude.ai")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
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
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: { showInstructions.toggle() }) {
                                HStack {
                                    Image(systemName: showInstructions ? "chevron.up" : "chevron.down")
                                    Text(showInstructions ? "Hide" : "Show Instructions")
                                }
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        if showInstructions {
                            VStack(alignment: .leading, spacing: 8) {
                                InstructionRow(text: "Open Developer Tools (F12 or Cmd+Option+I)")
                                InstructionRow(text: "Go to Application/Storage → Cookies → https://claude.ai")
                                InstructionRow(text: "Find the 'sessionKey' cookie")
                                InstructionRow(text: "Double-click its Value and copy (Cmd+C)")
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }

                    // Step 2: Enter Key
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("2")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor))

                            Text("Enter Your Session Key")
                                .font(.system(size: 16, weight: .semibold))
                        }

                        TextField("sk-ant-sid-...", text: $sessionKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            )

                        Text("Paste the sessionKey value you copied")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Validation Feedback
                    if case .success(let message) = validationState {
                        WizardStatusBox(message: message, type: .success)
                    } else if case .error(let message) = validationState {
                        WizardStatusBox(message: message, type: .error)
                    }

                    // Auto-start session option (always visible)
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 6) {
                            Text("Auto-start session on reset")
                                .font(.system(size: 13, weight: .semibold))

                            // BETA badge
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange)
                                )
                        }

                        Text("Automatically send 'Hi' to Claude 3.5 Haiku when your session resets to 0%. This keeps your session always ready without manual intervention.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(isOn: $autoStartSessionEnabled) {
                            Text("Enable auto-start session")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(.top, 8)

                    // Icon Appearance
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .padding(.vertical, 4)

                        Text("Menu Bar Appearance")
                            .font(.system(size: 13, weight: .semibold))

                        Text("Choose your preferred icon style")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        IconStylePicker(selectedStyle: $iconStyle)

                        Toggle("Monochrome (Adaptive)", isOn: $monochromeMode)
                            .toggleStyle(.switch)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(32)
            }

            Divider()

            // Footer
            VStack(spacing: 8) {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if case .success = validationState {
                        Button("Done") {
                            DataStore.shared.saveHasCompletedSetup(true)
                            DataStore.shared.saveAutoStartSessionEnabled(autoStartSessionEnabled)
                            DataStore.shared.saveMenuBarIconStyle(iconStyle)
                            DataStore.shared.saveMonochromeMode(monochromeMode)
                            NotificationCenter.default.post(name: .menuBarIconStyleChanged, object: nil)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: validateAndSave) {
                            if case .validating = validationState {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 60)
                            } else {
                                Text("Validate")
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sessionKey.isEmpty)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 580, height: 700)
    }

    private func validateAndSave() {
        guard !sessionKey.isEmpty else {
            validationState = .error("Please enter your session key")
            return
        }

        guard sessionKey.hasPrefix("sk-ant-") else {
            validationState = .error("Invalid format. Should start with 'sk-ant-'")
            return
        }

        validationState = .validating

        Task {
            do {
                try apiService.saveSessionKey(sessionKey)
                let orgId = try await apiService.fetchOrganizationId()

                await MainActor.run {
                    validationState = .success("Connected to \(orgId)")
                }
            } catch {
                await MainActor.run {
                    validationState = .error("Connection failed")
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct InstructionRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WizardStatusBox: View {
    let message: String
    let type: StatusType

    enum StatusType {
        case success, error

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12))
        }
        .foregroundColor(type.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(type.color.opacity(0.1))
        )
    }
}

#Preview {
    SetupWizardView()
}
