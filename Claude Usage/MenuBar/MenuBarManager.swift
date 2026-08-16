import Cocoa
import SwiftUI
import Combine

@MainActor
class MenuBarManager: NSObject, ObservableObject {
    static weak var current: MenuBarManager?

    private var statusItem: NSStatusItem?  // Legacy - kept for backwards compatibility
    private var statusBarUIManager: StatusBarUIManager?
    private var refreshTimer: Timer?
    @Published private(set) var usage: ClaudeUsage = .empty
    @Published private(set) var status: ClaudeStatus = .unknown
    @Published private(set) var openAIStatus: ClaudeStatus = .unknown
    @Published private(set) var apiUsage: APIUsage?
    @Published private(set) var codexUsage: CodexUsage?
    @Published private(set) var codexSettings = CodexProfileConfiguration()
    @Published private(set) var codexRefreshError: String?
    @Published private(set) var isCodexRefreshing = false
    @Published private(set) var zaiUsage: ZAIUsage?
    @Published private(set) var zaiSettings = ZAIProfileConfiguration()
    @Published private(set) var zaiRefreshError: String?
    @Published private(set) var isZAIRefreshing = false
    /// z.ai publishes no public status feed; a neutral placeholder keeps the
    /// popover header honest without implying an outage.
    @Published private(set) var zaiStatus = ClaudeStatus(indicator: .unknown, description: "z.ai")
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

    // Peak hours popover (separate from main popover)
    private var peakHoursPopover: NSPopover?

    // Track which button is currently showing the popover
    private weak var currentPopoverButton: NSStatusBarButton?

    private let apiService = ClaudeAPIService()
    private var codexServices: [UUID: CodexAppServerService] = [:]
    private var codexRefreshTokens: [UUID: UUID] = [:]
    private var codexRefreshErrorsByProfile: [UUID: String] = [:]
    private let zaiAPIService = ZAIAPIService()
    private var zaiRefreshTokens: [UUID: UUID] = [:]
    private var zaiRefreshErrorsByProfile: [UUID: String] = [:]
    private let statusService = ClaudeStatusService()
    private let openAIStatusService = OpenAIStatusService()
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

    // Observer for peak hours setting changes
    private var peakHoursObserver: NSObjectProtocol?

    private var multiProfileConfigObserver: NSObjectProtocol?
    private var codexSettingsObserver: NSObjectProtocol?
    private var zaiSettingsObserver: NSObjectProtocol?
    private var profileDeletedObserver: NSObjectProtocol?

    // MARK: - Image Caching (CPU Optimization)
    private var cachedImage: NSImage?
    private var cachedImageKey: String = ""
    private var updateDebounceTimer: Timer?
    private var cachedIsDarkMode: Bool = false

    override init() {
        super.init()
        Self.current = self
    }

