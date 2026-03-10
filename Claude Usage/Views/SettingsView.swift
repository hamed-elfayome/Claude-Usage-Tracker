import SwiftUI
import UserNotifications

// MARK: - Visual Effect Backgrounds

/// Full-window vibrancy background — same approach as the popover's VisualEffectBackground.
/// Using NSViewRepresentable inside SwiftUI means the entire view tree is SwiftUI-managed,
/// so there is no opaque flash on deminiaturize or appearance change.
struct SettingsBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        } else {
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
        }
        tintView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tintView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: container.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            }
        }
    }
}

struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        } else {
            tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        }
        tintView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tintView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: container.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
            }
        }
    }
}

/// Borderless window that keeps rounded corners, shadow, and drag-to-move.
final class BorderlessSettingsWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .miniaturizable],
                   backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isRestorable = false

        // Round corners via the content view's layer
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 10
        contentView?.layer?.masksToBounds = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Builds the settings window — fully borderless, no system titlebar.
enum SettingsWindowBuilder {
    static func makeWindow(size: CGSize) -> NSWindow {
        let window = BorderlessSettingsWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(rootView:
            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView?.addSubview(hostingView)
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            ])
        }

        return window
    }
}

// MARK: - Custom Traffic Light Buttons

struct TrafficLightButtons: View {
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightButton(type: .close)
            TrafficLightButton(type: .miniaturize)
        }
    }
}

struct TrafficLightButton: View {
    enum ButtonType {
        case close, miniaturize, zoom

        var activeColor: Color {
            switch self {
            case .close: return Color(nsColor: NSColor(red: 1.0, green: 0.38, blue: 0.34, alpha: 1.0))
            case .miniaturize: return Color(nsColor: NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0))
            case .zoom: return Color(nsColor: NSColor(red: 0.15, green: 0.78, blue: 0.24, alpha: 1.0))
            }
        }

