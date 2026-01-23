import SwiftUI
import UserNotifications

/// Professional, native macOS Settings interface with multi-profile support
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .appearance
    @StateObject private var profileManager = ProfileManager.shared

    var body: some View {
        HSplitView {
            // Sidebar with Profile Switcher
            VStack(spacing: 0) {
                // Profile Section (Switcher + Credentials + Settings)
                ProfileSectionContainer(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Spacer()

                // App Settings Section at bottom
                AppSettingsSection(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(minWidth: 160, idealWidth: 170, maxWidth: 180)

            // Content
            Group {
                switch selectedSection {
                // Credentials
                case .claudeAI:
                    PersonalUsageView()
                case .apiConsole:
                    APIBillingView()
                case .cliAccount:
                    CLIAccountView()

                // Profile Settings
                case .appearance:
                    AppearanceSettingsView()
                case .general:
                    GeneralSettingsView()

                // Shared Settings
                case .manageProfiles:
                    ManageProfilesView()
                case .language:
                    LanguageSettingsView()
                case .claudeCode:
                    ClaudeCodeView()
                case .updates:
                    UpdatesSettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .frame(width: 720, height: 580)
    }
}

// MARK: - Profile Section Container

struct ProfileSectionContainer: View {
    @Binding var selectedSection: SettingsSection
    @StateObject private var profileManager = ProfileManager.shared

    var profileSections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.isProfileSetting && !$0.isCredential }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile Switcher
            VStack(alignment: .leading, spacing: 4) {
                Text("section.active_profile".localized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { profileManager.activeProfile?.id ?? UUID() },
                    set: { newId in
                        Task {
                            await profileManager.activateProfile(newId)
                        }
                    }
                )) {
                    ForEach(profileManager.profiles) { profile in
                        HStack {
                            Text(profile.name)
                            if profile.hasCliAccount {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(8)

            Divider()
                .padding(.horizontal, 8)

            // Credentials
            VStack(alignment: .leading, spacing: 4) {
                Text("section.credentials".localized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                ProfileCredentialCardsRow(selectedSection: $selectedSection)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }

            Divider()
                .padding(.horizontal, 8)

            // Profile Settings
            VStack(alignment: .leading, spacing: 4) {
                Text("section.settings".localized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                VStack(spacing: 4) {
                    ForEach(profileSections, id: \.self) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            SettingMiniButton(
                                icon: section.icon,
                                title: section.title,
                                isSelected: selectedSection == section
                            )
                        }
                        .buttonStyle(.plain)
                        .help(section.description)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - App Settings Section

struct AppSettingsSection: View {
    @Binding var selectedSection: SettingsSection

    var sharedSections: [SettingsSection] {
        SettingsSection.allCases.filter { !$0.isProfileSetting && !$0.isCredential }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.app".localized)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ForEach(sharedSections, id: \.self) { section in
                SidebarItem(
                    icon: section.icon,
                    title: section.title,
                    description: section.description,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }
        }
    }
}

enum SettingsSection: String, CaseIterable {
    // Credentials (not shown in sidebar)
    case claudeAI
    case apiConsole
    case cliAccount

    // Profile Settings
    case appearance
    case general

    // Shared Settings
    case manageProfiles
    case language
    case claudeCode
    case updates
    case about

    var title: String {
        switch self {
        case .claudeAI: return "section.claudeai_title".localized
        case .apiConsole: return "section.api_console_title".localized
        case .cliAccount: return "section.cli_account_title".localized
        case .appearance: return "section.appearance_title".localized
        case .general: return "section.general_title".localized
        case .manageProfiles: return "section.manage_profiles_title".localized
        case .language: return "language.title".localized
        case .claudeCode: return "settings.claude_cli".localized
        case .updates: return "settings.updates".localized
        case .about: return "settings.about".localized
        }
    }

    var icon: String {
        switch self {
        case .claudeAI: return "key.fill"
        case .apiConsole: return "dollarsign.circle.fill"
        case .cliAccount: return "terminal.fill"
        case .appearance: return "paintbrush.fill"
        case .general: return "gearshape.fill"
        case .manageProfiles: return "person.2.fill"
        case .language: return "globe"
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        case .updates: return "arrow.down.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .claudeAI: return "section.claudeai_desc".localized
        case .apiConsole: return "section.api_console_desc".localized
        case .cliAccount: return "section.cli_account_desc".localized
        case .appearance: return "section.appearance_desc".localized
        case .general: return "section.general_desc".localized
        case .manageProfiles: return "section.manage_profiles_desc".localized
        case .language: return "language.subtitle".localized
        case .claudeCode: return "settings.claude_cli.description".localized
        case .updates: return "settings.updates.description".localized
        case .about: return "settings.about.description".localized
        }
    }

    var isCredential: Bool {
        switch self {
        case .claudeAI, .apiConsole, .cliAccount:
            return true
        default:
            return false
        }
    }

    var isProfileSetting: Bool {
        switch self {
        case .appearance, .general:
            return true
        default:
            return false
        }
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? SettingsColors.primary : Color.clear)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description)
    }
}

// MARK: - Profile Credential Cards Row

struct ProfileCredentialCardsRow: View {
    @Binding var selectedSection: SettingsSection
    @StateObject private var profileManager = ProfileManager.shared
    @State private var credentials: ProfileCredentials?
    @State private var hasCLICredentials = false

    var body: some View {
        VStack(spacing: 4) {
            // Claude.ai Card - connected if has session key OR CLI credentials
            Button {
                selectedSection = .claudeAI
            } label: {
                CredentialMiniCard(
                    icon: "key.fill",
                    title: "Claude.ai",
                    isConnected: (credentials?.hasClaudeAI ?? false) || hasCLICredentials,
                    isSelected: selectedSection == .claudeAI
                )
            }
            .buttonStyle(.plain)

            // API Console Card
            Button {
                selectedSection = .apiConsole
            } label: {
                CredentialMiniCard(
                    icon: "dollarsign.circle.fill",
                    title: "API Console",
                    isConnected: credentials?.apiSessionKey != nil,
                    isSelected: selectedSection == .apiConsole
                )
            }
            .buttonStyle(.plain)

            // CLI Account Card
            Button {
                selectedSection = .cliAccount
            } label: {
                CredentialMiniCard(
                    icon: "terminal.fill",
                    title: "CLI Account",
                    isConnected: profileManager.activeProfile?.hasCliAccount ?? false,
                    isSelected: selectedSection == .cliAccount
                )
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            loadCredentials()
            checkCLICredentials()
        }
        .onChange(of: profileManager.activeProfile?.id) { _, _ in
            loadCredentials()
            checkCLICredentials()
        }
    }

    private func loadCredentials() {
        guard let profile = profileManager.activeProfile else { return }
        credentials = try? ProfileStore.shared.loadProfileCredentials(profile.id)
    }

    private func checkCLICredentials() {
        Task {
            do {
                // Check profile CLI credentials or system CLI credentials
                if let profile = profileManager.activeProfile,
                   let cliJson = profile.cliCredentialsJSON,
                   !ClaudeCodeSyncService.shared.isTokenExpired(cliJson) {
                    await MainActor.run { hasCLICredentials = true }
                    return
                }

                if let creds = try ClaudeCodeSyncService.shared.readSystemCredentials(),
                   !ClaudeCodeSyncService.shared.isTokenExpired(creds) {
                    await MainActor.run { hasCLICredentials = true }
                    return
                }

                await MainActor.run { hasCLICredentials = false }
            } catch {
                await MainActor.run { hasCLICredentials = false }
            }
        }
    }
}

struct CredentialMiniCard: View {
    let icon: String
    let title: String
    let isConnected: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : (isConnected ? .green : .gray))
                .frame(width: 12)

            // Title
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            // Status indicator
            Circle()
                .fill(isSelected ? Color.white.opacity(0.9) : (isConnected ? Color.green : Color.gray.opacity(0.3)))
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? SettingsColors.primary : Color.clear)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}

struct SettingMiniButton: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 12)

            // Title
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? SettingsColors.primary : Color.clear)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
}