    func setup() {
        // Initialize cached appearance to avoid layout recursion
        cachedIsDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Observe profile changes - CRITICAL: Set up before anything else
        observeProfileChanges()

        // Initialize status bar UI manager
        statusBarUIManager = StatusBarUIManager()
        statusBarUIManager?.delegate = self

        codexUsage = profileManager.activeProfile?.codexUsage
        codexSettings = profileManager.activeProfile?.codexConfiguration
            ?? CodexProfileConfiguration()
        zaiUsage = profileManager.activeProfile?.zaiUsage
        zaiSettings = profileManager.activeProfile?.zaiConfiguration
            ?? ZAIProfileConfiguration()

        // Check if we should use multi-profile mode
        if profileManager.displayMode == .multi {
            // Multi-profile mode - setup with selected profiles
            setupMultiProfileMode()
        } else {
            // Single profile mode - setup with active profile's config
            let config = profileManager.activeProfile?.iconConfig ?? .default
            let displayConfig = effectiveMenuBarConfiguration(from: config)

            statusBarUIManager?.setup(target: self, action: #selector(togglePopover), config: displayConfig)
        }

        // Setup popover
        setupPopover()

        // Load saved data from active profile first (provides immediate feedback).
        // Credential check includes system Keychain CLI fallback so users who
        // authenticated only via `claude login` still see usage data.
        if let profile = profileManager.activeProfile {
            if hasAnyAvailableCredentials() {
                // Credentials available - show saved usage data if present
                if let savedUsage = profile.claudeUsage {
                    usage = savedUsage
                }
                if let savedAPIUsage = profile.apiUsage {
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
        observeCodexSettingsChanges()
        observeZAISettingsChanges()
        observeProfileDeletion()

        // Setup headless mode observer if enabled (for Remote Desktop support)
        setupHeadlessModeObserver()

        // Setup wake-from-sleep observer for auto-refresh
        setupWakeObserver()

        // Setup global keyboard shortcuts
        setupShortcuts()

        // Start peak hours service and indicator
        PeakHoursService.shared.start()
        let store = SharedDataStore.shared
        if store.loadPeakHoursIndicatorEnabled() && store.loadPeakHoursMenuIconEnabled() {
            statusBarUIManager?.setupPeakHoursIndicator(target: self, action: #selector(togglePeakHoursPopover))
        }
        observePeakHoursSettingChanges()
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
        if let codexSettingsObserver = codexSettingsObserver {
            NotificationCenter.default.removeObserver(codexSettingsObserver)
            self.codexSettingsObserver = nil
        }
        if let zaiSettingsObserver = zaiSettingsObserver {
            NotificationCenter.default.removeObserver(zaiSettingsObserver)
            self.zaiSettingsObserver = nil
        }
        if let profileDeletedObserver = profileDeletedObserver {
            NotificationCenter.default.removeObserver(profileDeletedObserver)
            self.profileDeletedObserver = nil
        }
        if let peakHoursObserver = peakHoursObserver {
            NotificationCenter.default.removeObserver(peakHoursObserver)
            self.peakHoursObserver = nil
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        detachedWindow?.close()
        detachedWindow = nil
        codexServices.values.forEach { $0.stop() }
        codexServices.removeAll()
        codexRefreshTokens.removeAll()
        codexRefreshErrorsByProfile.removeAll()
        isCodexRefreshing = false
        zaiRefreshTokens.removeAll()
        zaiRefreshErrorsByProfile.removeAll()
        isZAIRefreshing = false
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
        codexServices.removeValue(forKey: profileId)?.stop()
        codexRefreshTokens.removeValue(forKey: profileId)
        codexRefreshErrorsByProfile.removeValue(forKey: profileId)
        updateCodexRefreshingState()
        zaiRefreshTokens.removeValue(forKey: profileId)
        zaiRefreshErrorsByProfile.removeValue(forKey: profileId)
        updateZAIRefreshingState()
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
            self.codexUsage = profile.codexUsage
            self.codexSettings = profile.codexConfiguration
            self.codexRefreshError = self.codexRefreshErrorsByProfile[profile.id]
            self.zaiUsage = profile.zaiUsage
            self.zaiSettings = profile.zaiConfiguration
            self.zaiRefreshError = self.zaiRefreshErrorsByProfile[profile.id]
            self.isRefreshing = false
            self.updateCodexRefreshingState()
            self.updateZAIRefreshingState()
        }

        // 2. Update refresh interval with profile's setting
        restartAutoRefreshWithInterval(profile.refreshInterval)
        reconcileCodexServices()
        reconcileZAIRefreshState()

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

        let displayConfig = effectiveMenuBarConfiguration(from: config)

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
            Task { @MainActor [weak self] in
                self?.refreshUsage()
            }
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
                    // Use close() instead of performClose() to avoid async race condition
                    // No need to recreate contentViewController — SwiftUI already observes
                    // the @Published profile properties set earlier in this method
                    popover.close()
                    stopMonitoringForOutsideClicks()
                    // Activate first so the popover appears over a full-screen Space.
                    // An .accessory app that isn't active renders the popover on the
                    // desktop Space, hidden behind any frontmost full-screen app.
                    NSApp.activate(ignoringOtherApps: true)
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
                // Activate first so the popover appears over a full-screen Space
                // (otherwise an inactive .accessory app draws it on the desktop Space).
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                currentPopoverButton = button
                startMonitoringForOutsideClicks()
            }
        }
    }

    @objc private func togglePeakHoursPopover(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton else { return }

        if let popover = peakHoursPopover, popover.isShown {
            popover.close()
            peakHoursPopover = nil
            return
        }

        // Close the main popover if open
        if let mainPopover = popover, mainPopover.isShown {
            closePopover()
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 260, height: 140)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PeakHoursPopoverView())
        // Activate first so the popover appears over a full-screen Space.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        peakHoursPopover = popover
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
        let baseConfig = profileManager.activeProfile?.iconConfig ?? .default
        let effectiveConfig = effectiveMenuBarConfiguration(from: baseConfig)

        // Check if in multi-profile mode
        if profileManager.displayMode == .multi {
            // Update multi-profile icons using profiles from profileManager
            let config = profileManager.multiProfileConfig
            statusBarUIManager?.updateMultiProfileButtons(
                profiles: profileManager.profiles,
                config: config,
                activeProfileId: profileManager.activeProfile?.id,
                codexRefreshErrors: codexRefreshErrorsByProfile,
                zaiRefreshErrors: zaiRefreshErrorsByProfile
            )
        } else {
            // Single profile mode - use the standard update
            statusBarUIManager?.updateAllButtons(
                usage: usage,
                apiUsage: apiUsage,
                codexUsage: codexUsage,
                config: effectiveConfig,
                codexSettings: codexSettings,
                zaiUsage: zaiUsage,
                zaiSettings: zaiSettings
            )
        }
    }

    /// Updates a specific metric's status bar icon
    private func updateStatusBarIcon(for metricType: MenuBarMetricType) {
        statusBarUIManager?.updateButton(
            for: metricType,
            usage: usage,
            apiUsage: apiUsage,
            codexUsage: codexUsage,
            config: effectiveMenuBarConfiguration(from: profileManager.activeProfile?.iconConfig ?? .default),
            codexSettings: codexSettings,
            zaiUsage: zaiUsage,
            zaiSettings: zaiSettings
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
            Task { @MainActor [weak self] in
                self?.lastAutoRefreshTime = Date()
                self?.refreshUsage()
            }
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Debounce: only refresh if at least 10 seconds since last auto-refresh
                let timeSinceLastRefresh = Date().timeIntervalSince(self.lastAutoRefreshTime)
                guard timeSinceLastRefresh > 10 else {
                    LoggingService.shared.log("MenuBarManager: Skipping wake refresh (debounce)")
                    return
                }
                LoggingService.shared.log("MenuBarManager: Wake from sleep detected, refreshing after delay")
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self.lastAutoRefreshTime = Date()
                self.refreshUsage()
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Clear cache to force redraw with new style
                self.cachedImageKey = ""
                self.updateAllStatusBarIcons()
            }
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

    private func observeCodexSettingsChanges() {
        codexSettingsObserver = NotificationCenter.default.addObserver(
            forName: .codexSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let profile = self.profileManager.activeProfile,
                      profile.provider == .codex else { return }
                let targetChanged = !self.codexSettings.targetsSameInstallation(
                    as: profile.codexConfiguration
                )
                if targetChanged {
                    self.codexServices.removeValue(forKey: profile.id)?.stop()
                    self.codexRefreshTokens.removeValue(forKey: profile.id)
                    self.codexRefreshErrorsByProfile.removeValue(forKey: profile.id)
                    self.updateCodexRefreshingState()
                }
                self.codexSettings = profile.codexConfiguration
                self.codexUsage = profile.codexUsage
                self.codexRefreshError = self.codexRefreshErrorsByProfile[profile.id]

                if self.profileManager.displayMode == .multi {
                    self.updateMultiProfileDisplay()
                } else {
                    self.updateMenuBarDisplay(with: self.profileManager.activeProfile?.iconConfig ?? .default)
                }

                if targetChanged {
                    self.refreshCodexUsage(profileID: profile.id, reportUnavailable: true)
                }
            }
        }
    }

    private func observeZAISettingsChanges() {
        zaiSettingsObserver = NotificationCenter.default.addObserver(
            forName: .zaiSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let profile = self.profileManager.activeProfile,
                      profile.provider == .zai else { return }
                self.zaiSettings = profile.zaiConfiguration
                self.zaiUsage = profile.zaiUsage
                self.zaiRefreshError = self.zaiRefreshErrorsByProfile[profile.id]

                if self.profileManager.displayMode == .multi {
                    self.updateMultiProfileDisplay()
                } else {
                    self.updateMenuBarDisplay(with: self.profileManager.activeProfile?.iconConfig ?? .default)
                }

                self.refreshZAIUsage(profileID: profile.id, reportUnavailable: true)
            }
        }
    }

    private func observeProfileDeletion() {
        profileDeletedObserver = NotificationCenter.default.addObserver(
            forName: .profileDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let profileID = notification.object as? UUID else { return }
            Task { @MainActor in
                self.cleanupProfile(profileID)
                if self.clickedProfileId == profileID {
                    self.clickedProfileId = nil
                    self.clickedProfileUsage = nil
                    self.clickedProfileAPIUsage = nil
                    self.closePopoverOrWindow()
                }
                if self.profileManager.displayMode == .multi {
                    self.updateMultiProfileDisplay()
                }
            }
        }
    }

    private func observePeakHoursSettingChanges() {
        peakHoursObserver = NotificationCenter.default.addObserver(
            forName: .peakHoursSettingChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let store = SharedDataStore.shared
                if store.loadPeakHoursIndicatorEnabled() && store.loadPeakHoursMenuIconEnabled() {
                    self.statusBarUIManager?.setupPeakHoursIndicator(
                        target: self, action: #selector(self.togglePeakHoursPopover)
                    )
                } else {
                    self.statusBarUIManager?.removePeakHoursIndicator()
                }
            }
        }
    }

