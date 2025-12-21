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
                title: "API Billing",
                subtitle: "Monitor API usage and spending"
            )

            Divider()

            // Enable/Disable Toggle
            SettingToggle(
                title: "Enable API billing tracking",
                description: "Monitor your API usage, current spend, and remaining prepaid credits",
                badge: .new,
                isOn: $trackingEnabled
            )
            .onChange(of: trackingEnabled) { _, newValue in
                DataStore.shared.saveAPITrackingEnabled(newValue)
            }

            if trackingEnabled {
                // API Session Key Input
                SettingsInputField.secureMonospaced(
                    label: "API Session Key",
                    placeholder: "sk-ant-api03-...",
                    helpText: "Your session key from console.anthropic.com",
                    text: $apiSessionKey
                )

                // Organization Selection
                if !organizations.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.inputSpacing) {
                        Text("Organization")
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
                            title: validationState == .validating ? "Fetching..." : "Fetch Organizations",
                            icon: "building.2"
                        ) {
                            fetchOrganizations()
                        }
                        .disabled(apiSessionKey.isEmpty || validationState == .validating)
                    }

                    SettingsButton.primary(
                        title: "Save Configuration"
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
