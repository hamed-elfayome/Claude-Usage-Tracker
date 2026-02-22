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
    @StateObject private var profileManager = ProfileManager.shared
    @State private var wizardState = WizardState()
    @State private var currentCredentials: ProfileCredentials?
    @State private var hasCLICredentials = false
    private let apiService = ClaudeAPIService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "personal.title".localized,
                    subtitle: "personal.subtitle".localized
                )

                // Professional Status Card
                HStack(spacing: DesignTokens.Spacing.medium) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                        Text(isConnected ? "general.connected".localized : "general.not_connected".localized)
                            .font(DesignTokens.Typography.bodyMedium)

                        if let creds = currentCredentials, creds.hasClaudeAI {
                            Text(maskKey(creds.claudeSessionKey ?? ""))
                                .font(DesignTokens.Typography.captionMono)
                                .foregroundColor(.secondary)
                        } else if hasCLICredentials {
                            Text("Using Claude Code CLI credentials")
                                .font(DesignTokens.Typography.captionMono)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Remove button integrated into status card
                    if currentCredentials?.hasClaudeAI == true {
                        Button(action: removeCredentials) {
                            HStack(spacing: DesignTokens.Spacing.extraSmall) {
                                Image(systemName: "trash")
                                    .font(.system(size: DesignTokens.Icons.small))
                                Text("common.remove".localized)
                                    .font(DesignTokens.Typography.body)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .foregroundColor(.red)
                    }
                }
                .padding(DesignTokens.Spacing.medium)
                .background(DesignTokens.Colors.cardBackground)
                .cornerRadius(DesignTokens.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                        .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
                )

                // Configuration Card Container
                VStack(alignment: .leading, spacing: 0) {
                    // Step Indicator Header
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        Text("personal.configuration_title".localized)
                            .font(DesignTokens.Typography.sectionTitle)
                            .foregroundColor(.secondary)

                        HStack(spacing: DesignTokens.Spacing.small) {
                            ForEach(1...3, id: \.self) { step in
                                let stepEnum = WizardStep(rawValue: step)!
                                let isCurrent = wizardState.currentStep == stepEnum
                                let isCompleted = wizardState.currentStep > stepEnum

                                HStack(spacing: DesignTokens.Spacing.extraSmall) {
                                    ZStack {
                                        Circle()
                                            .fill(isCompleted ? Color.green : (isCurrent ? Color.accentColor : Color.secondary.opacity(0.2)))
                                            .frame(width: 20, height: 20)

                                        if isCompleted {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("\(step)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(isCurrent ? .white : .secondary)
                                        }
                                    }

                                    if isCurrent {
                                        Text(stepTitle(for: step))
                                            .font(DesignTokens.Typography.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                    }
                                }

                                if step < 3 {
                                    Rectangle()
                                        .fill(isCompleted ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.cardPadding)
                    .padding(.bottom, DesignTokens.Spacing.extraSmall)

                    Divider()

                    // Step Content
                    Group {
                        switch wizardState.currentStep {
                        case .enterKey:
                            EnterKeyStep(wizardState: $wizardState, apiService: apiService)
                        case .selectOrg:
                            SelectOrgStep(wizardState: $wizardState)
                        case .confirm:
                            ConfirmStep(
                                wizardState: $wizardState,
                                apiService: apiService,
                                onSave: { loadCurrentCredentials() }
                            )
                        }
                    }
                    .padding(DesignTokens.Spacing.cardPadding)
                    .animation(.easeInOut(duration: 0.25), value: wizardState.currentStep)
                }
                .background(DesignTokens.Colors.cardBackground)
                .cornerRadius(DesignTokens.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                        .strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 1)
                )

                Spacer()
            }
            .padding()
        }
        .onAppear {
            loadExistingConfiguration()
            loadCurrentCredentials()
            checkCLICredentials()
        }
        .onChange(of: profileManager.activeProfile?.id) { _, _ in
            // Reload when profile changes
            loadExistingConfiguration()
            loadCurrentCredentials()

            // Reset wizard state
            wizardState = WizardState()
        }
    }

    private func stepTitle(for step: Int) -> String {
        switch step {
        case 1: return "setup.step.enter_session_key".localized
        case 2: return "wizard.select_organization".localized
        case 3: return "wizard.review_config".localized
        default: return ""
        }
    }

    private func loadExistingConfiguration() {
        guard let profile = profileManager.activeProfile else { return }

        // Load existing credentials for comparison
        if let creds = try? ProfileStore.shared.loadProfileCredentials(profile.id) {
            wizardState.originalOrgId = creds.organizationId
            wizardState.originalSessionKey = creds.claudeSessionKey
        }
    }

    private func loadCurrentCredentials() {
        guard let profile = profileManager.activeProfile else { return }
        currentCredentials = try? ProfileStore.shared.loadProfileCredentials(profile.id)
    }

    private func checkCLICredentials() {
        Task {
            do {
                if let creds = try ClaudeCodeSyncService.shared.readSystemCredentials(),
                   !ClaudeCodeSyncService.shared.isTokenExpired(creds) {
                    await MainActor.run {
                        hasCLICredentials = true
                    }
                }
            } catch {
                // Ignore - no CLI credentials
            }
        }
    }

    /// Returns true if connected via session key OR CLI credentials
    private var isConnected: Bool {
        currentCredentials?.hasClaudeAI == true || hasCLICredentials
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 20 else { return "•••••••••" }
        let prefix = String(key.prefix(12))
        let suffix = String(key.suffix(4))
        return "\(prefix)•••••\(suffix)"
    }

    private func removeCredentials() {
        guard let profileId = profileManager.activeProfile?.id else {
            LoggingService.shared.logError("PersonalUsageView: No active profile for removal")
            return
        }

        LoggingService.shared.log("PersonalUsageView: Starting credential removal for profile \(profileId)")

        do {
            // Use ProfileManager's shared removal method
            try profileManager.removeClaudeAICredentials(for: profileId)

            // Update statusline scripts if installed
            try? StatuslineService.shared.updateScriptsIfInstalled()

            // Reload UI to update the view
            loadCurrentCredentials()

            // Reset wizard
            wizardState = WizardState()

            LoggingService.shared.log("PersonalUsageView: Successfully removed Claude.ai credentials")

        } catch {
            let appError = AppError.wrap(error)
            ErrorLogger.shared.log(appError, severity: .error)
            ErrorPresenter.shared.showAlert(for: appError)
            LoggingService.shared.logError("PersonalUsageView: Failed to remove credentials - \(appError.message)")
        }
    }
}

// MARK: - Step 1: Enter Key

struct EnterKeyStep: View {
    @Binding var wizardState: WizardState
    let apiService: ClaudeAPIService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Professional input field
            VStack(alignment: .leading, spacing: 8) {
                Text("personal.label_session_key".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("sk-ant-sid01-...", text: $wizardState.sessionKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Text("personal.help_session_key".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Balanced validation status
            if case .success(let message) = wizardState.validationState {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
            } else if case .error(let message) = wizardState.validationState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }

            // Balanced buttons
            HStack(spacing: 10) {
                Button(action: {
                    if let url = URL(string: "https://claude.ai") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                        Text("personal.button_open_claude".localized)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if wizardState.validationState == .validating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                        }
                        Text(wizardState.validationState == .validating ? "wizard.testing".localized : "wizard.test_connection".localized)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("wizard.select_organization".localized)
                    .font(.system(size: 13, weight: .medium))
                Text("wizard.choose_organization".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Balanced organization list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(wizardState.testedOrganizations, id: \.uuid) { org in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            wizardState.selectedOrgId = org.uuid
                        }
                    }) {
                        HStack(spacing: 10) {
                            // Radio button
                            ZStack {
                                Circle()
                                    .strokeBorder(
                                        wizardState.selectedOrgId == org.uuid
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.3),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 16, height: 16)

                                if wizardState.selectedOrgId == org.uuid {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(org.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(org.uuid)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if wizardState.selectedOrgId == org.uuid {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(10)
                        .background(
                            wizardState.selectedOrgId == org.uuid
                                ? Color.accentColor.opacity(0.06)
                                : Color(nsColor: .controlBackgroundColor).opacity(0.3)
                        )
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    wizardState.selectedOrgId == org.uuid
                                        ? Color.accentColor.opacity(0.3)
                                        : Color.secondary.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Navigation buttons
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation {
                        wizardState.currentStep = .enterKey
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text("common.back".localized)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button(action: {
                    withAnimation {
                        wizardState.currentStep = .confirm
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("common.next".localized)
                            .font(.system(size: 12))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(wizardState.selectedOrgId == nil)
            }
        }
        .onAppear {
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
    let onSave: () -> Void
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("wizard.review_config".localized)
                    .font(.system(size: 13, weight: .medium))
                Text("wizard.confirm_settings".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Balanced summary card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("wizard.session_key".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(maskSessionKey(wizardState.sessionKey))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }

                if let selectedOrg = wizardState.testedOrganizations.first(where: { $0.uuid == wizardState.selectedOrgId }) {
                    Divider()

                    HStack(spacing: 10) {
                        Image(systemName: "building.2")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("wizard.organization".localized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(selectedOrg.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Text(selectedOrg.uuid)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if keyHasChanged() {
                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("wizard.key_will_update".localized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )

            // Navigation buttons
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation {
                        wizardState.currentStep = .selectOrg
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11))
                        Text("common.back".localized)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSaving)

                Spacer()

                Button(action: saveConfiguration) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                        }
                        Text(isSaving ? "wizard.saving".localized : "wizard.save_configuration".localized)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isSaving)
            }
        }
    }

    private func keyHasChanged() -> Bool {
        guard let originalKey = wizardState.originalSessionKey else { return true }
        return originalKey != wizardState.sessionKey
    }

    private func saveConfiguration() {
        guard let profileId = ProfileManager.shared.activeProfile?.id else { return }

        isSaving = true

        Task {
            do {
                // Save to profile-specific Keychain
                var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
                creds.claudeSessionKey = wizardState.sessionKey
                creds.organizationId = wizardState.selectedOrgId
                try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

                // Also update the Profile model with the new credentials
                if var profile = ProfileManager.shared.activeProfile {
                    profile.claudeSessionKey = wizardState.sessionKey
                    profile.organizationId = wizardState.selectedOrgId
                    ProfileManager.shared.updateProfile(profile)
                    LoggingService.shared.log("PersonalUsageView: Updated profile model with new credentials")
                }

                // Update statusline scripts if key or org changed (only if already installed)
                let keyChanged = keyHasChanged()
                let orgChanged = wizardState.selectedOrgId != wizardState.originalOrgId
                if keyChanged || orgChanged {
                    try? StatuslineService.shared.updateScriptsIfInstalled()
                }

                await MainActor.run {
                    // Reset circuit breaker on successful credential save
                    ErrorRecovery.shared.recordSuccess(for: .api)

                    // Post single notification for credential change
                    if keyChanged || orgChanged {
                        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
                    }

                    // Reload credentials display
                    onSave()

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

// MARK: - Visual Components (kept minimal)

// MARK: - Previews

#Preview {
    PersonalUsageView()
        .frame(width: 520, height: 600)
}
