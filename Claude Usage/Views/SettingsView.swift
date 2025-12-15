import SwiftUI
import UserNotifications

/// Professional, native macOS Settings interface
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .api
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
                case .api:
                    APIView()
                case .general:
                    GeneralView(refreshInterval: $refreshInterval)
                case .session:
                    SessionView(autoStartSessionEnabled: $autoStartSessionEnabled)
                case .notifications:
                    NotificationsView(notificationsEnabled: $notificationsEnabled)
                case .claudeCode:
                    StatuslineView()
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
    case api = "API"
    case general = "General"
    case session = "Session"
    case notifications = "Notifications"
    case claudeCode = "Claude Code"
    case about = "About"

    var icon: String {
        switch self {
        case .api: return "key.horizontal.fill"
        case .general: return "gearshape.fill"
        case .session: return "clock.arrow.circlepath"
        case .notifications: return "bell.badge.fill"
        case .claudeCode: return "chevron.left.forwardslash.chevron.right"
        case .about: return "info.circle.fill"
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
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }
            Spacer()
        }
        .padding(.top, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - API View

struct APIView: View {
    @State private var sessionKey: String = ""
    @State private var isValidating: Bool = false
    @State private var validationState: ValidationState = .idle
    @State private var showWizard = false

    private let apiService = ClaudeAPIService()

    enum ValidationState {
        case idle
        case validating
        case success(String)
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                HStack(spacing: 16) {
                    // App Logo
                    Image("HeaderLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Setup")
                            .font(.system(size: 20, weight: .semibold))

                        Text("Configure your Claude session key for real-time usage tracking")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }

                Divider()

                // Session Key Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Session Key")
                        .font(.system(size: 13, weight: .medium))

                    TextField("sk-ant-sid-...", text: $sessionKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )

                    Text("Paste your sessionKey cookie from claude.ai DevTools")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Actions
                HStack(spacing: 10) {
                    Button(action: saveKey) {
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 70)
                    }
                    .disabled(sessionKey.isEmpty)

                    Button(action: testKey) {
                        if case .validating = validationState {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 70)
                        } else {
                            Text("Test")
                                .font(.system(size: 12))
                                .frame(width: 70)
                        }
                    }
                    .disabled(sessionKey.isEmpty)

                    Spacer()
                }
                .buttonStyle(.bordered)

                // Validation Feedback
                if case .success(let message) = validationState {
                    StatusBox(message: message, type: .success)
                } else if case .error(let message) = validationState {
                    StatusBox(message: message, type: .error)
                }

                Divider()

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 10) {
                        Button(action: { showWizard = true }) {
                            Label("Setup Wizard", systemImage: "wand.and.stars")
                                .font(.system(size: 12))
                        }

                        Button(action: {
                            if let url = URL(string: "https://claude.ai") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Label("Open claude.ai", systemImage: "safari")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(28)
        }
        .sheet(isPresented: $showWizard) {
            SetupWizardView()
        }
    }

    private func saveKey() {
        do {
            try apiService.saveSessionKey(sessionKey)
            validationState = .success("Session key saved")
            sessionKey = ""
        } catch {
            validationState = .error("Failed to save key")
        }
    }

    private func testKey() {
        validationState = .validating

        Task {
            do {
                let orgId = try await apiService.fetchOrganizationId()
                await MainActor.run {
                    validationState = .success("Connected to \(orgId)")
                }
            } catch {
                await MainActor.run {
                    validationState = .error("Connection failed")
                }
            }
        }
    }
}

// MARK: - General View

struct GeneralView: View {
    @Binding var refreshInterval: Double
    @State private var checkOverageLimitEnabled: Bool = DataStore.shared.loadCheckOverageLimitEnabled()

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("General")
                    .font(.system(size: 20, weight: .semibold))

