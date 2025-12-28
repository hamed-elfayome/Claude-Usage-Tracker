//
//  APISettingsView.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import SwiftUI

/// Settings view for API Usage tracking configuration
struct APISettingsView: View {
    @State private var apiSessionKey: String = DataStore.shared.loadAPISessionKey() ?? ""
    @State private var apiTrackingEnabled: Bool = DataStore.shared.loadAPITrackingEnabled()
    @State private var organizations: [APIOrganization] = []
    @State private var selectedOrganizationId: String = DataStore.shared.loadAPIOrganizationId() ?? ""
    @State private var validationState: ValidationState = .idle
    @State private var fetchingOrgs: Bool = false

    private let apiService = ClaudeAPIService()

    enum ValidationState {
        case idle
        case validating
        case success(String)
        case error(String)
    }

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
                isOn: $apiTrackingEnabled
            )
            .onChange(of: apiTrackingEnabled) { _, newValue in
                DataStore.shared.saveAPITrackingEnabled(newValue)
            }

            if apiTrackingEnabled {
                // API Session Key Input
                VStack(alignment: .leading, spacing: Spacing.inputSpacing) {
                    Text("api.label_api_session_key".localized)
                        .font(Typography.sectionHeader)

                    SecureField("api.placeholder_api_session_key".localized, text: $apiSessionKey)
                        .textFieldStyle(.plain)
                        .font(Typography.monospacedInput)
                        .padding(Spacing.inputPadding)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )

                    Text("api.help_api_session_key".localized)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                // Fetch Organizations Button
                HStack(spacing: Spacing.buttonRowSpacing) {
                    Button(action: fetchOrganizations) {
                        if fetchingOrgs {
                            HStack(spacing: Spacing.iconTextSpacing) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("api.button_fetching".localized)
                                    .font(Typography.label)
                            }
                            .frame(width: 140)
                        } else {
                            Text("api.button_fetch_organizations".localized)
                                .font(Typography.label)
                                .frame(width: 140)
                        }
                    }
                    .disabled(apiSessionKey.isEmpty || fetchingOrgs)
                    .buttonStyle(.bordered)

                    Spacer()
                }

                // Organization Selection
                if !organizations.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.inputSpacing) {
                        Text("ui.organization".localized)
                            .font(Typography.sectionHeader)

                        Picker("", selection: $selectedOrganizationId) {
                            ForEach(organizations) { org in
                                Text(org.displayName)
                                    .tag(org.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 300)
                        .onChange(of: selectedOrganizationId) { _, newValue in
                            DataStore.shared.saveAPIOrganizationId(newValue)
                        }

                        if organizations.count == 1 {
                            Text("api.single_organization".localized)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Save Button
                    HStack {
                        Button(action: saveConfiguration) {
                            Text("api.button_save_configuration".localized)
                                .font(Typography.label)
                                .frame(width: 140)
                        }
                        .disabled(selectedOrganizationId.isEmpty)
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }
                }

                // Validation Feedback
                if case .success(let message) = validationState {
                    APIStatusBox(message: message, type: .success)
                } else if case .error(let message) = validationState {
                    APIStatusBox(message: message, type: .error)
                }
            }

            Spacer()
        }
        .contentPadding()
    }

    // MARK: - Actions

    private func fetchOrganizations() {
        guard !apiSessionKey.isEmpty else { return }

        fetchingOrgs = true
        validationState = .idle

        Task {
            do {
                let orgs = try await apiService.fetchConsoleOrganizations(apiSessionKey: apiSessionKey)

                await MainActor.run {
                    organizations = orgs
                    fetchingOrgs = false

                    if orgs.count == 1 {
                        selectedOrganizationId = orgs[0].id
                        DataStore.shared.saveAPIOrganizationId(orgs[0].id)
                    } else if !orgs.isEmpty && selectedOrganizationId.isEmpty {
                        selectedOrganizationId = orgs[0].id
                    }

                    validationState = .success("api.success_organizations_found".localized(with: orgs.count))
                }
            } catch {
                await MainActor.run {
                    fetchingOrgs = false
                    validationState = .error("api.error_fetch_failed".localized(with: error.localizedDescription))
                }
            }
        }
    }

    private func saveConfiguration() {
        DataStore.shared.saveAPISessionKey(apiSessionKey)
        DataStore.shared.saveAPIOrganizationId(selectedOrganizationId)
        validationState = .success("api.success_configuration_saved".localized)
    }
}

// MARK: - API Status Box

struct APIStatusBox: View {
    let message: String
    let type: APIStatusType

    enum APIStatusType {
        case success
        case error

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.iconTextSpacing) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .font(.system(size: 14))

            Text(message)
                .font(Typography.label)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(Spacing.inputPadding)
        .background(
            RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                .fill(type.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                        .strokeBorder(type.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