    private func handleDisplayModeChange() {
        let displayMode = profileManager.displayMode

        LoggingService.shared.log("MenuBarManager: Display mode changed to \(displayMode.rawValue)")
        reconcileCodexServices()
        reconcileZAIRefreshState()

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
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
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
    /// system Keychain CLI credentials. Mirrors the fallback logic in
    /// `ClaudeAPIService.getAuthentication()` so the refresh path isn't gated off
    /// before the API service has a chance to discover system-level credentials.
    private func hasAnyAvailableCredentials() -> Bool {
        guard let profile = profileManager.activeProfile else { return false }

        if profile.provider == .codex {
            return profile.codexConfiguration.validationError == nil
        }
        if profile.provider == .zai {
            return profile.zaiAPIKey != nil
        }
        return profile.hasUsageCredentials
            || ClaudeCodeSyncService.shared.hasUsableSystemCredentials()
    }

    private func effectiveMenuBarConfiguration(from profileConfig: MenuBarIconConfiguration) -> MenuBarIconConfiguration {
        let provider = profileManager.activeProfile?.provider ?? .claude
        let hasCredentials = hasAnyAvailableCredentials()
        let metrics = profileConfig.metrics.map { metric -> MetricIconConfig in
            var metric = metric
            switch provider {
            case .claude:
                if metric.metricType == .codex || metric.metricType == .zai || !hasCredentials { metric.isEnabled = false }
            case .codex:
                if metric.metricType != .codex { metric.isEnabled = false }
            case .zai:
                if metric.metricType != .zai { metric.isEnabled = false }
            }
            return metric
        }

        return MenuBarIconConfiguration(
            colorMode: profileConfig.colorMode,
            singleColorHex: profileConfig.singleColorHex,
            showIconNames: profileConfig.showIconNames,
            showRemainingPercentage: profileConfig.showRemainingPercentage,
            showTimeMarker: profileConfig.showTimeMarker,
            showPaceMarker: profileConfig.showPaceMarker,
            usePaceColoring: profileConfig.usePaceColoring,
            metrics: metrics
        )
    }

    private func setupMultiProfileMode() {
        reconcileCodexServices()
        reconcileZAIRefreshState()
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
            self.statusBarUIManager?.updateMultiProfileButtons(
                profiles: self.profileManager.profiles,
                config: config,
                activeProfileId: self.profileManager.activeProfile?.id,
                codexRefreshErrors: self.codexRefreshErrorsByProfile,
                zaiRefreshErrors: self.zaiRefreshErrorsByProfile
            )
        }

        LoggingService.shared.log("MenuBarManager: Multi-profile mode enabled with \(selectedProfiles.count) profiles, style=\(config.iconStyle.rawValue)")

        // Refresh data for all selected profiles that have credentials
        refreshAllSelectedProfiles()
    }

    /// Incrementally updates multi-profile status items (without destroying/recreating them)
    /// Use this when only icon config changed but the set of profiles may or may not have changed.
    private func updateMultiProfileDisplay() {
        reconcileCodexServices()
        reconcileZAIRefreshState()
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
            self.statusBarUIManager?.updateMultiProfileButtons(
                profiles: self.profileManager.profiles,
                config: config,
                activeProfileId: self.profileManager.activeProfile?.id,
                codexRefreshErrors: self.codexRefreshErrorsByProfile,
                zaiRefreshErrors: self.zaiRefreshErrorsByProfile
            )
        }