                Text("Configure app behavior and preferences")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Refresh Interval
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Refresh Interval")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Text("\(Int(refreshInterval))s")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Slider(value: $refreshInterval, in: 5...120, step: 1)
                    .onChange(of: refreshInterval) { _, newValue in
                        DataStore.shared.saveRefreshInterval(newValue)
                    }

                Text("How often to check for usage updates")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Check Overage Limit Toggle
            Toggle(isOn: $checkOverageLimitEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check Extra Usage Limit")
                        .font(.system(size: 13, weight: .medium))

                    Text("Fetch and display monthly cost and overage limit information")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: checkOverageLimitEnabled) { _, newValue in
                DataStore.shared.saveCheckOverageLimitEnabled(newValue)
            }

            Spacer()
        }
        .padding(28)
    }
}

// MARK: - Session View

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SessionView: View {
    @Binding var autoStartSessionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Management")
                    .font(.system(size: 20, weight: .semibold))

                Text("Automatically manage your Claude usage sessions")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Auto-start session toggle
            Toggle(isOn: $autoStartSessionEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Auto-start session on reset")
                            .font(.system(size: 13, weight: .medium))

                        // BETA badge
                        Text("BETA")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange)
                            )
                    }

                    Text("Automatically initialize a new session when the current session resets")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: autoStartSessionEnabled) { _, newValue in
                DataStore.shared.saveAutoStartSessionEnabled(newValue)
            }

            // Explanation card
            VStack(alignment: .leading, spacing: 16) {
                Label {
                    Text("How it works")
                        .font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FeatureItem(
                        icon: "clock.arrow.circlepath",
                        title: "Automatic Detection",
                        description: "Monitors your session usage and detects when it resets to 0%"
                    )

                    FeatureItem(
                        icon: "paperplane.fill",
                        title: "Instant Initialization",
                        description: "Sends a simple 'Hi' message to Claude 3.5 Haiku (cheapest model)"
                    )

                    FeatureItem(
                        icon: "checkmark.circle.fill",
                        title: "Fresh Session Ready",
                        description: "Your new 5-hour session is immediately active and ready to use"
                    )
                }

                Divider()
                    .padding(.vertical, 4)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))

                    Text("This feature uses minimal tokens (just 'Hi') to initialize your session, ensuring you're always ready to chat with Claude without manual intervention.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Spacer()
        }
        .padding(28)
    }
}

// MARK: - Notifications View

struct NotificationsView: View {
    @Binding var notificationsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications")
                    .font(.system(size: 20, weight: .semibold))

                Text("Get alerts when approaching usage limits")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Toggle
            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable notifications")
                        .font(.system(size: 13, weight: .medium))

                    Text("Alerts at 75%, 90%, 95% usage, and session resets")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: notificationsEnabled) { _, newValue in
                DataStore.shared.saveNotificationsEnabled(newValue)

                // Send test notification when notifications are enabled
                if newValue {
                    Task {
                        let center = UNUserNotificationCenter.current()
                        let settings = await center.notificationSettings()

                        if settings.authorizationStatus == .authorized {
                            NotificationManager.shared.sendSimpleAlert(type: .notificationsEnabled)
                        } else if settings.authorizationStatus == .notDetermined {
                            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                            if granted == true {
                                NotificationManager.shared.sendSimpleAlert(type: .notificationsEnabled)
                            }
                        }
                    }
                }
            }

            if notificationsEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    ThresholdItem(level: "75%", color: .yellow, label: "Warning")
                    ThresholdItem(level: "90%", color: .orange, label: "High")
                    ThresholdItem(level: "95%", color: .red, label: "Critical")
                    ThresholdItem(level: "0%", color: .green, label: "Session Reset")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            Spacer()
        }
        .padding(28)
    }
}

// MARK: - About View

