//
//  StatusBarUIManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Cocoa
import Combine

/// Manages multiple menu bar status items for different metrics
final class StatusBarUIManager {
    // Dictionary to hold multiple status items keyed by metric type
    private var statusItems: [MenuBarMetricType: NSStatusItem] = [:]
    private var appearanceObserver: NSKeyValueObservation?

    weak var delegate: StatusBarUIManagerDelegate?

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Sets up status bar items based on configuration
    func setup(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        // Remove all existing items first
        cleanup()

        // Create status items for enabled metrics
        for metricConfig in config.enabledMetrics {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem.button {
                button.action = action
                button.target = target
            }

            statusItems[metricConfig.metricType] = statusItem
        }

        observeAppearanceChanges()
        LoggingService.shared.logUIEvent("Status bar initialized with \(config.enabledMetrics.count) metrics")
    }

    /// Updates status bar items based on new configuration
    func updateConfiguration(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        // Nuclear approach with proper cleanup to minimize warnings
        // This is the most reliable method even though it triggers some macOS warnings
        //
        // Note: macOS may log "Unhandled disconnected scene" warnings when removing status items.
        // These are harmless internal macOS Control Center messages and don't affect functionality.
        // The alternative (incremental updates) causes race conditions where wrong metrics appear.
        // We choose reliability over clean console logs.

        // Step 1: Clean up all existing items properly
        for (metricType, statusItem) in statusItems {
            if let button = statusItem.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            NSStatusBar.system.removeStatusItem(statusItem)
            LoggingService.shared.logUIEvent("Removed status item for \(metricType.displayName)")
        }
        statusItems.removeAll()

        // Step 2: Recreate all enabled metrics
        // Using the same run loop to avoid delay but after cleanup
        for metricConfig in config.enabledMetrics {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem.button {
                button.action = action
                button.target = target
            }

            statusItems[metricConfig.metricType] = statusItem
            LoggingService.shared.logUIEvent("Created status item for \(metricConfig.metricType.displayName)")
        }

        LoggingService.shared.logUIEvent("Status bar configuration complete: \(config.enabledMetrics.count) metrics")
    }

    func cleanup() {
        appearanceObserver?.invalidate()
        appearanceObserver = nil

        // Properly clean up all status items to avoid scene warnings
        for (_, statusItem) in statusItems {
            // Clear button references first
            if let button = statusItem.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            // Then remove from status bar
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItems.removeAll()

        LoggingService.shared.logUIEvent("Status bar cleaned up")
    }

    // MARK: - UI Updates

    /// Updates all status bar buttons based on current usage data
    func updateAllButtons(
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        manager: MenuBarManager
    ) {
        let config = DataStore.shared.loadMenuBarIconConfiguration()
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua

        for metricConfig in config.enabledMetrics {
            guard let statusItem = statusItems[metricConfig.metricType],
                  let button = statusItem.button else {
                continue
            }

            let image = manager.createImageForMetric(
                metricConfig.metricType,
                config: metricConfig,
                usage: usage,
                apiUsage: apiUsage,
                isDarkMode: isDarkMode,
                monochromeMode: config.monochromeMode,
                showIconName: config.showIconNames,
                showNextSessionTime: config.showNextSessionTime
            )

            button.image = image
            button.image?.isTemplate = false
        }
    }

    /// Updates a specific metric's button
    func updateButton(
        for metricType: MenuBarMetricType,
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        manager: MenuBarManager
    ) {
        guard let statusItem = statusItems[metricType],
              let button = statusItem.button else {
            return
        }

        let config = DataStore.shared.loadMenuBarIconConfiguration()
        guard let metricConfig = config.config(for: metricType) else {
            return
        }

        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua

        let image = manager.createImageForMetric(
            metricType,
            config: metricConfig,
            usage: usage,
            apiUsage: apiUsage,
            isDarkMode: isDarkMode,
            monochromeMode: config.monochromeMode,
            showIconName: config.showIconNames,
            showNextSessionTime: config.showNextSessionTime
        )

        button.image = image
        button.image?.isTemplate = false
    }

    /// Get button for a specific metric (used for popover positioning)
    func button(for metricType: MenuBarMetricType) -> NSStatusBarButton? {
        return statusItems[metricType]?.button
    }

    /// Get the first enabled metric's button (for backwards compatibility)
    var primaryButton: NSStatusBarButton? {
        let config = DataStore.shared.loadMenuBarIconConfiguration()
        guard let firstMetric = config.enabledMetrics.first else {
            return nil
        }
        return statusItems[firstMetric.metricType]?.button
    }

    /// Find which metric type owns the given button (sender)
    func metricType(for sender: NSStatusBarButton?) -> MenuBarMetricType? {
        guard let sender = sender else { return nil }

        // Find which status item has this button
        for (metricType, statusItem) in statusItems {
            if statusItem.button === sender {
                return metricType
            }
        }
        return nil
    }

    // MARK: - Appearance Observation

    private func observeAppearanceChanges() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.delegate?.statusBarAppearanceDidChange()
        }
    }
}

// MARK: - Delegate Protocol

protocol StatusBarUIManagerDelegate: AnyObject {
    func statusBarAppearanceDidChange()
}