        LoggingService.shared.log("MenuBarManager: Multi-profile display updated incrementally with \(selectedProfiles.count) profiles")
    }

    /// Keeps long-lived local/SSH app-server processes only for profiles that
    /// can currently be refreshed or displayed.
    private func reconcileCodexServices() {
        let retainedProfileIDs: Set<UUID>
        if profileManager.displayMode == .multi {
            retainedProfileIDs = Set(
                profileManager.profiles
                    .filter { $0.provider == .codex && $0.isSelectedForDisplay }
                    .map(\.id)
            )
        } else if let active = profileManager.activeProfile, active.provider == .codex {
            retainedProfileIDs = [active.id]
        } else {
            retainedProfileIDs = []
        }

        let retiredProfileIDs = Set(codexServices.keys)
            .union(codexRefreshTokens.keys)
            .union(codexRefreshErrorsByProfile.keys)
            .subtracting(retainedProfileIDs)
        for profileID in retiredProfileIDs {
            codexServices.removeValue(forKey: profileID)?.stop()
            codexRefreshTokens.removeValue(forKey: profileID)
            codexRefreshErrorsByProfile.removeValue(forKey: profileID)
        }
        updateCodexRefreshingState()
    }

    /// Drops z.ai refresh bookkeeping for profiles that are no longer
    /// displayed or active. Unlike Codex there is no app-server process to
    /// stop — z.ai is a plain HTTP fetch — so only tokens and error state
    /// need pruning.
    private func reconcileZAIRefreshState() {
        let retainedProfileIDs: Set<UUID>
        if profileManager.displayMode == .multi {
            retainedProfileIDs = Set(
                profileManager.profiles
                    .filter { $0.provider == .zai && $0.isSelectedForDisplay }
                    .map(\.id)
            )
        } else if let active = profileManager.activeProfile, active.provider == .zai {
            retainedProfileIDs = [active.id]
        } else {
            retainedProfileIDs = []
        }

        let retiredProfileIDs = Set(zaiRefreshTokens.keys)
            .union(zaiRefreshErrorsByProfile.keys)
            .subtracting(retainedProfileIDs)
        for profileID in retiredProfileIDs {
            zaiRefreshTokens.removeValue(forKey: profileID)
            zaiRefreshErrorsByProfile.removeValue(forKey: profileID)
        }
        updateZAIRefreshingState()
    }

    /// Refreshes usage data for all profiles selected for multi-profile display
    private func refreshAllSelectedProfiles() {
        // Filter on `hasAnyCredentials` (not `hasUsageCredentials`) so that profiles
        // whose CLI OAuth token has expired are still polled — `fetchUsageForProfile`
        // will transparently refresh expired tokens via the refresh_token grant.
        // Excluding them here would prevent the refresh path from ever running.
        let selectedProfiles = profileManager.profiles.filter {
            $0.isSelectedForDisplay
                && ($0.provider == .codex
                    ? $0.codexConfiguration.validationError == nil
                    : $0.hasAnyCredentials)
        }

        guard !selectedProfiles.isEmpty else {
            LoggingService.shared.log("MenuBarManager: No selected profiles with usage credentials to refresh")
            updateAllStatusBarIcons()
            return
        }

        LoggingService.shared.log("MenuBarManager: Refreshing \(selectedProfiles.count) selected profiles for multi-profile mode")

        if selectedProfiles.contains(where: { $0.provider == .claude }) {
            Task {
                do {
                    let newStatus = try await self.statusService.fetchStatus()
                    await MainActor.run { self.status = newStatus }
                } catch {
                    await MainActor.run {
                        self.status = ClaudeStatus(
                            indicator: .unknown,
                            description: "Claude status unavailable"
                        )
                    }
                }
            }
        }
        if selectedProfiles.contains(where: { $0.provider == .codex }) {
            Task {
                do {
                    let newStatus = try await self.openAIStatusService.fetchStatus()
                    await MainActor.run { self.openAIStatus = newStatus }
                } catch {
                    await MainActor.run {
                        self.openAIStatus = ClaudeStatus(
                            indicator: .unknown,
                            description: "OpenAI status unavailable"
                        )
                    }
                }
            }
        }

        Task {
            await MainActor.run {
                self.isRefreshing = true
            }

            // Fetch usage for each selected profile
            for profile in selectedProfiles {
                LoggingService.shared.log("MenuBarManager: Fetching usage for profile '\(profile.name)'")

                if profile.provider == .codex {
                    guard let refreshToken = await MainActor.run(body: {
                        self.beginCodexRefresh(profileID: profile.id)
                    }) else {
                        continue
                    }
                    do {
                        let snapshot = try await self.fetchCodexUsage(
                            for: profile,
                            refreshToken: refreshToken
                        )
                        await MainActor.run {
                            guard self.codexRefreshTokens[profile.id] == refreshToken else {
                                return
                            }
                            guard let currentProfile = self.profileManager.profiles.first(where: {
                                      $0.id == profile.id && $0.provider == .codex
                                  }),
                                  currentProfile.codexConfiguration.targetsSameInstallation(
                                      as: profile.codexConfiguration
                                  ) else {
                                self.codexRefreshTokens.removeValue(forKey: profile.id)
                                self.updateCodexRefreshingState()
                                return
                            }
                            self.codexRefreshTokens.removeValue(forKey: profile.id)
                            self.codexRefreshErrorsByProfile.removeValue(forKey: profile.id)
                            self.profileManager.saveCodexUsage(snapshot, for: profile.id)
                            if profile.id == self.profileManager.activeProfile?.id {
                                self.codexUsage = snapshot
                                self.codexSettings = currentProfile.codexConfiguration
                                self.codexRefreshError = nil
                            }
                            NotificationManager.shared.checkAndNotify(
                                codexUsage: snapshot,
                                profileID: profile.id,
                                profileName: currentProfile.name,
                                settings: currentProfile.notificationSettings,
                                selectedRateLimitID: currentProfile.codexConfiguration.selectedRateLimitID
                            )
                            self.updateCodexRefreshingState()
                        }
                    } catch {
                        LoggingService.shared.logError("Failed to refresh Codex profile '\(profile.name)': \(error.localizedDescription)")
                        await MainActor.run {
                            guard self.codexRefreshTokens[profile.id] == refreshToken else {
                                return
                            }
                            guard let currentProfile = self.profileManager.profiles.first(where: {
                                      $0.id == profile.id && $0.provider == .codex
                                  }),
                                  currentProfile.codexConfiguration.targetsSameInstallation(
                                      as: profile.codexConfiguration
                                  ) else {
                                self.codexRefreshTokens.removeValue(forKey: profile.id)
                                self.updateCodexRefreshingState()
                                return
                            }
                            self.codexRefreshTokens.removeValue(forKey: profile.id)
                            self.codexRefreshErrorsByProfile[profile.id] = error.localizedDescription
                            if profile.id == self.profileManager.activeProfile?.id {
                                self.codexRefreshError = error.localizedDescription
                            }
                            self.updateCodexRefreshingState()
                        }
                    }
                    continue
                }

                if profile.provider == .zai {
                    await self.refreshZAISelectedProfile(profile)
                    continue
                }

                // Capture previous usage for reset detection
                let previousUsage = profile.claudeUsage

                do {
                    let newUsage = try await fetchUsageForProfile(profile)

                    await MainActor.run {
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
                            UsageHistoryService.shared.recordSessionPeriodic(for: profile.id, usage: newUsage)
                        }

                        if !flags.weekly {
                            UsageHistoryService.shared.recordWeeklyPeriodic(for: profile.id, usage: newUsage)
                        }

                        // Clear reset flags for next cycle
                        self.resetJustRecorded[profile.id] = (session: false, weekly: false)

                        // Save to profile
                        self.profileManager.saveClaudeUsage(newUsage, for: profile.id)
                        LoggingService.shared.log("MenuBarManager: Saved usage for profile '\(profile.name)' - session: \(newUsage.sessionPercentage)%")

                        // If this is the active profile, also update the manager's usage
                        if profile.id == self.profileManager.activeProfile?.id {
                            self.usage = newUsage

                            // Write statusline cache for instant CLI rendering
                            if StatuslineService.shared.isInstalled {
                                StatuslineService.shared.writeUsageCache(
                                    usage: newUsage,
                                    profileName: profile.name
                                )
                            }
                        }
                    }
                } catch {
                    LoggingService.shared.logError("Failed to refresh profile '\(profile.name)': \(error.localizedDescription)")
                }

                // Fetch API usage if this profile has API console credentials
                if let apiSessionKey = profile.apiSessionKey,
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
                    activeProfileId: self.profileManager.activeProfile?.id,
                    codexRefreshErrors: self.codexRefreshErrorsByProfile,
                    zaiRefreshErrors: self.zaiRefreshErrorsByProfile
                )
                self.consecutiveRefreshFailures = 0
                self.lastRefreshError = nil
                self.hasCredentialError = false
                self.lastSuccessfulRefreshTime = Date()
                self.isRefreshing = false

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

    /// Fetches usage data for a specific profile using its credentials
    private func fetchUsageForProfile(_ profile: Profile) async throws -> ClaudeUsage {
        // Priority 1: claude.ai session key (cookie-based)
        if let sessionKey = profile.claudeSessionKey,
           let orgId = profile.organizationId {
            return try await apiService.fetchUsageData(sessionKey: sessionKey, organizationId: orgId)
        }

        // Priority 2: CLI OAuth credentials.
        // `ensureFreshCredentials` picks the source automatically:
        //   - If `profile.customKeychainServiceName` is set → pull fresh from that keychain entry
        //     (which Claude Code rotates during normal CLI use). No network refresh needed when
        //     the token there is still valid; otherwise transparently refresh via the
        //     refresh_token grant and write back to both keychain and profile cache.
        //   - Otherwise → use the profile's cached `cliCredentialsJSON`, refreshing if expired.
        // If `ensureFreshCredentials` returns nil (e.g. network failure during refresh), fall
        // back to the stored cliCredentialsJSON so a still-valid cached token isn't wasted.
        if profile.cliCredentialsJSON != nil || profile.customKeychainServiceName != nil {
            let usableJSON = await ClaudeCodeSyncService.shared.ensureFreshCredentials(for: profile.id)
                ?? profile.cliCredentialsJSON
            if let usableJSON = usableJSON,
               !ClaudeCodeSyncService.shared.isTokenExpired(usableJSON),
               let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: usableJSON) {
                return try await apiService.fetchUsageData(oauthAccessToken: accessToken)
            }
        }

        // Priority 3: System Keychain CLI OAuth token
        // Only use system keychain for the active profile — the keychain/credentials file
        // reflects the currently active `claude` CLI session. Using it for a non-active
        // profile would silently return the active profile's stats.
        if profile.id == profileManager.activeProfile?.id,
           let systemCredentials = try? ClaudeCodeSyncService.shared.readSystemCredentials(),
           !ClaudeCodeSyncService.shared.isTokenExpired(systemCredentials),
           let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: systemCredentials) {
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

        let displayConfig = effectiveMenuBarConfiguration(from: profile.iconConfig)

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

        // Single profile mode - refresh only active profile
        guard let profile = profileManager.activeProfile else {
            LoggingService.shared.log("MenuBarManager.refreshUsage: No active profile")
            return
        }

        if profile.provider == .codex {
            refreshCodexUsage(profileID: profile.id, reportUnavailable: true)
            Task {
                do {
                    let newStatus = try await openAIStatusService.fetchStatus()
                    await MainActor.run { self.openAIStatus = newStatus }
                } catch {
                    LoggingService.shared.log(
                        "MenuBarManager: Failed to fetch OpenAI status: \(error.localizedDescription)"
                    )
                    await MainActor.run {
                        self.openAIStatus = ClaudeStatus(
                            indicator: .unknown,
                            description: "OpenAI status unavailable"
                        )
                    }
                }
            }
            return
        }

        if profile.provider == .zai {
            refreshZAIUsage(profileID: profile.id, reportUnavailable: true)
            return
        }

        // Detailed logging
        LoggingService.shared.log("MenuBarManager.refreshUsage called:")
        LoggingService.shared.log("  - Profile: '\(profile.name)'")
        LoggingService.shared.log("  - hasUsageCredentials: \(profile.hasUsageCredentials)")

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

        LoggingService.shared.log("MenuBarManager: Proceeding with refresh")
        let sourceProfile = profile
        let sourceProfileID = profile.id
        Task {
            // Set loading state (keep existing data visible during refresh)
            await MainActor.run {
                self.isRefreshing = true
            }

            // Capture previous usage BEFORE fetching new data (for reset detection)
            let previousUsage = sourceProfile.claudeUsage
            let previousAPIUsage = sourceProfile.apiUsage

            // Fetch usage and status in parallel
            async let usageResult = fetchUsageForProfile(sourceProfile)
            async let statusResult = statusService.fetchStatus()

            var usageSuccess = false

            // Fetch usage with proper error handling
            do {
                let newUsage = try await usageResult

                await MainActor.run {
                    // Check for resets before updating usage
                    self.checkAndRecordSessionReset(
                        profileId: sourceProfileID,
                        previousUsage: previousUsage,
                        newUsage: newUsage
                    )
                    self.checkAndRecordWeeklyReset(
                        profileId: sourceProfileID,
                        previousUsage: previousUsage,
                        newUsage: newUsage
                    )
                    UsageHistoryService.shared.recordSessionPeriodic(for: sourceProfileID, usage: newUsage)
                    UsageHistoryService.shared.recordWeeklyPeriodic(for: sourceProfileID, usage: newUsage)
                    self.profileManager.saveClaudeUsage(newUsage, for: sourceProfileID)

                    NotificationManager.shared.checkAndNotify(
                        usage: newUsage,
                        profileName: sourceProfile.name,
                        settings: sourceProfile.notificationSettings
                    )

                    // Visible state and profile-switch side effects belong only
                    // to the profile that initiated this request.
                    guard self.profileManager.activeProfile?.id == sourceProfileID else { return }
                    self.usage = newUsage
                    if StatuslineService.shared.isInstalled {
                        StatuslineService.shared.writeUsageCache(
                            usage: newUsage,
                            profileName: sourceProfile.name
                        )
                    }
                    self.updateAllStatusBarIcons()
                    self.checkAutoSwitchIfNeeded(usage: newUsage, currentProfile: sourceProfile)
                }

                // Record success for circuit breaker
                ErrorRecovery.shared.recordSuccess(for: .api)
                usageSuccess = true

                await MainActor.run {
                    guard self.profileManager.activeProfile?.id == sourceProfileID else { return }
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
                    guard self.profileManager.activeProfile?.id == sourceProfileID else { return }
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
                await MainActor.run {
                    self.status = ClaudeStatus(
                        indicator: .unknown,
                        description: "Claude status unavailable"
                    )
                }
            }

            // Fetch API usage using the same source profile captured above.
            if let apiSessionKey = sourceProfile.apiSessionKey,
               let orgId = sourceProfile.apiOrganizationId {
                do {
                    let newAPIUsage = try await apiService.fetchAPIUsageData(organizationId: orgId, apiSessionKey: apiSessionKey)
                    await MainActor.run {
                        self.checkAndRecordBillingCycleReset(
                            profileId: sourceProfileID,
                            previousUsage: previousAPIUsage,
                            newUsage: newAPIUsage
                        )
                        self.profileManager.saveAPIUsage(newAPIUsage, for: sourceProfileID)
                        if self.profileManager.activeProfile?.id == sourceProfileID {
                            self.apiUsage = newAPIUsage
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
                if self.profileManager.activeProfile?.id == sourceProfileID {
                    self.isRefreshing = false
                }

                // Show success notification if this was user-triggered and successful
                if self.profileManager.activeProfile?.id == sourceProfileID,
                   usageSuccess,
                   abs(self.lastRefreshTriggerTime.timeIntervalSinceNow) < 5 {
                    self.showSuccessNotification()
                }
            }
        }
    }

    func refreshCodexUsageNow() {
        guard let profile = profileManager.activeProfile, profile.provider == .codex else { return }
        refreshCodexUsage(profileID: profile.id, reportUnavailable: true)
    }

    func refreshZAIUsageNow() {
        guard let profile = profileManager.activeProfile, profile.provider == .zai else { return }
        refreshZAIUsage(profileID: profile.id, reportUnavailable: true)
    }

    private func refreshCodexUsage(profileID: UUID, reportUnavailable: Bool = false) {
        guard let profile = profileManager.profiles.first(where: {
            $0.id == profileID && $0.provider == .codex
        }) else { return }
        if let validationError = profile.codexConfiguration.validationError {
            if reportUnavailable {
                codexRefreshErrorsByProfile[profile.id] = validationError
                if profileManager.activeProfile?.id == profile.id {
                    codexRefreshError = validationError
                }
            }
            return
        }
        guard let refreshToken = beginCodexRefresh(profileID: profileID) else { return }

        Task {
            do {
                let snapshot = try await fetchCodexUsage(
                    for: profile,
                    refreshToken: refreshToken
                )
                await MainActor.run {
                    guard self.codexRefreshTokens[profile.id] == refreshToken else {
                        return
                    }
                    guard let currentProfile = self.profileManager.profiles.first(where: {
                              $0.id == profile.id && $0.provider == .codex
                          }),
                          currentProfile.codexConfiguration.targetsSameInstallation(
                              as: profile.codexConfiguration
                          ) else {
                        self.codexRefreshTokens.removeValue(forKey: profile.id)
                        self.updateCodexRefreshingState()
                        return
                    }
                    self.codexRefreshTokens.removeValue(forKey: profile.id)
                    self.codexRefreshErrorsByProfile.removeValue(forKey: profile.id)
                    self.profileManager.saveCodexUsage(snapshot, for: profile.id)
                    WidgetSnapshotService.shared.publish(
                        profiles: self.profileManager.profiles,
                        activeProfileId: self.profileManager.activeProfile?.id
                    )
                    if self.profileManager.activeProfile?.id == profile.id {
                        self.codexUsage = snapshot
                        self.codexSettings = currentProfile.codexConfiguration
                        self.codexRefreshError = nil
                    }
                    NotificationManager.shared.checkAndNotify(
                        codexUsage: snapshot,
                        profileID: profile.id,
                        profileName: currentProfile.name,
                        settings: currentProfile.notificationSettings,
                        selectedRateLimitID: currentProfile.codexConfiguration.selectedRateLimitID
                    )
                    self.updateAllStatusBarIcons()
                    self.updateCodexRefreshingState()
                }
            } catch {
                LoggingService.shared.log("MenuBarManager: Codex usage refresh failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.codexRefreshTokens[profile.id] == refreshToken else {
                        return
                    }
                    guard let currentProfile = self.profileManager.profiles.first(where: {
                              $0.id == profile.id && $0.provider == .codex
                          }),
                          currentProfile.codexConfiguration.targetsSameInstallation(
                              as: profile.codexConfiguration
                          ) else {
                        self.codexRefreshTokens.removeValue(forKey: profile.id)
                        self.updateCodexRefreshingState()
                        return
                    }
                    self.codexRefreshTokens.removeValue(forKey: profile.id)
                    self.codexRefreshErrorsByProfile[profile.id] = error.localizedDescription
                    if self.profileManager.activeProfile?.id == profile.id {
                        self.codexRefreshError = error.localizedDescription
                    }
                    self.updateCodexRefreshingState()
                    self.updateAllStatusBarIcons()
                }
            }
        }
    }

    private func beginCodexRefresh(profileID: UUID) -> UUID? {
        guard codexRefreshTokens[profileID] == nil else { return nil }
        let refreshToken = UUID()
        codexRefreshTokens[profileID] = refreshToken
        updateCodexRefreshingState()
        return refreshToken
    }

    private func updateCodexRefreshingState() {
        guard let profile = profileManager.activeProfile, profile.provider == .codex else {
            isCodexRefreshing = false
            return
        }
        isCodexRefreshing = codexRefreshTokens[profile.id] != nil
    }

    private func fetchCodexUsage(
        for profile: Profile,
        refreshToken: UUID
    ) async throws -> CodexUsage {
        guard let service = await MainActor.run(body: { () -> CodexAppServerService? in
            guard self.codexRefreshTokens[profile.id] == refreshToken,
                  let currentProfile = self.profileManager.profiles.first(where: {
                      $0.id == profile.id && $0.provider == .codex
                  }),
                  currentProfile.codexConfiguration.targetsSameInstallation(
                      as: profile.codexConfiguration
                  ) else {
                return nil
            }
            if let existing = self.codexServices[profile.id] {
                return existing
            }
            let created = CodexAppServerService()
            self.codexServices[profile.id] = created
            return created
        }) else {
            throw CancellationError()
        }
        return try await service.fetchUsage(configuration: profile.codexConfiguration)
    }

    private func refreshZAIUsage(profileID: UUID, reportUnavailable: Bool = false) {
        guard let profile = profileManager.profiles.first(where: {
            $0.id == profileID && $0.provider == .zai
        }) else { return }
        guard let apiKey = profile.zaiAPIKey else {
            if reportUnavailable {
                zaiRefreshErrorsByProfile[profile.id] = "No z.ai API key configured."
                if profileManager.activeProfile?.id == profile.id {
                    zaiRefreshError = "No z.ai API key configured."
                }
            }
            return
        }
        guard let refreshToken = beginZAIRefresh(profileID: profileID) else { return }

        Task {
            do {
                let snapshot = try await fetchZAIUsage(
                    for: profile,
                    apiKey: apiKey,
                    refreshToken: refreshToken
                )
                await MainActor.run {
                    guard self.zaiRefreshTokens[profile.id] == refreshToken else {
                        return
                    }
                    guard let currentProfile = self.profileManager.profiles.first(where: {
                              $0.id == profile.id && $0.provider == .zai
                          }),
                          currentProfile.zaiAPIKey == apiKey else {
                        self.zaiRefreshTokens.removeValue(forKey: profile.id)
                        self.updateZAIRefreshingState()
                        return
                    }
                    self.zaiRefreshTokens.removeValue(forKey: profile.id)
                    self.zaiRefreshErrorsByProfile.removeValue(forKey: profile.id)
                    self.profileManager.saveZAIUsage(snapshot, for: profile.id)
                    WidgetSnapshotService.shared.publish(
                        profiles: self.profileManager.profiles,
                        activeProfileId: self.profileManager.activeProfile?.id
                    )
                    if self.profileManager.activeProfile?.id == profile.id {
                        self.zaiUsage = snapshot
                        self.zaiSettings = currentProfile.zaiConfiguration
                        self.zaiRefreshError = nil
                    }
                    NotificationManager.shared.checkAndNotify(
                        zaiUsage: snapshot,
                        profileID: profile.id,
                        profileName: currentProfile.name,
                        settings: currentProfile.notificationSettings,
                        selectedLimitID: currentProfile.zaiConfiguration.selectedLimitID
                    )
                    self.updateAllStatusBarIcons()
                    self.updateZAIRefreshingState()
                }
            } catch {
                LoggingService.shared.log("MenuBarManager: z.ai usage refresh failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.zaiRefreshTokens[profile.id] == refreshToken else {
                        return
                    }
                    guard let currentProfile = self.profileManager.profiles.first(where: {
                              $0.id == profile.id && $0.provider == .zai
                          }),
                          currentProfile.zaiAPIKey == apiKey else {
                        self.zaiRefreshTokens.removeValue(forKey: profile.id)
                        self.updateZAIRefreshingState()
                        return
                    }
                    self.zaiRefreshTokens.removeValue(forKey: profile.id)
                    self.zaiRefreshErrorsByProfile[profile.id] = error.localizedDescription
                    if self.profileManager.activeProfile?.id == profile.id {
                        self.zaiRefreshError = error.localizedDescription
                    }
                    self.updateZAIRefreshingState()
                    self.updateAllStatusBarIcons()
                }
            }
        }
    }

    private func beginZAIRefresh(profileID: UUID) -> UUID? {
        guard zaiRefreshTokens[profileID] == nil else { return nil }
        let refreshToken = UUID()
        zaiRefreshTokens[profileID] = refreshToken
        updateZAIRefreshingState()
        return refreshToken
    }

    /// Refreshes one z.ai profile as part of the multi-profile refresh loop.
    /// Re-validates the refresh token and the profile's API key after every
    /// suspension so racing profile edits can't apply one key's quota to
    /// another profile.
    private func refreshZAISelectedProfile(_ profile: Profile) async {
        guard let apiKey = profile.zaiAPIKey else { return }
        guard let refreshToken = beginZAIRefresh(profileID: profile.id) else { return }

        do {
            let snapshot = try await fetchZAIUsage(
                for: profile,
                apiKey: apiKey,
                refreshToken: refreshToken
            )
            guard zaiRefreshTokens[profile.id] == refreshToken else { return }
            guard let currentProfile = profileManager.profiles.first(where: {
                $0.id == profile.id && $0.provider == .zai
            }), currentProfile.zaiAPIKey == apiKey else {
                zaiRefreshTokens.removeValue(forKey: profile.id)
                updateZAIRefreshingState()
                return
            }
            zaiRefreshTokens.removeValue(forKey: profile.id)
            zaiRefreshErrorsByProfile.removeValue(forKey: profile.id)
            profileManager.saveZAIUsage(snapshot, for: profile.id)
            if profile.id == profileManager.activeProfile?.id {
                zaiUsage = snapshot
                zaiSettings = currentProfile.zaiConfiguration
                zaiRefreshError = nil
            }
            NotificationManager.shared.checkAndNotify(
                zaiUsage: snapshot,
                profileID: profile.id,
                profileName: currentProfile.name,
                settings: currentProfile.notificationSettings,
                selectedLimitID: currentProfile.zaiConfiguration.selectedLimitID
            )
            updateZAIRefreshingState()
        } catch {
            LoggingService.shared.logError("Failed to refresh z.ai profile '\(profile.name)': \(error.localizedDescription)")
            guard zaiRefreshTokens[profile.id] == refreshToken else { return }
            guard let currentProfile = profileManager.profiles.first(where: {
                $0.id == profile.id && $0.provider == .zai
            }), currentProfile.zaiAPIKey == apiKey else {
                zaiRefreshTokens.removeValue(forKey: profile.id)
                updateZAIRefreshingState()
                return
            }
            zaiRefreshTokens.removeValue(forKey: profile.id)
            zaiRefreshErrorsByProfile[profile.id] = error.localizedDescription
            if profile.id == profileManager.activeProfile?.id {
                zaiRefreshError = error.localizedDescription
            }
            updateZAIRefreshingState()
        }
    }

    private func updateZAIRefreshingState() {
        guard let profile = profileManager.activeProfile, profile.provider == .zai else {
            isZAIRefreshing = false
            return
        }
        isZAIRefreshing = zaiRefreshTokens[profile.id] != nil
    }

    private func fetchZAIUsage(
        for profile: Profile,
        apiKey: String,
        refreshToken: UUID
    ) async throws -> ZAIUsage {
        guard await MainActor.run(body: {
            self.zaiRefreshTokens[profile.id] == refreshToken
                && self.profileManager.profiles.contains(where: {
                    $0.id == profile.id && $0.provider == .zai
                })
        }) else {
            throw CancellationError()
        }
        return try await zaiAPIService.fetchUsage(apiKey: apiKey)
    }

    /// Shows a brief success notification for user-triggered refreshes
    private func showSuccessNotification() {
        NotificationManager.shared.sendSuccessNotification()
    }

    // MARK: - Auto-Switch Profile on Session Limit

    /// Checks if the current profile hit 100% and switches to the next available one
    private func checkAutoSwitchIfNeeded(usage: ClaudeUsage, currentProfile: Profile) {
        guard currentProfile.provider == .claude else { return }

        // Guard: feature must be enabled
        guard SharedDataStore.shared.loadAutoSwitchProfileEnabled() else { return }

        // Auto-switch changes Claude Code credentials, so Codex provider
        // profiles are never eligible targets.
        let profiles = profileManager.profiles
        guard profiles.filter({ $0.provider == .claude }).count > 1 else { return }

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
        guard let nextProfile = Self.nextClaudeAutoSwitchProfile(
            in: profiles,
            after: currentProfile.id
        ) else {
            LoggingService.shared.log("AutoSwitch: All profiles at 100% or unavailable, staying on '\(currentProfile.name)'")
            return
        }

        LoggingService.shared.log("AutoSwitch: Switching from '\(currentProfile.name)' to '\(nextProfile.name)'")

        // Activate the next profile
        let fromName = currentProfile.name
        let toName = nextProfile.name
        Task {
            await profileManager.activateProfile(nextProfile.id)

            await MainActor.run {
                // Send notification
                NotificationManager.shared.sendAutoSwitchNotification(fromProfile: fromName, toProfile: toName)

                // Post notification for UI reactivity
                NotificationCenter.default.post(name: .autoSwitchProfileTriggered, object: nil)
            }
        }
    }

    /// Finds the next Claude profile with available session capacity, wrapping around.
    nonisolated static func nextClaudeAutoSwitchProfile(
        in profiles: [Profile],
        after currentProfileID: UUID
    ) -> Profile? {
        guard let currentIndex = profiles.firstIndex(where: { $0.id == currentProfileID }) else {
            return nil
        }

        let count = profiles.count
        for offset in 1..<count {
            let index = (currentIndex + offset) % count
            let candidate = profiles[index]

            guard candidate.provider == .claude, candidate.hasUsageCredentials else { continue }

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

    /// Normalizes a date to minute precision for comparison (ignores seconds)
    private func normalizeToMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Checks if a session reset occurred and records a snapshot if so
    private func checkAndRecordSessionReset(
        profileId: UUID,
        previousUsage: ClaudeUsage?,
        newUsage: ClaudeUsage
    ) {
        let lastKnown = lastKnownSessionResetTime[profileId]
        let newResetTime = normalizeToMinute(newUsage.sessionResetTime)

        // First time seeing this profile - just record the reset time
        if lastKnown == nil {
            lastKnownSessionResetTime[profileId] = newResetTime
            return
        }

        // Normalize the last known time for comparison
        let normalizedLastKnown = normalizeToMinute(lastKnown!)

        // Check if reset time changed (indicates a reset occurred)
        // Use != instead of > to handle clock changes and backward time jumps
        if newResetTime != normalizedLastKnown {
            // Reset detected! Record snapshot of the previous usage
            LoggingService.shared.log("History: Session reset detected for profile \(profileId.uuidString.prefix(8)). Old: \(normalizedLastKnown), New: \(newResetTime)")
            if let prevUsage = previousUsage {
                Task { @MainActor in
                    UsageHistoryService.shared.recordSessionReset(
                        for: profileId,
                        previousUsage: prevUsage,
                        resetTime: prevUsage.sessionResetTime  // Use original reset time, not normalized
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
        let newResetTime = normalizeToMinute(newUsage.weeklyResetTime)

        // First time seeing this profile - just record the reset time
        if lastKnown == nil {
            lastKnownWeeklyResetTime[profileId] = newResetTime
            LoggingService.shared.log("History: Initial weekly reset time for profile \(profileId.uuidString.prefix(8)): \(newResetTime)")
            return
        }

        // Normalize the last known time for comparison
        let normalizedLastKnown = normalizeToMinute(lastKnown!)

        // Check if reset time changed (indicates a reset occurred)
        // Use != instead of > to handle clock changes and backward time jumps
        if newResetTime != normalizedLastKnown {
            // Reset detected! Record snapshot of the previous usage
            LoggingService.shared.log("History: Weekly reset detected for profile \(profileId.uuidString.prefix(8)). Old: \(normalizedLastKnown), New: \(newResetTime)")
            if let prevUsage = previousUsage {
                Task { @MainActor in
                    UsageHistoryService.shared.recordWeeklyReset(
                        for: profileId,
                        previousUsage: prevUsage,
                        resetTime: prevUsage.weeklyResetTime  // Use original reset time, not normalized
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
        let newResetTime = normalizeToMinute(newUsage.resetsAt)

        // First time seeing this profile - just record the reset time
        if lastKnown == nil {
            lastKnownAPIResetTime[profileId] = newResetTime
            LoggingService.shared.log("History: Initial API reset time for profile \(profileId.uuidString.prefix(8)): \(newResetTime)")
            return
        }

        // Normalize the last known time for comparison
        let normalizedLastKnown = normalizeToMinute(lastKnown!)

        // Check if reset time changed (indicates a reset occurred)
        // Use != instead of > to handle clock changes and backward time jumps
        if newResetTime != normalizedLastKnown {
            // Reset detected! Record snapshot of the previous usage
            LoggingService.shared.log("History: Billing cycle reset detected for profile \(profileId.uuidString.prefix(8)). Old: \(normalizedLastKnown), New: \(newResetTime)")
            if let prevUsage = previousUsage {
                Task { @MainActor in
                    UsageHistoryService.shared.recordBillingCycleReset(
                        for: profileId,
                        previousUsage: prevUsage,
                        resetTime: prevUsage.resetsAt  // Use original reset time, not normalized
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
        statusBarUIManager?.updatePeakHoursIcon()
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
