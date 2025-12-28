//
//  PersonalUsageView.swift
//  Claude Usage - Claude.ai Personal Usage Tracking
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Claude.ai personal usage tracking (free tier)
struct PersonalUsageView: View {
    @State private var sessionKey: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var showWizard = false

    private let apiService = ClaudeAPIService()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "personal.title".localized,
                subtitle: "personal.subtitle".localized
            )

            Divider()

            // Session Key Input
            SettingsInputField.secureMonospaced(
                label: "personal.label_session_key".localized,
                placeholder: "personal.placeholder_session_key".localized,
                helpText: "personal.help_session_key".localized,
                text: $sessionKey
            )

            // Validation Status
            if case .success(let message) = validationState {
                SettingsStatusBox(message: message, type: .success)
            } else if case .error(let message) = validationState {
                SettingsStatusBox(message: message, type: .error)
            }

            // Action Buttons
            HStack(spacing: Spacing.buttonRowSpacing) {
                SettingsButton(title: "personal.button_test_connection".localized) {
                    testKey()
                }
                .disabled(sessionKey.isEmpty || validationState == .validating)

                SettingsButton.primary(
                    title: validationState == .validating ? "personal.button_saving".localized : "common.save".localized
                ) {
                    saveKey()
                }
                .disabled(sessionKey.isEmpty || validationState == .validating)
            }

            // Quick Actions
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("ui.quick_actions".localized)
                    .font(Typography.sectionHeader)

                HStack(spacing: Spacing.buttonRowSpacing) {
                    SettingsButton(title: "personal.button_setup_wizard".localized, icon: "wand.and.stars") {
                        showWizard = true
                    }

                    SettingsButton(title: "personal.button_open_claude".localized, icon: "safari") {
                        if let url = URL(string: "https://claude.ai") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Spacer()
        }
        .contentPadding()
        .sheet(isPresented: $showWizard) {
            SetupWizardView()
        }
    }

    private func saveKey() {
        // Validate using professional validator first
        let validator = SessionKeyValidator()
        let validationResult = validator.validationStatus(sessionKey)

        guard validationResult.isValid else {
            validationState = .error(validationResult.errorMessage ?? "Invalid session key")
            return
        }

        validationState = .validating

        do {
            try apiService.saveSessionKey(sessionKey)
            validationState = .success("personal.success_key_saved".localized)
            sessionKey = ""

        } catch {
            // Convert to AppError and log
            let appError = AppError.wrap(error)
            ErrorLogger.shared.log(appError, severity: .error)

            let errorMessage = "\(appError.message)\n\nError Code: \(appError.code.rawValue)"
            validationState = .error(errorMessage)
        }
    }

    func testKey() {
        // Validate using professional validator first
        let validator = SessionKeyValidator()
        let validationResult = validator.validationStatus(sessionKey)

        guard validationResult.isValid else {
            validationState = .error(validationResult.errorMessage ?? "Invalid session key")
            return
        }

        validationState = .validating

        Task {
            do {
                // Temporarily save to test (won't persist if test fails)
                try apiService.saveSessionKey(sessionKey)
                _ = try await apiService.fetchOrganizationId()

                await MainActor.run {
                    validationState = .success("personal.success_connected".localized)
                }

            } catch {
                // Convert to AppError and log
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .error)

                await MainActor.run {
                    let errorMessage = "\(appError.message)\n\nError Code: \(appError.code.rawValue)"
                    validationState = .error(errorMessage)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview {
    PersonalUsageView()
        .frame(width: 520, height: 600)
}
