//
//  PersonalUsageView.swift
//  Claude Usage - Claude.ai Personal Usage Tracking
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

// MARK: - Wizard State Machine

enum WizardStep: Int, Comparable {
    case enterKey = 1
    case selectOrg = 2
    case confirm = 3

    static func < (lhs: WizardStep, rhs: WizardStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WizardState {
    var currentStep: WizardStep = .enterKey
    var sessionKey: String = ""
    var validationState: ValidationState = .idle
    var testedOrganizations: [ClaudeAPIService.AccountInfo] = []
    var selectedOrgId: String? = nil
    var originalSessionKey: String? = nil
    var originalOrgId: String? = nil
}

/// Claude.ai personal usage tracking (free tier)
struct PersonalUsageView: View {
    @State private var wizardState = WizardState()
    private let apiService = ClaudeAPIService()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Wizard header with step indicator
            WizardHeader(currentStep: wizardState.currentStep)

            Divider()

            // Step content based on wizard state
            Group {
                switch wizardState.currentStep {
                case .enterKey:
                    EnterKeyStep(wizardState: $wizardState, apiService: apiService)
                case .selectOrg:
                    SelectOrgStep(wizardState: $wizardState)
                case .confirm:
                    ConfirmStep(wizardState: $wizardState, apiService: apiService)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: wizardState.currentStep)

            Spacer()
        }
        .contentPadding()
        .onAppear {
            loadExistingConfiguration()
        }
    }

    private func loadExistingConfiguration() {
        // Load existing org for comparison
        wizardState.originalOrgId = DataStore.shared.loadOrganizationId()

        // Load existing key for comparison (don't display it)
        wizardState.originalSessionKey = try? KeychainService.shared.load(for: .claudeSessionKey)
    }
}

// MARK: - Step 1: Enter Key

struct EnterKeyStep: View {
    @Binding var wizardState: WizardState
    let apiService: ClaudeAPIService

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            StepIndicator(stepNumber: 1, title: "Enter Session Key")

            SettingsInputField.secureMonospaced(
                label: "personal.label_session_key".localized,
                placeholder: "sk-ant-sid01-...",
                helpText: "personal.help_session_key".localized,
                text: $wizardState.sessionKey
            )

            // Validation Status
            if case .success(let message) = wizardState.validationState {
                SettingsStatusBox(message: message, type: .success)
            } else if case .error(let message) = wizardState.validationState {
                SettingsStatusBox(message: message, type: .error)
            }

