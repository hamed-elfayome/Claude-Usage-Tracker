//
//  LaunchAtLoginManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import ServiceManagement

/// Manages the "Launch at Login" functionality using SMAppService
/// Provides a simple interface to enable/disable automatic app startup on macOS
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    // MARK: - Public API

    /// Returns whether the app is currently set to launch at login
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enables or disables launch at login
    /// - Parameter enabled: Whether to enable or disable launch at login
    /// - Returns: `true` if the operation succeeded, `false` otherwise
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    // Already enabled
                    return true
                }
                try SMAppService.mainApp.register()
                LoggingService.shared.logInfo("Launch at Login enabled")
                return true
            } else {
                if SMAppService.mainApp.status != .enabled {
                    // Already disabled
                    return true
                }
                try SMAppService.mainApp.unregister()
                LoggingService.shared.logInfo("Launch at Login disabled")
                return true
            }
        } catch {
            LoggingService.shared.logError("Failed to set Launch at Login", error: error)
            return false
        }
    }

    /// Returns the current status of the login item for debugging
    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "Not found"
        @unknown default:
            return "Unknown"
        }
    }
}
