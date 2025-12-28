//
//  APIBillingView.swift
//  Claude Usage - API Console Billing Tracking
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// API Console billing and credits tracking
struct APIBillingView: View {
    @State private var apiSessionKey: String = DataStore.shared.loadAPISessionKey() ?? ""
    @State private var organizations: [APIOrganization] = []
    @State private var selectedOrganizationId: String = DataStore.shared.loadAPIOrganizationId() ?? ""
    @State private var validationState: ValidationState = .idle
    @State private var trackingEnabled: Bool = DataStore.shared.loadAPITrackingEnabled()

    private let apiService = ClaudeAPIService()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionSpacing) {
            // Header
            SettingsHeader(
                title: "api.title".localized,
                subtitle: "api.subtitle".localized
            )

            Divider()

            // Enable/Disable Toggle
            SettingToggle(
                title: "api.enable_billing_tracking".localized,
                description: "api.enable_billing_description".localized,
                badge: .new,
                isOn: $trackingEnabled
            )
            .onChange(of: trackingEnabled) { _, newValue in
                DataStore.shared.saveAPITrackingEnabled(newValue)
            }

            if trackingEnabled {
                // API Session Key Input
                SettingsInputField.secureMonospaced(
                    label: "api.label_api_session_key".localized,
                    placeholder: "api.placeholder_api_session_key".localized,
                    helpText: "api.help_api_session_key".localized,
                    text: $apiSessionKey
                )

                // Organization Selection
                if !organizations.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.inputSpacing) {
                        Text("ui.organization".localized)
                            .font(Typography.sectionHeader)

                        Picker("", selection: $selectedOrganizationId) {
                            ForEach(organizations, id: \.id) { org in
                                Text(org.name).tag(org.id)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: selectedOrganizationId) { _, newValue in
                            DataStore.shared.saveAPIOrganizationId(newValue)
                        }
                    }
                }

                // Validation Status
                if case .success(let message) = validationState {
                    SettingsStatusBox(message: message, type: .success)
                } else if case .error(let message) = validationState {
                    SettingsStatusBox(message: message, type: .error)
                }

                // Action Buttons
                HStack(spacing: Spacing.buttonRowSpacing) {
                    if organizations.isEmpty {
                        SettingsButton(
                            title: validationState == .validating ? "api.button_fetching".localized : "api.button_fetch_organizations".localized,
                            icon: "building.2"
                        ) {
                            fetchOrganizations()
                        }
                        .disabled(apiSessionKey.isEmpty || validationState == .validating)
                    }

                    SettingsButton.primary(
                        title: "api.button_save_configuration".localized
                    ) {
                        saveConfiguration()
                    }
                    .disabled(apiSessionKey.isEmpty || selectedOrganizationId.isEmpty)
                }
            }

            Spacer()
        }
        .contentPadding()
    }

    private func fetchOrganizations() {
        validationState = .validating

        Task {
            do {
                let orgs = try await apiService.fetchConsoleOrganizations(apiSessionKey: apiSessionKey)
                await MainActor.run {
                    self.organizations = orgs
                    if let firstOrg = orgs.first {
                        self.selectedOrganizationId = firstOrg.id
                    }
                    validationState = .success("Found \(orgs.count) organization(s)")
                }
            } catch {
                await MainActor.run {
                    validationState = .error("Failed to fetch organizations: \(error.localizedDescription)")
                }
            }
        }
    }

    private func saveConfiguration() {
        DataStore.shared.saveAPISessionKey(apiSessionKey)
        DataStore.shared.saveAPIOrganizationId(selectedOrganizationId)
        validationState = .success("API configuration saved successfully")
    }
}

// MARK: - Previews

#Preview {
    APIBillingView()
        .frame(width: 520, height: 600)
}
