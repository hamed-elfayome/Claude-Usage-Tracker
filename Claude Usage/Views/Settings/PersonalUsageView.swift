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
        VStack(alignment: .leading, spacing: 16) {
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
            HStack(spacing: 10) {
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

            Divider()
                .padding(.vertical, 4)

            // Quick Actions
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Actions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 10) {
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
        .padding(28)
        .sheet(isPresented: $showWizard) {
            SetupWizardView()
        }
    }

    private func saveKey() {
        validationState = .validating

        do {
            try apiService.saveSessionKey(sessionKey)
            validationState = .success("Session key saved successfully")
            sessionKey = ""
        } catch {
            validationState = .error("Failed to save session key")
        }
    }

    private func testKey() {
        validationState = .validating

        Task {
            do {
                let orgId = try await apiService.fetchOrganizationId()
                await MainActor.run {
                    validationState = .success("Connected to organization: \(orgId)")
                }
            } catch {
                await MainActor.run {
                    validationState = .error("Connection failed: \(error.localizedDescription)")
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
