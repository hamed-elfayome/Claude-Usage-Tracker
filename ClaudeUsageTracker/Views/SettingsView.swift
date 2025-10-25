import SwiftUI

/// Professional, native macOS Settings interface
struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .api
    @State private var notificationsEnabled: Bool = DataStore.shared.loadNotificationsEnabled()
    @State private var refreshInterval: Double = DataStore.shared.loadRefreshInterval()

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
                case .notifications:
                    NotificationsView(notificationsEnabled: $notificationsEnabled)
                case .about:
                    AboutView()
                }
            }
            .frame(minWidth: 450, maxWidth: .infinity)
        }
        .frame(width: 720, height: 480)
    }
}

enum SettingsSection: String, CaseIterable {
    case api = "API"
    case general = "General"
    case notifications = "Notifications"
    case about = "About"

    var icon: String {
        switch self {
        case .api: return "key.horizontal.fill"
        case .general: return "gearshape.fill"
        case .notifications: return "bell.badge.fill"
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
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 28) {
                Spacer()

                // App Logo
                Image("AboutLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)

                // Info
                VStack(spacing: 6) {
                    Text("Claude Usage Tracker")
                        .font(.system(size: 18, weight: .semibold))

                    Text("Version 1.0.0")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text("Real-time usage monitoring for Claude")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Creator Info
                VStack(spacing: 4) {
                    Text("Created by")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Hamed Elfayome")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 8)

                Spacer()

                // Links
                VStack(spacing: 8) {
                    Button(action: {
                        if let url = URL(string: "https://github.com/hamed-elfayome") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "link")
                            Text("GitHub")
                            Spacer()
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)

                    Button(action: {
                        if let url = URL(string: "mailto:hamedelfayome@gmail.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Email")
                            Spacer()
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 200)
            }
            .padding(28)
        }
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