            // Action Buttons
            HStack(spacing: Spacing.buttonRowSpacing) {
                SettingsButton(title: "personal.button_open_claude".localized, icon: "safari") {
                    if let url = URL(string: "https://claude.ai") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Spacer()

                SettingsButton.primary(
                    title: wizardState.validationState == .validating ? "Testing..." : "Test Connection"
                ) {
                    testConnection()
                }
                .disabled(wizardState.sessionKey.isEmpty || wizardState.validationState == .validating)
            }
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

struct SelectOrgStep: View {
    @Binding var wizardState: WizardState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            StepIndicator(stepNumber: 2, title: "Select Organization")

            Text("Which organization do you want to track?")
                .font(Typography.body)

            Text("Select the Claude organization for usage monitoring")
                .font(Typography.caption)
                .foregroundColor(.secondary)

            // Organization list with radio buttons
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(wizardState.testedOrganizations, id: \.uuid) { org in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: wizardState.selectedOrgId == org.uuid ? "circle.fill" : "circle")
                            .foregroundColor(wizardState.selectedOrgId == org.uuid ? .accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(org.name)
                                .font(Typography.body)
                            Text(org.uuid)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(Spacing.sm)
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

            // Navigation Buttons
            HStack(spacing: Spacing.buttonRowSpacing) {
                SettingsButton(title: "Back") {
                    withAnimation {
                        wizardState.currentStep = .enterKey
                    }
                }

                Spacer()

                SettingsButton.primary(title: "Next") {
                    withAnimation {
                        wizardState.currentStep = .confirm
                    }
                }
                .disabled(wizardState.selectedOrgId == nil)
            }
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

struct ConfirmStep: View {
    @Binding var wizardState: WizardState
    let apiService: ClaudeAPIService
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            StepIndicator(stepNumber: 3, title: "Confirm & Save")

            // Summary Card
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Configuration Summary")
                    .font(Typography.sectionHeader)

                // Session Key (masked)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Key")
                        .font(Typography.label)
                        .foregroundColor(.secondary)
                    Text(maskSessionKey(wizardState.sessionKey))
                        .font(Typography.monospacedInput)
                }

                Divider()

                // Selected Organization
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization")
                        .font(Typography.label)
                        .foregroundColor(.secondary)
                    if let selectedOrg = wizardState.testedOrganizations.first(where: { $0.uuid == wizardState.selectedOrgId }) {
                        Text(selectedOrg.name)
                            .font(Typography.body)
                        Text("ID: \(selectedOrg.uuid)")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Change detection
                if keyHasChanged() {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Session key will be updated")
                            .font(Typography.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(Spacing.sm)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(Spacing.md)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Action Buttons
            HStack(spacing: Spacing.buttonRowSpacing) {
                SettingsButton(title: "Back") {
                    withAnimation {
                        wizardState.currentStep = .selectOrg
                    }
                }
                .disabled(isSaving)

                Spacer()

                SettingsButton.primary(
                    title: isSaving ? "Saving..." : "Save Configuration",
                    icon: "checkmark.circle"
                ) {
                    saveConfiguration()
                }
                .disabled(isSaving)
            }
        }
    }

    private func keyHasChanged() -> Bool {
        guard let originalKey = wizardState.originalSessionKey else { return true }
        return originalKey != wizardState.sessionKey
    }

    private func saveConfiguration() {
        isSaving = true

        Task {
            do {
                // Save session key with smart org preservation
                try apiService.saveSessionKey(
                    wizardState.sessionKey,
                    preserveOrgIfUnchanged: true
                )

                // Save selected organization
                if let selectedOrgId = wizardState.selectedOrgId {
                    DataStore.shared.saveOrganizationId(selectedOrgId)
                }

                await MainActor.run {
                    // Determine which notification to send
                    if keyHasChanged() {
                        // Key changed - full refresh
                        NotificationCenter.default.post(name: .sessionKeyUpdated, object: nil)
                    } else if wizardState.selectedOrgId != wizardState.originalOrgId {
                        // Only org changed - targeted refresh
                        NotificationCenter.default.post(name: .organizationChanged, object: nil)
                    }

                    // Reset wizard to start
                    withAnimation {
                        wizardState = WizardState()
                    }
                    isSaving = false
                }

            } catch {
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .error)

                await MainActor.run {
                    wizardState.validationState = .error("\(appError.message)\n\nError Code: \(appError.code.rawValue)")
                    isSaving = false
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

struct WizardHeader: View {
    let currentStep: WizardStep

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SettingsHeader(
                title: "personal.title".localized,
                subtitle: "personal.subtitle".localized
            )

            // Step progress indicator
            HStack(spacing: 8) {
                StepCircle(number: 1, isCurrent: currentStep == .enterKey, isCompleted: currentStep > .enterKey)
                StepLine(isCompleted: currentStep > .enterKey)
                StepCircle(number: 2, isCurrent: currentStep == .selectOrg, isCompleted: currentStep > .selectOrg)
                StepLine(isCompleted: currentStep > .selectOrg)
                StepCircle(number: 3, isCurrent: currentStep == .confirm, isCompleted: false)
                Spacer()
            }
        }
    }
}

struct StepIndicator: View {
    let stepNumber: Int
    let title: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("\(stepNumber)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            Text(title)
                .font(.system(size: 18, weight: .semibold))
        }
        .padding(.bottom, Spacing.sm)
    }
}

struct StepCircle: View {
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

struct StepLine: View {
    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 40, height: 2)
    }
}

// MARK: - Previews

#Preview {
    PersonalUsageView()
        .frame(width: 520, height: 600)
}