        var icon: String {
            switch self {
            case .close: return "xmark"
            case .miniaturize: return "minus"
            case .zoom: return "plus"
            }
        }
    }

    let type: ButtonType
    @State private var isHovered = false
    @Environment(\.controlActiveState) private var controlActiveState

    private var isActive: Bool { controlActiveState == .key }

    var body: some View {
        Circle()
            .fill(isActive ? type.activeColor : Color.primary.opacity(0.15))
            .frame(width: 12, height: 12)
            .overlay {
                if isHovered && isActive {
                    Image(systemName: type.icon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture { performAction() }
    }

    private func performAction() {
        guard let window = NSApp.keyWindow else { return }
        switch type {
        case .close: window.close()
        case .miniaturize: window.miniaturize(nil)
        case .zoom: window.zoom(nil)
        }
    }
}

/// Professional, native macOS Settings interface with multi-profile support
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .appearance
    @StateObject private var profileManager = ProfileManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar with Profile Switcher
            VStack(spacing: 0) {
                // Traffic light buttons
                HStack {
                    TrafficLightButtons()
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 12)

                // Profile Section (Switcher + Credentials + Settings)
                ProfileSectionContainer(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                Spacer()

                // App Settings Section
                AppSettingsSection(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)

                // Bottom bar: About, Debug, Support, Updates
                BottomBarSection(selectedSection: $selectedSection)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .padding(.top, 4)
            }
            .background(SidebarVisualEffect())
            .frame(width: 190)

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
                case .history:
                    UsageHistoryView()

                // Shared Settings
                case .appSettings:
                    AppSettingsView()
                case .manageProfiles:
                    ManageProfilesView()
                case .language:
                    LanguageSettingsView()
                case .claudeCode:
                    ClaudeCodeView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .updates:
                    UpdatesSettingsView()
                case .support:
                    SupportView()
                case .mobileApp:
                    MobileAppView()
                case .popover:
                    PopoverSettingsView()
                case .debug:
                    DebugNetworkLogView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                colorScheme == .dark
                    ? Color.black.opacity(0.15)
                    : Color.white.opacity(0.3)
            )
        }
        .frame(minWidth: 720, maxWidth: 720, maxHeight: .infinity)
        .background(SettingsBackground())
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
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - App Settings Section

struct AppSettingsSection: View {
    @Binding var selectedSection: SettingsSection

    var sharedSections: [SettingsSection] {
        SettingsSection.allCases.filter { !$0.isProfileSetting && !$0.isCredential && !$0.isBottomBarItem }
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

struct BottomBarSection: View {
    @Binding var selectedSection: SettingsSection
    @State private var hoveredItem: String?

    var items: [SettingsSection] {
        SettingsSection.allCases.filter { $0.isBottomBarItem }
    }

    var body: some View {
        VStack(spacing: 6) {
            Divider()

            HStack(spacing: 0) {
                ForEach(items, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        bottomBarLabel(
                            icon: section.icon,
                            label: section.shortLabel,
                            isSelected: selectedSection == section,
                            isHovered: hoveredItem == section.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredItem = hovering ? section.rawValue : nil
                    }
                    .help(section.title)
                }

                // Quit button
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    bottomBarLabel(
                        icon: "power",
                        label: "common.quit".localized,
                        isSelected: false,
                        isHovered: hoveredItem == "quit",
                        hoverColor: Color.red.opacity(0.1)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredItem = hovering ? "quit" : nil
                }
                .help("common.quit".localized)
            }
        }
    }

    private func bottomBarLabel(icon: String, label: String, isSelected: Bool, isHovered: Bool, hoverColor: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(height: 14)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? SettingsColors.primary : (isHovered ? (hoverColor ?? Color.primary.opacity(0.06)) : Color.clear))
        )
        .contentShape(Rectangle())
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
    case history

    // Shared Settings
    case appSettings
    case manageProfiles
    case language
    case claudeCode
    case shortcuts
    case updates
    case support
    case mobileApp
    case popover
    case debug
    case about

    var title: String {
        switch self {
        case .claudeAI: return "section.claudeai_title".localized
        case .apiConsole: return "section.api_console_title".localized
        case .cliAccount: return "section.cli_account_title".localized
        case .appearance: return "section.appearance_title".localized
        case .general: return "section.general_title".localized
        case .history: return "section.history_title".localized
        case .appSettings: return "section.app_settings_title".localized
        case .manageProfiles: return "section.manage_profiles_title".localized
        case .language: return "language.title".localized
        case .claudeCode: return "settings.claude_cli".localized
        case .shortcuts: return "section.shortcuts_title".localized
        case .updates: return "settings.updates".localized
        case .support: return "section.support_title".localized
        case .mobileApp: return "section.mobile_app_title".localized
        case .popover: return "section.popover_title".localized
        case .debug: return "section.debug_title".localized
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
        case .history: return "chart.bar.xaxis"
        case .appSettings: return "gearshape.2.fill"
        case .manageProfiles: return "person.2.fill"
        case .language: return "globe"
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        case .shortcuts: return "keyboard"
        case .updates: return "arrow.down.circle.fill"
        case .support: return "heart.fill"
        case .mobileApp: return "iphone"
        case .popover: return "rectangle.topthird.inset.filled"
        case .debug: return "ladybug.fill"
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
        case .history: return "section.history_desc".localized
        case .appSettings: return "section.app_settings_desc".localized
        case .manageProfiles: return "section.manage_profiles_desc".localized
        case .language: return "language.subtitle".localized
        case .claudeCode: return "settings.claude_cli.description".localized
        case .shortcuts: return "section.shortcuts_desc".localized
        case .updates: return "settings.updates.description".localized
        case .support: return "section.support_desc".localized
        case .mobileApp: return "section.mobile_app_desc".localized
        case .popover: return "section.popover_desc".localized
        case .debug: return "section.debug_desc".localized
        case .about: return "settings.about.description".localized
        }
    }

    var shortLabel: String {
        switch self {
        case .about: return "About"
        case .debug: return "Debug"
        case .support: return "Support"
        default: return title
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
        case .appearance, .general, .history:
            return true
        default:
            return false
        }
    }

    var isBottomBarItem: Bool {
        switch self {
        case .about, .debug, .support:
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
    @State private var isHovered = false

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
                    .fill(isSelected ? SettingsColors.primary : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(description)
    }
}

// MARK: - Profile Credential Cards Row

struct ProfileCredentialCardsRow: View {
    @Binding var selectedSection: SettingsSection
    @StateObject private var profileManager = ProfileManager.shared
    @State private var credentials: ProfileCredentials?

    var body: some View {
        VStack(spacing: 4) {
            // Claude.ai Card
            Button {
                selectedSection = .claudeAI
            } label: {
                CredentialMiniCard(
                    icon: "key.fill",
                    title: "Claude.ai",
                    isConnected: credentials?.hasClaudeAI ?? false,
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
        }
        .onChange(of: profileManager.activeProfile?.id) { _, _ in
            loadCredentials()
        }
    }

    private func loadCredentials() {
        guard let profile = profileManager.activeProfile else { return }
        credentials = try? ProfileStore.shared.loadProfileCredentials(profile.id)
    }
}

struct CredentialMiniCard: View {
    let icon: String
    let title: String
    let isConnected: Bool
    let isSelected: Bool
    @State private var isHovered = false

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
                .fill(isSelected ? SettingsColors.primary : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SettingMiniButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    @State private var isHovered = false

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
                .fill(isSelected ? SettingsColors.primary : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
