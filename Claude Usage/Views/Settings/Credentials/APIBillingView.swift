//
//  APIBillingView.swift
//  Claude Usage - API Console Billing Tracking
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

// MARK: - Wizard State Machine

enum APIWizardStep: Int, Comparable {
    case enterKey = 1
    case selectOrg = 2
    case confirm = 3

    static func < (lhs: APIWizardStep, rhs: APIWizardStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct APIWizardState {
    var currentStep: APIWizardStep = .enterKey
    var apiSessionKey: String = ""
    var validationState: ValidationState = .idle
    var testedOrganizations: [APIOrganization] = []
    var selectedOrgId: String? = nil
    var originalApiSessionKey: String? = nil
    var originalOrgId: String? = nil
}

/// API Console billing and credits tracking
struct APIBillingView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var wizardState = APIWizardState()
    @State private var currentCredentials: ProfileCredentials?

    private let apiService = ClaudeAPIService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "api.title".localized,
                    subtitle: "api.subtitle".localized
                )

                // Professional Status Card
                HStack(spacing: DesignTokens.Spacing.medium) {
                    Circle()
                        .fill(currentCredentials?.apiSessionKey != nil ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: DesignTokens.StatusDot.standard, height: DesignTokens.StatusDot.standard)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                        Text(currentCredentials?.apiSessionKey != nil ? "general.connected".localized : "general.not_connected".localized)
                            .font(DesignTokens.Typography.bodyMedium)

                        if let creds = currentCredentials, let apiKey = creds.apiSessionKey {
                            Text(maskKey(apiKey))
                                .font(DesignTokens.Typography.captionMono)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Remove button integrated into status card
                    if currentCredentials?.apiSessionKey != nil {
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

                // Configuration Card Container with 3 Steps
                VStack(alignment: .leading, spacing: 0) {
                        // Step Indicator Header
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                            Text("personal.configuration_title".localized)
                                .font(DesignTokens.Typography.sectionTitle)
                                .foregroundColor(.secondary)

                            HStack(spacing: DesignTokens.Spacing.small) {
                                ForEach(1...3, id: \.self) { step in
                                    let stepEnum = APIWizardStep(rawValue: step)!
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
                                APIEnterKeyStep(wizardState: $wizardState, apiService: apiService)
                            case .selectOrg:
                                APISelectOrgStep(wizardState: $wizardState)
                            case .confirm:
                                APIConfirmStep(
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
        }
        .onChange(of: profileManager.activeProfile?.id) { _, _ in
            // Reload when profile changes
            loadExistingConfiguration()
            loadCurrentCredentials()

            // Reset wizard state
            wizardState = APIWizardState()
        }
    }

    private func stepTitle(for step: Int) -> String {
        switch step {
        case 1: return "wizard.enter_key".localized
        case 2: return "wizard.select_org".localized
        case 3: return "wizard.confirm".localized
        default: return ""
        }
    }

    private func loadExistingConfiguration() {
        guard let profile = profileManager.activeProfile else { return }

        // Load existing credentials for comparison
        if let creds = try? ProfileStore.shared.loadProfileCredentials(profile.id) {
            wizardState.originalOrgId = creds.apiOrganizationId
            wizardState.originalApiSessionKey = creds.apiSessionKey
        }
    }

    private func loadCurrentCredentials() {
        guard let profile = profileManager.activeProfile else { return }
        currentCredentials = try? ProfileStore.shared.loadProfileCredentials(profile.id)
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 20 else { return "•••••••••" }
        let prefix = String(key.prefix(12))
        let suffix = String(key.suffix(4))
        return "\(prefix)•••••\(suffix)"
    }

    private func removeCredentials() {
        guard let profileId = profileManager.activeProfile?.id else {
            LoggingService.shared.logError("APIBillingView: No active profile for removal")
            return
        }

        LoggingService.shared.log("APIBillingView: Starting credential removal for profile \(profileId)")

        do {
            // Use ProfileManager's shared removal method
            try profileManager.removeAPICredentials(for: profileId)

            // Reload UI to update the view
            loadCurrentCredentials()

            // Reset wizard
            wizardState = APIWizardState()

            LoggingService.shared.log("APIBillingView: Successfully removed API Console credentials")

        } catch {
            let appError = AppError.wrap(error)
            ErrorLogger.shared.log(appError, severity: .error)
            ErrorPresenter.shared.showAlert(for: appError)
            LoggingService.shared.logError("APIBillingView: Failed to remove credentials - \(appError.message)")
        }
    }
}

// MARK: - Step 1: Enter Key

struct APIEnterKeyStep: View {
    @Binding var wizardState: APIWizardState
    let apiService: ClaudeAPIService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Professional input field
            VStack(alignment: .leading, spacing: 8) {
                Text("api.label_api_session_key".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("api.placeholder_api_session_key".localized, text: $wizardState.apiSessionKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Text("api.help_api_session_key".localized)
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
                Spacer()

                Button(action: fetchOrganizations) {
                    HStack(spacing: 6) {
                        if wizardState.validationState == .validating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "building.2")
                                .font(.system(size: 12))
                        }
                        Text(wizardState.validationState == .validating ? "wizard.fetching".localized : "wizard.fetch_organizations".localized)
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(wizardState.apiSessionKey.isEmpty || wizardState.validationState == .validating)
            }
        }
    }

    private func fetchOrganizations() {
        wizardState.validationState = .validating

        Task {
            do {
                let orgs = try await apiService.fetchConsoleOrganizations(apiSessionKey: wizardState.apiSessionKey)

                await MainActor.run {
                    wizardState.testedOrganizations = orgs
                    wizardState.validationState = .success("Found \(orgs.count) organization(s)")

                    // Auto-advance to next step
                    withAnimation {
                        wizardState.currentStep = .selectOrg
                    }
                }
            } catch {
                await MainActor.run {
                    wizardState.validationState = .error("Failed to fetch: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Step 2: Select Organization

struct APISelectOrgStep: View {
    @Binding var wizardState: APIWizardState

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
                ForEach(wizardState.testedOrganizations, id: \.id) { org in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            wizardState.selectedOrgId = org.id
                        }
                    }) {
                        HStack(spacing: 10) {
                            // Radio button
                            ZStack {
                                Circle()
                                    .strokeBorder(
                                        wizardState.selectedOrgId == org.id
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.3),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 16, height: 16)

                                if wizardState.selectedOrgId == org.id {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(org.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(org.id)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if wizardState.selectedOrgId == org.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(10)
                        .background(
                            wizardState.selectedOrgId == org.id
                                ? Color.accentColor.opacity(0.06)
                                : Color(nsColor: .controlBackgroundColor).opacity(0.3)
                        )
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    wizardState.selectedOrgId == org.id
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
                wizardState.selectedOrgId = firstOrg.id
            }
        }
    }
}

// MARK: - Step 3: Confirm & Save

struct APIConfirmStep: View {
    @Binding var wizardState: APIWizardState
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
                        Text("wizard.api_session_key".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(maskSessionKey(wizardState.apiSessionKey))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }

                if let selectedOrg = wizardState.testedOrganizations.first(where: { $0.id == wizardState.selectedOrgId }) {
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
                            Text(selectedOrg.id)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if apiKeyHasChanged() {
                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("wizard.api_key_will_update".localized)
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

    private func apiKeyHasChanged() -> Bool {
        guard let originalKey = wizardState.originalApiSessionKey else { return true }
        return originalKey != wizardState.apiSessionKey
    }

    private func saveConfiguration() {
        guard let profileId = ProfileManager.shared.activeProfile?.id else { return }

        isSaving = true

        Task {
            do {
                // Save to profile-specific Keychain
                var creds = try ProfileStore.shared.loadProfileCredentials(profileId)
                creds.apiSessionKey = wizardState.apiSessionKey
                creds.apiOrganizationId = wizardState.selectedOrgId
                try ProfileStore.shared.saveProfileCredentials(profileId, credentials: creds)

                // Also update the Profile model with the new credentials
                if var profile = ProfileManager.shared.activeProfile {
                    profile.apiSessionKey = wizardState.apiSessionKey
                    profile.apiOrganizationId = wizardState.selectedOrgId
                    ProfileManager.shared.updateProfile(profile)
                    LoggingService.shared.log("APIBillingView: Updated profile model with new credentials")
                }

                await MainActor.run {
                    // Reset circuit breaker on successful credential save
                    ErrorRecovery.shared.recordSuccess(for: .api)

                    // Determine which notification to send
                    let keyChanged = apiKeyHasChanged()
                    let orgChanged = wizardState.selectedOrgId != wizardState.originalOrgId
                    if keyChanged || orgChanged {
                        // Post notification to trigger refresh only if credentials actually changed
                        NotificationCenter.default.post(name: .credentialsChanged, object: nil)
                    }

                    // Reload credentials display
                    onSave()

                    // Reset wizard to start
                    withAnimation {
                        wizardState = APIWizardState()
                    }
                    isSaving = false
                }

            } catch {
                await MainActor.run {
                    wizardState.validationState = .error("Failed to save: \(error.localizedDescription)")
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

// MARK: - Previews

#Preview {
    APIBillingView()
        .frame(width: 520, height: 600)
}
