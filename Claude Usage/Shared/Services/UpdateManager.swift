//
//  UpdateManager.swift
//  Claude Usage
//
//  Sparkle update manager wrapper
//

import Foundation
import Combine
import Sparkle

/// Manages automatic updates using Sparkle framework
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var automaticChecksEnabled: Bool

    private init() {
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        automaticChecksEnabled = updaterController.updater.automaticallyChecksForUpdates
        canCheckForUpdates = updaterController.updater.canCheckForUpdates

        LoggingService.shared.logInfo("Update manager initialized")
    }

    /// Manually check for updates
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
        LoggingService.shared.logInfo("Manual update check triggered")
    }

    /// Toggle automatic update checks
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticChecksEnabled = enabled
        DataStore.shared.userDefaults.set(enabled, forKey: "SUEnableAutomaticChecks")
        LoggingService.shared.logInfo("Automatic updates: \(enabled)")
    }

    /// Get last update check date
    var lastUpdateCheckDate: Date? {
        return updaterController.updater.lastUpdateCheckDate
    }
}
