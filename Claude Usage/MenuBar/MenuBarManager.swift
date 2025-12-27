import Cocoa
import SwiftUI
import Combine

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    @Published private(set) var usage: ClaudeUsage = .empty
    @Published private(set) var status: ClaudeStatus = .unknown
    @Published private(set) var apiUsage: APIUsage? = nil

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

    // MARK: - Image Caching (CPU Optimization)
    private var cachedImage: NSImage?
    private var cachedImageKey: String = ""
    private var updateDebounceTimer: Timer?

    func setup() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusButton(button, usage: usage)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Setup popover
        setupPopover()

        // Load saved data first (provides immediate feedback)
        if let savedUsage = dataStore.loadUsage() {
            usage = savedUsage
            if let button = statusItem?.button {
                updateStatusButton(button, usage: savedUsage)
            }
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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        detachedWindow?.close()
        detachedWindow = nil
        statusItem = nil
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
        guard let button = statusItem?.button else { return }
        
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
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
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

    private func updateStatusButton(_ button: NSStatusBarButton, usage: ClaudeUsage) {
        let iconStyle = dataStore.loadMenuBarIconStyle()
        let isDarkAppearance = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let monochromeMode = dataStore.loadMonochromeMode()

        // Generate cache key based on all factors that affect the image
        let percentage = Int(usage.sessionPercentage)
        let cacheKey = "\(percentage)_\(isDarkAppearance)_\(iconStyle.rawValue)_\(monochromeMode)"

        // Check if we can reuse the cached image
        if cachedImage != nil && cachedImageKey == cacheKey {
            // Image hasn't changed, skip expensive redraw
            return
        }

        // Debounce rapid updates to prevent rendering congestion
        updateDebounceTimer?.invalidate()
        updateDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // Create the image based on selected style
            let image: NSImage
            switch iconStyle {
            case .battery:
                image = self.createBatteryStyle(usage: usage, isDarkMode: isDarkAppearance, monochromeMode: monochromeMode)
            case .progressBar:
                image = self.createProgressBarStyle(usage: usage, isDarkMode: isDarkAppearance, monochromeMode: monochromeMode)
            case .percentageOnly:
                image = self.createPercentageOnlyStyle(usage: usage, isDarkMode: isDarkAppearance, monochromeMode: monochromeMode)
            case .icon:
                image = self.createIconWithBarStyle(usage: usage, isDarkMode: isDarkAppearance, monochromeMode: monochromeMode)
            case .compact:
                image = self.createCompactStyle(usage: usage, isDarkMode: isDarkAppearance, monochromeMode: monochromeMode)
            }

            // Cache the image and key
            self.cachedImage = image
            self.cachedImageKey = cacheKey

            // Update the button image
            button.image = image
            button.image?.isTemplate = false
            button.title = ""
        }
    }

    // MARK: - Icon Style: Battery (Classic)
    private func createBatteryStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let percentage = CGFloat(usage.sessionPercentage) / 100.0

        // Create a taller image to fit battery + text
        let width: CGFloat = 42
        let totalHeight: CGFloat = 28
        let barHeight: CGFloat = 10
        let image = NSImage(size: NSSize(width: width, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Choose outline and text color based on menu bar appearance
        let outlineColor: NSColor = isDarkMode ? .white : .black
        let textColor: NSColor = isDarkMode ? .white : .black

        // Get color based on usage level or monochrome
        let fillColor = monochromeMode ? (isDarkMode ? NSColor.white : NSColor.black) : getColorForUsageLevel(usage.statusLevel)

        // Position and size calculations for the bar
        let barY = totalHeight - barHeight - 4
        let barWidth = width - 2
        let padding: CGFloat = 2.0

        // Draw outer capsule/container (at top) - clean rounded rectangle
        let containerPath = NSBezierPath(roundedRect: NSRect(x: 1, y: barY, width: barWidth, height: barHeight), xRadius: 2.5, yRadius: 2.5)
        outlineColor.withAlphaComponent(0.5).setStroke()
        containerPath.lineWidth = 1.2
        containerPath.stroke()

        // Draw fill level inside - perfectly aligned with container
        let fillWidth = (barWidth - padding * 2) * percentage
        if fillWidth > 1 {
            let fillPath = NSBezierPath(roundedRect: NSRect(x: 1 + padding, y: barY + padding, width: fillWidth, height: barHeight - padding * 2), xRadius: 1.5, yRadius: 1.5)
            fillColor.setFill()
            fillPath.fill()
        }

        // Draw "Claude" text below the battery
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: textColor.withAlphaComponent(0.85)
        ]
        let text = "Claude" as NSString
        let textSize = text.size(withAttributes: textAttributes)
        let textX = (width - textSize.width) / 2
        let textY: CGFloat = 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttributes)

        return image
    }

    // MARK: - Icon Style: Progress Bar
    private func createProgressBarStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let width: CGFloat = 40
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let fillColor = monochromeMode ? (isDarkMode ? NSColor.white : NSColor.black) : getColorForUsageLevel(usage.statusLevel)
        let backgroundColor: NSColor = isDarkMode ? NSColor.white.withAlphaComponent(0.2) : NSColor.black.withAlphaComponent(0.15)

        // Progress bar
        let barWidth: CGFloat = width - 2
        let barHeight: CGFloat = 8
        let barX: CGFloat = 1
        let barY = (height - barHeight) / 2

        // Background
        let bgPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight), xRadius: 4, yRadius: 4)
        backgroundColor.setFill()
        bgPath.fill()

        // Fill
        let fillWidth = barWidth * CGFloat(usage.sessionPercentage / 100.0)
        if fillWidth > 1 {
            let fillPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillWidth, height: barHeight), xRadius: 4, yRadius: 4)
            fillColor.setFill()
            fillPath.fill()
        }

        return image
    }

    // MARK: - Icon Style: Percentage Only
    private func createPercentageOnlyStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let percentageText = "\(Int(usage.sessionPercentage))%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let fillColor = monochromeMode ? (isDarkMode ? NSColor.white : NSColor.black) : getColorForUsageLevel(usage.statusLevel)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fillColor
        ]

        let textSize = percentageText.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: textSize.width + 2, height: 18))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textY = (18 - textSize.height) / 2
        percentageText.draw(at: NSPoint(x: 1, y: textY), withAttributes: attributes)

        return image
    }

    // MARK: - Icon Style: Icon with Bar
    private func createIconWithBarStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textColor: NSColor = isDarkMode ? .white : .black
        let fillColor = monochromeMode ? (isDarkMode ? NSColor.white : NSColor.black) : getColorForUsageLevel(usage.statusLevel)

        // Progress arc (outer ring)
        let percentage = usage.sessionPercentage / 100.0
        let center = NSPoint(x: size / 2, y: size / 2)
        let radius = (size - 3.5) / 2
        let startAngle: CGFloat = 90
        let endAngle = startAngle + (360 * CGFloat(percentage))

        // Background ring
        let bgArcPath = NSBezierPath()
        bgArcPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        textColor.withAlphaComponent(0.15).setStroke()
        bgArcPath.lineWidth = 3.5
        bgArcPath.lineCapStyle = .round
        bgArcPath.stroke()

        // Progress ring
        if percentage > 0 {
            let arcPath = NSBezierPath()
            arcPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            fillColor.setStroke()
            arcPath.lineWidth = 3.5
            arcPath.lineCapStyle = .round
            arcPath.stroke()
        }

        return image
    }

    // MARK: - Icon Style: Compact
    private func createCompactStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let width: CGFloat = 8
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let fillColor = monochromeMode ? (isDarkMode ? NSColor.white : NSColor.black) : getColorForUsageLevel(usage.statusLevel)
        let dotSize: CGFloat = 6

        // Draw dot
        let dotY = (height - dotSize) / 2
        let dotRect = NSRect(x: (width - dotSize) / 2, y: dotY, width: dotSize, height: dotSize)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        fillColor.setFill()
        dotPath.fill()

        return image
    }

    // Helper method to get color based on usage level
    private func getColorForUsageLevel(_ level: UsageStatusLevel) -> NSColor {
        switch level {
        case .safe:
            return NSColor.systemGreen
        case .moderate:
            return NSColor.systemOrange
        case .critical:
            return NSColor.systemRed
        }
    }

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
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            guard let self = self,
                  let button = self.statusItem?.button else { return }
            DispatchQueue.main.async {
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
            guard let self = self,
                  let button = self.statusItem?.button else { return }
            // Clear cache to force redraw with new style
            self.cachedImageKey = ""
            self.updateStatusButton(button, usage: self.usage)
        }
    }

    func refreshUsage() {
        Task {
            // Fetch usage and status in parallel
            async let usageResult = apiService.fetchUsageData()
            async let statusResult = statusService.fetchStatus()

            do {
                let newUsage = try await usageResult

                await MainActor.run {
                    self.usage = newUsage
                    dataStore.saveUsage(newUsage)

                    // Update menu bar button
                    if let button = statusItem?.button {
                        updateStatusButton(button, usage: newUsage)
                    }

                    // Check if we should send notifications
                    NotificationManager.shared.checkAndNotify(usage: newUsage)
                }
            } catch {
                // Silently handle errors - user can check manually
            }

            // Fetch status separately (don't fail if usage fetch works)
            do {
                let newStatus = try await statusResult
                await MainActor.run {
                    self.status = newStatus
                }
            } catch {
                // Silently fail - status will remain unknown
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
                    // Silently fail - API usage will remain nil
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
        window.title = "Claude Usage"
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
