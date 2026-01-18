import SwiftUI
import AppKit

// MARK: - Wizard State Machine

enum SetupWizardStep: Int, Comparable {
    case enterKey = 1
    case selectOrg = 2
    case confirm = 3

    static func < (lhs: SetupWizardStep, rhs: SetupWizardStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct SetupWizardState {
    var currentStep: SetupWizardStep = .enterKey
    var sessionKey: String = ""
    var validationState: ValidationState = .idle
    var testedOrganizations: [ClaudeAPIService.AccountInfo] = []
    var selectedOrgId: String? = nil
    var autoStartSessionEnabled: Bool = false
    var showInstructions: Bool = false
}

/// Professional, native macOS setup wizard with 3-step flow
struct SetupWizardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var wizardState = SetupWizardState()
    @State private var hasClaudeCodeCredentials = false
    @State private var isMigrating = false
    @State private var migrationMessage: String?
    private let apiService = ClaudeAPIService()

    var body: some View {
        VStack(spacing: 0) {
            // Header with logo and progress indicator
            VStack(spacing: 16) {
                // Logo and title
                HStack(spacing: 2) {
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
                .padding(.top, 32)

                // Step progress indicator
                HStack(spacing: 8) {
                    SetupStepCircle(number: 1, isCurrent: wizardState.currentStep == .enterKey, isCompleted: wizardState.currentStep > .enterKey)
                    SetupStepLine(isCompleted: wizardState.currentStep > .enterKey)
                    SetupStepCircle(number: 2, isCurrent: wizardState.currentStep == .selectOrg, isCompleted: wizardState.currentStep > .selectOrg)
                    SetupStepLine(isCompleted: wizardState.currentStep > .selectOrg)
                    SetupStepCircle(number: 3, isCurrent: wizardState.currentStep == .confirm, isCompleted: false)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }

            Divider()

            // Claude Code info section - compact (only show if credentials exist)
            if hasClaudeCodeCredentials {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("wizard.claude_code_info_title".localized)
                            .font(.system(size: 12, weight: .medium))
                        Text("wizard.claude_code_info_description".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button(action: {
                        dismiss()
                    }) {
                        Text("wizard.claude_code_skip_setup".localized)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.purple.opacity(0.08))

                Divider()
            }

            // Migration section - compact (only show if migration not completed yet)
            if MigrationService.shared.shouldShowMigrationOption() {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("wizard.migrate_old_data".localized)
                            .font(.system(size: 12, weight: .medium))

                        if let message = migrationMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .lineLimit(1)
                        } else {
                            Text("wizard.migrate_description_short".localized)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: migrateOldData) {
                            HStack {
                                if isMigrating {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Text("wizard.migrate_button".localized)
                                        .font(.system(size: 11))
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isMigrating)

                        Button(action: skipMigration) {
                            Text("wizard.skip_migration".localized)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .disabled(isMigrating)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.08))

                Divider()
            }

            // Step content based on wizard state
            Group {
                switch wizardState.currentStep {
                case .enterKey:
                    EnterKeyStepSetup(wizardState: $wizardState, apiService: apiService)
                case .selectOrg:
                    SelectOrgStepSetup(wizardState: $wizardState)
                case .confirm:
                    ConfirmStepSetup(wizardState: $wizardState, apiService: apiService, dismiss: dismiss)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: wizardState.currentStep)
        }
        .frame(width: 580, height: 680)
        .onAppear {
            // Load auto-start preference from active profile
            if let activeProfile = ProfileManager.shared.activeProfile {
                wizardState.autoStartSessionEnabled = activeProfile.autoStartSessionEnabled
            }

            // Check if Claude Code credentials exist
            Task {
                do {
                    let credentials = try ClaudeCodeSyncService.shared.readSystemCredentials()
                    await MainActor.run {
                        hasClaudeCodeCredentials = (credentials != nil)
                    }
                } catch {
                    // If error reading credentials, assume they don't exist
                    await MainActor.run {
                        hasClaudeCodeCredentials = false
                    }
                }
            }
        }
    }

    // MARK: - Migration Functions

    private func migrateOldData() {
        isMigrating = true
        migrationMessage = nil

        Task {
            do {
                let count = try MigrationService.shared.migrateFromAppGroup()
                await MainActor.run {
                    isMigrating = false
                    migrationMessage = String(format: "wizard.migration_success".localized, count)
                    // Reload profiles to reflect migrated data
                    ProfileManager.shared.loadProfiles()
                }

                // Auto-close wizard after successful migration
                // Give user a moment to see the success message
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isMigrating = false
                    migrationMessage = String(format: "wizard.migration_failed".localized, error.localizedDescription)
                }
            }
        }
    }

    private func skipMigration() {
        // Mark migration as completed (declined) so we don't ask again
        UserDefaults.standard.set(true, forKey: "HasMigratedFromAppGroup")
        migrationMessage = "wizard.migration_skipped".localized
    }
}

// MARK: - Step 1: Enter Key

struct EnterKeyStepSetup: View {
    @Environment(\.dismiss) var dismiss
    @Binding var wizardState: SetupWizardState
    let apiService: ClaudeAPIService

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Step header
                    SetupStepHeader(stepNumber: 1, title: "setup.step.get_session_key".localized)

                    Text("setup.step.get_session_key.description".localized)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    // Action buttons
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

                        Button(action: { wizardState.showInstructions.toggle() }) {
                            HStack {
                                Image(systemName: wizardState.showInstructions ? "chevron.up" : "chevron.down")
                                Text(wizardState.showInstructions ? "setup.hide_instructions".localized : "setup.show_instructions".localized)
                            }
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    // Instructions (expandable)
                    if wizardState.showInstructions {
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

                    Divider()

                    // Session key input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("personal.label_session_key".localized)
                            .font(.system(size: 13, weight: .medium))

                        TextField("personal.placeholder_session_key".localized, text: $wizardState.sessionKey)
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

                    // Validation Status
                    if case .success(let message) = wizardState.validationState {
                        WizardStatusBox(message: message, type: .success)
                    } else if case .error(let message) = wizardState.validationState {
                        WizardStatusBox(message: message, type: .error)
                    }
                }
                .padding(32)
            }

            Divider()

            // Footer
            HStack {
                Button("common.cancel".localized) {
                    // Dismiss handled by parent
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: testConnection) {
                    if case .validating = wizardState.validationState {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 100)
                    } else {
                        Text("wizard.test_connection".localized)
                            .frame(width: 100)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(wizardState.sessionKey.isEmpty || wizardState.validationState == .validating)
            }
            .padding(20)
        }
    }

    private func testConnection() {
        let validator = SessionKeyValidator()
        let validationResult = validator.validationStatus(wizardState.sessionKey)

        guard validationResult.isValid else {
            wizardState.validationState = .error(validationResult.errorMessage ?? "Invalid")
            return
        }

        wizardState.validationState = .validating

        Task {
            do {
                // READ-ONLY TEST - does NOT save to Keychain
                let organizations = try await apiService.testSessionKey(wizardState.sessionKey)

                await MainActor.run {
                    wizardState.testedOrganizations = organizations
                    wizardState.validationState = .success("Connection successful! Found \(organizations.count) organization(s)")

                    // Auto-advance to next step
                    withAnimation {
                        wizardState.currentStep = .selectOrg
                    }
                }

            } catch {
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .error)

                await MainActor.run {
                    let errorMessage = "\(appError.message)\n\nError Code: \(appError.code.rawValue)"
                    wizardState.validationState = .error(errorMessage)
                }
            }
        }
    }
}

// MARK: - Step 2: Select Organization

struct SelectOrgStepSetup: View {
    @Binding var wizardState: SetupWizardState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Step header
                    SetupStepHeader(stepNumber: 2, title: "wizard.select_organization".localized)

                    Text("wizard.select_org_title".localized)
                        .font(.system(size: 13))

                    Text("wizard.select_org_subtitle".localized)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    // Organization list with radio buttons
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(wizardState.testedOrganizations, id: \.uuid) { org in
                            HStack(spacing: 12) {
                                Image(systemName: wizardState.selectedOrgId == org.uuid ? "circle.fill" : "circle")
                                    .foregroundColor(wizardState.selectedOrgId == org.uuid ? .accentColor : .secondary)
                                    .font(.system(size: 14))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(org.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(org.uuid)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(wizardState.selectedOrgId == org.uuid ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(wizardState.selectedOrgId == org.uuid ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                wizardState.selectedOrgId = org.uuid
                            }
                        }
                    }
                }
                .padding(32)
            }

            Divider()

            // Footer
            HStack {
                Button("common.back".localized) {
                    withAnimation {
                        wizardState.currentStep = .enterKey
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("common.next".localized) {
                    withAnimation {
                        wizardState.currentStep = .confirm
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(wizardState.selectedOrgId == nil)
            }
            .padding(20)
        }
        .onAppear {
            // Auto-select first org if none selected
            if wizardState.selectedOrgId == nil,
               let firstOrg = wizardState.testedOrganizations.first {
                wizardState.selectedOrgId = firstOrg.uuid
            }
        }
    }
}

// MARK: - Step 3: Confirm & Save

struct ConfirmStepSetup: View {
    @Binding var wizardState: SetupWizardState
    let apiService: ClaudeAPIService
    let dismiss: DismissAction
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Step header
                    SetupStepHeader(stepNumber: 3, title: "wizard.review_config".localized)

                    // Summary Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("wizard.config_summary".localized)
                            .font(.system(size: 14, weight: .semibold))

                        // Session Key (masked)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("wizard.session_key".localized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(maskSessionKey(wizardState.sessionKey))
                                .font(.system(size: 11, design: .monospaced))
                        }

                        Divider()

                        // Selected Organization
                        VStack(alignment: .leading, spacing: 6) {
                            Text("wizard.organization".localized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            if let selectedOrg = wizardState.testedOrganizations.first(where: { $0.uuid == wizardState.selectedOrgId }) {
                                Text(selectedOrg.name)
                                    .font(.system(size: 13))
                                Text(String(format: "wizard.organization_id".localized, selectedOrg.uuid))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(10)

                    // Auto-start session option
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()

                        HStack(spacing: 6) {
                            Text("setup.auto_start_session".localized)
                                .font(.system(size: 13, weight: .semibold))

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

                        Toggle(isOn: $wizardState.autoStartSessionEnabled) {
                            Text("setup.enable_auto_start".localized)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .toggleStyle(.switch)
                    }
                }
                .padding(32)
            }

            Divider()

            // Footer
            HStack {
                Button("common.back".localized) {
                    withAnimation {
                        wizardState.currentStep = .selectOrg
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)

                Spacer()

                Button(action: saveConfiguration) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 100)
                    } else {
                        Text("common.done".localized)
                            .frame(width: 100)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding(20)
        }
    }

    private func saveConfiguration() {
        isSaving = true

        Task {
            do {
                guard let profileId = ProfileManager.shared.activeProfile?.id else {
                    throw NSError(domain: "SetupWizard", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "No active profile found"
                    ])
                }

                // Save to profile-specific Keychain using the refactored pattern
                var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
                creds.claudeSessionKey = wizardState.sessionKey
                creds.organizationId = wizardState.selectedOrgId
                try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

                // Also update the Profile model with the new credentials
                if var profile = ProfileManager.shared.activeProfile {
                    profile.claudeSessionKey = wizardState.sessionKey
                    profile.organizationId = wizardState.selectedOrgId
                    profile.autoStartSessionEnabled = wizardState.autoStartSessionEnabled
                    ProfileManager.shared.updateProfile(profile)
                    LoggingService.shared.log("SetupWizard: Updated profile model with new credentials")
                }

                // Update statusline scripts if installed
                try? StatuslineService.shared.updateScriptsIfInstalled()

                // Mark setup as completed (shared setting)
                SharedDataStore.shared.saveHasCompletedSetup(true)

                await MainActor.run {
                    // Reset circuit breaker on successful credential save
                    ErrorRecovery.shared.recordSuccess(for: .api)

                    // Trigger immediate refresh of usage data
                    NotificationCenter.default.post(name: .credentialsChanged, object: nil)

                    isSaving = false
                    dismiss()
                }

            } catch {
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .error)

                await MainActor.run {
                    let errorMessage = "\(appError.message)\n\nError Code: \(appError.code.rawValue)"
                    wizardState.validationState = .error(errorMessage)
                    isSaving = false

                    // Go back to first step to show error
                    withAnimation {
                        wizardState.currentStep = .enterKey
                    }
                }
            }
        }
    }

    private func maskSessionKey(_ key: String) -> String {
        guard key.count > 20 else { return "•••••••••" }
        let prefix = String(key.prefix(12))
        let suffix = String(key.suffix(4))
        return "\(prefix)•••••\(suffix)"
    }
}

// MARK: - Visual Components

struct SetupStepHeader: View {
    let stepNumber: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(stepNumber)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            Text(title)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

struct SetupStepCircle: View {
    let number: Int
    let isCurrent: Bool
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 24, height: 24)

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(textColor)
            }
        }
    }

    private var backgroundColor: Color {
        if isCompleted { return .green }
        if isCurrent { return .accentColor }
        return Color.gray.opacity(0.3)
    }

    private var textColor: Color {
        isCurrent ? .white : .secondary
    }
}

struct SetupStepLine: View {
    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 40, height: 2)
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
