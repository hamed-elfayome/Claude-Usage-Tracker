import SwiftUI
import Charts

// MARK: - Always-active vibrancy background
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        // Base vibrancy layer
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)

        // Solid tint overlay for more density
        let tintView = NSView()
        tintView.wantsLayer = true
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
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
        // Update tint for appearance changes
        if let tintView = nsView.subviews.last {
            tintView.wantsLayer = true
            if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            } else {
                tintView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            }
        }
    }
}

/// Native macOS popover interface - minimal, flat, system-style
struct PopoverContentView: View {
    @ObservedObject var manager: MenuBarManager
    let onRefresh: () -> Void
    let onPreferences: () -> Void

    @State private var isRefreshing = false
    @State private var showInsights = false
    // Drives a custom entrance animation. The native NSPopover open animation is
    // disabled (see MenuBarManager) because its animated window resize recurses
    // infinitely on macOS 26/27; this fades/scales the content in from the top
    // instead — a pure SwiftUI transform on a fixed-size view, so it can't trigger
    // the window-resize loop.
    @State private var appeared = false
    @StateObject private var profileManager = ProfileManager.shared

    private func profileInitials(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    // Computed properties for multi-profile mode support
    private var displayUsage: ClaudeUsage {
        manager.clickedProfileUsage ?? manager.usage
    }

    private var displayAPIUsage: APIUsage? {
        // When viewing a non-active profile, use only that profile's API data
        // to avoid leaking the active profile's console data
        if manager.clickedProfileUsage != nil {
            return manager.clickedProfileAPIUsage
        }
        return manager.apiUsage
    }

    private var displayProfile: Profile? {
        Self.resolveDisplayProfile(
            displayMode: profileManager.displayMode,
            clickedProfileID: manager.clickedProfileId,
            profiles: profileManager.profiles,
            activeProfile: profileManager.activeProfile
        )
    }

    private var isCodexProfile: Bool {
        displayProfile?.provider == .codex
    }

    private var isZAIProfile: Bool {
        displayProfile?.provider == .zai
    }

    private var displayCodexUsage: CodexUsage? {
        if profileManager.displayMode == .multi, manager.clickedProfileId != nil {
            return displayProfile?.codexUsage
        }
        return manager.codexUsage
    }

    private var displayZAIUsage: ZAIUsage? {
        if profileManager.displayMode == .multi, manager.clickedProfileId != nil {
            return displayProfile?.zaiUsage
        }
        return manager.zaiUsage
    }

    private var displayStatus: ClaudeStatus {
        if isCodexProfile { return manager.openAIStatus }
        if isZAIProfile { return manager.zaiStatus }
        return manager.status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            SmartHeader(
                usage: displayUsage,
                status: displayStatus,
                profile: displayProfile,
                isRefreshing: isRefreshing,
                onRefresh: refresh,
                onManageProfiles: onPreferences,
                onPreferences: onPreferences,
                clickedProfileId: manager.clickedProfileId
            )

            PopoverDivider()

            // Error / stale data banners
            if isZAIProfile,
               displayProfile?.id == profileManager.activeProfile?.id,
               let refreshError = manager.zaiRefreshError {
                StatusBannerView(
                    icon: "exclamationmark.triangle.fill",
                    message: refreshError,
                    color: .orange
                ) {
                    onRefresh()
                }
            } else if isCodexProfile,
               displayProfile?.id == profileManager.activeProfile?.id,
               let refreshError = manager.codexRefreshError {
                StatusBannerView(
                    icon: "exclamationmark.triangle.fill",
                    message: refreshError,
                    color: .orange
                ) {
                    onRefresh()
                }
            } else if !isCodexProfile && !isZAIProfile && manager.hasCredentialError {
                StatusBannerView(
                    icon: "exclamationmark.triangle.fill",
                    message: "popover.banner.credentials_expired".localized,
                    color: .orange
                ) {
                    onPreferences()
                }
            } else if !isCodexProfile && !isZAIProfile && manager.consecutiveRefreshFailures >= 3 {
                StatusBannerView(
                    icon: "arrow.clockwise.circle.fill",
                    message: String(format: "popover.banner.refresh_failed".localized, manager.consecutiveRefreshFailures),
                    color: .yellow
                ) {
                    onRefresh()
                }
            } else if !isCodexProfile && !isZAIProfile, let lastRefresh = manager.lastSuccessfulRefreshTime,
                      Date().timeIntervalSince(lastRefresh) > 300 {
                let minutesAgo = Int(Date().timeIntervalSince(lastRefresh) / 60)
                StatusBannerView(
                    icon: "clock.fill",
                    message: String(format: "popover.banner.updated_ago".localized, minutesAgo),
                    color: .orange
                ) {
                    onRefresh()
                }
            }

            // Viewing usage tag (shown in multi-profile mode)
            if profileManager.displayMode == .multi,
               let viewingProfile = manager.clickedProfileId.flatMap({ id in
                   profileManager.profiles.first(where: { $0.id == id })
               }) ?? profileManager.activeProfile {
                HStack(spacing: 8) {
                    // Profile initials avatar
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 20, height: 20)

                        Text(profileInitials(for: viewingProfile.name))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                    }

                    Text(viewingProfile.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    if viewingProfile.id == profileManager.activeProfile?.id {
                        Text("Active")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }

            // Usage
            if isZAIProfile {
                ZAIUsageDashboard(
                    usage: displayZAIUsage,
                    settings: displayProfile?.zaiConfiguration ?? ZAIProfileConfiguration(),
                    profile: displayProfile
                )
            } else if isCodexProfile {
                CodexUsageDashboard(
                    usage: displayCodexUsage,
                    settings: displayProfile?.codexConfiguration ?? CodexProfileConfiguration(),
                    profile: displayProfile
                )
            } else {
                SmartUsageDashboard(
                    usage: displayUsage,
                    apiUsage: displayAPIUsage
                )
            }

            // Contextual Insights
            if !isCodexProfile && !isZAIProfile && showInsights {
                PopoverDivider()
                ContextualInsights(usage: displayUsage)
                    .transition(.opacity)
            }

        }
        .padding(.bottom, 8)
        .frame(width: 280)
        .background(VisualEffectBackground())
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private func refresh() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isRefreshing = true
        }
        onRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isRefreshing = false
            }
        }
    }

    static func resolveDisplayProfile(
        displayMode: ProfileDisplayMode,
        clickedProfileID: UUID?,
        profiles: [Profile],
        activeProfile: Profile?
    ) -> Profile? {
        guard displayMode == .multi, let clickedProfileID else {
            return activeProfile
        }
        return profiles.first { $0.id == clickedProfileID } ?? activeProfile
    }
}

