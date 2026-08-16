//
//  StatusBarUIManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Cocoa
import Combine

/// Describes the smallest set of mutations needed to change the metrics displayed
/// in single-profile mode. Removed and added metrics are paired first so their
/// existing NSStatusItems can be reassigned instead of removed from the menu bar.
struct StatusBarMetricTransition: Equatable {
    struct Reassignment: Equatable {
        let from: MenuBarMetricType
        let to: MenuBarMetricType
    }

    let reassignments: [Reassignment]
    let removals: [MenuBarMetricType]
    let additions: [MenuBarMetricType]

    static func calculate(
        currentOrder: [MenuBarMetricType],
        newOrder: [MenuBarMetricType]
    ) -> StatusBarMetricTransition {
        let current = Set(currentOrder)
        let new = Set(newOrder)
        let removed = currentOrder.filter { !new.contains($0) }
        let added = newOrder.filter { !current.contains($0) }
        let replacementCount = min(removed.count, added.count)

        let reassignments = (0..<replacementCount).map {
            Reassignment(from: removed[$0], to: added[$0])
        }

        return StatusBarMetricTransition(
            reassignments: reassignments,
            removals: Array(removed.dropFirst(replacementCount)),
            additions: Array(added.dropFirst(replacementCount))
        )
    }
}

/// Manages multiple menu bar status items for different metrics
@MainActor
final class StatusBarUIManager {
    // Dictionary to hold multiple status items keyed by metric type (single profile mode)
    private var statusItems: [MenuBarMetricType: NSStatusItem] = [:]
    private var singleProfileMetricOrder: [MenuBarMetricType] = []

    // Dictionary to hold status items keyed by profile ID (multi-profile mode)
    private var multiProfileStatusItems: [UUID: NSStatusItem] = [:]

    // Peak hours indicator (independent of metric system)
    private var peakHoursStatusItem: NSStatusItem?
    private var peakHoursTimer: Timer?
    private weak var peakHoursTarget: AnyObject?
    private var peakHoursAction: Selector?

    // Current display mode
    private var isMultiProfileMode: Bool = false

    private var appearanceObservers: [NSKeyValueObservation] = []
    private var appearanceDebounceTimer: Timer?

    // Image cache to avoid redundant button.image assignments (which trigger KVO)
    private var lastImageData: [ObjectIdentifier: Data] = [:]

    // Icon renderer for creating menu bar images
    private let renderer = MenuBarIconRenderer()

    weak var delegate: StatusBarUIManagerDelegate?

    // MARK: - Stable autosaveName helpers

    /// Base prefix for all status item autosave names.
    /// Ice (icemenubar.app) and macOS use autosaveName to persist item positions.
    private static let autosavePrefix = "claudeUsageTracker"

    /// Returns a stable autosaveName for a single-profile metric item
    private static func autosaveName(for metricType: MenuBarMetricType) -> NSStatusItem.AutosaveName {
        return "\(autosavePrefix).metric.\(metricType.rawValue)"
    }

    /// Returns a stable autosaveName for a multi-profile item by profile ID
    private static func autosaveName(forProfileId id: UUID) -> NSStatusItem.AutosaveName {
        return "\(autosavePrefix).multiProfile.\(id.uuidString)"
    }

    /// Returns a stable autosaveName for the peak hours indicator
    private static let peakHoursAutosaveName: NSStatusItem.AutosaveName = "\(autosavePrefix).peakHours"

    /// Returns a stable autosaveName for the default logo (no credentials)
    private static let defaultLogoAutosaveName: NSStatusItem.AutosaveName = "\(autosavePrefix).defaultLogo"

    // MARK: - Multi-profile identity helpers

