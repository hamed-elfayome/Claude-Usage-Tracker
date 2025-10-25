import Cocoa
import SwiftUI
import Combine

class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    @Published private(set) var usage: ClaudeUsage = .empty
    
    // Popover for beautiful SwiftUI interface
    private var popover: NSPopover?
    
    // Settings window reference
    private var settingsWindow: NSWindow?

    private let apiService = ClaudeAPIService()
    private let dataStore = DataStore.shared
    
    // Observer for refresh interval changes
    private var refreshIntervalObserver: NSKeyValueObservation?

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
    }

    func cleanup() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshIntervalObserver?.invalidate()
        refreshIntervalObserver = nil
        statusItem = nil
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 600)
        popover.behavior = .transient
        popover.animates = true
        
        // Create SwiftUI content view
        let contentView = PopoverContentView(
            manager: self,
            onRefresh: { [weak self] in
                self?.refreshUsage()
            },
            onPreferences: { [weak self] in
                self?.popover?.performClose(nil)
                self?.preferencesClicked()
            },
            onQuit: { [weak self] in
                self?.quitClicked()
            }
        )
        
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
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
        
        // Get color based on usage level
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
        NSColor.labelColor.withAlphaComponent(0.3).setStroke()
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
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
        ]
        let text = "Claude" as NSString
        let textSize = text.size(withAttributes: textAttributes)
        let textX = (width - textSize.width) / 2
        let textY: CGFloat = 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttributes)
        
        image.unlockFocus()
        
        // Set template to support dark mode
        image.isTemplate = false
        
        // Set the image to the button
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

    func refreshUsage() {
        Task {
            do {
                let newUsage = try await apiService.fetchUsageData()
                
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
        }
    }


    @objc private func preferencesClicked() {
        // Close the popover first
        popover?.performClose(nil)

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
            window.setContentSize(NSSize(width: 600, height: 550))
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
}

// MARK: - NSWindowDelegate
extension MenuBarManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == settingsWindow {
            // Hide dock icon again when settings window closes
            NSApp.setActivationPolicy(.accessory)
            settingsWindow = nil
        }
    }
}