// MARK: - Native Divider

struct PopoverDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
    }
}

// MARK: - Profile Switcher Compact (for header)

struct ProfileSwitcherCompact: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isHovered = false
    let onManageProfiles: () -> Void
    var displayedProfile: Profile? = nil

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button(action: {
                    Task {
                        await profileManager.activateProfile(profile.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: profile.provider.icon)
                            .font(.system(size: 12))

                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        HStack(spacing: 4) {
                            if profile.provider == .claude && profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.adaptiveGreen)
                            }

                            if profile.provider == .claude && profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
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
            Text(displayedProfile?.name ?? profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
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
                        Image(systemName: profile.provider.icon)
                            .font(.system(size: 12))

                        Text(profile.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        HStack(spacing: 4) {
                            if profile.provider == .claude && profile.hasCliAccount {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.adaptiveGreen)
                            }

                            if profile.provider == .claude && profile.claudeSessionKey != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }

                            if profile.id == profileManager.activeProfile?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
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
            HStack(spacing: 8) {
                // Profile avatar
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)

                    Text(profileInitials)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(profileManager.activeProfile?.name ?? "popover.no_profile".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

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
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("common.switch".localized)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
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
    let profile: Profile?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onManageProfiles: () -> Void
    let onPreferences: () -> Void
    var clickedProfileId: UUID? = nil

    @StateObject private var profileManager = ProfileManager.shared

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .adaptiveGreen
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .gray: return .gray
        }
    }

    private var isMultiProfileMode: Bool {
        profileManager.displayMode == .multi
    }

    private var clickedProfile: Profile? {
        guard let id = clickedProfileId else { return nil }
        return profileManager.profiles.first { $0.id == id }
    }

    private var statusURL: URL? {
        if profile?.provider == .codex {
            return URL(string: "https://status.openai.com")
        }
        if profile?.provider == .zai {
            return URL(string: "https://z.ai/manage-apikey/subscription")
        }
        return URL(string: "https://status.claude.com")
    }

    private var statusHelp: String {
        if profile?.provider == .codex {
            return "Click to open status.openai.com"
        }
        if profile?.provider == .zai {
            return "Click to open your z.ai subscription"
        }
        return "Click to open status.claude.com"
    }

    private func profileInitials(for name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                ProfileSwitcherCompact(
                    onManageProfiles: onManageProfiles,
                    displayedProfile: profile
                )

                // Status
                Button(action: {
                    if let url = statusURL {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)

                        Text(status.description)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(statusHelp)
            }

            Spacer()

            HStack(alignment: .center, spacing: 2) {
                // Refresh
                HeaderIconButton(
                    icon: "arrow.clockwise",
                    isRefreshing: isRefreshing,
                    action: onRefresh
                )
                .disabled(isRefreshing)

                // Settings
                HeaderIconButton(
                    icon: "gearshape.fill",
                    fontSize: 12,
                    action: onPreferences
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Header Icon Button
struct HeaderIconButton: View {
    let icon: String
    var fontSize: CGFloat = 10.5
    var isRefreshing: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: fontSize, weight: .medium))
                        .imageScale(.medium)
                }
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .frame(width: 24, height: 24, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Smart Usage Dashboard
struct SmartUsageDashboard: View {
    let usage: ClaudeUsage
    let apiUsage: APIUsage?
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var peakHoursService = PeakHoursService.shared

    private var isPeakHours: Bool {
        SharedDataStore.shared.loadPeakHoursIndicatorEnabled() && peakHoursService.isPeakHours
    }

    private var showRemainingPercentage: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showRemainingPercentage
        }
        return profileManager.activeProfile?.iconConfig.showRemainingPercentage ?? false
    }

    private var showTimeMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showTimeMarker
        }
        return profileManager.activeProfile?.iconConfig.showTimeMarker ?? true
    }

    private var usePaceColoring: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.usePaceColoring
        }
        return profileManager.activeProfile?.iconConfig.usePaceColoring ?? true
    }

    private var showPaceMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showPaceMarker
        }
        return profileManager.activeProfile?.iconConfig.showPaceMarker ?? true
    }

    private var timeDisplay: PopoverTimeDisplay {
        SharedDataStore.shared.loadPopoverTimeDisplay()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Primary: Session Usage
            UsageRow(
                title: "menubar.session_usage".localized,
                subtitle: "menubar.5_hour_window".localized,
                usedPercentage: usage.effectiveSessionPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.sessionResetTime,
                periodDuration: Constants.sessionWindow,
                showTimeMarker: showTimeMarker,
                showPaceMarker: showPaceMarker,
                usePaceColoring: usePaceColoring,
                timeDisplay: timeDisplay,
                isPeakHighlighted: isPeakHours
            )

            if usage.designWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.design_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.designWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.designWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            // All Models (Weekly)
            UsageRow(
                title: "menubar.all_models".localized,
                tag: "menubar.weekly".localized,
                subtitle: nil,
                usedPercentage: usage.weeklyPercentage,
                showRemaining: showRemainingPercentage,
                resetTime: usage.weeklyResetTime,
                periodDuration: Constants.weeklyWindow,
                showTimeMarker: showTimeMarker,
                showPaceMarker: showPaceMarker,
                usePaceColoring: usePaceColoring,
                timeDisplay: timeDisplay
            )

            if usage.fableWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.fable_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.fableWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.fableWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            if usage.opusWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.opus_usage".localized,
                    tag: "menubar.weekly".localized,
                    subtitle: nil,
                    usedPercentage: usage.opusWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    periodDuration: nil
                )
            }

            if usage.sonnetWeeklyTokensUsed > 0 {
                UsageRow(
                    title: "menubar.sonnet_usage".localized,
                    subtitle: nil,
                    usedPercentage: usage.sonnetWeeklyPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: usage.sonnetWeeklyResetTime,
                    periodDuration: nil,
                    timeDisplay: timeDisplay
                )
            }

            // Extra usage (cost-based)
            if let used = usage.costUsed, let limit = usage.costLimit, let currency = usage.costCurrency, limit > 0 {
                let usedPercentage = (used / limit) * 100.0
                UsageRow(
                    title: "menubar.extra_usage".localized,
                    subtitle: String(format: "%.2f / %.2f %@", used / 100.0, limit / 100.0, currency),
                    usedPercentage: usedPercentage,
                    showRemaining: showRemainingPercentage,
                    resetTime: nil,
                    periodDuration: nil
                )

                // Overage credit grant balance
                if let balance = usage.overageBalance, let balanceCurrency = usage.overageBalanceCurrency {
                    HStack {
                        Text("popover.overage_balance".localized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f %@", balance / 100.0, balanceCurrency.uppercased()))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.adaptiveGreen)
                    }
                }
            }

            // API Usage
            if let apiUsage = apiUsage {
                APIUsageCard(apiUsage: apiUsage, showRemaining: showRemainingPercentage, timeDisplay: timeDisplay)

                // API Cost Card (only if cost data is available)
                if let costCents = apiUsage.apiTokenCostCents, costCents > 0 {
                    APICostCard(apiUsage: apiUsage)
                }
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Codex Provider Dashboard

struct CodexUsageDashboard: View {
    let usage: CodexUsage?
    let settings: CodexProfileConfiguration
    let profile: Profile?

    @StateObject private var profileManager = ProfileManager.shared

    private var showRemainingPercentage: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showRemainingPercentage
        }
        return profile?.iconConfig.showRemainingPercentage ?? false
    }

    private var showTimeMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showTimeMarker
        }
        return profile?.iconConfig.showTimeMarker ?? true
    }

    private var usePaceColoring: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.usePaceColoring
        }
        return profile?.iconConfig.usePaceColoring ?? true
    }

    private var showPaceMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showPaceMarker
        }
        return profile?.iconConfig.showPaceMarker ?? true
    }

    private var timeDisplay: PopoverTimeDisplay {
        SharedDataStore.shared.loadPopoverTimeDisplay()
    }

    private func orderedRateLimits(_ usage: CodexUsage) -> [CodexRateLimit] {
        guard let selectedID = settings.selectedRateLimitID,
              let selected = usage.rateLimits.first(where: { $0.id == selectedID }) else {
            return usage.rateLimits
        }
        return [selected] + usage.rateLimits.filter { $0.id != selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let usage, !usage.rateLimits.isEmpty {
                ForEach(orderedRateLimits(usage)) { limit in
                    if let window = limit.primary {
                        UsageRow(
                            title: limit.displayName,
                            subtitle: codexWindowDescription(window.windowDurationMinutes),
                            usedPercentage: window.usedPercent,
                            showRemaining: showRemainingPercentage,
                            resetTime: window.resetsAt,
                            periodDuration: window.duration,
                            showTimeMarker: showTimeMarker,
                            showPaceMarker: showPaceMarker,
                            usePaceColoring: usePaceColoring,
                            timeDisplay: timeDisplay
                        )
                    }
                    if let window = limit.secondary {
                        UsageRow(
                            title: "\(limit.displayName) secondary",
                            subtitle: codexWindowDescription(window.windowDurationMinutes),
                            usedPercentage: window.usedPercent,
                            showRemaining: showRemainingPercentage,
                            resetTime: window.resetsAt,
                            periodDuration: window.duration,
                            showTimeMarker: showTimeMarker,
                            showPaceMarker: showPaceMarker,
                            usePaceColoring: usePaceColoring,
                            timeDisplay: timeDisplay
                        )
                    }
                    if let credits = limit.credits, credits.hasCredits {
                        HStack {
                            Text("\(limit.displayName) \("codex.settings.credits".localized.lowercased())")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(
                                credits.unlimited
                                    ? "codex.settings.unlimited".localized
                                    : (credits.balance ?? "codex.settings.available".localized)
                            )
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        }
                    }
                }

                if let lifetimeTokens = usage.tokenUsage?.lifetimeTokens {
                    HStack {
                        Text("codex.settings.lifetime_tokens".localized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(lifetimeTokens.formatted(.number.notation(.compactName)))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("codex.settings.no_usage".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func codexWindowDescription(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        if minutes % (7 * 24 * 60) == 0 {
            let weeks = minutes / (7 * 24 * 60)
            return weeks == 1 ? "7-day window" : "\(weeks)-week window"
        }
        if minutes % (24 * 60) == 0 {
            return "\(minutes / (24 * 60))-day window"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)-hour window"
        }
        return "\(minutes)-minute window"
    }
}

// MARK: - Z.ai Provider Dashboard

struct ZAIUsageDashboard: View {
    let usage: ZAIUsage?
    let settings: ZAIProfileConfiguration
    let profile: Profile?

    @StateObject private var profileManager = ProfileManager.shared

    private var showRemainingPercentage: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showRemainingPercentage
        }
        return profile?.iconConfig.showRemainingPercentage ?? false
    }

    private var showTimeMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showTimeMarker
        }
        return profile?.iconConfig.showTimeMarker ?? true
    }

    private var usePaceColoring: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.usePaceColoring
        }
        return profile?.iconConfig.usePaceColoring ?? true
    }

    private var showPaceMarker: Bool {
        if profileManager.displayMode == .multi {
            return profileManager.multiProfileConfig.showPaceMarker
        }
        return profile?.iconConfig.showPaceMarker ?? true
    }

    private var timeDisplay: PopoverTimeDisplay {
        SharedDataStore.shared.loadPopoverTimeDisplay()
    }

    private func orderedRateLimits(_ usage: ZAIUsage) -> [ZAIRateLimit] {
        guard let selectedID = settings.selectedLimitID,
              let selected = usage.rateLimits.first(where: { $0.id == selectedID }) else {
            return usage.rateLimits
        }
        return [selected] + usage.rateLimits.filter { $0.id != selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let usage, !usage.rateLimits.isEmpty {
                ForEach(orderedRateLimits(usage)) { limit in
                    if let window = limit.primary {
                        UsageRow(
                            title: rowTitle(for: limit),
                            tag: creditsText(window),
                            subtitle: zaiWindowDescription(limit),
                            usedPercentage: window.usedPercent,
                            showRemaining: showRemainingPercentage,
                            resetTime: window.resetsAt,
                            periodDuration: window.duration,
                            showTimeMarker: showTimeMarker,
                            showPaceMarker: showPaceMarker,
                            usePaceColoring: usePaceColoring,
                            timeDisplay: timeDisplay
                        )
                    }
                }

                if let plan = usage.account?.planType {
                    HStack {
                        Text("zai.settings.plan".localized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(plan.capitalized)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("zai.settings.no_usage".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Row headline in the user's terms: the 5-hour quota is the session
    /// metric, the 7-day quota is the weekly one, mirroring Claude rows.
    private func rowTitle(for limit: ZAIRateLimit) -> String {
        if limit.isFiveHourSessionWindow { return "menubar.session_usage".localized }
        if limit.isWeeklyWindow { return "menubar.weekly_usage".localized }
        if limit.kind == .toolCalls { return "zai.window.tools_title".localized }
        return limit.displayName
    }

    /// Compact "used/total" credit summary shown as the row tag.
    private func creditsText(_ window: ZAIRateLimitWindow) -> String? {
        guard let used = window.usedCredits else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        guard let usedText = formatter.string(from: NSNumber(value: used)) else { return nil }
        if let total = window.totalCredits,
           let totalText = formatter.string(from: NSNumber(value: total)) {
            return "\(usedText)/\(totalText)"
        }
        return usedText
    }

    private func zaiWindowDescription(_ limit: ZAIRateLimit) -> String? {
        if limit.isFiveHourSessionWindow { return "zai.window.session".localized }
        if limit.isWeeklyWindow { return "zai.window.weekly".localized }
        if limit.kind == .toolCalls { return "zai.window.tools".localized }
        return nil
    }
}

// MARK: - Usage Row (flat, native style)
struct UsageRow: View {
    let title: String
    var tag: String? = nil
    let subtitle: String?
    let usedPercentage: Double
    let showRemaining: Bool
    let resetTime: Date?
    let periodDuration: TimeInterval?
    var showTimeMarker: Bool = true
    var showPaceMarker: Bool = true
    var usePaceColoring: Bool = true
    var timeDisplay: PopoverTimeDisplay = .resetTime
    var isPeakHighlighted: Bool = false

    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining
        )
    }

    private var rawElapsedFraction: Double? {
        UsageStatusCalculator.elapsedFraction(
            resetTime: resetTime,
            duration: periodDuration ?? 0,
            showRemaining: false
        )
    }

    private var timeMarkerFraction: CGFloat? {
        guard showTimeMarker, let f = rawElapsedFraction else { return nil }
        return CGFloat(showRemaining ? 1.0 - f : f)
    }

    private var paceStatus: PaceStatus? {
        guard showPaceMarker, let elapsed = rawElapsedFraction else { return nil }
        return PaceStatus.calculate(usedPercentage: usedPercentage, elapsedFraction: elapsed)
    }

    private var timeMarkerColor: Color {
        if let pace = paceStatus {
            return pace.swiftUIColor
        }
        return Color(nsColor: .labelColor)
    }

    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: usedPercentage,
            showRemaining: showRemaining,
            elapsedFraction: usePaceColoring ? rawElapsedFraction : nil
        )
    }

    private var statusColor: Color {
        switch statusLevel {
        case .safe: return .adaptiveGreen
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title row with percentage
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        if let tag = tag {
                            Text(tag)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("\(Int(displayPercentage))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(statusColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(statusColor)
                        .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                        .animation(.easeInOut(duration: 0.6), value: displayPercentage)
                }
                .overlay(alignment: .leading) {
                    if let fraction = timeMarkerFraction {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(timeMarkerColor)
                            .frame(width: 2.5, height: 8)
                            .offset(x: round(geometry.size.width * fraction) - 0.75)
                    }
                }
            }
            .frame(height: 4)

            // Reset time
            if let reset = resetTime {
                Text(resetTimeText(for: reset))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isPeakHighlighted ? Color.red.opacity(0.6) : Color.primary.opacity(0.1),
                    lineWidth: isPeakHighlighted ? 1.5 : 0.5
                )
        )
    }

    private func resetTimeText(for reset: Date) -> String {
        switch timeDisplay {
        case .resetTime:
            return "menubar.resets_time".localized(with: reset.resetTimeString())
        case .remainingTime:
            return "menubar.resets_in".localized(with: reset.timeRemainingString())
        case .both:
            return "menubar.resets_both".localized(with: reset.timeRemainingString(), reset.resetTimeString())
        }
    }
}

// MARK: - Contextual Insights
struct ContextualInsights: View {
    let usage: ClaudeUsage

    private var insights: [Insight] {
        var result: [Insight] = []

        if usage.effectiveSessionPercentage > 80 {
            result.append(Insight(
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                title: "usage.high_session".localized,
                description: "usage.high_session.desc".localized
            ))
        }

        if usage.weeklyPercentage > 90 {
            result.append(Insight(
                icon: "clock.fill",
                color: .red,
                title: "usage.weekly_approaching".localized,
                description: "usage.weekly_approaching.desc".localized
            ))
        }

        if usage.effectiveSessionPercentage < 20 && usage.weeklyPercentage < 30 {
            result.append(Insight(
                icon: "checkmark.circle.fill",
                color: .adaptiveGreen,
                title: "usage.efficient".localized,
                description: "usage.efficient.desc".localized
            ))
        }

        return result
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(insights, id: \.title) { insight in
                HStack(spacing: 8) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 11))
                        .foregroundColor(insight.color)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)

                        Text(insight.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 4)
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

    var body: some View {
        HStack {
            Spacer()
            SmartActionButton(
                icon: "gearshape.fill",
                title: "common.settings".localized,
                action: onPreferences
            )
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Claude Status Row
struct ClaudeStatusRow: View {
    let status: ClaudeStatus
    @State private var isHovered = false

    private var statusColor: Color {
        switch status.indicator.color {
        case .green: return .adaptiveGreen
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
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(status.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help("Click to open status.claude.com")
    }
}

// MARK: - Smart Action Button (kept for backward compatibility)
struct SmartActionButton: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isDestructive ? .red : (isHovered ? .primary : .secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - API Cost Card
struct APICostCard: View {
    let apiUsage: APIUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("API Cost")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("This Month")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Total cost
                if let formatted = apiUsage.formattedAPICost {
                    Text(formatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }

            // Daily cost chart
            DailyCostChart(dailyCosts: apiUsage.sortedDailyCosts, currency: apiUsage.currency)

            // Per-key breakdown (if multiple sources) or flat model list
            if apiUsage.hasMultipleSources {
                VStack(spacing: 6) {
                    ForEach(apiUsage.sortedCostSources) { source in
                        APICostSourceRow(source: source, currency: apiUsage.currency)
                    }
                }
            } else {
                // Single source or no source data — show flat model breakdown
                let models = apiUsage.sortedModelCosts
                if !models.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(models, id: \.model) { item in
                            HStack {
                                Text(item.model)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Text(item.cost)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Daily Cost Chart
struct DailyCostChart: View {
    let dailyCosts: [(date: Date, cents: Double)]
    let currency: String

    private struct DayCost: Identifiable {
        let id: Date
        let dollars: Double
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let today = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        // End of today (start of tomorrow)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today))!
        return startOfMonth ... endOfToday
    }

    var body: some View {
        if !dailyCosts.isEmpty {
            let data = dailyCosts.map { DayCost(id: $0.date, dollars: $0.cents / 100.0) }
            let maxValue = data.map(\.dollars).max() ?? 0
            Chart(data) { item in
                BarMark(
                    x: .value("Day", item.id, unit: .day),
                    y: .value("Cost", item.dollars),
                    width: .fixed(12)
                )
                .foregroundStyle(Color.orange.opacity(0.75))
                .cornerRadius(2)
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatDollars(v, max: maxValue))
                                .font(.system(size: 7, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .chartYScale(domain: 0 ... max(maxValue * 1.15, 0.01))
            .frame(height: 80)
        }
    }

    private func formatDollars(_ amount: Double, max: Double) -> String {
        if max >= 100 {
            return "$\(Int(amount))"
        } else if max >= 1 {
            return String(format: "$%.1f", amount)
        } else {
            return String(format: "$%.2f", amount)
        }
    }
}

// MARK: - API Cost Source Row
struct APICostSourceRow: View {
    let source: APICostSource
    let currency: String
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 4) {
            // Source header (tappable to expand)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: source.sourceType.icon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Text(source.keyName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(source.formattedTotal(currency: currency))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)

            // Expanded model breakdown
            if isExpanded {
                let models = source.sortedModelCosts(currency: currency)
                VStack(spacing: 3) {
                    ForEach(models, id: \.model) { item in
                        HStack {
                            Text(item.model)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(item.cost)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - API Usage Card
struct APIUsageCard: View {
    let apiUsage: APIUsage
    let showRemaining: Bool
    var timeDisplay: PopoverTimeDisplay = .resetTime

    private var displayPercentage: Double {
        UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: apiUsage.usagePercentage,
            showRemaining: showRemaining
        )
    }

    private var statusLevel: UsageStatusLevel {
        UsageStatusCalculator.calculateStatus(
            usedPercentage: apiUsage.usagePercentage,
            showRemaining: showRemaining
        )
    }

    private var usageColor: Color {
        switch statusLevel {
        case .safe: return .adaptiveGreen
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("menubar.api_credits".localized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text("menubar.anthropic_console".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(Int(displayPercentage))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(usageColor)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(usageColor)
                        .frame(width: geometry.size.width * min(displayPercentage / 100.0, 1.0))
                        .animation(.easeInOut(duration: 0.6), value: displayPercentage)
                }
            }
            .frame(height: 4)

            // Used / Remaining
            HStack {
                Text(apiUsage.formattedUsed)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text(apiUsage.formattedRemaining)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // Reset Time
            if apiUsage.resetsAt > Date() {
                Text(resetTimeText(for: apiUsage.resetsAt))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func resetTimeText(for reset: Date) -> String {
        switch timeDisplay {
        case .resetTime:
            return "menubar.resets_time".localized(with: reset.resetTimeString())
        case .remainingTime:
            return "menubar.resets_in".localized(with: reset.timeRemainingString())
        case .both:
            return "menubar.resets_both".localized(with: reset.timeRemainingString(), reset.resetTimeString())
        }
    }
}

// MARK: - Status Banner View
struct StatusBannerView: View {
    let icon: String
    let message: String
    let color: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .onTapGesture { onTap?() }
    }
}
