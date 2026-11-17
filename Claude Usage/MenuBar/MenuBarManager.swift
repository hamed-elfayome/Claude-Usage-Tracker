import Cocoa
import SwiftUI
import Combine

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?  // Legacy - kept for backwards compatibility
    private var statusBarUIManager: StatusBarUIManager?
    private var refreshTimer: Timer?
    @Published private(set) var usage: ClaudeUsage = .empty
    @Published private(set) var status: ClaudeStatus = .unknown
    @Published private(set) var apiUsage: APIUsage?
    @Published private(set) var isRefreshing: Bool = false

    // Error tracking for stale data / credential banners
    @Published private(set) var hasCredentialError: Bool = false
    @Published private(set) var consecutiveRefreshFailures: Int = 0
    @Published private(set) var lastRefreshError: String? = nil
    @Published private(set) var lastSuccessfulRefreshTime: Date? = nil

    // Multi-profile mode: track which profile's icon was clicked
    @Published private(set) var clickedProfileId: UUID?
    @Published private(set) var clickedProfileUsage: ClaudeUsage?
    @Published private(set) var clickedProfileAPIUsage: APIUsage?

    // Track when refresh was last triggered (for distinguishing user vs auto refresh)
    private var lastRefreshTriggerTime: Date = .distantPast

    // Track last known reset times for history recording
    private var lastKnownSessionResetTime: [UUID: Date] = [:]
    private var lastKnownWeeklyResetTime: [UUID: Date] = [:]
    private var lastKnownAPIResetTime: [UUID: Date] = [:]

    // Track if a reset was just recorded to prevent duplicate periodic snapshots
    private var resetJustRecorded: [UUID: (session: Bool, weekly: Bool)] = [:]

    // Popover for beautiful SwiftUI interface
    private var popover: NSPopover?

    // Event monitor for closing popover on outside click
    private var eventMonitor: Any?

    // Timestamp of the most recent popover close. Used to debounce the
    // status-item click that dismisses the popover: that same click also fires
    // togglePopover, which would otherwise immediately re-show the popover
    // (the "click makes it bounce back instead of closing" race).
    private var lastPopoverCloseDate: Date = .distantPast
    private weak var lastPopoverCloseButton: NSStatusBarButton?

    // Detached window reference (when popover is detached)
    private var detachedWindow: NSWindow?

    // Settings window reference
    private var settingsWindow: NSWindow?

    // GitHub star prompt window reference
    private var githubPromptWindow: NSWindow?

    // Feedback prompt window reference
    private var feedbackWindow: NSWindow?


    // Track which button is currently showing the popover
    private weak var currentPopoverButton: NSStatusBarButton?

    private let apiService = ClaudeAPIService()
    private let statusService = ClaudeStatusService()

    /// Status service for the active profile's provider (Statuspage-compatible
    /// endpoints across providers; falls back to the Anthropic default).
    private var statusServiceForActiveProfile: ClaudeStatusService {
        guard let url = profileManager.activeProfile?.provider.descriptor.statusPageURL else {
            return statusService
        }
        return ClaudeStatusService(statusURL: url)
    }
    private let dataStore = DataStore.shared
    private let networkMonitor = NetworkMonitor.shared
    private let profileManager = ProfileManager.shared
    private let autoStartService = AutoStartSessionService.shared

    // Combine cancellables for profile observation
    private var cancellables = Set<AnyCancellable>()

    // Track if we've handled the first profile switch (to allow returning to initial profile)
    private var hasHandledFirstProfileSwitch = false

    // Track which profiles have already triggered auto-switch (prevents repeated firing)
    private var autoSwitchedProfileIds: Set<UUID> = []

    // Observer for refresh interval changes
    private var refreshIntervalObserver: NSKeyValueObservation?

    // Observer for icon style changes
    private var iconStyleObserver: NSObjectProtocol?

    // Observer for icon configuration changes
    private var iconConfigObserver: NSObjectProtocol?

    // Observer for credential changes (add, remove, update)
    private var credentialsObserver: NSObjectProtocol?

    // Observer for display mode changes (single/multi profile)
    private var displayModeObserver: NSObjectProtocol?

    // Observer for screen/display changes (headless mode support)
    private var screenObserver: NSObjectProtocol?

    // Observer for wake-from-sleep
    private var wakeObserver: NSObjectProtocol?
    private var lastAutoRefreshTime: Date = .distantPast


    private var multiProfileConfigObserver: NSObjectProtocol?

    // MARK: - Image Caching (CPU Optimization)
    private var cachedImage: NSImage?
    private var cachedImageKey: String = ""
    private var updateDebounceTimer: Timer?
    private var cachedIsDarkMode: Bool = false

    // MARK: - Team tracking (docs/specs/multi-team-tracking.md §7, §10, §11)

    /// Banner text when the shown account needs a new login (Team tracking only); nil otherwise.
    @Published private(set) var teamLoginMessage: String?
    private var teamTrackingObserver: NSObjectProtocol?
    private var teamTrackingWasEnabled = false
    private var livePollGate = LivePollGate()   // one tracker live fetch in flight at a time

    /// The profile the menu bar and popover show: the current account while Team tracking runs
    /// (without activating it), else the active profile. A Codex active profile is always shown.
    var menuBarProfile: Profile? {
        let tracker = TeamTracker.shared
        return Self.menuBarProfile(running: tracker.isRunning, current: tracker.global.current,
                                   profiles: profileManager.profiles, active: profileManager.activeProfile)
    }

    static func menuBarProfile(running: Bool, current: PairRef?, profiles: [Profile], active: Profile?) -> Profile? {
        // Codex profiles never change: a non-anthropic active profile stays shown (and on today's path).
        // No active profile while running: the current account, as there is nothing else to show.
        guard running, (active?.provider ?? .anthropic) == .anthropic, let current,
              let p = profiles.first(where: { $0.id == current.profileId }) else { return active }
        return p
    }

    /// Console API usage the single-mode popover shows for `menuBarProfile`.
    var shownAPIUsage: APIUsage? {
        Self.shownAPIUsage(shown: menuBarProfile, activeId: profileManager.activeProfile?.id, live: apiUsage)
    }

    /// `live` (`apiUsage`, refreshed for the active profile) only when the shown profile is the active
    /// one; else the shown profile's own saved data, so the current account's view never carries the
    /// active profile's console billing.
    static func shownAPIUsage(shown: Profile?, activeId: UUID?, live: APIUsage?) -> APIUsage? {
        guard let shown, shown.id != activeId else { return live }
        return shown.apiUsage
    }

    /// How single mode refreshes the shown profile.
    enum ShownFetchPlan: Equatable {
        case legacy                                  // tracker off or not anthropic: today's path
        case skip                                    // tracker owns it but has no live target: keep cached
        case tracked(orgId: String, byProfile: Bool) // byProfile: fetchUsage(for:), never activating it
    }

    static func shownFetchPlan(subject: Profile, activeId: UUID?, running: Bool,
                               target: (profile: Profile, orgId: String)?) -> ShownFetchPlan {
        guard running, subject.provider == .anthropic else { return .legacy }
        guard let target, target.profile.id == subject.id else { return .skip }
        return .tracked(orgId: target.orgId, byProfile: subject.id != activeId)
    }

    /// Single mode with a non-anthropic shown profile (Codex): the tracker's live target, which the
    /// pass also polls without showing it. The tracker never probes the current pair (spec §4, §7),
    /// so without this poll it gets no live sample and cannot defend at detection. Nil when the
    /// tracker is off or the subject is anthropic (`shownFetchPlan` covers those).
    static func backgroundLiveTarget(subject: Profile, running: Bool,
                                     target: (profile: Profile, orgId: String)?) -> (profile: Profile, orgId: String)? {
        guard running, subject.provider != .anthropic else { return nil }
        return target
    }

    /// Polls `target` without showing it, the way multi mode fetches an unselected current account:
    /// a fresh reading is saved to that account and every result goes to the tracker. `usage`, the
    /// credential banner, the statusline, threshold alerts and auto-switch stay with the shown profile.
    static func pollLiveTarget(_ target: (profile: Profile, orgId: String), tracker: TeamTracker,
                               store: TeamProfileStore, fetch: (Profile) async throws -> ClaudeUsage) async {
        let id = target.profile.id
        do {
            let newUsage = try await fetch(target.profile)
            // A provider with no usable live credential hands back the cached reading: no new sample.
            let isCachedReading = target.profile.claudeUsage == newUsage
            if !isCachedReading { store.saveClaudeUsage(newUsage, for: id) }
            tracker.ingestLive(profileId: id, orgId: target.orgId, result: .success(newUsage),
                               isCachedReading: isCachedReading)
        } catch {
            LoggingService.shared.logError("MenuBarManager: Live poll of current account '\(target.profile.name)' failed: \(error.localizedDescription)")
            tracker.ingestLive(profileId: id, orgId: target.orgId, result: .failure(error), isCachedReading: false)
        }
    }

    /// Starts `poll` in a Task when `gate` is free and releases the gate when it ends (success,
    /// failure or cancellation). Nil, and nothing started, when a live fetch is already in flight:
    /// the pass keeps the cached value.
    @discardableResult
    static func startGatedLivePoll(gate: inout LivePollGate, release: @escaping () -> Void,
                                   poll: @escaping () async -> Void) -> Task<Void, Never>? {
        guard gate.begin() else {
            LoggingService.shared.log("MenuBarManager: Team tracking live fetch already in flight - keeping cached usage")
            return nil
        }
        return Task {
            defer { release() }
            await poll()
        }
    }

    /// Ends a tracker live fetch of `fetched`: `release` frees the gate first, then `rerun` runs once
    /// when the tracker's live target is now another pair. That pair's pass found the gate busy and was
    /// dropped (`onCurrentChanged` fired while the fetch was in flight, or inside its own `ingestLive`).
    /// A pass for the same pair stays dropped: that duplicate is what the gate exists to stop.
    static func endGatedLivePoll(fetched: PairRef, tracker: TeamTracker, release: () -> Void, rerun: () -> Void) {
        release()
        guard let target = tracker.liveTarget(),
              PairRef(profileId: target.profile.id, orgId: target.orgId) != fetched else { return }
        LoggingService.shared.log("MenuBarManager: Team tracking live target moved during a live fetch - refreshing the new current account")
        rerun()
    }

    /// Single mode: whether a fetched reading reaches the menu bar (`usage`, icons, statusline cache).
    /// Tracker-owned only while the fetched account is still the shown one, as the current account can
    /// move while the fetch is in flight; today's path (tracker off) always.
    static func showsFetchedReading(trackerOwned: Bool, fetchedId: UUID, shownId: UUID?) -> Bool {
        !trackerOwned || fetchedId == shownId
    }

    /// One multi-mode pass. Tracker off: the selection as is, nothing skipped (today's loop).
    struct MultiFetchPlan: Equatable {
        var profiles: [Profile]                // loop order
        var liveOrgIds: [UUID: String] = [:]   // tracker-owned usage fetch: org per profile
        var usageSkip: Set<UUID> = []          // no claude.ai usage fetch (the tracker keeps it)
        var consoleSkip: Set<UUID> = []        // no console-billing fetch (not selected)
    }

    /// Tracker running: the current account first (the live target, fetched even when not selected),
    /// then the rest of the selection. Other selected anthropic profiles skip only the claude.ai usage
    /// fetch; console billing still runs for every selected profile, and never for an unselected one.
    static func multiFetchPlan(selected: [Profile], allProfiles: [Profile], running: Bool,
                               target: (profile: Profile, orgId: String)?) -> MultiFetchPlan {
        var plan = MultiFetchPlan(profiles: selected)
        guard running else { return plan }
        plan.usageSkip = Set(selected.filter { $0.provider == .anthropic && $0.id != target?.profile.id }.map(\.id))
        guard let target else { return plan }
        let current = allProfiles.first { $0.id == target.profile.id } ?? target.profile
        if !selected.contains(where: { $0.id == current.id }) { plan.consoleSkip = [current.id] }
        plan.profiles = [current] + selected.filter { $0.id != current.id }
        plan.liveOrgIds = [current.id: target.orgId]
        return plan
    }

    static func teamLoginMessage(for shown: Profile?) -> String? {
        guard let shown, shown.provider == .anthropic,
              case .needsLogin = shown.orgTracking?.authState else { return nil }
        return "multiteam.login_again".localized
    }

    /// Runs after each refresh pass: a shown account that needs a login keeps the credential banner up.
    private func applyTeamLoginState() {
        guard TeamTracker.shared.isRunning, let message = Self.teamLoginMessage(for: menuBarProfile) else {
            if teamLoginMessage != nil { teamLoginMessage = nil }
            return
        }
        hasCredentialError = true
        lastRefreshError = message
        teamLoginMessage = message
    }

    /// Frees the live poll gate after a tracker live fetch of `fetched`, then runs the pass it dropped
    /// for a pair the tracker moved to meanwhile (`endGatedLivePoll`).
    private func endLivePoll(fetched: PairRef) {
        Self.endGatedLivePoll(fetched: fetched, tracker: TeamTracker.shared,
                              release: { livePollGate.end() }, rerun: { refreshUsage() })
    }

    private func setupTeamTracking() {
        let tracker = TeamTracker.shared
        tracker.notifier = NotificationManager.shared
        tracker.onCurrentChanged = { [weak self] _ in
            guard let self else { return }
            if self.profileManager.displayMode != .multi, let shown = self.menuBarProfile {
                self.clickedProfileId = shown.id  // an open popover (e.g. "Make current") follows it
                self.usage = shown.claudeUsage ?? .empty
                self.updateAllStatusBarIcons()
            }
            self.refreshUsage()
        }
        tracker.onSample = { [weak self] id, sample in
            guard let self else { return }
            if let active = self.profileManager.activeProfile, id == active.id,
               active.provider.descriptor.capabilities.cliAccountSync,
               StatuslineService.shared.isInstalled {
                StatuslineService.shared.writeUsageCache(usage: sample, profileName: active.name)
            }
            if self.profileManager.displayMode != .multi, id == self.menuBarProfile?.id {
                self.usage = sample
            }
            self.updateAllStatusBarIcons()
        }
        tracker.start()
        teamTrackingWasEnabled = TeamTrackingSettings.isEnabled()
        if let teamTrackingObserver { NotificationCenter.default.removeObserver(teamTrackingObserver) }
        teamTrackingObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.teamTrackingSettingChanged() }
        }
    }

    private func teamTrackingSettingChanged() {
        let enabled = TeamTrackingSettings.isEnabled()
        guard enabled != teamTrackingWasEnabled else { return }
        teamTrackingWasEnabled = enabled
        if enabled {
            TeamTracker.shared.start()
        } else {
            TeamTracker.shared.stop()
            // A fetch still in flight must not block the next start.
            // ponytail: that old fetch's end() can later clear a newer fetch's gate, and its re-run check can
            // start one more pass (one duplicate at most); a generation token in begin()/end() closes it if ever needed.
            livePollGate = LivePollGate()
            teamLoginMessage = nil
            if profileManager.displayMode != .multi, let active = profileManager.activeProfile {
                usage = active.claudeUsage ?? .empty
            }
        }
        updateAllStatusBarIcons()
        refreshUsage()
    }

    func setup() {
        // Initialize cached appearance to avoid layout recursion
        cachedIsDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Observe profile changes - CRITICAL: Set up before anything else
        observeProfileChanges()

        // Initialize status bar UI manager
        statusBarUIManager = StatusBarUIManager()
        statusBarUIManager?.delegate = self

        // Check if we should use multi-profile mode
        if profileManager.displayMode == .multi {
            // Multi-profile mode - setup with selected profiles
            setupMultiProfileMode()
        } else {
            // Single profile mode - setup with active profile's config
            let config = profileManager.activeProfile?.iconConfig ?? .default
            // Includes system Keychain CLI credentials as a fallback so users who
            // only authenticated via `claude login` still get metrics enabled.
            let hasCredentials = hasAnyAvailableCredentials()

            // If no credentials anywhere, create empty config to show default logo
            let displayConfig: MenuBarIconConfiguration
            if !hasCredentials {
                displayConfig = MenuBarIconConfiguration(
                    colorMode: config.colorMode,
                    singleColorHex: config.singleColorHex,
                    showIconNames: config.showIconNames,
                    metrics: config.metrics.map { metric in
                        var updatedMetric = metric
                        updatedMetric.isEnabled = false
                        return updatedMetric
                    }
                )
            } else {
                displayConfig = configAdjustedForPlanLimits(config)
            }

            statusBarUIManager?.setup(target: self, action: #selector(togglePopover), config: displayConfig)
        }

        // Setup popover
        setupPopover()

        // Team tracking: start before the first reads so the menu bar shows the current account.
        setupTeamTracking()

        // Load saved data from active profile first (provides immediate feedback).
        // Credential check includes system Keychain CLI fallback so users who
        // authenticated only via `claude login` still see usage data.
        if let profile = menuBarProfile {
            if hasAnyAvailableCredentials() {
                // Credentials available - show saved usage data if present
                if let savedUsage = profile.claudeUsage {
                    usage = savedUsage
                }
                // Console billing follows the active profile (same as the refresh writes).
                if let savedAPIUsage = profileManager.activeProfile?.apiUsage {
                    apiUsage = savedAPIUsage
                }
            } else {
                // No credentials anywhere - clear any old usage data and show default logo
                usage = .empty
                apiUsage = nil
                LoggingService.shared.log("MenuBarManager: No credentials available (profile or system keychain), showing default logo")
            }
            updateAllStatusBarIcons()
        }

        // Start network monitoring - fetch data when network is available
        networkMonitor.onNetworkAvailable = { [weak self] in
            // Only refresh if we haven't refreshed recently (avoid duplicate on startup)
            guard let self = self else { return }

            // Skip only if no credentials exist anywhere (profile or system keychain)
            guard self.hasAnyAvailableCredentials() else {
                LoggingService.shared.log("Skipping network-available refresh (no credentials available)")
                return
            }

            let timeSinceLastRefresh = Date().timeIntervalSince(self.lastRefreshTriggerTime)
            if timeSinceLastRefresh > 2.0 {  // At least 2 seconds since last refresh
                self.refreshUsage()
            } else {
                LoggingService.shared.log("Skipping network-available refresh (too soon after last refresh)")
            }
        }
        networkMonitor.startMonitoring()

        // Initial data fetch (with small delay for launch-at-login scenarios).
        // Includes system Keychain CLI credentials as a fallback.
        if hasAnyAvailableCredentials() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refreshUsage()
            }
        } else {
            LoggingService.shared.log("Skipping initial refresh (no credentials available)")
        }

        // Start auto-refresh timer with active profile's interval
        startAutoRefresh()

        // Start auto-start session service (5-minute cycle for all profiles)
        autoStartService.start()

        // Observe icon configuration changes
        observeIconConfigChanges()

        // Observe session key updates
        observeCredentialChanges()

        // Observe display mode changes (single/multi profile)
        observeDisplayModeChanges()
        observeMultiProfileConfigChanges()

        // Setup headless mode observer if enabled (for Remote Desktop support)
        setupHeadlessModeObserver()

        // Setup wake-from-sleep observer for auto-refresh
        setupWakeObserver()

        // Setup global keyboard shortcuts
        setupShortcuts()

    }

    private func setupShortcuts() {
        let shortcutManager = ShortcutManager.shared
        shortcutManager.onTogglePopover = { [weak self] in
            self?.togglePopover(nil)
        }
        shortcutManager.onRefresh = { [weak self] in
            self?.refreshUsage()
        }
        shortcutManager.onOpenSettings = { [weak self] in
            self?.preferencesClicked()
        }
        shortcutManager.onNextProfile = { [weak self] in
            self?.switchToNextProfile()
        }
        shortcutManager.startListening()
    }

    func cleanup() {
        TeamTracker.shared.stop()
        if let teamTrackingObserver = teamTrackingObserver {
            NotificationCenter.default.removeObserver(teamTrackingObserver)
            self.teamTrackingObserver = nil
        }
        ShortcutManager.shared.stopListening()
        refreshTimer?.invalidate()
        refreshTimer = nil
        networkMonitor.stopMonitoring()
        autoStartService.stop()
        cancellables.removeAll()  // Clean up Combine subscriptions
        refreshIntervalObserver?.invalidate()
        refreshIntervalObserver = nil
        if let iconStyleObserver = iconStyleObserver {
            NotificationCenter.default.removeObserver(iconStyleObserver)
            self.iconStyleObserver = nil
        }
        if let iconConfigObserver = iconConfigObserver {
            NotificationCenter.default.removeObserver(iconConfigObserver)
            self.iconConfigObserver = nil
        }
        if let credentialsObserver = credentialsObserver {
            NotificationCenter.default.removeObserver(credentialsObserver)
            self.credentialsObserver = nil
        }
        if let displayModeObserver = displayModeObserver {
            NotificationCenter.default.removeObserver(displayModeObserver)
            self.displayModeObserver = nil
        }
        if let screenObserver = screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let multiProfileConfigObserver = multiProfileConfigObserver {
            NotificationCenter.default.removeObserver(multiProfileConfigObserver)
            self.multiProfileConfigObserver = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        detachedWindow?.close()
        detachedWindow = nil
        statusItem = nil
        statusBarUIManager?.cleanup()
        statusBarUIManager = nil

        // Clean up history tracking dictionaries to prevent memory leaks
        lastKnownSessionResetTime.removeAll()
        lastKnownWeeklyResetTime.removeAll()
        lastKnownAPIResetTime.removeAll()
        resetJustRecorded.removeAll()
    }

    /// Cleans up tracking data for a specific profile (called when profile is deleted)
    func cleanupProfile(_ profileId: UUID) {
        lastKnownSessionResetTime.removeValue(forKey: profileId)
        lastKnownWeeklyResetTime.removeValue(forKey: profileId)
        lastKnownAPIResetTime.removeValue(forKey: profileId)
        resetJustRecorded.removeValue(forKey: profileId)
        autoSwitchedProfileIds.remove(profileId)
    }

    // MARK: - Profile Observation

    private func observeProfileChanges() {
        // Store the initial profile ID to skip only the very first startup update
        let initialProfileId = profileManager.activeProfile?.id

        // Observe active profile changes
        profileManager.$activeProfile
            .removeDuplicates { oldProfile, newProfile in
                // Only trigger if the profile ID actually changed
                let result = oldProfile?.id == newProfile?.id
                if !result {
                    LoggingService.shared.log("MenuBarManager: Profile ID changed from \(oldProfile?.id.uuidString ?? "nil") to \(newProfile?.id.uuidString ?? "nil")")
                }
                return result
            }
            .dropFirst()  // Skip the initial value
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProfile in
                guard let self = self, let profile = newProfile else { return }

                // Skip ONLY if this is the startup profile AND we haven't switched yet
                if !self.hasHandledFirstProfileSwitch && profile.id == initialProfileId {
                    LoggingService.shared.log("MenuBarManager: Skipping initial startup profile update to: \(profile.name)")
                    self.hasHandledFirstProfileSwitch = true
                    return
                }

                // Mark that we've handled at least one profile switch
                self.hasHandledFirstProfileSwitch = true

                Task { @MainActor in
                    await self.handleProfileSwitch(to: profile)
                }
            }
            .store(in: &cancellables)

        LoggingService.shared.log("MenuBarManager: Observing profile changes (initial: \(initialProfileId?.uuidString ?? "nil"))")
    }

    private func handleProfileSwitch(to profile: Profile) async {
        LoggingService.shared.log("MenuBarManager: Handling profile switch to: \(profile.name)")

        // 1. Load saved data from new profile (for immediate display)
        await MainActor.run {
            // Team tracking: the menu bar keeps showing the current account, not the newly active
            // one (a Codex active profile is shown as before).
            let tracker = TeamTracker.shared
            let shown = Self.menuBarProfile(running: tracker.isRunning, current: tracker.global.current,
                                            profiles: self.profileManager.profiles, active: profile) ?? profile
            if let savedUsage = shown.claudeUsage {
                self.usage = savedUsage
            } else {
                self.usage = .empty
            }

            if let savedAPIUsage = profile.apiUsage {
                self.apiUsage = savedAPIUsage
            } else {
                self.apiUsage = nil
            }
        }

        // 2. Update refresh interval with profile's setting
        restartAutoRefreshWithInterval(profile.refreshInterval)

        // 3. Update menu bar based on current display mode
        // IMPORTANT: In multi-profile mode, we update all icons, not just switch config
        if profileManager.displayMode == .multi {
            // Multi-profile mode - update icons without recreating status items
            updateMultiProfileDisplay()
        } else {
            // Single profile mode - update menu bar configuration
            updateMenuBarDisplay(with: profile.iconConfig)
        }

        // 4. Recreate popover with new profile data
        recreatePopover()

        // 5. Trigger immediate refresh if any credentials are available, including
        // system Keychain CLI fallback used by ClaudeAPIService.
        if hasAnyAvailableCredentials() {
            self.lastRefreshTriggerTime = Date()
            refreshUsage()
        } else {
            LoggingService.shared.log("MenuBarManager: Skipping refresh for profile without usage credentials")
        }
    }

    private func recreatePopover() {
        // Close existing popover if open
        if popover?.isShown == true {
            closePopover()
        }

        // Recreate popover with fresh content
        let newPopover = NSPopover()
        newPopover.contentSize = Constants.WindowSizes.popoverSize
        newPopover.behavior = .semitransient
        // Disabled to avoid an infinite layout-recursion crash on macOS 26/27.
        // The hosting controller's sizingOptions/preferredContentSize (PR #200)
        // keep the popover sized to its content; with animation on, each animated
        // resize re-triggers layout (updateAnimatedWindowSize -> setFrame -> layout)
        // and never converges, overflowing the main-thread stack. Disabling only the
        // animation breaks the loop while preserving content sizing/positioning.
        // See Discussion #64.
        newPopover.animates = false
        newPopover.delegate = self
        newPopover.contentViewController = createContentViewController()

        self.popover = newPopover

        LoggingService.shared.log("MenuBarManager: Popover recreated for profile switch")
    }

    private func updateMenuBarDisplay(with config: MenuBarIconConfiguration) {
        // Skip if in multi-profile mode - this method is for single profile mode only
        guard profileManager.displayMode == .single else {
            LoggingService.shared.log("MenuBarManager: Skipping updateMenuBarDisplay (in multi-profile mode)")
            return
        }

        // Keep configuration decisions aligned with the fetch path so users with
        // only system Keychain CLI credentials keep their configured metric items.
        let hasUsageCredentials = hasAnyAvailableCredentials()

        // If no usage credentials, use an empty config (will show default logo)
        let displayConfig: MenuBarIconConfiguration
        if !hasUsageCredentials {
            // Create config with no enabled metrics (will trigger default logo)
            displayConfig = MenuBarIconConfiguration(
                colorMode: config.colorMode,
                singleColorHex: config.singleColorHex,
                showIconNames: config.showIconNames,
                metrics: config.metrics.map { metric in
                    var updatedMetric = metric
                    updatedMetric.isEnabled = false
                    return updatedMetric
                }
            )
        } else {
            displayConfig = configAdjustedForPlanLimits(config)
        }

        statusBarUIManager?.updateConfiguration(
            target: self,
            action: #selector(togglePopover),
            config: displayConfig
        )

        // Defer icon update to next run loop iteration to let NSStatusBar finalize layout
        DispatchQueue.main.async { [weak self] in
            self?.updateAllStatusBarIcons()
        }
    }

    private func restartAutoRefreshWithInterval(_ interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = nil

        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }

        LoggingService.shared.log("Updated refresh interval to \(interval)s")
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = Constants.WindowSizes.popoverSize
        popover.behavior = .semitransient  // Changed to allow detaching
        // Disabled to avoid an infinite layout-recursion crash on macOS 26/27.
        // The hosting controller's sizingOptions/preferredContentSize (PR #200)
        // keep the popover sized to its content; with animation on, each animated
        // resize re-triggers layout (updateAnimatedWindowSize -> setFrame -> layout)
        // and never converges, overflowing the main-thread stack. Disabling only the
        // animation breaks the loop while preserving content sizing/positioning.
        // See Discussion #64.
        popover.animates = false
        popover.delegate = self

        popover.contentViewController = createContentViewController()
        self.popover = popover
    }

    private func createContentViewController() -> NSHostingController<PopoverContentView> {
        // Create SwiftUI content view
        let contentView = PopoverContentView(
            manager: self,
            onRefresh: { [weak self] in
                self?.refreshUsage()
            },
            onPreferences: { [weak self] in
                self?.closePopoverOrWindow()
                self?.preferencesClicked()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        hostingController.preferredContentSize = Constants.WindowSizes.popoverSize
        hostingController.sizingOptions = .preferredContentSize
        return hostingController
    }

    @objc private func togglePopover(_ sender: Any?) {
        // Right-click → show context menu instead of toggling the popover
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu(for: sender as? NSStatusBarButton)
            return
        }

        // Determine which button was clicked
        let clickedButton: NSStatusBarButton?
        if let button = sender as? NSStatusBarButton {
            clickedButton = button
        } else if statusBarUIManager?.isInMultiProfileMode == true,
                  let activeId = profileManager.activeProfile?.id,
                  let activeButton = statusBarUIManager?.button(for: activeId) {
            // Multi-profile mode: use the active profile's button
            clickedButton = activeButton
        } else {
            // Single profile mode: fallback to primary button
            clickedButton = statusBarUIManager?.primaryButton
        }

        guard let button = clickedButton else { return }

        // In multi-profile mode, determine which profile was clicked
        if statusBarUIManager?.isInMultiProfileMode == true,
           let profileId = statusBarUIManager?.profileId(for: button),
           let profile = profileManager.profiles.first(where: { $0.id == profileId }) {
            // Set the clicked profile data
            clickedProfileId = profileId
            clickedProfileUsage = profile.claudeUsage ?? .empty
            clickedProfileAPIUsage = profile.apiUsage
            LoggingService.shared.log("Multi-profile popover: showing data for '\(profile.name)'")
        } else {
            // Single profile mode - view the shown profile (the active profile, or the current
            // account while Team tracking runs)
            clickedProfileId = menuBarProfile?.id
            clickedProfileUsage = nil  // Will use manager.usage
            clickedProfileAPIUsage = nil  // Will use manager.shownAPIUsage
        }

        // If there's a detached window, close it
        if let window = detachedWindow {
            window.close()
            detachedWindow = nil
            currentPopoverButton = nil
            return
        }

        // Otherwise toggle the popover
        if let popover = popover {
            if popover.isShown {
                // Check if clicking the same button or a different one
                if currentPopoverButton === button {
                    // Same button - close the popover
                    closePopover()
                } else {
                    // Different button - close current and show at new position
                    // Use close() instead of performClose() to avoid async race condition
                    // No need to recreate contentViewController — SwiftUI already observes
                    // the @Published profile properties set earlier in this method
                    popover.close()
                    stopMonitoringForOutsideClicks()
                    showPopover(popover, from: button)
                    currentPopoverButton = button
                    startMonitoringForOutsideClicks()
                }
            } else {
                // Popover not shown - show it.
                // Guard against the dismiss/re-open race: if the popover was just
                // closed (e.g. the outside-click monitor handled this same click a
                // moment before the button action fired), treat this click as the
                // dismissing click and don't immediately re-open it. Only for the
                // button the popover was anchored to — a click on a different
                // status item is a deliberate open, not the dismissing click.
                if button === lastPopoverCloseButton,
                   Date().timeIntervalSince(lastPopoverCloseDate) < 0.25 {
                    return
                }
                // Stop any existing monitor first
                stopMonitoringForOutsideClicks()
                // Update content view controller for current profile data
                popover.contentViewController = createContentViewController()
                showPopover(popover, from: button)
                currentPopoverButton = button
                startMonitoringForOutsideClicks()
            }
        }
    }

    /// Shows `popover` anchored to a status bar button and gives its backing window
    /// the Space placement a menu bar popover needs to appear over a full-screen app.
    private func showPopover(_ popover: NSPopover, from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.enableDisplayOnFullScreenSpaces()
            // AppKit hands initial key focus to the first focusable control in
            // the popover, drawing an accent-colored focus ring around the
            // profile-switcher menu. Nothing in the popover needs initial
            // keyboard focus, so drop first responder to the window itself.
            window.makeFirstResponder(nil)
        }
    }

    /// Shows a lightweight context menu (Refresh / Settings / Quit) anchored to the
    /// status bar button that received the right-click.
    private func showContextMenu(for button: NSStatusBarButton?) {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "common.refresh".localized, action: #selector(contextMenuRefresh), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "common.settings".localized, action: #selector(preferencesClicked), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "common.quit".localized, action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        // Show the menu at the button's location
        if let button = button {
            // Position the menu below the status bar button
            if let window = button.window {
                let buttonRect = button.convert(button.bounds, to: nil)
                let screenRect = window.convertToScreen(buttonRect)
                menu.popUp(positioning: nil, at: NSPoint(x: screenRect.origin.x, y: screenRect.origin.y), in: nil)
            }
        }
    }

    @objc private func contextMenuRefresh() {
        refreshUsage()
    }

    private func closePopover() {
        popover?.performClose(nil)
        stopMonitoringForOutsideClicks()
        lastPopoverCloseButton = currentPopoverButton
        currentPopoverButton = nil
        lastPopoverCloseDate = Date()
    }

    private func startMonitoringForOutsideClicks() {
        // Only monitor when popover is shown (not detached)
        // Stop monitoring if popover gets detached
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self,
                  let popover = self.popover,
                  popover.isShown,
                  self.detachedWindow == nil else { return }
            self.closePopover()
        }
    }

    private func stopMonitoringForOutsideClicks() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func closePopoverOrWindow() {
        if let window = detachedWindow {
            window.close()
            detachedWindow = nil
        } else {
            popover?.performClose(nil)
        }
    }

    // MARK: - Status Bar Icon Updates

    /// Updates all enabled status bar icons
    private func updateAllStatusBarIcons() {
        // Check if in multi-profile mode
        if profileManager.displayMode == .multi {
            // Update multi-profile icons using profiles from profileManager
            let config = profileManager.multiProfileConfig
            statusBarUIManager?.updateMultiProfileButtons(
                profiles: profileManager.profiles,
                config: config,
                activeProfileId: profileManager.activeProfile?.id
            )
        } else {
            // Single profile mode - use the standard update
            statusBarUIManager?.updateAllButtons(
                usage: usage,
                apiUsage: apiUsage
            )
        }
    }

    /// Updates a specific metric's status bar icon
    private func updateStatusBarIcon(for metricType: MenuBarMetricType) {
        statusBarUIManager?.updateButton(
            for: metricType,
            usage: usage,
            apiUsage: apiUsage
        )
    }

    // Legacy method kept for backwards compatibility (now uses new system)
    private func updateStatusButton(_ button: NSStatusBarButton, usage: ClaudeUsage) {
        // This method is deprecated but kept for any remaining references
        // The new system handles updates through updateAllStatusBarIcons()
        updateAllStatusBarIcons()
    }

    // MARK: - Icon Style: Battery (Classic)

    private func startAutoRefresh() {
        let interval = profileManager.activeProfile?.refreshInterval ?? 30.0
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.lastAutoRefreshTime = Date()
            self?.refreshUsage()
        }
        refreshTimer?.tolerance = interval * 0.1  // 10% tolerance for energy efficiency
        LoggingService.shared.log("Started auto-refresh with interval: \(interval)s")
    }

    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Debounce: only refresh if at least 10 seconds since last auto-refresh
            let timeSinceLastRefresh = Date().timeIntervalSince(self.lastAutoRefreshTime)
            guard timeSinceLastRefresh > 10 else {
                LoggingService.shared.log("MenuBarManager: Skipping wake refresh (debounce)")
                return
            }
            LoggingService.shared.log("MenuBarManager: Wake from sleep detected, refreshing after delay")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.lastAutoRefreshTime = Date()
                self?.refreshUsage()
            }
        }
    }

    private func restartAutoRefresh() {
        // Invalidate existing timer
        refreshTimer?.invalidate()
        refreshTimer = nil

        // Start new timer with updated interval
        startAutoRefresh()
    }

    private func observeRefreshIntervalChanges() {
        // Observe the same UserDefaults instance that DataStore uses
        refreshIntervalObserver = dataStore.userDefaults.observe(\.refreshInterval, options: [.new]) { [weak self] _, change in
            if let newValue = change.newValue, newValue > 0 {
                DispatchQueue.main.async {
                    self?.restartAutoRefresh()
                }
            }
        }
    }

    private func observeIconStyleChanges() {
        // Observe icon style changes from settings (now consolidated with menuBarIconConfigChanged)
        iconStyleObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Clear cache to force redraw with new style
            self.cachedImageKey = ""
            self.updateAllStatusBarIcons()
        }
    }

    private func observeCredentialChanges() {
        // Observe credential changes (add, remove, or update)
        credentialsObserver = NotificationCenter.default.addObserver(
            forName: .credentialsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                // Check if active profile has any credentials, including system
                // Keychain CLI fallback.
                guard let profile = self.profileManager.activeProfile, self.hasAnyAvailableCredentials() else {
                    LoggingService.shared.logInfo("Credentials changed but no usage credentials - showing default logo")

                    // Reconfigure menu bar to show default logo
                    let config = self.profileManager.activeProfile?.iconConfig ?? .default
                    self.updateMenuBarDisplay(with: config)

                    // No refresh will run, so publish directly: this clears
                    // (or trims) the widget snapshot instead of letting stale
                    // usage linger until the widget's stale threshold.
                    WidgetSnapshotService.shared.publish(
                        profiles: self.profileManager.profiles,
                        activeProfileId: self.profileManager.activeProfile?.id
                    )
                    return
                }

                LoggingService.shared.logInfo("Credentials changed - triggering immediate refresh")

                // Reconfigure menu bar to show metrics (in case we were showing default logo)
                let config = profile.iconConfig
                self.updateMenuBarDisplay(with: config)

                // Mark this as user-triggered
                self.lastRefreshTriggerTime = Date()

                self.refreshUsage()
            }
        }
    }

    private func observeIconConfigChanges() {
        // Observe configuration changes (metrics enabled/disabled, order changes, etc.)
        iconConfigObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Reload configuration from active profile (already on main queue)
            Task { @MainActor in
                // Handle differently based on display mode
                if self.profileManager.displayMode == .multi {
                    // Multi-profile mode - update icons without recreating status items
                    self.updateMultiProfileDisplay()
                } else {
                    // Single profile mode
                    let newConfig = self.profileManager.activeProfile?.iconConfig ?? .default
                    self.updateMenuBarDisplay(with: newConfig)
                }
            }
        }
    }

    private func observeDisplayModeChanges() {
        // Observe display mode changes (single/multi profile)
        displayModeObserver = NotificationCenter.default.addObserver(
            forName: .displayModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.handleDisplayModeChange()
            }
        }
    }

    private func observeMultiProfileConfigChanges() {
        // Observe multi-profile visual config changes (icon style, toggles, profile selection)
        // Uses incremental update — does NOT destroy/recreate status items
        multiProfileConfigObserver = NotificationCenter.default.addObserver(
            forName: .multiProfileConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.updateMultiProfileDisplay()
            }
        }
    }

    private func handleDisplayModeChange() {
        let displayMode = profileManager.displayMode

        LoggingService.shared.log("MenuBarManager: Display mode changed to \(displayMode.rawValue)")

        if displayMode == .multi {
            // Switch to multi-profile mode
            setupMultiProfileMode()
        } else {
            // Switch back to single profile mode
            setupSingleProfileMode()
        }
    }

    // MARK: - Headless Mode (Remote Desktop Support)

    private func setupHeadlessModeObserver() {
        // Always observe screen changes to support headless Mac setups (Remote Desktop)
        LoggingService.shared.log("MenuBarManager: Setting up screen change observer for headless support")

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    private func handleScreenChange() {
        // Only proceed if we have screens now
        guard !NSScreen.screens.isEmpty else { return }

        // Check if status bar needs retry (button is nil means it failed on headless startup)
        guard let uiManager = statusBarUIManager else { return }

        if !uiManager.hasValidStatusBar {
            LoggingService.shared.log("MenuBarManager: Headless mode - display connected, retrying status bar setup (screens: \(NSScreen.screens.count))")
            setup()
        }
    }

    /// Returns whether the status bar has at least one valid button
    func hasValidStatusBar() -> Bool {
        return statusBarUIManager?.hasValidStatusBar ?? false
    }

    /// Checks if ANY credentials are available for the active profile, including
    /// provider-specific system-level fallbacks (e.g. Anthropic's system Keychain
    /// CLI credentials, mirroring `ClaudeAPIService.getAuthentication()`).
    private func hasAnyAvailableCredentials() -> Bool {
        guard let profile = profileManager.activeProfile else { return false }
        return ProviderRegistry.service(for: profile.provider).hasCredentials(for: profile)
    }

    /// The icon config to display for the active profile's last usage, so the
    /// session icon is hidden on plans without a session limit (see `effective(for:)`).
    private func configAdjustedForPlanLimits(_ config: MenuBarIconConfiguration) -> MenuBarIconConfiguration {
        config.effective(for: menuBarProfile?.claudeUsage ?? usage)
    }

    private func setupMultiProfileMode() {
        let selectedProfiles = profileManager.getSelectedProfiles()
        let config = profileManager.multiProfileConfig

        statusBarUIManager?.setupMultiProfile(
            profiles: selectedProfiles,
            target: self,
            action: #selector(togglePopover)
        )

        // Defer icon update to next run loop iteration to let NSStatusBar finalize layout
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusBarUIManager?.updateMultiProfileButtons(profiles: self.profileManager.profiles, config: config, activeProfileId: self.profileManager.activeProfile?.id)
        }

        LoggingService.shared.log("MenuBarManager: Multi-profile mode enabled with \(selectedProfiles.count) profiles, style=\(config.iconStyle.rawValue)")

        // Refresh data for all selected profiles that have credentials
        refreshAllSelectedProfiles()
    }

    /// Incrementally updates multi-profile status items (without destroying/recreating them)
    /// Use this when only icon config changed but the set of profiles may or may not have changed.
    private func updateMultiProfileDisplay() {
        let selectedProfiles = profileManager.getSelectedProfiles()
        let config = profileManager.multiProfileConfig

        statusBarUIManager?.updateMultiProfileConfiguration(
            profiles: selectedProfiles,
            target: self,
            action: #selector(togglePopover)
        )

        // WORKAROUND: Defer icon update to next run loop iteration to avoid race condition
        // where NSStatusBar layout hasn't finalized yet after status item creation.
        // This prevents potential flicker or layout issues during incremental updates.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusBarUIManager?.updateMultiProfileButtons(profiles: self.profileManager.profiles, config: config, activeProfileId: self.profileManager.activeProfile?.id)
        }

        LoggingService.shared.log("MenuBarManager: Multi-profile display updated incrementally with \(selectedProfiles.count) profiles")
    }

    /// Refreshes usage data for all profiles selected for multi-profile display
    private func refreshAllSelectedProfiles() {
        // Filter on `hasAnyCredentials` (not `hasUsageCredentials`) so that profiles
        // whose CLI OAuth token has expired are still polled — `fetchUsageForProfile`
        // will transparently refresh expired tokens via the refresh_token grant.
        // Excluding them here would prevent the refresh path from ever running.
        let selected = profileManager.profiles.filter { $0.isSelectedForDisplay && $0.hasAnyCredentials }

        // Team tracking: anthropic accounts other than the current one skip the usage fetch (their
        // claudeUsage is rendered as the tracker keeps it) but keep their console billing; the current
        // account is fetched even when it is not selected. Every set is empty with the tracker off.
        let tracker = TeamTracker.shared
        let plan = Self.multiFetchPlan(selected: selected, allProfiles: profileManager.profiles,
                                       running: tracker.isRunning, target: tracker.isRunning ? tracker.liveTarget() : nil)
        let selectedProfiles = plan.profiles
        let consoleSkip = plan.consoleSkip

        guard !selectedProfiles.isEmpty else {
            LoggingService.shared.log("MenuBarManager: No selected profiles with usage credentials to refresh")
            updateAllStatusBarIcons()
            applyTeamLoginState()
            return
        }

        // One tracker live fetch in flight at a time: when another pass is still fetching the current
        // account, this pass skips its usage fetch and keeps the cached value. The gate taken here is
        // released by the defer in the loop below, at the current account (always first in the plan).
        let gateBusy = !plan.liveOrgIds.isEmpty && !livePollGate.begin()
        if gateBusy {
            LoggingService.shared.log("MenuBarManager: Team tracking live fetch already in flight - keeping cached usage")
        }
        let liveOrgIds = gateBusy ? [:] : plan.liveOrgIds
        let usageSkip = gateBusy ? plan.usageSkip.union(plan.liveOrgIds.keys) : plan.usageSkip
        let holdsLiveGate = !liveOrgIds.isEmpty

        LoggingService.shared.log("MenuBarManager: Refreshing \(selectedProfiles.count) selected profiles for multi-profile mode")

        Task {
            await MainActor.run {
                self.isRefreshing = true
            }

            // Fetch Claude status (same as single profile mode)
            do {
                let newStatus = try await statusServiceForActiveProfile.fetchStatus()
                await MainActor.run {
                    self.status = newStatus
                }
            } catch {
                let appError = AppError.wrap(error)
                LoggingService.shared.log("MenuBarManager: Failed to fetch status - [\(appError.code.rawValue)] \(appError.message)")
            }

            // Fetch usage for each selected profile
            for profile in selectedProfiles {
                // Team tracking: the tracker keeps this account's usage, so only its console billing
                // below runs this pass (usageSkip is empty with the tracker off).
                if !usageSkip.contains(profile.id) {
                    // Team tracking: release the live poll gate on success, failure or cancellation, then
                    // re-run the pass if the tracker moved its live target meanwhile.
                    defer {
                        if holdsLiveGate, let orgId = liveOrgIds[profile.id] {
                            self.endLivePoll(fetched: PairRef(profileId: profile.id, orgId: orgId))
                        }
                    }
                    LoggingService.shared.log("MenuBarManager: Fetching usage for profile '\(profile.name)'")

                    // Capture previous usage for reset detection
                    let previousUsage = profile.claudeUsage

                    do {
                        let newUsage = try await fetchUsageForProfile(profile)

                        // A provider with no usable live credential hands back the
                        // profile's cached reading unchanged. It stays on display, but
                        // it is not a new sample: feeding it to reset detection and the
                        // history charts would record stale points as if they were live.
                        let isCachedReading = previousUsage.map { $0 == newUsage } ?? false
                        if isCachedReading {
                            LoggingService.shared.log("MenuBarManager: No live reading for profile '\(profile.name)' - keeping the cached one")
                        }

                        if let orgId = liveOrgIds[profile.id] {
                            // Tracker-owned: per-pair history replaces the profile reset checks and recorders.
                            await MainActor.run {
                                if !isCachedReading {
                                    self.profileManager.saveClaudeUsage(newUsage, for: profile.id)
                                    if profile.id == self.profileManager.activeProfile?.id {
                                        self.usage = newUsage
                                        if profile.provider.descriptor.capabilities.cliAccountSync,
                                           StatuslineService.shared.isInstalled {
                                            StatuslineService.shared.writeUsageCache(usage: newUsage, profileName: profile.name)
                                        }
                                    }
                                }
                                TeamTracker.shared.ingestLive(profileId: profile.id, orgId: orgId, result: .success(newUsage),
                                                              isCachedReading: isCachedReading)
                            }
                        }

                        await MainActor.run {
                            // Tracker-owned profiles were handled above (liveOrgIds is empty with the tracker off).
                            guard !isCachedReading, liveOrgIds[profile.id] == nil else { return }

                            // Check for resets before updating usage
                            self.checkAndRecordSessionReset(
                                profileId: profile.id,
                                previousUsage: previousUsage,
                                newUsage: newUsage
                            )
                            self.checkAndRecordWeeklyReset(
                                profileId: profile.id,
                                previousUsage: previousUsage,
                                newUsage: newUsage
                            )

                            // Record periodic snapshots for history charts (skip if reset just occurred)
                            let flags = self.resetJustRecorded[profile.id] ?? (session: false, weekly: false)

                            if !flags.session {
                                UsageHistoryService.shared.recordSessionPeriodic(for: profile.id, usage: newUsage, provider: profile.provider)
                            }

                            if !flags.weekly {
                                UsageHistoryService.shared.recordWeeklyPeriodic(for: profile.id, usage: newUsage, provider: profile.provider)
                            }

                            // Clear reset flags for next cycle
                            self.resetJustRecorded[profile.id] = (session: false, weekly: false)

                            // Save to profile
                            self.profileManager.saveClaudeUsage(newUsage, for: profile.id)
                            LoggingService.shared.log("MenuBarManager: Saved usage for profile '\(profile.name)' - session: \(newUsage.sessionPercentage)%")

                            // If this is the active profile, also update the manager's usage
                            if profile.id == self.profileManager.activeProfile?.id {
                                self.usage = newUsage

                                // Write statusline cache for instant CLI rendering (Claude Code only)
                                if profile.provider.descriptor.capabilities.cliAccountSync,
                                   StatuslineService.shared.isInstalled {
                                    StatuslineService.shared.writeUsageCache(
                                        usage: newUsage,
                                        profileName: profile.name
                                    )
                                }
                            }
                        }
                    } catch {
                        LoggingService.shared.logError("Failed to refresh profile '\(profile.name)': \(error.localizedDescription)")
                        if let orgId = liveOrgIds[profile.id] {
                            await MainActor.run {
                                TeamTracker.shared.ingestLive(profileId: profile.id, orgId: orgId, result: .failure(error),
                                                              isCachedReading: false)
                            }
                        }
                    }
                }

                // Fetch API usage if this profile's provider has console billing
                // and the profile has API console credentials (Team tracking: not for an
                // unselected current account; consoleSkip is empty with the tracker off)
                if !consoleSkip.contains(profile.id),
                   profile.provider.descriptor.capabilities.consoleBilling,
                   let apiSessionKey = profile.apiSessionKey,
                   let orgId = profile.apiOrganizationId {
                    do {
                        let previousAPIUsage = profile.apiUsage
                        let newAPIUsage = try await apiService.fetchAPIUsageData(organizationId: orgId, apiSessionKey: apiSessionKey)
                        await MainActor.run {
                            self.checkAndRecordBillingCycleReset(
                                profileId: profile.id,
                                previousUsage: previousAPIUsage,
                                newUsage: newAPIUsage
                            )
                            self.profileManager.saveAPIUsage(newAPIUsage, for: profile.id)
                            if profile.id == self.profileManager.activeProfile?.id {
                                self.apiUsage = newAPIUsage
                            }
                        }
                    } catch {
                        LoggingService.shared.logError("Failed to refresh API usage for profile '\(profile.name)': \(error.localizedDescription)")
                    }
                }
            }

            // Update all icons once after all profiles are refreshed
            await MainActor.run {
                let config = self.profileManager.multiProfileConfig
                self.statusBarUIManager?.updateMultiProfileButtons(
                    profiles: self.profileManager.profiles,
                    config: config,
                    activeProfileId: self.profileManager.activeProfile?.id
                )
                self.consecutiveRefreshFailures = 0
                self.lastRefreshError = nil
                self.hasCredentialError = false
                self.lastSuccessfulRefreshTime = Date()
                self.isRefreshing = false
                self.applyTeamLoginState()

                WidgetSnapshotService.shared.publish(
                    profiles: self.profileManager.profiles,
                    activeProfileId: self.profileManager.activeProfile?.id
                )

                // Check auto-switch for the active profile
                if let activeProfile = self.profileManager.activeProfile,
                   let activeUsage = activeProfile.claudeUsage {
                    self.checkAutoSwitchIfNeeded(usage: activeUsage, currentProfile: activeProfile)
                }
            }
        }
    }

    /// Fetches usage data for a specific profile using its provider's service.
    /// (The Anthropic 3-source chain that used to live here moved verbatim to
    /// `AnthropicUsageProvider.fetchUsage(for:)`.)
    private func fetchUsageForProfile(_ profile: Profile) async throws -> ClaudeUsage {
        try await ProviderRegistry.service(for: profile.provider).fetchUsage(for: profile)
    }

    private func setupSingleProfileMode() {
        guard let profile = profileManager.activeProfile else { return }

        let hasUsageCredentials = hasAnyAvailableCredentials()
        let config = profile.iconConfig

        // If no usage credentials, create empty config to show default logo
        let displayConfig: MenuBarIconConfiguration
        if !hasUsageCredentials {
            displayConfig = MenuBarIconConfiguration(
                colorMode: config.colorMode,
                singleColorHex: config.singleColorHex,
                showIconNames: config.showIconNames,
                metrics: config.metrics.map { metric in
                    var updatedMetric = metric
                    updatedMetric.isEnabled = false
                    return updatedMetric
                }
            )
        } else {
            displayConfig = configAdjustedForPlanLimits(config)
        }

        statusBarUIManager?.setup(target: self, action: #selector(togglePopover), config: displayConfig)

        // Defer icon update to next run loop iteration to let NSStatusBar finalize layout
        DispatchQueue.main.async { [weak self] in
            self?.updateAllStatusBarIcons()
        }

        LoggingService.shared.log("MenuBarManager: Single profile mode enabled")
    }

    func refreshUsage() {
        // In multi-profile mode, refresh ALL selected profiles
        if profileManager.displayMode == .multi {
            refreshAllSelectedProfiles()
            return
        }

        // Single profile mode - refresh only the shown profile (the active profile, or the
        // current account while Team tracking runs)
        guard let profile = menuBarProfile else {
            LoggingService.shared.log("MenuBarManager.refreshUsage: No active profile")
            return
        }

        // Detailed logging
        LoggingService.shared.log("MenuBarManager.refreshUsage called:")
        LoggingService.shared.log("  - Profile: '\(profile.name)'")
        LoggingService.shared.log("  - hasUsageCredentials: \(profile.hasUsageCredentials)")

        // Team tracking owns anthropic subjects: fetch only the tracker's live target, never
        // activating it. Nil when the tracker is off or the subject is not anthropic (old path).
        let tracker = TeamTracker.shared
        let liveTarget = tracker.isRunning ? tracker.liveTarget() : nil
        let plan = Self.shownFetchPlan(subject: profile, activeId: profileManager.activeProfile?.id,
                                       running: tracker.isRunning, target: liveTarget)

        // A Codex shown profile stays on today's path below, and the current pair still gets its
        // live poll this pass: per profile, never activated, not shown. It starts before the
        // credentials guard, which checks the active (Codex) profile. Nil with the tracker off or
        // an anthropic subject.
        if let background = Self.backgroundLiveTarget(subject: profile, running: tracker.isRunning, target: liveTarget) {
            let fetched = PairRef(profileId: background.profile.id, orgId: background.orgId)
            Self.startGatedLivePoll(gate: &livePollGate, release: { [weak self] in self?.endLivePoll(fetched: fetched) }) {
                await Self.pollLiveTarget(background, tracker: tracker, store: self.profileManager) {
                    try await ProviderRegistry.service(for: .anthropic).fetchUsage(for: $0)
                }
            }
        }

        let trackerOrgId: String?
        let fetchesByProfile: Bool
        let skipsUsage: Bool
        switch plan {
        case .skip:
            // Only the usage fetch is skipped: the status and the active profile's console
            // billing still run, and the pass ends with applyTeamLoginState().
            LoggingService.shared.log("MenuBarManager: Team tracking has no live target for '\(profile.name)' - keeping cached usage")
            trackerOrgId = nil
            fetchesByProfile = false
            skipsUsage = true
        case let .tracked(orgId, byProfile):
            if livePollGate.begin() {
                // Released by the defer in the usage-fetch block of the Task below.
                trackerOrgId = orgId
                fetchesByProfile = byProfile
                skipsUsage = false
            } else {
                // A live fetch of the current pair is already in flight: skip like `.skip`.
                LoggingService.shared.log("MenuBarManager: Team tracking live fetch already in flight - keeping cached usage for '\(profile.name)'")
                trackerOrgId = nil
                fetchesByProfile = false
                skipsUsage = true
            }
        case .legacy:
            trackerOrgId = nil
            fetchesByProfile = false
            skipsUsage = false

            // Check for ANY available credentials, including system Keychain CLI fallback.
            // Without this fallback, users who only authenticated via `claude login`
            // would be gated off here before ClaudeAPIService.getAuthentication() could
            // discover their system-level credentials.
            guard hasAnyAvailableCredentials() else {
                LoggingService.shared.log("MenuBarManager: Skipping refresh - no credentials available (profile or system keychain)")
                // Update icons to show default logo if needed
                updateAllStatusBarIcons()
                return
            }
        }
        let isTrackerOwned = trackerOrgId != nil

        LoggingService.shared.log("MenuBarManager: Proceeding with refresh")
        Task {
            // Set loading state (keep existing data visible during refresh)
            await MainActor.run {
                self.isRefreshing = true
            }

            // Capture previous usage BEFORE fetching new data (for reset detection)
            let previousUsage = await MainActor.run { self.usage }
            let previousAPIUsage = await MainActor.run { self.apiUsage }
            let currentProfileId = await MainActor.run { self.profileManager.activeProfile?.id }

            // Fetch usage and status in parallel (usage via the profile's provider;
            // for Anthropic this is the same no-arg fetchUsageData() chain as before)
            let providerService = ProviderRegistry.service(for: profile.provider)
            async let statusResult = statusServiceForActiveProfile.fetchStatus()

            var usageSuccess = false

            // Team tracking without a live target (.skip): no usage fetch, the cached usage stays.
            if !skipsUsage {
                // Team tracking: release the live poll gate taken above on success, failure or cancellation,
                // then re-run the pass if the tracker moved its live target meanwhile.
                defer {
                    if let orgId = trackerOrgId { self.endLivePoll(fetched: PairRef(profileId: profile.id, orgId: orgId)) }
                }

                // Team tracking, current account != active profile: per-profile fetch, so the account is
                // never activated and the active profile's Claude Code credentials are not touched.
                async let usageResult = fetchesByProfile
                    ? providerService.fetchUsage(for: profile)
                    : providerService.fetchUsageForActiveProfile(profile)

                // Fetch usage with proper error handling
                do {
                    let newUsage = try await usageResult
                    // A per-profile fetch with no live credential hands back the cached reading: no new sample.
                    let isCachedReading = isTrackerOwned && (profile.claudeUsage.map { $0 == newUsage } ?? false)

                    await MainActor.run {
                        // Check for resets before updating usage (tracker-owned: per-pair history instead)
                        if !isTrackerOwned, let profileId = currentProfileId {
                            self.checkAndRecordSessionReset(
                                profileId: profileId,
                                previousUsage: previousUsage,
                                newUsage: newUsage
                            )
                            self.checkAndRecordWeeklyReset(
                                profileId: profileId,
                                previousUsage: previousUsage,
                                newUsage: newUsage
                            )

                            // Record periodic snapshots for history charts
                            UsageHistoryService.shared.recordSessionPeriodic(for: profileId, usage: newUsage, provider: profile.provider)
                            UsageHistoryService.shared.recordWeeklyPeriodic(for: profileId, usage: newUsage, provider: profile.provider)
                        }

                        // Tracker-owned: the current account can move while this fetch is in flight. The
                        // reading is still saved and goes to the tracker, but it reaches the menu bar only
                        // while its account is the shown one.
                        let isShown = Self.showsFetchedReading(trackerOwned: isTrackerOwned, fetchedId: profile.id,
                                                               shownId: self.menuBarProfile?.id)
                        if isShown { self.usage = newUsage }

                        // Save to active profile instead of global DataStore (tracker-owned: the shown account)
                        if let profileId = isTrackerOwned ? profile.id : self.profileManager.activeProfile?.id {
                            self.profileManager.saveClaudeUsage(newUsage, for: profileId)
                        }

                        // The session icon is shown or hidden by the plan's limits, so
                        // rebuild the status items when the session limit appears or goes away
                        if isShown, newUsage.hasSessionLimit != previousUsage.hasSessionLimit,
                           let activeProfile = self.profileManager.activeProfile {
                            self.updateMenuBarDisplay(with: activeProfile.iconConfig)
                        }

                        // Write statusline cache for instant CLI rendering (Claude Code only;
                        // tracker-owned: only when the shown account is the active profile)
                        if isShown, !isTrackerOwned || profile.id == self.profileManager.activeProfile?.id,
                           profile.provider.descriptor.capabilities.cliAccountSync,
                           StatuslineService.shared.isInstalled {
                            StatuslineService.shared.writeUsageCache(
                                usage: newUsage,
                                profileName: self.profileManager.activeProfile?.name
                            )
                        }

                        // Update all menu bar icons
                        if isShown { self.updateAllStatusBarIcons() }

                        // Check if we should send notifications (using active profile's settings;
                        // tracker-owned: the shown account's)
                        let notifyProfile = isTrackerOwned
                            ? (self.profileManager.profiles.first { $0.id == profile.id } ?? profile)
                            : self.profileManager.activeProfile
                        if let profile = notifyProfile {
                            NotificationManager.shared.checkAndNotify(
                                usage: newUsage,
                                profileName: profile.name,
                                settings: profile.notificationSettings
                            )

                            // Check if auto-switch should trigger (only on the active profile's own usage)
                            if profile.id == self.profileManager.activeProfile?.id {
                                self.checkAutoSwitchIfNeeded(usage: newUsage, currentProfile: profile)
                            }
                        }

                        if let orgId = trackerOrgId {
                            TeamTracker.shared.ingestLive(profileId: profile.id, orgId: orgId, result: .success(newUsage),
                                                          isCachedReading: isCachedReading)
                        }
                    }

                    // Record success for circuit breaker
                    ErrorRecovery.shared.recordSuccess(for: .api)
                    usageSuccess = true

                    await MainActor.run {
                        self.consecutiveRefreshFailures = 0
                        self.lastRefreshError = nil
                        self.hasCredentialError = false
                        self.lastSuccessfulRefreshTime = Date()

                        WidgetSnapshotService.shared.publish(
                            profiles: self.profileManager.profiles,
                            activeProfileId: self.profileManager.activeProfile?.id
                        )
                    }

                } catch {
                    // Convert to AppError and log
                    let appError = AppError.wrap(error)
                    ErrorLogger.shared.log(appError, severity: .error)

                    // Record failure for circuit breaker
                    ErrorRecovery.shared.recordFailure(for: .api)

                    // Track error state for UI banners
                    await MainActor.run {
                        if let orgId = trackerOrgId {
                            TeamTracker.shared.ingestLive(profileId: profile.id, orgId: orgId, result: .failure(error),
                                                          isCachedReading: false)
                        }
                        self.consecutiveRefreshFailures += 1
                        self.lastRefreshError = appError.message

                        // Track credential errors specifically
                        if appError.code == .apiUnauthorized || appError.code == .sessionKeyExpired {
                            self.hasCredentialError = true
                        }

                        // Check if this refresh was triggered within last 5 seconds
                        // (indicates user-initiated action like saving session key)
                        if abs(self.lastRefreshTriggerTime.timeIntervalSinceNow) < 5 {
                            ErrorPresenter.shared.showAlert(for: appError)
                        } else {
                            // Background refresh - just log
                            LoggingService.shared.logError("MenuBarManager: Failed to fetch usage - [\(appError.code.rawValue)] \(appError.message)")
                        }
                    }
                }
            }

            // Fetch status separately (don't fail if usage fetch works)
            do {
                let newStatus = try await statusResult
                await MainActor.run {
                    self.status = newStatus
                }
            } catch {
                // Convert to AppError and log
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .info)

                // Don't show error for status - it's not critical
                LoggingService.shared.log("MenuBarManager: Failed to fetch status - [\(appError.code.rawValue)] \(appError.message)")
            }

            // Fetch API usage (using active profile's API credentials; console
            // billing is provider-gated)
            if let profile = await MainActor.run(body: { self.profileManager.activeProfile }),
               profile.provider.descriptor.capabilities.consoleBilling,
               let apiSessionKey = profile.apiSessionKey,
               let orgId = profile.apiOrganizationId {
                do {
                    let newAPIUsage = try await apiService.fetchAPIUsageData(organizationId: orgId, apiSessionKey: apiSessionKey)
                    await MainActor.run {
                        // Check for billing cycle reset before updating usage
                        if let profileId = currentProfileId {
                            self.checkAndRecordBillingCycleReset(
                                profileId: profileId,
                                previousUsage: previousAPIUsage,
                                newUsage: newAPIUsage
                            )
                        }

                        self.apiUsage = newAPIUsage

                        // Save to active profile instead of global DataStore
                        if let profileId = self.profileManager.activeProfile?.id {
                            self.profileManager.saveAPIUsage(newAPIUsage, for: profileId)
                        }
                    }
                } catch {
                    // Convert to AppError and log
                    let appError = AppError.wrap(error)
                    ErrorLogger.shared.log(appError, severity: .info)

                    LoggingService.shared.log("MenuBarManager: Failed to fetch API usage - [\(appError.code.rawValue)] \(appError.message)")
                }
            }

            // Clear loading state
            await MainActor.run {
                self.isRefreshing = false
                self.applyTeamLoginState()

                // Show success notification if this was user-triggered and successful
                if usageSuccess && abs(self.lastRefreshTriggerTime.timeIntervalSinceNow) < 5 {
                    self.showSuccessNotification()
                }
            }
        }
    }

    /// Shows a brief success notification for user-triggered refreshes
    private func showSuccessNotification() {
        NotificationManager.shared.sendSuccessNotification()
    }

    // MARK: - Auto-Switch Profile on Session Limit

    /// Checks if the current profile hit 100% and switches to the next available one
    private func checkAutoSwitchIfNeeded(usage: ClaudeUsage, currentProfile: Profile) {
        // Guard: feature must be enabled
        guard SharedDataStore.shared.loadAutoSwitchProfileEnabled() else { return }

        // Guard: need more than 1 profile
        let profiles = profileManager.profiles
        guard profiles.count > 1 else { return }

        let profileId = currentProfile.id

        // If usage dropped below 100%, clear the flag (session reset)
        if usage.effectiveSessionPercentage < 100.0 {
            autoSwitchedProfileIds.remove(profileId)
            return
        }

        // Guard: usage must be >= 100%
        guard usage.effectiveSessionPercentage >= 100.0 else { return }

        // Guard: don't re-trigger for this profile
        guard !autoSwitchedProfileIds.contains(profileId) else { return }

        // Mark as triggered
        autoSwitchedProfileIds.insert(profileId)

        // Find the next available profile
        guard let nextProfile = findNextAvailableProfile(after: currentProfile) else {
            LoggingService.shared.log("AutoSwitch: All profiles at 100% or unavailable, staying on '\(currentProfile.name)'")
            return
        }

        LoggingService.shared.log("AutoSwitch: Switching from '\(currentProfile.name)' to '\(nextProfile.name)'")

        // Activate the next profile
        let fromName = currentProfile.name
        let toName = nextProfile.name
        let notificationSettings = currentProfile.notificationSettings
        Task {
            // A cancelled switch (e.g. the target's saved CLI login is dead) must not be announced
            guard await profileManager.activateProfile(nextProfile.id) else {
                LoggingService.shared.log("AutoSwitch: switch to '\(toName)' did not complete, staying on '\(fromName)'")
                return
            }

            await MainActor.run {
                // Send notification
                NotificationManager.shared.sendAutoSwitchNotification(
                    fromProfile: fromName,
                    toProfile: toName,
                    settings: notificationSettings
                )

                // Post notification for UI reactivity
                NotificationCenter.default.post(name: .autoSwitchProfileTriggered, object: nil)
            }
        }
    }

    /// Finds the next profile with available session capacity, wrapping around
    private func findNextAvailableProfile(after currentProfile: Profile) -> Profile? {
        let profiles = profileManager.profiles
        guard let currentIndex = profiles.firstIndex(where: { $0.id == currentProfile.id }) else { return nil }

        let count = profiles.count
        for offset in 1..<count {
            let index = (currentIndex + offset) % count
            let candidate = profiles[index]

            // Must have usage credentials
            guard candidate.hasUsageCredentials else { continue }

            // If no saved usage data, treat as available
            guard let candidateUsage = candidate.claudeUsage else { return candidate }

            // Must be below 100%
            if candidateUsage.effectiveSessionPercentage < 100.0 {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Reset Detection for History Recording

    /// Checks if a session reset occurred and records a snapshot if so
    private func checkAndRecordSessionReset(
        profileId: UUID,
        previousUsage: ClaudeUsage?,
        newUsage: ClaudeUsage
    ) {
        guard newUsage.hasSessionLimit else {
            lastKnownSessionResetTime.removeValue(forKey: profileId)
            return
        }

        let lastKnown = lastKnownSessionResetTime[profileId]
        let newResetTime = newUsage.sessionResetTime

        // First time seeing this profile - just record the reset time
        if lastKnown == nil {
            lastKnownSessionResetTime[profileId] = newResetTime
            return
        }

        // Check if reset time moved beyond API jitter (indicates a reset occurred).
        // Compare in both directions to handle clock changes and backward time jumps.
        if ResetDetection.isReset(from: lastKnown!, to: newResetTime) {
            // Reset detected! Record snapshot of the previous usage
            LoggingService.shared.log("History: Session reset detected for profile \(profileId.uuidString.prefix(8)). Old: \(lastKnown!), New: \(newResetTime)")
            if let prevUsage = previousUsage {
                let provider = profileManager.profiles.first(where: { $0.id == profileId })?.provider ?? .anthropic
                Task { @MainActor in
                    UsageHistoryService.shared.recordSessionReset(
                        for: profileId,
                        previousUsage: prevUsage,
                        resetTime: prevUsage.sessionResetTime,
                        provider: provider
                    )
                }
            }

            // Mark that session reset was just recorded to prevent duplicate periodic snapshot
            var flags = resetJustRecorded[profileId] ?? (session: false, weekly: false)
            flags.session = true
            resetJustRecorded[profileId] = flags
        }

        // Update the last known reset time
        lastKnownSessionResetTime[profileId] = newResetTime
    }

    /// Checks if a weekly reset occurred and records a snapshot if so
    private func checkAndRecordWeeklyReset(
        profileId: UUID,
        previousUsage: ClaudeUsage?,
        newUsage: ClaudeUsage
    ) {
        let lastKnown = lastKnownWeeklyResetTime[profileId]
        let newResetTime = newUsage.weeklyResetTime

        // First time seeing this profile - just record the reset time
        if lastKnown == nil {
            lastKnownWeeklyResetTime[profileId] = newResetTime
            LoggingService.shared.log("History: Initial weekly reset time for profile \(profileId.uuidString.prefix(8)): \(newResetTime)")
            return
        }

        // Check if reset time moved beyond API jitter (indicates a reset occurred).
        // Compare in both directions to handle clock changes and backward time jumps.
        if ResetDetection.isReset(from: lastKnown!, to: newResetTime) {
            // Reset detected! Record snapshot of the previous usage
            LoggingService.shared.log("History: Weekly reset detected for profile \(profileId.uuidString.prefix(8)). Old: \(lastKnown!), New: \(newResetTime)")
            if let prevUsage = previousUsage {
                let provider = profileManager.profiles.first(where: { $0.id == profileId })?.provider ?? .anthropic
                Task { @MainActor in
                    UsageHistoryService.shared.recordWeeklyReset(
                        for: profileId,
                        previousUsage: prevUsage,
                        resetTime: prevUsage.weeklyResetTime,
                        provider: provider
                    )
                }
            }

            // Mark that weekly reset was just recorded to prevent duplicate periodic snapshot
            var flags = resetJustRecorded[profileId] ?? (session: false, weekly: false)
            flags.weekly = true
            resetJustRecorded[profileId] = flags
        }

        // Update the last known reset time
        lastKnownWeeklyResetTime[profileId] = newResetTime
    }

    /// Checks if a billing cycle reset occurred and records a snapshot if so
    private func checkAndRecordBillingCycleReset(
        profileId: UUID,
        previousUsage: APIUsage?,
        newUsage: APIUsage
    ) {
        let lastKnown = lastKnownAPIResetTime[profileId]
        let newResetTime = newUsage.resetsAt

        // First time seeing this profile - just record the reset time
        if lastKnown == nil {
            lastKnownAPIResetTime[profileId] = newResetTime
            LoggingService.shared.log("History: Initial API reset time for profile \(profileId.uuidString.prefix(8)): \(newResetTime)")
            return
        }

        // Check if reset time moved beyond API jitter (indicates a reset occurred).
        // Compare in both directions to handle clock changes and backward time jumps.
        if ResetDetection.isReset(from: lastKnown!, to: newResetTime) {
            // Reset detected! Record snapshot of the previous usage
            LoggingService.shared.log("History: Billing cycle reset detected for profile \(profileId.uuidString.prefix(8)). Old: \(lastKnown!), New: \(newResetTime)")
            if let prevUsage = previousUsage {
                Task { @MainActor in
                    UsageHistoryService.shared.recordBillingCycleReset(
                        for: profileId,
                        previousUsage: prevUsage,
                        resetTime: prevUsage.resetsAt
                    )
                }
            }
        }

        // Update the last known reset time
        lastKnownAPIResetTime[profileId] = newResetTime
    }

    @objc private func preferencesClicked() {
        // Close the popover or detached window first
        closePopoverOrWindow()

        // If settings window already exists, just bring it to front
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Small delay to ensure smooth transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Temporarily show dock icon for the settings window (like setup wizard)
            NSApp.setActivationPolicy(.regular)

            // Create and show the settings window
            let window = SettingsWindowBuilder.makeWindow(size: Constants.WindowSizes.settingsWindow)
            window.title = "Claude Usage - Settings"
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self

            self.settingsWindow = window

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func switchToNextProfile() {
        let profiles = profileManager.profiles
        guard profiles.count > 1,
              let currentId = profileManager.activeProfile?.id,
              let currentIndex = profiles.firstIndex(where: { $0.id == currentId }) else {
            return
        }

        let nextIndex = (profiles.index(after: currentIndex)) % profiles.count
        let nextProfile = profiles[nextIndex]

        Task {
            await profileManager.activateProfile(nextProfile.id)
        }
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }

    /// Shows the GitHub star prompt window
    func showGitHubStarPrompt() {
        // If window already exists, just bring it to front
        if let existingWindow = githubPromptWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Temporarily show dock icon for the prompt window
        NSApp.setActivationPolicy(.regular)

        // Create the GitHub star prompt view
        let promptView = GitHubStarPromptView(
            onStar: { [weak self] in
                self?.handleGitHubStarClick()
            },
            onMaybeLater: { [weak self] in
                self?.handleMaybeLaterClick()
            },
            onDontAskAgain: { [weak self] in
                self?.handleDontAskAgainClick()
            }
        )

        let hostingController = NSHostingController(rootView: promptView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 300, height: 145))
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = .floating
        window.delegate = self

        // Store reference
        githubPromptWindow = window

        // Mark that we've shown the prompt
        dataStore.saveLastGitHubStarPromptDate(Date())

        // Show the window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleGitHubStarClick() {
        // Open GitHub repository
        if let url = URL(string: Constants.githubRepoURL) {
            NSWorkspace.shared.open(url)
        }

        // Mark as starred
        dataStore.saveHasStarredGitHub(true)

        // Close the prompt window
        githubPromptWindow?.close()
        githubPromptWindow = nil

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    private func handleMaybeLaterClick() {
        // Just close the window - the prompt will show again after the reminder interval
        githubPromptWindow?.close()
        githubPromptWindow = nil

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    private func handleDontAskAgainClick() {
        // Mark to never show again
        dataStore.saveNeverShowGitHubPrompt(true)

        // Close the prompt window
        githubPromptWindow?.close()
        githubPromptWindow = nil

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Feedback Prompt

    /// Shows the feedback collection prompt window
    func showFeedbackPrompt() {
        if let existingWindow = feedbackWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.regular)

        let promptView = FeedbackPromptView(
            onSubmit: { [weak self] _, _, _, _ in
                SharedDataStore.shared.saveHasSubmittedFeedback(true)
                // Close after a brief delay to show the thanks state
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.closeFeedbackWindow()
                }
            },
            onRemindLater: { [weak self] in
                SharedDataStore.shared.saveLastFeedbackPromptDate(Date())
                self?.closeFeedbackWindow()
            },
            onDontAskAgain: { [weak self] in
                SharedDataStore.shared.saveNeverShowFeedbackPrompt(true)
                self?.closeFeedbackWindow()
            }
        )

        let hostingController = NSHostingController(rootView: promptView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 380, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = .floating
        window.delegate = self

        feedbackWindow = window
        SharedDataStore.shared.saveLastFeedbackPromptDate(Date())

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeFeedbackWindow() {
        feedbackWindow?.close()
        feedbackWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - NSPopoverDelegate
extension MenuBarManager: NSPopoverDelegate {
    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        // Allow popover to be detached by dragging
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        // Record every close (transient dismiss, outside-click monitor, or
        // explicit close) so togglePopover can debounce the dismissing click
        // and avoid the "click bounces the popover back open" race.
        lastPopoverCloseDate = Date()
        lastPopoverCloseButton = currentPopoverButton
    }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        // Stop monitoring for outside clicks when detaching
        stopMonitoringForOutsideClicks()

        // Create content view controller sized for a window (not a popover).
        // We don't use createContentViewController() here because its
        // preferredContentSize/sizingOptions (added by PR #200 for popover
        // positioning) conflict with the window's layout constraints.
        let contentView = PopoverContentView(
            manager: self,
            onRefresh: { [weak self] in self?.refreshUsage() },
            onPreferences: { [weak self] in
                self?.closePopoverOrWindow()
                self?.preferencesClicked()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 600),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 280, height: 600))
        window.isReleasedWhenClosed = false
        window.level = .floating
        // Allow a torn-off popover to stay on a full-screen app's Space.
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isRestorable = false
        window.delegate = self
        window.backgroundColor = .clear

        // Store reference to the detached window
        detachedWindow = window

        return window
    }
}

// MARK: - StatusBarUIManagerDelegate
extension MenuBarManager: StatusBarUIManagerDelegate {
    func statusBarAppearanceDidChange() {
        // Safe from infinite loops: StatusBarUIManager's observer deduplicates by
        // appearance name, and setButtonImage() only assigns button.image when the
        // rendered TIFF data actually changes — so even if setting button.image
        // triggers effectiveAppearance KVO, the cycle stops immediately.
        cachedIsDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        cachedImageKey = ""
        updateAllStatusBarIcons()
    }
}

// MARK: - NSWindowDelegate
extension MenuBarManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                // Hide dock icon again when settings window closes
                NSApp.setActivationPolicy(.accessory)
                settingsWindow = nil
            } else if window == detachedWindow {
                // Clear detached window reference when closed
                detachedWindow = nil
            } else if window == githubPromptWindow {
                // Hide dock icon again when GitHub prompt window closes
                NSApp.setActivationPolicy(.accessory)
                githubPromptWindow = nil
            }
        }
    }
}

// MARK: - Team tracking live poll gate

/// One tracker live fetch in flight at a time: the refresh timer and `TeamTracker.onCurrentChanged`
/// can both start a pass, and a duplicate request raises the 429 risk that backs off the current account.
/// A dropped pass for another pair runs when the fetch ends (`MenuBarManager.endGatedLivePoll`).
struct LivePollGate {
    private(set) var inFlight = false

    /// False when a fetch is already in flight; else claims the gate.
    mutating func begin() -> Bool {
        guard !inFlight else { return false }
        inFlight = true
        return true
    }

    mutating func end() { inFlight = false }
}
