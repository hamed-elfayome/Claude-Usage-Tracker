//
//  ManageProfilesView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import SwiftUI

struct ManageProfilesView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var showingCreateProfile = false
    @State private var newProfileName = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Page Header
                SettingsPageHeader(
                    title: "profiles.title".localized,
                    subtitle: "profiles.subtitle".localized
                )

                // Profile List
                SettingsContentCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        ForEach(profileManager.profiles) { profile in
                            ProfileRow(profile: profile)
                                .padding(.vertical, DesignTokens.Spacing.extraSmall)

                            if profile.id != profileManager.profiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                // Create New Profile Button
                SettingsButton(
                    title: "profiles.create_new".localized,
                    icon: "plus.circle.fill"
                ) {
                    showingCreateProfile = true
                }

                // Info Card
                SettingsContentCard {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                        HStack(spacing: DesignTokens.Spacing.small) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: DesignTokens.Icons.standard))
                            Text("profiles.about_title".localized)
                                .font(DesignTokens.Typography.sectionTitle)
                        }

                        Text("profiles.about_description".localized)
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.extraSmall) {
                            BulletPoint("profiles.about_credentials".localized)
                            BulletPoint("profiles.about_api".localized)
                            BulletPoint("profiles.about_cli".localized)
                            BulletPoint("profiles.about_appearance".localized)
                            BulletPoint("profiles.about_notifications".localized)
                            BulletPoint("profiles.about_refresh".localized)
                        }
                        .font(DesignTokens.Typography.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, DesignTokens.Spacing.small)
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingCreateProfile) {
            CreateProfileSheet(
                profileName: $newProfileName,
                onSave: {
                    createNewProfile()
                },
                onCancel: {
                    showingCreateProfile = false
                    newProfileName = ""
                }
            )
        }
    }

    private func createNewProfile() {
        let name = newProfileName.isEmpty ? nil : newProfileName
        _ = profileManager.createProfile(name: name)
        showingCreateProfile = false
        newProfileName = ""
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let profile: Profile
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Profile Icon
            Image(systemName: profile.hasCliAccount ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(profileManager.activeProfile?.id == profile.id ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Profile Name", text: $editedName, onCommit: {
                        saveProfileName()
                    })
                    .textFieldStyle(.roundedBorder)
                } else {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.system(size: 14, weight: .medium))

                        if profileManager.activeProfile?.id == profile.id {
                            Text("profiles.active_badge".localized)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }
                }

                Text(profileInfo)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if !isEditing {
                    // Rename Button
                    Button(action: {
                        editedName = profile.name
                        isEditing = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("profiles.rename".localized)

                    // Activate Button (if not active)
                    if profileManager.activeProfile?.id != profile.id {
                        Button(action: {
                            Task {
                                await profileManager.activateProfile(profile.id)
                            }
                        }) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("profiles.activate".localized)
                    }

                    // Delete Button (if not the last profile)
                    if profileManager.profiles.count > 1 {
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("profiles.delete".localized)
                    }
                } else {
                    // Save Button
                    Button(action: {
                        saveProfileName()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)

                    // Cancel Button
                    Button(action: {
                        isEditing = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("profiles.delete_title".localized, isPresented: $showingDeleteConfirmation) {
            Button("common.cancel".localized, role: .cancel) {}
            Button("common.delete".localized, role: .destructive) {
                deleteProfile()
            }
        } message: {
            Text(String(format: "profiles.delete_confirm".localized, profile.name))
        }
    }

    private var profileInfo: String {
        var parts: [String] = []

        if profile.hasCliAccount {
            parts.append("profiles.cli_synced".localized)
        }

        parts.append("\("profiles.created".localized) \(profile.createdAt.formatted(date: .abbreviated, time: .omitted))")

        return parts.joined(separator: " • ")
    }

    private func saveProfileName() {
        if !editedName.isEmpty && editedName != profile.name {
            var updated = profile
            updated.name = editedName
            profileManager.updateProfile(updated)
        }
        isEditing = false
    }

    private func deleteProfile() {
        do {
            try profileManager.deleteProfile(profile.id)
        } catch {
            // Error handled by ProfileManager
        }
    }
}

// MARK: - Create Profile Sheet

struct CreateProfileSheet: View {
    @Binding var profileName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("profiles.create_title".localized)
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("profiles.name_label".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("profiles.name_placeholder".localized, text: $profileName)
                    .textFieldStyle(.roundedBorder)

                Text("profiles.name_hint".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("common.cancel".localized) {
                    onCancel()
                }
                .buttonStyle(.plain)

                Button("common.create".localized) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
