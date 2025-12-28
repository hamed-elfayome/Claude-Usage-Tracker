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
                    Text("setup.welcome.title".localized)
                        .font(.system(size: 24, weight: .semibold))

                    Text("setup.welcome.subtitle".localized)
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
                            Text("setup.step_number_1".localized)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor))

                            Text("setup.step.get_session_key".localized)
                                .font(.system(size: 16, weight: .semibold))
                        }

                        Text("setup.step.get_session_key.description".localized)
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
                                    Text("setup.open_claude_ai".localized)
                                }
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(action: { showInstructions.toggle() }) {
                                HStack {
                                    Image(systemName: showInstructions ? "chevron.up" : "chevron.down")
                                    Text(showInstructions ? "setup.hide_instructions".localized : "setup.show_instructions".localized)
                                }
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        if showInstructions {
                            VStack(alignment: .leading, spacing: 8) {
                                InstructionRow(text: "setup.instruction.step1".localized)
                                InstructionRow(text: "setup.instruction.step2".localized)
                                InstructionRow(text: "setup.instruction.step3".localized)
                                InstructionRow(text: "setup.instruction.step4".localized)
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
                            Text("setup.step_number_2".localized)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor))

                            Text("setup.step.enter_session_key".localized)
                                .font(.system(size: 16, weight: .semibold))
                        }

                        TextField("personal.placeholder_session_key".localized, text: $sessionKey)
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

                        Text("setup.paste_session_key".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Validation Feedback
                    if case .success = validationState {
                        WizardStatusBox(message: "setup.validation.success".localized, type: .success)
                    } else if case .error(let message) = validationState {
                        WizardStatusBox(message: message, type: .error)
                    }

                    // Auto-start session option (always visible)
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 6) {
                            Text("setup.auto_start_session".localized)
                                .font(.system(size: 13, weight: .semibold))

                            // BETA badge
                            Text("session.beta_badge".localized)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.orange)
                                )
                        }

                        Text("setup.auto_start_session.description".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(isOn: $autoStartSessionEnabled) {
                            Text("setup.enable_auto_start".localized)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(.top, 8)

                    // Icon Appearance
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .padding(.vertical, 4)

                        Text("setup.menubar_appearance".localized)
                            .font(.system(size: 13, weight: .semibold))

                        Text("setup.choose_icon_style".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        IconStylePicker(selectedStyle: $iconStyle)

                        Toggle("setup.monochrome_adaptive".localized, isOn: $monochromeMode)
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
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if case .success = validationState {
                        Button("common.done".localized) {
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
                                Text("common.validate".localized)
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
        // Step 1: Comprehensive validation using professional validator
        let validator = SessionKeyValidator()
        let validationResult = validator.validationStatus(sessionKey)

        guard validationResult.isValid else {
            // Show detailed error message from validator
            validationState = .error(validationResult.errorMessage ?? "Invalid session key")
            return
        }

        // Step 2: Start validation process
        validationState = .validating

        Task {
            do {
                // Save with professional validation (will validate again internally)
                try apiService.saveSessionKey(sessionKey)

                // Test the connection
                _ = try await apiService.fetchOrganizationId()

                await MainActor.run {
                    validationState = .success("setup.validation.success".localized)
                }

            } catch {
                // Convert to AppError and log
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .error)

                await MainActor.run {
                    // Show user-friendly error message with error code
                    let errorMessage = "\(appError.message)\n\nError Code: \(appError.code.rawValue)"
                    validationState = .error(errorMessage)
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
