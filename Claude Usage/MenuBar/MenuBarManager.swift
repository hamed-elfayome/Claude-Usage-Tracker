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

    // Multi-profile mode: track which profile's icon was clicked
    @Published private(set) var clickedProfileId: UUID?
    @Published private(set) var clickedProfileUsage: ClaudeUsage?
    @Published private(set) var clickedProfileAPIUsage: APIUsage?

    // Track when refresh was last triggered (for distinguishing user vs auto refresh)
    private var lastRefreshTriggerTime: Date = .distantPast

    // Popover for beautiful SwiftUI interface
    private var popover: NSPopover?

    // Event monitor for closing popover on outside click
    private var eventMonitor: Any?

    // Detached window reference (when popover is detached)
    private var detachedWindow: NSWindow?

    // Settings window reference
    private var settingsWindow: NSWindow?

    // GitHub star prompt window reference
    private var githubPromptWindow: NSWindow?

    // Track which button is currently showing the popover
    private weak var currentPopoverButton: NSStatusBarButton?

    private let apiService = ClaudeAPIService()
    private let statusService = ClaudeStatusService()
    private let dataStore = DataStore.shared
    private let networkMonitor = NetworkMonitor.shared
    private let profileManager = ProfileManager.shared
    private let autoStartService = AutoStartSessionService.shared

    // Combine cancellables for profile observation
    private var cancellables = Set<AnyCancellable>()

    // Track if we've handled the first profile switch (to allow returning to initial profile)
    private var hasHandledFirstProfileSwitch = false

    // Observer for refresh interval changes
    private var refreshIntervalObserver: NSKeyValueObservation?

    // Observer for appearance changes
    private var appearanceObserver: NSKeyValueObservation?

    // Observer for icon style changes
    private var iconStyleObserver: NSObjectProtocol?

    // Observer for icon configuration changes
    private var iconConfigObserver: NSObjectProtocol?

    // Observer for credential changes (add, remove, update)
    private var credentialsObserver: NSObjectProtocol?

    // Observer for display mode changes (single/multi profile)
    private var displayModeObserver: NSObjectProtocol?

    // MARK: - Image Caching (CPU Optimization)
    private var cachedImage: NSImage?
    private var cachedImageKey: String = ""
    private var updateDebounceTimer: Timer?
    private var cachedIsDarkMode: Bool = false

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
            let hasUsageCredentials = profileManager.activeProfile?.hasUsageCredentials ?? false

            // If no usage credentials, create empty config to show default logo
            let displayConfig: MenuBarIconConfiguration
            if !hasUsageCredentials {
                displayConfig = MenuBarIconConfiguration(
                    monochromeMode: config.monochromeMode,
                    showIconNames: config.showIconNames,
                    metrics: config.metrics.map { metric in
                        var updatedMetric = metric
                        updatedMetric.isEnabled = false
                        return updatedMetric
                    }
                )
            } else {
                displayConfig = config
            }

            statusBarUIManager?.setup(target: self, action: #selector(togglePopover), config: displayConfig)
        }

        // Setup popover
        setupPopover()

        // Load saved data from active profile first (provides immediate feedback)
        // BUT only if profile has usage credentials - CLI alone can't show usage
        if let profile = profileManager.activeProfile {
            if profile.hasUsageCredentials {
                // Profile has usage credentials - show saved usage data if available
                if let savedUsage = profile.claudeUsage {
                    usage = savedUsage
                }
                if let savedAPIUsage = profile.apiUsage {
                    apiUsage = savedAPIUsage
                }
            } else {
                // No usage credentials - clear any old usage data and show default logo
                usage = .empty
                apiUsage = nil
                LoggingService.shared.log("MenuBarManager: Profile has no usage credentials, showing default logo")
            }
            updateAllStatusBarIcons()
        }

        // Start network monitoring - fetch data when network is available
        networkMonitor.onNetworkAvailable = { [weak self] in
            // Only refresh if we haven't refreshed recently (avoid duplicate on startup)
            guard let self = self else { return }

            // Skip if profile has no usage credentials (CLI alone can't be used)
            guard let profile = self.profileManager.activeProfile, profile.hasUsageCredentials else {
                LoggingService.shared.log("Skipping network-available refresh (no usage credentials)")
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

        // Initial data fetch (with small delay for launch-at-login scenarios)
        // Only if profile has usage credentials (not just CLI)
        if let profile = profileManager.activeProfile, profile.hasUsageCredentials {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refreshUsage()
            }
        } else {
            LoggingService.shared.log("Skipping initial refresh (no usage credentials)")
        }

        // Start auto-refresh timer with active profile's interval
        startAutoRefresh()

        // Start auto-start session service (5-minute cycle for all profiles)
        autoStartService.start()

        // Observe appearance changes
        observeAppearanceChanges()

        // Observe icon configuration changes
        observeIconConfigChanges()

        // Observe session key updates
        observeCredentialChanges()

        // Observe display mode changes (single/multi profile)
        observeDisplayModeChanges()
    }

    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        networkMonitor.stopMonitoring()
        autoStartService.stop()
        cancellables.removeAll()  // Clean up Combine subscriptions
        refreshIntervalObserver?.invalidate()
        refreshIntervalObserver = nil
        appearanceObserver?.invalidate()
        appearanceObserver = nil
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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        detachedWindow?.close()
        detachedWindow = nil
        statusItem = nil
        statusBarUIManager?.cleanup()
        statusBarUIManager = nil
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
            if let savedUsage = profile.claudeUsage {
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
            // Multi-profile mode - refresh all profile icons
            setupMultiProfileMode()
        } else {
            // Single profile mode - update menu bar configuration
            updateMenuBarDisplay(with: profile.iconConfig)
        }

        // 4. Recreate popover with new profile data
        recreatePopover()

        // 5. Trigger immediate refresh ONLY if profile has usage credentials
        if profile.hasUsageCredentials {
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
        newPopover.contentSize = NSSize(width: 320, height: 600)
        newPopover.behavior = .semitransient
        newPopover.animates = true
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

        // Check if active profile has usage credentials (not just CLI)
        let hasUsageCredentials = profileManager.activeProfile?.hasUsageCredentials ?? false

        // If no usage credentials, use an empty config (will show default logo)
        let displayConfig: MenuBarIconConfiguration
        if !hasUsageCredentials {
            // Create config with no enabled metrics (will trigger default logo)
            displayConfig = MenuBarIconConfiguration(
                monochromeMode: config.monochromeMode,
                showIconNames: config.showIconNames,
                metrics: config.metrics.map { metric in
                    var updatedMetric = metric
                    updatedMetric.isEnabled = false
                    return updatedMetric
                }
            )
        } else {
            displayConfig = config
        }

        statusBarUIManager?.updateConfiguration(
            target: self,
            action: #selector(togglePopover),
            config: displayConfig
        )

        updateAllStatusBarIcons()
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
        popover.contentSize = NSSize(width: 320, height: 600)
        popover.behavior = .semitransient  // Changed to allow detaching
        popover.animates = true
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
            },
            onQuit: { [weak self] in
                self?.quitClicked()
            }
        )

        return NSHostingController(rootView: contentView)
    }

    @objc private func togglePopover(_ sender: Any?) {
        // Determine which button was clicked
        let clickedButton: NSStatusBarButton?
        if let button = sender as? NSStatusBarButton {
            clickedButton = button
        } else {
            // Fallback to primary button for backwards compatibility
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
            // Single profile mode - use active profile
            clickedProfileId = profileManager.activeProfile?.id
            clickedProfileUsage = nil  // Will use manager.usage
            clickedProfileAPIUsage = nil  // Will use manager.apiUsage
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
                    popover.performClose(nil)
                    stopMonitoringForOutsideClicks()
                    // Update content view controller for new profile data
                    popover.contentViewController = createContentViewController()
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    currentPopoverButton = button
                    startMonitoringForOutsideClicks()
                }
            } else {
                // Popover not shown - show it
                // Stop any existing monitor first
                stopMonitoringForOutsideClicks()
                // Update content view controller for current profile data
                popover.contentViewController = createContentViewController()
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                currentPopoverButton = button
                startMonitoringForOutsideClicks()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        stopMonitoringForOutsideClicks()
        currentPopoverButton = nil
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
                config: config
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
            self?.refreshUsage()
        }
        LoggingService.shared.log("Started auto-refresh with interval: \(interval)s")
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

    private func observeAppearanceChanges() {
        // Observe appearance changes on NSApp (fires less frequently than button)
        // This optimization reduces redundant redraws
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, change in
            guard let self = self,
                  let button = self.statusItem?.button else { return }

            // Cache the dark mode state to avoid querying it during layout
            let isDark = change.newValue?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            DispatchQueue.main.async {
                self.cachedIsDarkMode = isDark
                // Clear cache to force redraw with new appearance
                self.cachedImageKey = ""
                self.updateStatusButton(button, usage: self.usage)
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
                // Check if active profile has usage credentials
                guard let profile = self.profileManager.activeProfile, profile.hasUsageCredentials else {
                    LoggingService.shared.logInfo("Credentials changed but no usage credentials - showing default logo")

                    // Reconfigure menu bar to show default logo
                    let config = self.profileManager.activeProfile?.iconConfig ?? .default
                    self.updateMenuBarDisplay(with: config)
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
                    // Multi-profile mode - refresh all profile icons
                    self.setupMultiProfileMode()
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

    private func setupMultiProfileMode() {
        let selectedProfiles = profileManager.getSelectedProfiles()
        let config = profileManager.multiProfileConfig

        statusBarUIManager?.setupMultiProfile(
            profiles: selectedProfiles,
            target: self,
            action: #selector(togglePopover)
        )

        // Update icons for all selected profiles with the display config
        // Use profiles from profileManager to get the latest data
        statusBarUIManager?.updateMultiProfileButtons(profiles: profileManager.profiles, config: config)

        LoggingService.shared.log("MenuBarManager: Multi-profile mode enabled with \(selectedProfiles.count) profiles, style=\(config.iconStyle.rawValue)")

        // Refresh data for all selected profiles that have credentials
        refreshAllSelectedProfiles()
    }

    /// Refreshes usage data for all profiles selected for multi-profile display
    private func refreshAllSelectedProfiles() {
        let selectedProfiles = profileManager.profiles.filter { $0.isSelectedForDisplay && $0.hasUsageCredentials }

        guard !selectedProfiles.isEmpty else {
            LoggingService.shared.log("MenuBarManager: No selected profiles with usage credentials to refresh")
            updateAllStatusBarIcons()
            return
        }

        LoggingService.shared.log("MenuBarManager: Refreshing \(selectedProfiles.count) selected profiles for multi-profile mode")

        Task {
            await MainActor.run {
                self.isRefreshing = true
            }

            // Fetch Claude status (same as single profile mode)
            do {
                let newStatus = try await statusService.fetchStatus()
                await MainActor.run {
                    self.status = newStatus
                }
            } catch {
                let appError = AppError.wrap(error)
                LoggingService.shared.log("MenuBarManager: Failed to fetch status - [\(appError.code.rawValue)] \(appError.message)")
            }

            // Fetch usage for each selected profile
            for profile in selectedProfiles {
                LoggingService.shared.log("MenuBarManager: Fetching usage for profile '\(profile.name)'")
                do {
                    let newUsage = try await fetchUsageForProfile(profile)

                    await MainActor.run {
                        // Save to profile
                        self.profileManager.saveClaudeUsage(newUsage, for: profile.id)
                        LoggingService.shared.log("MenuBarManager: Saved usage for profile '\(profile.name)' - session: \(newUsage.sessionPercentage)%")

                        // If this is the active profile, also update the manager's usage
                        if profile.id == self.profileManager.activeProfile?.id {
                            self.usage = newUsage
                        }
                    }
                } catch {
                    LoggingService.shared.logError("Failed to refresh profile '\(profile.name)': \(error.localizedDescription)")
                }
            }

            // Update all icons once after all profiles are refreshed
            await MainActor.run {
                let config = self.profileManager.multiProfileConfig
                self.statusBarUIManager?.updateMultiProfileButtons(
                    profiles: self.profileManager.profiles,
                    config: config
                )
                self.isRefreshing = false
            }
        }
    }

    /// Fetches usage data for a specific profile using its credentials
    private func fetchUsageForProfile(_ profile: Profile) async throws -> ClaudeUsage {
        // Try cookie-based claude.ai session first
        if let sessionKey = profile.claudeSessionKey,
           let orgId = profile.organizationId {
            do {
                return try await apiService.fetchUsageData(sessionKey: sessionKey, organizationId: orgId)
            } catch {
                LoggingService.shared.logError("Cookie-session fetch failed for profile '\(profile.name)', trying OAuth fallback: \(error.localizedDescription)")
            }
        }

        // Fall back to saved CLI OAuth token
        if let cliJSON = profile.cliCredentialsJSON,
           !ClaudeCodeSyncService.shared.isTokenExpired(cliJSON),
           let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: cliJSON) {
            return try await apiService.fetchUsageData(oauthAccessToken: accessToken)
        }

        throw AppError(
            code: .sessionKeyNotFound,
            message: "Missing credentials for profile '\(profile.name)'",
            isRecoverable: false
        )
    }

    private func setupSingleProfileMode() {
        guard let profile = profileManager.activeProfile else { return }

        let hasUsageCredentials = profile.hasUsageCredentials
        let config = profile.iconConfig

        // If no usage credentials, create empty config to show default logo
        let displayConfig: MenuBarIconConfiguration
        if !hasUsageCredentials {
            displayConfig = MenuBarIconConfiguration(
                monochromeMode: config.monochromeMode,
                showIconNames: config.showIconNames,
                metrics: config.metrics.map { metric in
                    var updatedMetric = metric
                    updatedMetric.isEnabled = false
                    return updatedMetric
                }
            )
        } else {
            displayConfig = config
        }

        statusBarUIManager?.setup(target: self, action: #selector(togglePopover), config: displayConfig)
        updateAllStatusBarIcons()

        LoggingService.shared.log("MenuBarManager: Single profile mode enabled")
    }

    func refreshUsage() {
        // In multi-profile mode, refresh ALL selected profiles
        if profileManager.displayMode == .multi {
            refreshAllSelectedProfiles()
            return
        }

        // Single profile mode - refresh only active profile
        guard let profile = profileManager.activeProfile else {
            LoggingService.shared.log("MenuBarManager.refreshUsage: No active profile")
            return
        }

        // Detailed logging
        LoggingService.shared.log("MenuBarManager.refreshUsage called:")
        LoggingService.shared.log("  - Profile: '\(profile.name)'")
        LoggingService.shared.log("  - hasUsageCredentials: \(profile.hasUsageCredentials)")

        // Check for usage credentials (Claude.ai or API Console, not just CLI)
        guard profile.hasUsageCredentials else {
            LoggingService.shared.log("MenuBarManager: Skipping refresh - no usage credentials")
            // Update icons to show default logo if needed
            updateAllStatusBarIcons()
            return
        }

        LoggingService.shared.log("MenuBarManager: Proceeding with refresh")
        Task {
            // Set loading state (keep existing data visible during refresh)
            await MainActor.run {
                self.isRefreshing = true
            }

            // Fetch usage and status in parallel
            async let usageResult = apiService.fetchUsageData()
            async let statusResult = statusService.fetchStatus()

            var usageSuccess = false

            // Fetch usage with proper error handling
            do {
                let newUsage = try await usageResult

                await MainActor.run {
                    self.usage = newUsage

                    // Save to active profile instead of global DataStore
                    if let profileId = self.profileManager.activeProfile?.id {
                        self.profileManager.saveClaudeUsage(newUsage, for: profileId)
                    }

                    // Update all menu bar icons
                    self.updateAllStatusBarIcons()

                    // Check if we should send notifications (using active profile's settings)
                    if let profile = self.profileManager.activeProfile {
                        NotificationManager.shared.checkAndNotify(
                            usage: newUsage,
                            profileName: profile.name,
                            settings: profile.notificationSettings
                        )
                    }
                }

                // Record success for circuit breaker
                ErrorRecovery.shared.recordSuccess(for: .api)
                usageSuccess = true

            } catch {
                // Convert to AppError and log
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .error)

                // Record failure for circuit breaker
                ErrorRecovery.shared.recordFailure(for: .api)

                // Show error to user if this was triggered by session key update
                await MainActor.run {
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

            // Fetch API usage if enabled (using active profile's API credentials)
            if let profile = await MainActor.run(body: { self.profileManager.activeProfile }),
               let apiSessionKey = profile.apiSessionKey,
               let orgId = profile.apiOrganizationId {
                do {
                    let newAPIUsage = try await apiService.fetchAPIUsageData(organizationId: orgId, apiSessionKey: apiSessionKey)
                    await MainActor.run {
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

            // Create and show the settings window programmatically
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Claude Usage - Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 720, height: 600))
            window.center()
            window.isReleasedWhenClosed = false
            window.isRestorable = false

            // Set window delegate to clean up reference when closed
            window.delegate = self

            // Store reference
            self.settingsWindow = window

            // Show the window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
}

// MARK: - NSPopoverDelegate
extension MenuBarManager: NSPopoverDelegate {
    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        // Allow popover to be detached by dragging
        return true
    }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        // Stop monitoring for outside clicks when detaching
        stopMonitoringForOutsideClicks()

        // Create a new window with NEW content view controller
        // This prevents the popover from losing its content
        let newContentViewController = createContentViewController()

        let window = NSWindow(contentViewController: newContentViewController)
        window.title = "app.window.main".localized
        window.styleMask = [.titled, .closable]  // Close-only, minimal and clean
        window.setContentSize(NSSize(width: 320, height: 600))
        window.isReleasedWhenClosed = false
        window.level = .floating  // Keep it above other windows
        window.isRestorable = false  // Don't persist across app restarts
        window.delegate = self

        // Store reference to the detached window
        detachedWindow = window

        return window
    }
}

// MARK: - StatusBarUIManagerDelegate
extension MenuBarManager: StatusBarUIManagerDelegate {
    func statusBarAppearanceDidChange() {
        // Update cached dark mode state
        cachedIsDarkMode = NSApp.effectiveAppearance.name == .darkAqua
        // Update all icons with new appearance
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
