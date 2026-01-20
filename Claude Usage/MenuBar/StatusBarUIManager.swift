//
//  StatusBarUIManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Cocoa
import Combine

/// Manages multiple menu bar status items for different metrics
@MainActor
final class StatusBarUIManager {
    // Dictionary to hold multiple status items keyed by metric type
    private var statusItems: [MenuBarMetricType: NSStatusItem] = [:]
    private var appearanceObserver: NSKeyValueObservation?

    // Icon renderer for creating menu bar images
    private let renderer = MenuBarIconRenderer()

    weak var delegate: StatusBarUIManagerDelegate?

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Sets up status bar items based on configuration
    func setup(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        // Remove all existing items first
        cleanup()

        // Check if there are any enabled metrics
        if config.enabledMetrics.isEmpty {
            // No credentials/metrics - show default app logo
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem.button {
                button.action = action
                button.target = target
                // Set a temporary placeholder - will be updated with actual logo
                button.title = ""
            }

            // Use a special key to identify the default icon
            statusItems[.session] = statusItem  // Use session as placeholder key
            LoggingService.shared.logUIEvent("Status bar initialized with default app logo (no credentials)")
        } else {
            // Create status items for enabled metrics
            for metricConfig in config.enabledMetrics {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                }

                statusItems[metricConfig.metricType] = statusItem
            }

            LoggingService.shared.logUIEvent("Status bar initialized with \(config.enabledMetrics.count) metrics")
        }

        observeAppearanceChanges()
    }

    /// Updates status bar items based on new configuration (incremental approach)
    func updateConfiguration(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        // Determine what the new set of items should be
        let newMetricTypes: Set<MenuBarMetricType>
        if config.enabledMetrics.isEmpty {
            // No credentials/metrics - show default app logo using .session as placeholder
            newMetricTypes = [.session]
        } else {
            newMetricTypes = Set(config.enabledMetrics.map { $0.metricType })
        }

        let currentMetricTypes = Set(statusItems.keys)

        // Step 1: Remove items that are no longer needed
        let itemsToRemove = currentMetricTypes.subtracting(newMetricTypes)
        for metricType in itemsToRemove {
            if let statusItem = statusItems[metricType] {
                if let button = statusItem.button {
                    button.image = nil
                    button.action = nil
                    button.target = nil
                }
                NSStatusBar.system.removeStatusItem(statusItem)
                LoggingService.shared.logUIEvent("Removed status item for \(metricType.displayName)")
            }
            statusItems.removeValue(forKey: metricType)
        }

        // Step 2: Add items that are new
        let itemsToAdd = newMetricTypes.subtracting(currentMetricTypes)
        for metricType in itemsToAdd {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

            if let button = statusItem.button {
                button.action = action
                button.target = target
                if metricType == .session {
                    // Default logo placeholder
                    button.title = ""
                }
            }

            statusItems[metricType] = statusItem
            LoggingService.shared.logUIEvent("Created status item for \(metricType.displayName)")
        }

        // Step 3: Items that already exist don't need recreation, just keep them
        // Their images will be updated by updateAllButtons() or updateButton()

        LoggingService.shared.logUIEvent("Status bar configuration updated: removed=\(itemsToRemove.count), added=\(itemsToAdd.count), kept=\(currentMetricTypes.intersection(newMetricTypes).count)")
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
        apiUsage: APIUsage?
    ) {
        // Get config from active profile
        let profile = ProfileManager.shared.activeProfile
        let config = profile?.iconConfig ?? .default
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua

        // Check if we should show default logo (no usage credentials OR no enabled metrics)
        let hasUsageCredentials = profile?.hasUsageCredentials ?? false
        if !hasUsageCredentials || config.enabledMetrics.isEmpty {
            // Show default app logo
            if let statusItem = statusItems[.session],  // We use .session as placeholder key
               let button = statusItem.button {
                let logoImage = renderer.createDefaultAppLogo(isDarkMode: isDarkMode)
                button.image = logoImage
                button.image?.isTemplate = false
            }
            return
        }

        // Normal metric display
        for metricConfig in config.enabledMetrics {
            guard let statusItem = statusItems[metricConfig.metricType],
                  let button = statusItem.button else {
                continue
            }

            // Create image directly using our renderer
            let image = renderer.createImage(
                for: metricConfig.metricType,
                config: metricConfig,
                usage: usage,
                apiUsage: apiUsage,
                isDarkMode: isDarkMode,
                monochromeMode: config.monochromeMode,
                showIconName: config.showIconNames,
                showNextSessionTime: metricConfig.showNextSessionTime
            )

            button.image = image
            button.image?.isTemplate = false
        }
    }

    /// Updates a specific metric's button
    func updateButton(
        for metricType: MenuBarMetricType,
        usage: ClaudeUsage,
        apiUsage: APIUsage?
    ) {
        guard let statusItem = statusItems[metricType],
              let button = statusItem.button else {
            return
        }

        // Get config from active profile
        let config = ProfileManager.shared.activeProfile?.iconConfig ?? .default
        guard let metricConfig = config.config(for: metricType) else {
            return
        }

        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua

        // Create image directly using our renderer
        let image = renderer.createImage(
            for: metricType,
            config: metricConfig,
            usage: usage,
            apiUsage: apiUsage,
            isDarkMode: isDarkMode,
            monochromeMode: config.monochromeMode,
            showIconName: config.showIconNames,
            showNextSessionTime: metricConfig.showNextSessionTime
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