struct AboutView: View {
    @State private var contributors: [Contributor] = []
    @State private var isLoadingContributors = false
    @State private var contributorsError: String?

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 26) {
                // App Info Section
                VStack(spacing: 16) {
                    Image("AboutLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    VStack(spacing: 4) {
                        Text("Claude Usage Tracker")
                            .font(.system(size: 18, weight: .semibold))

                        Text("Version \(appVersion)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Text("Real-time usage monitoring for Claude AI")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Creator Section
                VStack(spacing: 8) {
                    Text("Created by")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button(action: {
                        if let url = URL(string: "https://github.com/hamed-elfayome") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Hamed Elfayome")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Contributors Section
                VStack(spacing: 16) {
                    HStack {
                        Text("Contributors")
                            .font(.system(size: 13, weight: .semibold))

                        if !contributors.isEmpty {
                            Text("\(contributors.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if isLoadingContributors {
                        ContributorsLoadingView()
                    } else if let error = contributorsError {
                        ContributorsErrorView(error: error) {
                            fetchContributors()
                        }
                    } else if contributors.isEmpty {
                        EmptyContributorsView()
                    } else {
                        ContributorsGridView(contributors: contributors)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Links Section
                HStack(spacing: 12) {
                    Button(action: {
                        if let url = URL(string: "https://github.com/hamed-elfayome/Claude-Usage-Tracker") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))

                            Text("Star on GitHub")
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        if let url = URL(string: "mailto:hamedelfayome@gmail.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 11))

                            Text("Send Feedback")
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear {
            if contributors.isEmpty && !isLoadingContributors {
                fetchContributors()
            }
        }
    }

    private func fetchContributors() {
        isLoadingContributors = true
        contributorsError = nil

        Task {
            do {
                let fetchedContributors = try await GitHubService.shared.fetchContributors()
                await MainActor.run {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        self.contributors = fetchedContributors
                        self.isLoadingContributors = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.contributorsError = error.localizedDescription
                    self.isLoadingContributors = false
                }
            }
        }
    }
}

// MARK: - Contributors Grid View

struct ContributorsGridView: View {
    let contributors: [Contributor]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 44, maximum: 48), spacing: 10)
        ], spacing: 10) {
            ForEach(contributors) { contributor in
                ContributorAvatar(contributor: contributor)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Contributor Avatar

struct ContributorAvatar: View {
    let contributor: Contributor
    @State private var isHovered = false
    @State private var imageData: Data?
    @State private var isLoadingImage = true

    var body: some View {
        Button(action: {
            if let url = URL(string: contributor.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }) {
            ZStack {
                if let data = imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else if isLoadingImage {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary.opacity(0.3))
                        )
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isHovered ? 1 : 0)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help(contributor.login)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            loadAvatar()
        }
    }

    private func loadAvatar() {
        guard let url = URL(string: contributor.avatarUrl) else {
            isLoadingImage = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    self.imageData = data
                    self.isLoadingImage = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }
}

// MARK: - Loading View

struct ContributorsLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading contributors...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Error View

struct ContributorsErrorView: View {
    let error: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)

            Text("Failed to load contributors")
                .font(.system(size: 12, weight: .medium))

            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Empty View

struct EmptyContributorsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No contributors found")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Supporting Views

struct StatusBox: View {
    let message: String
    let type: StatusType

    enum StatusType {
        case success, error

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12))
        }
        .foregroundColor(type.color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(type.color.opacity(0.1))
        )
    }
}

struct ThresholdItem: View {
    let level: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(level)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
    }
}

// MARK: - Statusline View

/// Settings view for configuring Claude Code statusline integration.
/// Allows users to select which components to display and apply/reset the configuration.
struct StatuslineView: View {
    // Component visibility settings
    @State private var showDirectory: Bool = DataStore.shared.loadStatuslineShowDirectory()
    @State private var showBranch: Bool = DataStore.shared.loadStatuslineShowBranch()
    @State private var showUsage: Bool = DataStore.shared.loadStatuslineShowUsage()
    @State private var showProgressBar: Bool = DataStore.shared.loadStatuslineShowProgressBar()

    // Status feedback
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code Statusline")
                    .font(.system(size: 20, weight: .semibold))

                Text("Customize your terminal statusline display")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Preview Card (keep as is - user loves it!)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Live Preview", systemImage: "eye.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text("Updates in real-time")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(generatePreview())
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
                                )
                        )

                    Text("This is how your statusline will appear in Claude Code")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            // Components - Simple and clean
            VStack(alignment: .leading, spacing: 10) {
                Text("Display Components")
                    .font(.system(size: 13, weight: .semibold))

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Directory name", isOn: $showDirectory)
                        .font(.system(size: 12))

                    Toggle("Git branch", isOn: $showBranch)
                        .font(.system(size: 12))

                    Toggle("Usage statistics", isOn: $showUsage)
                        .font(.system(size: 12))

                    if showUsage {
                        HStack(spacing: 0) {
                            Spacer().frame(width: 20)
                            Toggle("Progress bar", isOn: $showProgressBar)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Action buttons - compact
            HStack(spacing: 10) {
                Button(action: applyConfiguration) {
                    Text("Apply")
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)

                Button(action: resetConfiguration) {
                    Text("Reset")
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 70)
                }
                .buttonStyle(.bordered)
            }

            // Status message
            if let message = statusMessage {
                HStack(spacing: 10) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isSuccess ? .green : .red)

                    Text(message)
                        .font(.system(size: 12))

                    Spacer()

                    Button(action: { statusMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((isSuccess ? Color.green : Color.red).opacity(0.1))
                )
            }

            // Info - minimal
            VStack(alignment: .leading, spacing: 6) {
                Text("Requirements")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("• Session key configured in API tab")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("• Restart Claude Code after applying changes")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(28)
    }

    // MARK: - Actions

    /// Applies the current configuration to Claude Code statusline.
    /// Installs scripts, updates config file, and enables statusline in settings.json.
    private func applyConfiguration() {
        // Validate: at least one component must be selected
        guard showDirectory || showBranch || showUsage else {
            statusMessage = "Please select at least one component to display"
            isSuccess = false
            return
        }

        // Validate: session key must be configured
        guard StatuslineService.shared.hasValidSessionKey() else {
            statusMessage = "Session key not configured. Please set it in the General tab first."
            isSuccess = false
            return
        }

        // Save user preferences
        DataStore.shared.saveStatuslineShowDirectory(showDirectory)
        DataStore.shared.saveStatuslineShowBranch(showBranch)
        DataStore.shared.saveStatuslineShowUsage(showUsage)
        DataStore.shared.saveStatuslineShowProgressBar(showProgressBar)

        do {
            // Install scripts to ~/.claude/
            try StatuslineService.shared.installScripts()

            // Write configuration file
            try StatuslineService.shared.updateConfiguration(
                showDirectory: showDirectory,
                showBranch: showBranch,
                showUsage: showUsage,
                showProgressBar: showProgressBar
            )

            // Update Claude Code settings.json
            try StatuslineService.shared.updateClaudeCodeSettings(enabled: true)

            statusMessage = "Configuration applied! Restart Claude Code to see changes."
            isSuccess = true
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isSuccess = false
        }
    }

    /// Disables the statusline by removing it from Claude Code settings.json.
    private func resetConfiguration() {
        do {
            try StatuslineService.shared.updateClaudeCodeSettings(enabled: false)
            statusMessage = "Statusline disabled. Restart Claude Code."
            isSuccess = true
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isSuccess = false
        }
    }

    /// Generates a preview of what the statusline will look like based on current selections.
    private func generatePreview() -> String {
        var parts: [String] = []

        if showDirectory {
            parts.append("claude-usage")
        }

        if showBranch {
            parts.append("⎇ main")
        }

        if showUsage {
            parts.append(showProgressBar ? "Usage: 29% ▓▓▓░░░░░░░" : "Usage: 29%")
        }

        return parts.isEmpty ? "No components selected" : parts.joined(separator: " │ ")
    }
}
