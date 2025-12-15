import Cocoa
import SwiftUI
import Combine

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    @Published private(set) var usage: ClaudeUsage = .empty
    @Published private(set) var status: ClaudeStatus = .unknown
    
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
    
    // Observer for refresh interval changes
    private var refreshIntervalObserver: NSKeyValueObservation?

    // Observer for appearance changes
    private var appearanceObserver: NSKeyValueObservation?

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

        // Load initial data
        refreshUsage()

        // Start auto-refresh timer
        startAutoRefresh()

        // Observe refresh interval changes
        observeRefreshIntervalChanges()

        // Observe appearance changes
        observeAppearanceChanges()
    }

    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshIntervalObserver?.invalidate()
        refreshIntervalObserver = nil
        appearanceObserver?.invalidate()
        appearanceObserver = nil
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
        let percentage = CGFloat(usage.sessionPercentage) / 100.0

        // Create a taller image to fit battery + text
        let width: CGFloat = 42
        let totalHeight: CGFloat = 28
        let barHeight: CGFloat = 10
        let image = NSImage(size: NSSize(width: width, height: totalHeight))

        image.lockFocus()

        // Detect if menu bar is in dark or light appearance
        let isDarkAppearance = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Choose outline and text color based on menu bar appearance
        let outlineColor: NSColor = isDarkAppearance ? .white : .black
        let textColor: NSColor = isDarkAppearance ? .white : .black

        // Get color based on usage level (always vibrant)
        let fillColor: NSColor
        switch usage.statusLevel {
        case .safe:
            fillColor = NSColor.systemGreen
        case .moderate:
            fillColor = NSColor.systemOrange
        case .critical:
            fillColor = NSColor.systemRed
        }

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

        image.unlockFocus()

        // Not using template mode - we manually handle appearance colors
        image.isTemplate = false

        button.image = image
        button.title = ""
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
        // Observe appearance changes on the status bar button
        guard let button = statusItem?.button else { return }

        // Observe effectiveAppearance changes using KVO
        appearanceObserver = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Redraw the icon with the new appearance
                self.updateStatusButton(button, usage: self.usage)
            }
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

