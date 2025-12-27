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
                title: "Personal Usage",
                subtitle: "Track your Claude.ai usage and sessions"
            )

            Divider()

            // Session Key Input
            SettingsInputField.secureMonospaced(
                label: "Session Key",
                placeholder: "sk-ant-sid-...",
                helpText: "Paste your sessionKey cookie from claude.ai DevTools",
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
                SettingsButton(title: "Test Connection") {
                    testKey()
                }
                .disabled(sessionKey.isEmpty || validationState == .validating)

                SettingsButton.primary(
                    title: validationState == .validating ? "Saving..." : "Save"
                ) {
                    saveKey()
                }
                .disabled(sessionKey.isEmpty || validationState == .validating)
            }

            // Quick Actions
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Quick Actions")
                    .font(Typography.sectionHeader)

                HStack(spacing: Spacing.buttonRowSpacing) {
                    SettingsButton(title: "Setup Wizard", icon: "wand.and.stars") {
                        showWizard = true
                    }

                    SettingsButton(title: "Open claude.ai", icon: "safari") {
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
            validationState = .success("Session key saved successfully")
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
                let orgId = try await apiService.fetchOrganizationId()

                await MainActor.run {
                    validationState = .success("Connected successfully to organization")
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
