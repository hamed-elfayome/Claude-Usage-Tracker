import SwiftUI

/// Smart, minimal, and professional popover interface
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void
    let onQuit: () -> Void

    @State private var isRefreshing = false
    @State private var showInsights = false
    @StateObject private var profileManager = ProfileManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Smart Header with Status and Profile Switcher
            SmartHeader(
                usage: manager.usage,
                status: manager.status,
                isRefreshing: isRefreshing,
                onRefresh: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isRefreshing = true
                    }
                    onRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRefreshing = false
                        }
                    }
                },
                onManageProfiles: onPreferences
            )

            // Intelligent Usage Dashboard
            SmartUsageDashboard(usage: manager.usage, apiUsage: manager.apiUsage)

            // Contextual Insights
            if showInsights {
                ContextualInsights(usage: manager.usage)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }

            // Smart Footer with Actions
            SmartFooter(
                usage: manager.usage,
                status: manager.status,
                showInsights: $showInsights,
                onPreferences: onPreferences,
                onQuit: onQuit
            )
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 10)
    }
}

// MARK: - Profile Switcher Compact (for header)

struct ProfileSwitcherCompact: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isHovered = false
    let onManageProfiles: () -> Void

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button(action: {
                    Task {
                        await profileManager.activateProfile(profile.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        // Profile icon
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))

                        // Profile name
                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        // Badges
                        HStack(spacing: 4) {
                            // CLI Account badge
                            if profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }

                            // Claude.ai badge
                            if profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            // Active indicator
                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: onManageProfiles) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("popover.manage_profiles".localized)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Status badges
                if profileManager.activeProfile?.hasCliAccount == true || profileManager.activeProfile?.claudeSessionKey != nil {
                    HStack(spacing: 3) {
                        if profileManager.activeProfile?.hasCliAccount == true {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                        }
                        if profileManager.activeProfile?.claudeSessionKey != nil {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Profile Switcher Bar

struct ProfileSwitcherBar: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isHovered = false
    let onManageProfiles: () -> Void

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button(action: {
                    Task {
                        await profileManager.activateProfile(profile.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        // Profile icon
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))

                        // Profile name
                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        // Badges
                        HStack(spacing: 4) {
                            // CLI Account badge
                            if profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.green)
                            }

                            // Claude.ai badge
                            if profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            // Active indicator
                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            Divider()

            Button(action: onManageProfiles) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("popover.manage_profiles".localized)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Profile avatar with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Text(profileInitials)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }

                // Profile info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        // Status badges
                        HStack(spacing: 3) {
                            if profileManager.activeProfile?.hasCliAccount == true {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                            }
                            if profileManager.activeProfile?.claudeSessionKey != nil {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        if profileManager.profiles.count > 1 {
                            Text(String(format: "popover.profiles_count".localized, profileManager.profiles.count))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            Text("popover.profile_count_singular".localized)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        Text("•")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("common.switch".localized)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .rotationEffect(.degrees(isHovered ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isHovered
                        ? Color.accentColor.opacity(0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isHovered
                                ? Color.accentColor.opacity(0.3)
                                : Color.secondary.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var profileInitials: String {
        guard let name = profileManager.activeProfile?.name else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}

// MARK: - Smart Header Component
struct SmartHeader: View {
    let usage: ClaudeUsage
    let status: ClaudeStatus
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onManageProfiles: () -> Void

    @StateObject private var profileManager = ProfileManager.shared

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // App Logo
            HStack(spacing: 8) {
                Image("HeaderLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    // Profile Switcher replacing title
                    ProfileSwitcherCompact(onManageProfiles: onManageProfiles)

                    // Claude Status Badge
                    Button(action: {
                        if let url = URL(string: "https://status.claude.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)

                            Text(status.description)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(statusColor.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Click to open status.claude.com")
                }
            }

            Spacer()

            // Smart Refresh Button
            Button(action: onRefresh) {
                ZStack {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(.secondary)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: ClaudeUsage
    let apiUsage: APIUsage?
    @StateObject private var profileManager = ProfileManager.shared

    // Check if API tracking is enabled globally
    private var isAPITrackingEnabled: Bool {
        DataStore.shared.loadAPITrackingEnabled()
    }

    var body: some View {
        VStack(spacing: 16) {
            // Primary Usage Card
            SmartUsageCard(
                title: "menubar.session_usage".localized,
                subtitle: "menubar.5_hour_window".localized,
                percentage: usage.sessionPercentage,
                resetTime: usage.sessionResetTime,
                isPrimary: true
            )

            // Secondary Usage Cards
            HStack(spacing: 12) {
                SmartUsageCard(
                    title: "menubar.all_models".localized,
                    subtitle: "menubar.weekly".localized,
                    percentage: usage.weeklyPercentage,
                    resetTime: usage.weeklyResetTime,
                    isPrimary: false
                )

                if usage.opusWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "menubar.opus_usage".localized,
                        subtitle: "menubar.weekly".localized,
                        percentage: usage.opusWeeklyPercentage,
                        resetTime: nil,
                        isPrimary: false
                    )
                }

                if usage.sonnetWeeklyTokensUsed > 0 {
                    SmartUsageCard(
                        title: "menubar.sonnet_usage".localized,
                        subtitle: "menubar.weekly".localized,
                        percentage: usage.sonnetWeeklyPercentage,
                        resetTime: usage.sonnetWeeklyResetTime,
                        isPrimary: false
                    )
                }
            }

            if let used = usage.costUsed, let limit = usage.costLimit, let currency = usage.costCurrency, limit > 0 {
                let percentage = (used / limit) * 100.0
                SmartUsageCard(
                    title: "menubar.extra_usage".localized,
                    subtitle: String(format: "%.2f / %.2f %@", used / 100.0, limit / 100.0, currency),
                    percentage: percentage,
                    resetTime: nil,
                    isPrimary: false
                )
            }

            // API Usage Card (only if tracking is enabled AND profile has credentials)
            if isAPITrackingEnabled,
               let apiUsage = apiUsage,
               let profile = profileManager.activeProfile,
               profile.hasAPIConsole {
                APIUsageCard(apiUsage: apiUsage)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Smart Usage Card
struct SmartUsageCard: View {
    let title: String
    let subtitle: String
    let percentage: Double
    let resetTime: Date?
    let isPrimary: Bool

    private var statusColor: Color {
        switch percentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    private var statusIcon: String {
        switch percentage {
        case 0..<50: return "checkmark.circle.fill"
        case 50..<80: return "exclamationmark.triangle.fill"
        default: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: isPrimary ? 12 : 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: isPrimary ? 13 : 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.system(size: isPrimary ? 10 : 9, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: isPrimary ? 12 : 10, weight: .medium))
                        .foregroundColor(statusColor)

                    Text("\(Int(percentage))%")
                        .font(.system(size: isPrimary ? 16 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                }
            }

            // Progress visualization
            VStack(spacing: 6) {
                // Animated progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(percentage / 100.0, 1.0))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .animation(.easeInOut(duration: 0.8), value: percentage)
                    }
                }
                .frame(height: 8)

                // Reset time information
                if let reset = resetTime {
                    HStack {
                        Spacer()
                        Text("menubar.resets_time".localized(with: reset.resetTimeString()))
                            .font(.system(size: isPrimary ? 9 : 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(isPrimary ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - Contextual Insights
struct ContextualInsights: View {
    let usage: ClaudeUsage

    private var insights: [Insight] {
        var result: [Insight] = []

        // Session insights
        if usage.sessionPercentage > 80 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: "usage.high_session".localized,
                description: "usage.high_session.desc".localized
            ))
        }

        // Weekly insights
        if usage.weeklyPercentage > 90 {
            result.append(Insight(
                icon: "clock.fill",
                color: .red,
                title: "usage.weekly_approaching".localized,
                description: "usage.weekly_approaching.desc".localized
            ))
        }

        // Efficiency insights
        if usage.sessionPercentage < 20 && usage.weeklyPercentage < 30 {
            result.append(Insight(
                icon: "checkmark.circle.fill",
                color: .green,
                title: "usage.efficient".localized,
                description: "usage.efficient.desc".localized
            ))
        }

        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(insights, id: \.title) { insight in
                HStack(spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(insight.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(insight.description)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(insight.color.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct Insight {
    let icon: String
    let color: Color
    let title: String
    let description: String
}

// MARK: - Smart Footer
struct SmartFooter: View {
    let usage: ClaudeUsage
    let status: ClaudeStatus
    @Binding var showInsights: Bool
    let onPreferences: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            // Action buttons
            HStack(spacing: 8) {
                SmartActionButton(
                    icon: "gearshape.fill",
                    title: "common.settings".localized,
                    action: onPreferences
                )

                SmartActionButton(
                    icon: "power",
                    title: "common.quit".localized,
                    isDestructive: true,
                    action: onQuit
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Claude Status Row
struct ClaudeStatusRow: View {
    let status: ClaudeStatus
    @State private var isHovered = false

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    var body: some View {
        Button(action: {
            if let url = URL(string: "https://status.claude.com") {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 8) {
                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Status text
                Text(status.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // External link icon
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help("Click to open status.claude.com")
    }
}

// MARK: - Smart Action Button
struct SmartActionButton: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .secondary)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isHovered
                        ? (isDestructive ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - API Usage Card
struct APIUsageCard: View {
    let apiUsage: APIUsage

    private var usageColor: Color {
        switch apiUsage.usagePercentage {
        case 0..<50: return .green
        case 50..<80: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("menubar.api_credits".localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("menubar.anthropic_console".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Percentage
                Text("\(Int(apiUsage.usagePercentage))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(usageColor)
            }

            // Progress Bar
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(usageColor)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: apiUsage.usagePercentage / 100.0, y: 1.0, anchor: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 8)

            // Used / Remaining
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("menubar.used".localized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(apiUsage.formattedUsed)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("menubar.remaining".localized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(apiUsage.formattedRemaining)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }

            // Reset Time
            if apiUsage.resetsAt > Date() {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Text("menubar.resets_time".localized(with: apiUsage.resetsAt.formatted(.relative(presentation: .named))))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(usageColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
