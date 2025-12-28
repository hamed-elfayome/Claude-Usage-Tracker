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

    private let apiService = ClaudeAPIService()
    private let statusService = ClaudeStatusService()
    private let dataStore = DataStore.shared
    private let networkMonitor = NetworkMonitor.shared

    // Observer for refresh interval changes
    private var refreshIntervalObserver: NSKeyValueObservation?

    // Observer for appearance changes
    private var appearanceObserver: NSKeyValueObservation?

    // Observer for icon style changes
    private var iconStyleObserver: NSObjectProtocol?

    // Observer for icon configuration changes
    private var iconConfigObserver: NSObjectProtocol?

    // MARK: - Image Caching (CPU Optimization)
    private var cachedImage: NSImage?
    private var cachedImageKey: String = ""
    private var updateDebounceTimer: Timer?
    private var cachedIsDarkMode: Bool = false

    func setup() {
        // Initialize cached appearance to avoid layout recursion
        cachedIsDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Setup new multi-metric status bar system
        let config = dataStore.loadMenuBarIconConfiguration()
        statusBarUIManager = StatusBarUIManager()
        statusBarUIManager?.delegate = self
        statusBarUIManager?.setup(target: self, action: #selector(togglePopover), config: config)

        // Setup popover
        setupPopover()

        // Load saved data first (provides immediate feedback)
        if let savedUsage = dataStore.loadUsage() {
            usage = savedUsage
            updateAllStatusBarIcons()
        }
        if let savedAPIUsage = dataStore.loadAPIUsage() {
            apiUsage = savedAPIUsage
        }

        // Start network monitoring - fetch data when network is available
        networkMonitor.onNetworkAvailable = { [weak self] in
            self?.refreshUsage()
        }
        networkMonitor.startMonitoring()

        // Initial data fetch (with small delay for launch-at-login scenarios)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshUsage()
        }

        // Start auto-refresh timer
        startAutoRefresh()

        // Observe refresh interval changes
        observeRefreshIntervalChanges()

        // Observe appearance changes
        observeAppearanceChanges()

        // Observe icon style changes
        observeIconStyleChanges()

        // Observe icon configuration changes
        observeIconConfigChanges()
    }

    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        networkMonitor.stopMonitoring()
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

    @objc private func togglePopover() {
        // Use primary button (first enabled metric) for popover positioning
        guard let button = statusBarUIManager?.primaryButton else { return }

        // If there's a detached window, close it
        if let window = detachedWindow {
            window.close()
            detachedWindow = nil
            return
        }

        // Otherwise toggle the popover
        if let popover = popover {
            if popover.isShown {
                closePopover()
            } else {
                // Recreate content if it was moved to a detached window
                if popover.contentViewController == nil {
                    popover.contentViewController = createContentViewController()
                }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                startMonitoringForOutsideClicks()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        stopMonitoringForOutsideClicks()
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
        statusBarUIManager?.updateAllButtons(
            usage: usage,
            apiUsage: apiUsage,
            manager: self
        )
    }

    /// Updates a specific metric's status bar icon
    private func updateStatusBarIcon(for metricType: MenuBarMetricType) {
        statusBarUIManager?.updateButton(
            for: metricType,
            usage: usage,
            apiUsage: apiUsage,
            manager: self
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
        let interval = dataStore.loadRefreshInterval()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
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
        // Observe icon style changes from settings
        iconStyleObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconStyleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Clear cache to force redraw with new style
            self.cachedImageKey = ""
            self.updateAllStatusBarIcons()
        }
    }

    private var lastKnownConfig: MenuBarIconConfiguration?

    private func observeIconConfigChanges() {
        // Observe configuration changes (metrics enabled/disabled, order changes, etc.)
        iconConfigObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconConfigChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Reload configuration
            let newConfig = self.dataStore.loadMenuBarIconConfiguration()

            // Check if enabled metrics actually changed
            let oldEnabledMetrics = Set(self.lastKnownConfig?.enabledMetrics.map { $0.metricType } ?? [])
            let newEnabledMetrics = Set(newConfig.enabledMetrics.map { $0.metricType })

            if oldEnabledMetrics != newEnabledMetrics {
                // Metrics changed - recreate status bar items
                self.statusBarUIManager?.updateConfiguration(
                    target: self,
                    action: #selector(self.togglePopover),
                    config: newConfig
                )
            }
            // If only styling changed, skip status bar recreation

            // Always update the icons (styling might have changed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateAllStatusBarIcons()
            }

            // Save current config for next comparison
            self.lastKnownConfig = newConfig
        }
    }

    func refreshUsage() {
        Task {
            // Fetch usage and status in parallel
            async let usageResult = apiService.fetchUsageData()
            async let statusResult = statusService.fetchStatus()

            // Fetch usage with proper error handling
            do {
                let newUsage = try await usageResult

                await MainActor.run {
                    self.usage = newUsage
                    dataStore.saveUsage(newUsage)

                    // Update all menu bar icons
                    self.updateAllStatusBarIcons()

                    // Check if we should send notifications
                    NotificationManager.shared.checkAndNotify(usage: newUsage)
                }

                // Record success for circuit breaker
                ErrorRecovery.shared.recordSuccess(for: .api)

            } catch {
                // Convert to AppError and log
                let appError = AppError.wrap(error)
                ErrorLogger.shared.log(appError, severity: .warning)

                // Record failure for circuit breaker
                ErrorRecovery.shared.recordFailure(for: .api)

                // Don't show error to user for background refresh - just log it
                print("⚠️ [\(appError.code.rawValue)] Failed to fetch usage: \(appError.message)")
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
                print("ℹ️ [\(appError.code.rawValue)] Failed to fetch status: \(appError.message)")
            }

            // Fetch API usage if enabled
            if dataStore.loadAPITrackingEnabled(),
               let apiSessionKey = dataStore.loadAPISessionKey(),
               let orgId = dataStore.loadAPIOrganizationId() {
                do {
                    let newAPIUsage = try await apiService.fetchAPIUsageData(organizationId: orgId, apiSessionKey: apiSessionKey)
                    await MainActor.run {
                        self.apiUsage = newAPIUsage
                        dataStore.saveAPIUsage(newAPIUsage)
                    }
                } catch {
                    // Convert to AppError and log
                    let appError = AppError.wrap(error)
                    ErrorLogger.shared.log(appError, severity: .info)

                    print("ℹ️ [\(appError.code.rawValue)] Failed to fetch API usage: \(appError.message)")
                }
            }
        }
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
