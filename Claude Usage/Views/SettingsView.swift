import SwiftUI
import UserNotifications

/// Professional, native macOS Settings interface
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .personalUsage
    @State private var notificationsEnabled: Bool = DataStore.shared.loadNotificationsEnabled()
    @State private var refreshInterval: Double = DataStore.shared.loadRefreshInterval()
    @State private var autoStartSessionEnabled: Bool = DataStore.shared.loadAutoStartSessionEnabled()

    var body: some View {
        HSplitView {
            // Sidebar
            SidebarView(selectedSection: $selectedSection)
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)

            // Content
            Group {
                switch selectedSection {
                case .personalUsage:
                    PersonalUsageView()
                case .apiBilling:
                    APIBillingView()
                case .general:
                    GeneralSettingsView(refreshInterval: $refreshInterval)
                case .appearance:
                    AppearanceSettingsView()
                case .sessionManagement:
                    SessionManagementView(autoStartSessionEnabled: $autoStartSessionEnabled)
                case .notifications:
                    NotificationsSettingsView(notificationsEnabled: $notificationsEnabled)
                case .claudeCode:
                    ClaudeCodeView()
                case .about:
                    AboutView()
                }
            }
            .frame(minWidth: 450, maxWidth: .infinity)
        }
        .frame(width: 720, height: 600)
    }
}

enum SettingsSection: String, CaseIterable {
    case personalUsage = "Personal Usage"
    case apiBilling = "API Billing"
    case general = "General"
    case appearance = "Appearance"
    case sessionManagement = "Session Management"
    case notifications = "Notifications"
    case claudeCode = "Claude CLI"
    case about = "About"

    var icon: String {
        switch self {
        case .personalUsage: return "person.fill"
        case .apiBilling: return "dollarsign.circle.fill"
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .sessionManagement: return "clock.arrow.circlepath"
        case .notifications: return "bell.badge.fill"
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        case .about: return "info.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .personalUsage: return "Track your Claude.ai free tier usage"
        case .apiBilling: return "Monitor API Console billing and credits"
        case .general: return "App behavior and preferences"
        case .appearance: return "Menu bar icon customization"
        case .sessionManagement: return "Automatic session management"
        case .notifications: return "Usage alerts and notifications"
        case .claudeCode: return "Terminal statusline integration"
        case .about: return "App information and credits"
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                SidebarItem(
                    icon: section.icon,
                    title: section.rawValue,
                    description: section.description,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }
            Spacer()
        }
        .padding(.top, Spacing.lg)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.iconTextSpacing) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(Typography.body)
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusMedium)
                    .fill(isSelected ? SettingsColors.primary : Color.clear)
            )
            .padding(.horizontal, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(description)
    }
}
