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
                title: "API Usage Tracking",
                subtitle: "Monitor your Anthropic API usage and spending"
            )

            Divider()

            // Enable/Disable Toggle
            SettingToggle(
                title: "Enable API Usage Tracking",
                description: "Track your API spending and remaining credits from console.anthropic.com",
                isOn: $apiTrackingEnabled
            )
            .onChange(of: apiTrackingEnabled) { _, newValue in
                DataStore.shared.saveAPITrackingEnabled(newValue)
            }

            if apiTrackingEnabled {
                // API Session Key Input
                VStack(alignment: .leading, spacing: Spacing.inputSpacing) {
                    Text("API Console Session Key")
                        .font(Typography.sectionHeader)

                    SecureField("sk-ant-sid-...", text: $apiSessionKey)
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

                    Text("Paste your sessionKey cookie from console.anthropic.com DevTools")
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
                                Text("Fetching...")
                                    .font(Typography.label)
                            }
                            .frame(width: 140)
                        } else {
                            Text("Fetch Organizations")
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
                        Text("Select Organization")
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
                            Text("Single organization found and selected automatically")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Save Button
                    HStack {
                        Button(action: saveConfiguration) {
                            Text("Save Configuration")
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

                    validationState = .success("Found \(orgs.count) organization(s)")
                }
            } catch {
                await MainActor.run {
                    fetchingOrgs = false
                    validationState = .error("Failed to fetch organizations: \(error.localizedDescription)")
                }
            }
        }
    }

    private func saveConfiguration() {
        DataStore.shared.saveAPISessionKey(apiSessionKey)
        DataStore.shared.saveAPIOrganizationId(selectedOrganizationId)
        validationState = .success("Configuration saved successfully")
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