    /// Well-known placeholder UUID used for the default logo in multi-profile mode
    private static let defaultLogoPlaceholderUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

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
            statusItem.autosaveName = Self.defaultLogoAutosaveName
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true

            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                // Set a temporary placeholder - will be updated with actual logo
                button.title = ""
            } else {
                LoggingService.shared.logWarning("Status bar button is nil - screens: \(NSScreen.screens.count)")
            }

            // Use a special key to identify the default icon
            statusItems[.session] = statusItem  // Use session as placeholder key
            singleProfileMetricOrder = [.session]
            LoggingService.shared.logUIEvent("Status bar initialized with default app logo (no credentials)")
        } else {
            // Create status items for enabled metrics
            for metricConfig in config.enabledMetrics {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.autosaveName = Self.autosaveName(for: metricConfig.metricType)
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true

                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                } else {
                    LoggingService.shared.logWarning("Status bar button is nil for \(metricConfig.metricType.displayName) - screens: \(NSScreen.screens.count)")
                }

                statusItems[metricConfig.metricType] = statusItem
            }
            singleProfileMetricOrder = config.enabledMetrics.map(\.metricType)

            LoggingService.shared.logUIEvent("Status bar initialized with \(config.enabledMetrics.count) metrics")
        }

        observeAppearanceChanges()
    }

    /// Updates status bar items based on new configuration (incremental approach)
    func updateConfiguration(target: AnyObject, action: Selector, config: MenuBarIconConfiguration) {
        // Determine what the new set of items should be
        let newMetricOrder: [MenuBarMetricType]
        if config.enabledMetrics.isEmpty {
            // No credentials/metrics - show default app logo using .session as placeholder
            newMetricOrder = [.session]
        } else {
            newMetricOrder = config.enabledMetrics.map(\.metricType)
        }

        let currentOrder = singleProfileMetricOrder.isEmpty
            ? MenuBarMetricType.allCases.filter { statusItems[$0] != nil }
            : singleProfileMetricOrder
        let transition = StatusBarMetricTransition.calculate(
            currentOrder: currentOrder,
            newOrder: newMetricOrder
        )

        // Step 1: Reassign existing items before adding/removing anything. This is
        // the common path for Claude <-> Codex profile switches and preserves the
        // NSStatusItem identity, position, and autosaveName.
        for reassignment in transition.reassignments {
            guard let statusItem = statusItems.removeValue(forKey: reassignment.from) else {
                continue
            }
            statusItems[reassignment.to] = statusItem

            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.title = ""
                lastImageData.removeValue(forKey: ObjectIdentifier(button))
            }

            LoggingService.shared.logUIEvent(
                "Reassigned status item from \(reassignment.from.displayName) to \(reassignment.to.displayName)"
            )
        }

        // Step 2: Remove only surplus items when the new profile displays fewer metrics.
        for metricType in transition.removals {
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

        // Step 3: Add only surplus items when the new profile displays more metrics.
        for metricType in transition.additions {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // When enabledMetrics is empty, only .session is in newMetricOrder, so this is safe.
            statusItem.autosaveName = config.enabledMetrics.isEmpty
                ? Self.defaultLogoAutosaveName
                : Self.autosaveName(for: metricType)
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true

            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                if metricType == .session {
                    // Default logo placeholder
                    button.title = ""
                }
            }

            statusItems[metricType] = statusItem
            LoggingService.shared.logUIEvent("Created status item for \(metricType.displayName)")
        }

        singleProfileMetricOrder = newMetricOrder
        LoggingService.shared.logUIEvent(
            "Status bar configuration updated: reassigned=\(transition.reassignments.count), removed=\(transition.removals.count), added=\(transition.additions.count)"
        )
    }

    func cleanup() {
        appearanceObservers.forEach { $0.invalidate() }
        appearanceObservers.removeAll()

        // Clean up single profile status items
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
        singleProfileMetricOrder.removeAll()

        // Clean up multi-profile status items
        for (_, statusItem) in multiProfileStatusItems {
            if let button = statusItem.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        multiProfileStatusItems.removeAll()

        isMultiProfileMode = false

        removePeakHoursIndicator()

        LoggingService.shared.logUIEvent("Status bar cleaned up")
    }

    // MARK: - Peak Hours Indicator

    /// Starts monitoring peak hours. Shows the flame icon only during peak hours.
    func setupPeakHoursIndicator(target: AnyObject, action: Selector) {
        removePeakHoursIndicator()

        peakHoursTarget = target
        peakHoursAction = action

        // Show immediately if currently peak
        updatePeakHoursIcon()

        peakHoursTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePeakHoursIcon()
            }
        }
        peakHoursTimer?.tolerance = 10
    }

    /// Removes the peak hours status item and stops monitoring.
    func removePeakHoursIndicator() {
        peakHoursTimer?.invalidate()
        peakHoursTimer = nil
        peakHoursTarget = nil
        peakHoursAction = nil
        removePeakHoursStatusItem()
    }

    /// Updates the peak hours icon: shows during peak, hides when off-peak.
    func updatePeakHoursIcon() {
        let isPeak = PeakHoursService.checkIsPeakHours()

        if isPeak {
            // Create the status item if not already showing
            if peakHoursStatusItem == nil, let target = peakHoursTarget, let action = peakHoursAction {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.autosaveName = Self.peakHoursAutosaveName
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true
                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                }
                peakHoursStatusItem = statusItem
            }
            if let button = peakHoursStatusItem?.button {
                let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let image = renderer.createPeakHoursIcon(isPeak: true, isDarkMode: menuBarIsDark)
                image.isTemplate = false
                setButtonImage(button, image: image)
            }
        } else {
            // Remove the icon when off-peak
            removePeakHoursStatusItem()
        }
    }

    private func removePeakHoursStatusItem() {
        if let item = peakHoursStatusItem {
            if let button = item.button {
                button.image = nil
                button.action = nil
                button.target = nil
            }
            NSStatusBar.system.removeStatusItem(item)
        }
        peakHoursStatusItem = nil
    }

    // MARK: - Multi-Profile Mode

    /// Sets up status bar for multi-profile display mode
    func setupMultiProfile(
        profiles: [Profile],
        target: AnyObject,
        action: Selector
    ) {
        // Clean up existing items
        cleanup()

        isMultiProfileMode = true

        // Filter to only profiles selected for display
        let selectedProfiles = profiles.filter { $0.isSelectedForDisplay }

        if selectedProfiles.isEmpty {
            // No profiles selected - show default logo
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = Self.defaultLogoAutosaveName
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true
            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.title = ""
            } else {
                LoggingService.shared.logWarning("Multi-profile status bar button is nil - screens: \(NSScreen.screens.count)")
            }
            // Use a well-known placeholder UUID for default logo (stable across calls)
            multiProfileStatusItems[Self.defaultLogoPlaceholderUUID] = statusItem
            LoggingService.shared.logUIEvent("Multi-profile: No profiles selected, showing default logo")
        } else {
            // Create one status item per selected profile
            for profile in selectedProfiles {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.autosaveName = Self.autosaveName(forProfileId: profile.id)
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true

                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                } else {
                    LoggingService.shared.logWarning("Multi-profile status bar button is nil for \(profile.name) - screens: \(NSScreen.screens.count)")
                }

                multiProfileStatusItems[profile.id] = statusItem
            }

            LoggingService.shared.logUIEvent("Multi-profile: Created \(selectedProfiles.count) status items")
        }

        observeAppearanceChanges()
    }

    /// Incrementally updates multi-profile status items without destroying existing ones.
    /// Only adds/removes items when the set of selected profiles changes.
    func updateMultiProfileConfiguration(
        profiles: [Profile],
        target: AnyObject,
        action: Selector
    ) {
        guard isMultiProfileMode else {
            // Not in multi-profile mode yet - do a full setup
            setupMultiProfile(
                profiles: profiles,
                target: target,
                action: action
            )
            return
        }

        let selectedProfiles = profiles.filter { $0.isSelectedForDisplay }
        var newProfileIds = Set(selectedProfiles.map { $0.id })
        if newProfileIds.isEmpty {
            newProfileIds.insert(Self.defaultLogoPlaceholderUUID)
        }
        let currentProfileIds = Set(multiProfileStatusItems.keys)

        // Step 1: Remove items that are no longer needed
        let idsToRemove = currentProfileIds.subtracting(newProfileIds)
        for profileId in idsToRemove {
            if let statusItem = multiProfileStatusItems[profileId] {
                if let button = statusItem.button {
                    button.image = nil
                    button.action = nil
                    button.target = nil
                }
                NSStatusBar.system.removeStatusItem(statusItem)
                LoggingService.shared.logUIEvent("Multi-profile: Removed status item for profile \(profileId)")
            }
            multiProfileStatusItems.removeValue(forKey: profileId)
        }

        // Step 2: Add items that are new
        let idsToAdd = newProfileIds.subtracting(currentProfileIds)

        if selectedProfiles.isEmpty && idsToAdd.contains(Self.defaultLogoPlaceholderUUID) {
            // Need to add default logo
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = Self.defaultLogoAutosaveName
            // Override any persisted false from a prior cmd-drag.
            statusItem.isVisible = true
            if let button = statusItem.button {
                button.action = action
                button.target = target
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.title = ""
            }
            multiProfileStatusItems[Self.defaultLogoPlaceholderUUID] = statusItem
            LoggingService.shared.logUIEvent("Multi-profile: Added default logo")
        } else {
            for profile in selectedProfiles where idsToAdd.contains(profile.id) {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItem.autosaveName = Self.autosaveName(forProfileId: profile.id)
                // Override any persisted false from a prior cmd-drag.
                statusItem.isVisible = true
                if let button = statusItem.button {
                    button.action = action
                    button.target = target
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                }
                multiProfileStatusItems[profile.id] = statusItem
                LoggingService.shared.logUIEvent("Multi-profile: Added status item for profile \(profile.name)")
            }

        }

        LoggingService.shared.logUIEvent("Multi-profile config updated: removed=\(idsToRemove.count), added=\(idsToAdd.count), kept=\(currentProfileIds.intersection(newProfileIds).count)")
    }

    /// Adds a thin green underline to an image to indicate the active profile
    private func addGreenUnderline(to image: NSImage) -> NSImage {
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }
        // Shift content up 2px to create a 1px gap above the underline
        image.draw(at: NSPoint(x: 0, y: 2), from: .zero, operation: .copy, fraction: 1.0)
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 1, y: 0, width: image.size.width - 2, height: 1)).fill()
        return newImage
    }

    /// Updates all multi-profile status items
    func updateMultiProfileButtons(
        profiles: [Profile],
        config: MultiProfileDisplayConfig,
        activeProfileId: UUID? = nil,
        codexRefreshErrors: [UUID: String] = [:],
        zaiRefreshErrors: [UUID: String] = [:]
    ) {
        guard isMultiProfileMode else { return }

        for profile in profiles where profile.isSelectedForDisplay {
            guard let statusItem = multiProfileStatusItems[profile.id],
                  let button = statusItem.button else {
                continue
            }

            if profile.provider == .codex {
                updateCodexProfileButton(
                    profile: profile,
                    config: config,
                    activeProfileId: activeProfileId,
                    refreshError: codexRefreshErrors[profile.id]
                )
                continue
            }

            if profile.provider == .zai {
                updateZAIProfileButton(
                    profile: profile,
                    config: config,
                    activeProfileId: activeProfileId,
                    refreshError: zaiRefreshErrors[profile.id]
                )
                continue
            }

            // Get actual menu bar appearance from the button (based on wallpaper, not system mode)
            let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Get usage data for this profile
            let usage = profile.claudeUsage ?? ClaudeUsage.empty
            let showRemaining = config.showRemainingPercentage

            // Calculate percentages
            let sessionUsed = usage.effectiveSessionPercentage
            let weekUsed = usage.weeklyPercentage

            let sessionDisplay = UsageStatusCalculator.getDisplayPercentage(
                usedPercentage: sessionUsed,
                showRemaining: showRemaining
            )
            let weekDisplay = UsageStatusCalculator.getDisplayPercentage(
                usedPercentage: weekUsed,
                showRemaining: showRemaining
            )

            let sessionElapsed = UsageStatusCalculator.elapsedFraction(
                resetTime: usage.sessionResetTime,
                duration: Constants.sessionWindow,
                showRemaining: false
            )
            let weekElapsed = UsageStatusCalculator.elapsedFraction(
                resetTime: usage.weeklyResetTime,
                duration: Constants.weeklyWindow,
                showRemaining: false
            )
            let sessionStatus = UsageStatusCalculator.calculateStatus(
                usedPercentage: sessionUsed,
                showRemaining: showRemaining,
                elapsedFraction: config.usePaceColoring ? sessionElapsed : nil
            )
            let weekStatus = UsageStatusCalculator.calculateStatus(
                usedPercentage: weekUsed,
                showRemaining: showRemaining,
                elapsedFraction: config.usePaceColoring ? weekElapsed : nil
            )

            // Use multi-profile config's useSystemColor as monochrome mode
            // When useSystemColor is ON, icons will be white (like single-profile monochrome)
            let useMonochrome = config.useSystemColor

            // Calculate time marker fractions for multi-profile display
            let sessionMarker: CGFloat? = config.showTimeMarker
                ? sessionElapsed.map { CGFloat(showRemaining ? 1.0 - $0 : $0) }
                : nil
            let weekMarker: CGFloat? = config.showTimeMarker
                ? weekElapsed.map { CGFloat(showRemaining ? 1.0 - $0 : $0) }
                : nil

            // Compute pace status for multi-profile rendering
            let sessionPaceStatus: PaceStatus? = {
                guard config.showPaceMarker, let elapsed = sessionElapsed else { return nil }
                return PaceStatus.calculate(usedPercentage: sessionUsed, elapsedFraction: elapsed)
            }()
            let weekPaceStatus: PaceStatus? = {
                guard config.showPaceMarker, let elapsed = weekElapsed else { return nil }
                return PaceStatus.calculate(usedPercentage: weekUsed, elapsedFraction: elapsed)
            }()

            // Create icon based on selected style
            let image: NSImage
            switch config.iconStyle {
            case .concentric:
                if config.showProfileLabel {
                    image = renderer.createConcentricIconWithLabel(
                        sessionPercentage: sessionDisplay,
                        weekPercentage: config.showWeek ? weekDisplay : 0,
                        sessionStatus: sessionStatus,
                        weekStatus: weekStatus,
                        profileName: profile.name,
                        monochromeMode: useMonochrome,
                        isDarkMode: menuBarIsDark,
                        useSystemColor: false,
                        sessionTimeMarker: sessionMarker,
                        weekTimeMarker: config.showWeek ? weekMarker : nil,
                        sessionPaceStatus: sessionPaceStatus,
                        weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                        showPaceMarker: config.showPaceMarker
                    )
                } else {
                    image = renderer.createConcentricIcon(
                        sessionPercentage: sessionDisplay,
                        weekPercentage: config.showWeek ? weekDisplay : 0,
                        sessionStatus: sessionStatus,
                        weekStatus: weekStatus,
                        profileInitial: String(profile.name.prefix(1)),
                        monochromeMode: useMonochrome,
                        isDarkMode: menuBarIsDark,
                        useSystemColor: false,
                        sessionTimeMarker: sessionMarker,
                        weekTimeMarker: config.showWeek ? weekMarker : nil,
                        sessionPaceStatus: sessionPaceStatus,
                        weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                        showPaceMarker: config.showPaceMarker
                    )
                }
            case .progressBar:
                image = renderer.createMultiProfileProgressBar(
                    sessionPercentage: sessionDisplay,
                    weekPercentage: config.showWeek ? weekDisplay : nil,
                    sessionStatus: sessionStatus,
                    weekStatus: weekStatus,
                    profileName: config.showProfileLabel ? profile.name : nil,
                    monochromeMode: useMonochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionTimeMarker: sessionMarker,
                    weekTimeMarker: config.showWeek ? weekMarker : nil,
                    sessionPaceStatus: sessionPaceStatus,
                    weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                    showPaceMarker: config.showPaceMarker
                )
            case .compact:
                image = renderer.createCompactDot(
                    percentage: sessionDisplay,
                    status: sessionStatus,
                    profileInitial: config.showProfileLabel ? String(profile.name.prefix(1)) : nil,
                    monochromeMode: useMonochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    paceStatus: sessionPaceStatus,
                    showPaceMarker: config.showPaceMarker
                )
            case .percentage:
                image = renderer.createMultiProfilePercentage(
                    sessionPercentage: sessionDisplay,
                    weekPercentage: config.showWeek ? weekDisplay : nil,
                    sessionStatus: sessionStatus,
                    weekStatus: weekStatus,
                    profileName: config.showProfileLabel ? profile.name : nil,
                    monochromeMode: useMonochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionPaceStatus: sessionPaceStatus,
                    weekPaceStatus: config.showWeek ? weekPaceStatus : nil,
                    showPaceMarker: config.showPaceMarker
                )
            }

            if profile.id == activeProfileId && config.showActiveProfileIndicator {
                let underlinedImage = addGreenUnderline(to: image)
                underlinedImage.isTemplate = false
                button.image = underlinedImage
            } else {
                image.isTemplate = useMonochrome && !config.showPaceMarker
                button.image = image
            }
        }
    }

    /// Renders Codex as a peer of the selected Claude profiles. The selected
    /// Codex bucket is the primary value; its secondary window (or the next
    /// available bucket) supplies the optional second ring/bar.
    func updateCodexProfileButton(
        profile: Profile,
        config: MultiProfileDisplayConfig,
        activeProfileId: UUID? = nil,
        refreshError: String? = nil
    ) {
        guard isMultiProfileMode,
              profile.provider == .codex,
              let statusItem = multiProfileStatusItems[profile.id],
              let button = statusItem.button else {
            return
        }

        guard let usage = profile.codexUsage,
              let selectedLimit = usage.rateLimit(
                preferredID: profile.codexConfiguration.selectedRateLimitID
              ),
              let primaryWindow = selectedLimit.primary else {
            let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let image = renderer.createDefaultAppLogo(isDarkMode: menuBarIsDark)
            button.toolTip = "\(profile.name): \(refreshError ?? "Codex usage unavailable")"
            if profile.id == activeProfileId && config.showActiveProfileIndicator {
                let underlined = addGreenUnderline(to: image)
                underlined.isTemplate = false
                setButtonImage(button, image: underlined)
            } else {
                image.isTemplate = false
                setButtonImage(button, image: image)
            }
            return
        }
        if let refreshError {
            button.toolTip = "\(profile.name): \(refreshError) · Showing data from \(usage.lastUpdated.formatted(date: .abbreviated, time: .shortened))"
        } else {
            button.toolTip = nil
        }

        let secondaryWindow = selectedLimit.secondary
            ?? usage.rateLimits.first(where: { $0.id != selectedLimit.id })?.primary

        let primaryUsed = primaryWindow.usedPercent
        let secondaryUsed = secondaryWindow?.usedPercent ?? 0
        let showSecondary = config.showWeek && secondaryWindow != nil
        let showRemaining = config.showRemainingPercentage

        let primaryDisplay = UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: primaryUsed,
            showRemaining: showRemaining
        )
        let secondaryDisplay = UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: secondaryUsed,
            showRemaining: showRemaining
        )
        let primaryElapsed: Double? = {
            guard let duration = primaryWindow.duration else { return nil }
            return UsageStatusCalculator.elapsedFraction(
                resetTime: primaryWindow.resetsAt,
                duration: duration,
                showRemaining: false
            )
        }()
        let secondaryElapsed = secondaryWindow.flatMap { window -> Double? in
            guard let duration = window.duration else { return nil }
            return UsageStatusCalculator.elapsedFraction(
                resetTime: window.resetsAt,
                duration: duration,
                showRemaining: false
            )
        }
        let primaryStatus = UsageStatusCalculator.calculateStatus(
            usedPercentage: primaryUsed,
            showRemaining: showRemaining,
            elapsedFraction: config.usePaceColoring ? primaryElapsed : nil
        )
        let secondaryStatus = UsageStatusCalculator.calculateStatus(
            usedPercentage: secondaryUsed,
            showRemaining: showRemaining,
            elapsedFraction: config.usePaceColoring ? secondaryElapsed : nil
        )
        let primaryMarker: CGFloat? = config.showTimeMarker
            ? primaryElapsed.map { CGFloat(showRemaining ? 1 - $0 : $0) }
            : nil
        let secondaryMarker: CGFloat? = config.showTimeMarker
            ? secondaryElapsed.map { CGFloat(showRemaining ? 1 - $0 : $0) }
            : nil
        let primaryPace = config.showPaceMarker
            ? primaryElapsed.flatMap { PaceStatus.calculate(usedPercentage: primaryUsed, elapsedFraction: $0) }
            : nil
        let secondaryPace = config.showPaceMarker
            ? secondaryElapsed.flatMap { PaceStatus.calculate(usedPercentage: secondaryUsed, elapsedFraction: $0) }
            : nil
        let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let monochrome = config.useSystemColor

        let image: NSImage
        switch config.iconStyle {
        case .concentric:
            if config.showProfileLabel {
                image = renderer.createConcentricIconWithLabel(
                    sessionPercentage: primaryDisplay,
                    weekPercentage: showSecondary ? secondaryDisplay : 0,
                    sessionStatus: primaryStatus,
                    weekStatus: secondaryStatus,
                    profileName: profile.name,
                    monochromeMode: monochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionTimeMarker: primaryMarker,
                    weekTimeMarker: showSecondary ? secondaryMarker : nil,
                    sessionPaceStatus: primaryPace,
                    weekPaceStatus: showSecondary ? secondaryPace : nil,
                    showPaceMarker: config.showPaceMarker
                )
            } else {
                image = renderer.createConcentricIcon(
                    sessionPercentage: primaryDisplay,
                    weekPercentage: showSecondary ? secondaryDisplay : 0,
                    sessionStatus: primaryStatus,
                    weekStatus: secondaryStatus,
                    profileInitial: String(profile.name.prefix(1)),
                    monochromeMode: monochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionTimeMarker: primaryMarker,
                    weekTimeMarker: showSecondary ? secondaryMarker : nil,
                    sessionPaceStatus: primaryPace,
                    weekPaceStatus: showSecondary ? secondaryPace : nil,
                    showPaceMarker: config.showPaceMarker
                )
            }
        case .progressBar:
            image = renderer.createMultiProfileProgressBar(
                sessionPercentage: primaryDisplay,
                weekPercentage: showSecondary ? secondaryDisplay : nil,
                sessionStatus: primaryStatus,
                weekStatus: secondaryStatus,
                profileName: config.showProfileLabel ? profile.name : nil,
                monochromeMode: monochrome,
                isDarkMode: menuBarIsDark,
                useSystemColor: false,
                sessionTimeMarker: primaryMarker,
                weekTimeMarker: showSecondary ? secondaryMarker : nil,
                sessionPaceStatus: primaryPace,
                weekPaceStatus: showSecondary ? secondaryPace : nil,
                showPaceMarker: config.showPaceMarker
            )
        case .compact:
            image = renderer.createCompactDot(
                percentage: primaryDisplay,
                status: primaryStatus,
                profileInitial: config.showProfileLabel ? String(profile.name.prefix(1)) : nil,
                monochromeMode: monochrome,
                isDarkMode: menuBarIsDark,
                useSystemColor: false,
                paceStatus: primaryPace,
                showPaceMarker: config.showPaceMarker
            )
        case .percentage:
            image = renderer.createMultiProfilePercentage(
                sessionPercentage: primaryDisplay,
                weekPercentage: showSecondary ? secondaryDisplay : nil,
                sessionStatus: primaryStatus,
                weekStatus: secondaryStatus,
                profileName: config.showProfileLabel ? profile.name : nil,
                monochromeMode: monochrome,
                isDarkMode: menuBarIsDark,
                useSystemColor: false,
                sessionPaceStatus: primaryPace,
                weekPaceStatus: showSecondary ? secondaryPace : nil,
                showPaceMarker: config.showPaceMarker
            )
        }

        if profile.id == activeProfileId && config.showActiveProfileIndicator {
            let underlined = addGreenUnderline(to: image)
            underlined.isTemplate = false
            setButtonImage(button, image: underlined)
        } else {
            image.isTemplate = monochrome && !config.showPaceMarker
            setButtonImage(button, image: image)
        }
    }

    /// Renders a z.ai profile as a peer of the selected Claude profiles. The
    /// selected quota window is the primary value; the weekly window supplies
    /// the optional second ring/bar.
    func updateZAIProfileButton(
        profile: Profile,
        config: MultiProfileDisplayConfig,
        activeProfileId: UUID? = nil,
        refreshError: String? = nil
    ) {
        guard isMultiProfileMode,
              profile.provider == .zai,
              let statusItem = multiProfileStatusItems[profile.id],
              let button = statusItem.button else {
            return
        }

        guard let usage = profile.zaiUsage,
              let selectedLimit = usage.rateLimit(
                  preferredID: profile.zaiConfiguration.selectedLimitID
              ),
              let primaryWindow = selectedLimit.primary else {
            let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let image = renderer.createDefaultAppLogo(isDarkMode: menuBarIsDark)
            button.toolTip = "\(profile.name): \(refreshError ?? "Z.ai usage unavailable")"
            if profile.id == activeProfileId && config.showActiveProfileIndicator {
                let underlined = addGreenUnderline(to: image)
                underlined.isTemplate = false
                setButtonImage(button, image: underlined)
            } else {
                image.isTemplate = false
                setButtonImage(button, image: image)
            }
            return
        }
        if let refreshError {
            button.toolTip = "\(profile.name): \(refreshError) · Showing data from \(usage.lastUpdated.formatted(date: .abbreviated, time: .shortened))"
        } else {
            button.toolTip = nil
        }

        let secondaryWindow = usage.rateLimits
            .first(where: { $0.id != selectedLimit.id && $0.kind == .tokens })?
            .primary

        let primaryUsed = primaryWindow.usedPercent
        let secondaryUsed = secondaryWindow?.usedPercent ?? 0
        let showSecondary = config.showWeek && secondaryWindow != nil
        let showRemaining = config.showRemainingPercentage

        let primaryDisplay = UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: primaryUsed,
            showRemaining: showRemaining
        )
        let secondaryDisplay = UsageStatusCalculator.getDisplayPercentage(
            usedPercentage: secondaryUsed,
            showRemaining: showRemaining
        )
        let primaryElapsed: Double? = {
            guard let duration = primaryWindow.duration else { return nil }
            return UsageStatusCalculator.elapsedFraction(
                resetTime: primaryWindow.resetsAt,
                duration: duration,
                showRemaining: false
            )
        }()
        let secondaryElapsed = secondaryWindow.flatMap { window -> Double? in
            guard let duration = window.duration else { return nil }
            return UsageStatusCalculator.elapsedFraction(
                resetTime: window.resetsAt,
                duration: duration,
                showRemaining: false
            )
        }
        let primaryStatus = UsageStatusCalculator.calculateStatus(
            usedPercentage: primaryUsed,
            showRemaining: showRemaining,
            elapsedFraction: config.usePaceColoring ? primaryElapsed : nil
        )
        let secondaryStatus = UsageStatusCalculator.calculateStatus(
            usedPercentage: secondaryUsed,
            showRemaining: showRemaining,
            elapsedFraction: config.usePaceColoring ? secondaryElapsed : nil
        )
        let primaryMarker: CGFloat? = config.showTimeMarker
            ? primaryElapsed.map { CGFloat(showRemaining ? 1 - $0 : $0) }
            : nil
        let secondaryMarker: CGFloat? = config.showTimeMarker
            ? secondaryElapsed.map { CGFloat(showRemaining ? 1 - $0 : $0) }
            : nil
        let primaryPace = config.showPaceMarker
            ? primaryElapsed.flatMap { PaceStatus.calculate(usedPercentage: primaryUsed, elapsedFraction: $0) }
            : nil
        let secondaryPace = config.showPaceMarker
            ? secondaryElapsed.flatMap { PaceStatus.calculate(usedPercentage: secondaryUsed, elapsedFraction: $0) }
            : nil
        let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let monochrome = config.useSystemColor

        let image: NSImage
        switch config.iconStyle {
        case .concentric:
            if config.showProfileLabel {
                image = renderer.createConcentricIconWithLabel(
                    sessionPercentage: primaryDisplay,
                    weekPercentage: showSecondary ? secondaryDisplay : 0,
                    sessionStatus: primaryStatus,
                    weekStatus: secondaryStatus,
                    profileName: profile.name,
                    monochromeMode: monochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionTimeMarker: primaryMarker,
                    weekTimeMarker: showSecondary ? secondaryMarker : nil,
                    sessionPaceStatus: primaryPace,
                    weekPaceStatus: showSecondary ? secondaryPace : nil,
                    showPaceMarker: config.showPaceMarker
                )
            } else {
                image = renderer.createConcentricIcon(
                    sessionPercentage: primaryDisplay,
                    weekPercentage: showSecondary ? secondaryDisplay : 0,
                    sessionStatus: primaryStatus,
                    weekStatus: secondaryStatus,
                    profileInitial: String(profile.name.prefix(1)),
                    monochromeMode: monochrome,
                    isDarkMode: menuBarIsDark,
                    useSystemColor: false,
                    sessionTimeMarker: primaryMarker,
                    weekTimeMarker: showSecondary ? secondaryMarker : nil,
                    sessionPaceStatus: primaryPace,
                    weekPaceStatus: showSecondary ? secondaryPace : nil,
                    showPaceMarker: config.showPaceMarker
                )
            }
        case .progressBar:
            image = renderer.createMultiProfileProgressBar(
                sessionPercentage: primaryDisplay,
                weekPercentage: showSecondary ? secondaryDisplay : nil,
                sessionStatus: primaryStatus,
                weekStatus: secondaryStatus,
                profileName: config.showProfileLabel ? profile.name : nil,
                monochromeMode: monochrome,
                isDarkMode: menuBarIsDark,
                useSystemColor: false,
                sessionTimeMarker: primaryMarker,
                weekTimeMarker: showSecondary ? secondaryMarker : nil,
                sessionPaceStatus: primaryPace,
                weekPaceStatus: showSecondary ? secondaryPace : nil,
                showPaceMarker: config.showPaceMarker
            )
        case .compact:
            image = renderer.createCompactDot(
                percentage: primaryDisplay,
                status: primaryStatus,
                profileInitial: config.showProfileLabel ? String(profile.name.prefix(1)) : nil,
                monochromeMode: monochrome,
                isDarkMode: menuBarIsDark,
                useSystemColor: false,
                paceStatus: primaryPace,
                showPaceMarker: config.showPaceMarker
            )
        case .percentage:
            image = renderer.createMultiProfilePercentage(
                sessionPercentage: primaryDisplay,
                weekPercentage: showSecondary ? secondaryDisplay : nil,
                sessionStatus: primaryStatus,
                weekStatus: secondaryStatus,
                profileName: config.showProfileLabel ? profile.name : nil,
                monochromeMode: monochrome,
                isDarkMode: menuBarIsDark,
                useSystemColor: false,
                sessionPaceStatus: primaryPace,
                weekPaceStatus: showSecondary ? secondaryPace : nil,
                showPaceMarker: config.showPaceMarker
            )
        }

        if profile.id == activeProfileId && config.showActiveProfileIndicator {
            let underlined = addGreenUnderline(to: image)
            underlined.isTemplate = false
            setButtonImage(button, image: underlined)
        } else {
            image.isTemplate = monochrome && !config.showPaceMarker
            setButtonImage(button, image: image)
        }
    }

    /// Checks if currently in multi-profile mode
    var isInMultiProfileMode: Bool {
        return isMultiProfileMode
    }

    /// Checks if status bar has at least one valid button (for headless mode detection)
    var hasValidStatusBar: Bool {
        // Check single-profile status items
        for (_, statusItem) in statusItems {
            if statusItem.button != nil {
                return true
            }
        }
        // Check multi-profile status items
        for (_, statusItem) in multiProfileStatusItems {
            if statusItem.button != nil {
                return true
            }
        }
        return false
    }

    /// Get button for a specific profile (multi-profile mode)
    func button(for profileId: UUID) -> NSStatusBarButton? {
        return multiProfileStatusItems[profileId]?.button
    }

    /// Find which profile ID owns the given button (multi-profile mode)
    func profileId(for sender: NSStatusBarButton?) -> UUID? {
        guard let sender = sender else { return nil }

        for (profileId, statusItem) in multiProfileStatusItems {
            if statusItem.button === sender {
                return profileId
            }
        }
        return nil
    }

    // MARK: - UI Updates

    /// Updates all status bar buttons based on current usage data
    func updateAllButtons(
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        codexUsage: CodexUsage?,
        config: MenuBarIconConfiguration,
        codexSettings: CodexProfileConfiguration,
        zaiUsage: ZAIUsage? = nil,
        zaiSettings: ZAIProfileConfiguration = ZAIProfileConfiguration()
    ) {
        if config.enabledMetrics.isEmpty {
            // Show default app logo
            if let statusItem = statusItems[.session],  // We use .session as placeholder key
               let button = statusItem.button {
                // Get actual menu bar appearance from the button
                let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let logoImage = renderer.createDefaultAppLogo(isDarkMode: menuBarIsDark)
                logoImage.isTemplate = true  // Let macOS handle the color
                setButtonImage(button, image: logoImage)
            }
            return
        }

        // Normal metric display
        for metricConfig in config.enabledMetrics {
            guard let statusItem = statusItems[metricConfig.metricType],
                  let button = statusItem.button else {
                continue
            }

            // Get actual menu bar appearance from the button
            let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // Create image directly using our renderer
            let image = renderer.createImage(
                for: metricConfig.metricType,
                config: metricConfig,
                globalConfig: config,
                usage: usage,
                apiUsage: apiUsage,
                codexUsage: codexUsage,
                codexRateLimitID: codexSettings.selectedRateLimitID,
                zaiUsage: zaiUsage,
                zaiRateLimitID: zaiSettings.selectedLimitID,
                isDarkMode: menuBarIsDark,
                colorMode: config.colorMode,
                singleColorHex: config.singleColorHex,
                showIconName: config.showIconNames,
                showNextSessionTime: metricConfig.showNextSessionTime
            )

            image.isTemplate = config.colorMode == .monochrome && !config.showPaceMarker
            button.image = image
        }
    }

    /// Updates a specific metric's button
    func updateButton(
        for metricType: MenuBarMetricType,
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        codexUsage: CodexUsage?,
        config: MenuBarIconConfiguration,
        codexSettings: CodexProfileConfiguration,
        zaiUsage: ZAIUsage? = nil,
        zaiSettings: ZAIProfileConfiguration = ZAIProfileConfiguration()
    ) {
        guard let statusItem = statusItems[metricType],
              let button = statusItem.button else {
            return
        }

        guard let metricConfig = config.config(for: metricType) else {
            return
        }

        // Get the actual menu bar appearance from the button's effective appearance
        let menuBarIsDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Create image directly using our renderer
        let image = renderer.createImage(
            for: metricType,
            config: metricConfig,
            globalConfig: config,
            usage: usage,
            apiUsage: apiUsage,
            codexUsage: codexUsage,
            codexRateLimitID: codexSettings.selectedRateLimitID,
            zaiUsage: zaiUsage,
            zaiRateLimitID: zaiSettings.selectedLimitID,
            isDarkMode: menuBarIsDark,
            colorMode: config.colorMode,
            singleColorHex: config.singleColorHex,
            showIconName: config.showIconNames,
            showNextSessionTime: metricConfig.showNextSessionTime
        )

        image.isTemplate = config.colorMode == .monochrome && !config.showPaceMarker
        button.image = image
    }

    /// Get button for a specific metric (used for popover positioning)
    func button(for metricType: MenuBarMetricType) -> NSStatusBarButton? {
        return statusItems[metricType]?.button
    }

    /// Get the first enabled metric's button (for backwards compatibility)
    var primaryButton: NSStatusBarButton? {
        for metricType in [MenuBarMetricType.session, .week, .api, .codex, .zai] {
            if let button = statusItems[metricType]?.button {
                return button
            }
        }
        return nil
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

    private var lastObservedAppearanceName: NSAppearance.Name?

    private func observeAppearanceChanges() {
        appearanceObservers.forEach { $0.invalidate() }
        appearanceObservers.removeAll()

        // IMPORTANT: Do NOT observe per-button effectiveAppearance.
        // Setting button.image triggers effectiveAppearance KVO on the button,
        // which causes an infinite redraw loop.
        let appObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, change in
            let newName = change.newValue?.name
            Task { @MainActor [weak self] in
                guard let self, newName != self.lastObservedAppearanceName else { return }
                self.lastObservedAppearanceName = newName
                // Clear image cache so next update re-renders with new appearance
                self.lastImageData.removeAll()
                self.delegate?.statusBarAppearanceDidChange()
            }
        }
        appearanceObservers.append(appObserver)
    }

    /// Only sets button.image if the image data actually changed.
    /// This prevents triggering effectiveAppearance KVO when the image is identical.
    private func setButtonImage(_ button: NSStatusBarButton, image: NSImage) {
        let buttonId = ObjectIdentifier(button)
        // Avoid NSImage.tiffRepresentation: macOS 26 SDK crashes in
        // SetupTIFFErrorHandler dispatch_once. Hash via CGImage bytes instead.
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let newData = cg.dataProvider?.data as Data? else {
            button.image = image
            return
        }
        if lastImageData[buttonId] == newData { return }
        lastImageData[buttonId] = newData
        button.image = image
    }

    /// Debounces appearance change notifications so multiple displays/buttons
    /// coalesce into a single delegate callback
    private func scheduleAppearanceUpdate() {
        appearanceDebounceTimer?.invalidate()
        appearanceDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.delegate?.statusBarAppearanceDidChange()
            }
        }
    }
}

// MARK: - Delegate Protocol

@MainActor
protocol StatusBarUIManagerDelegate: AnyObject {
    func statusBarAppearanceDidChange()
}
