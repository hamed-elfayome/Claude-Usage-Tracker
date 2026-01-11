//
//  Notification+Extensions.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

extension Notification.Name {
    /// Posted when the menu bar icon configuration changes (metrics enabled/disabled, order, styling, etc.)
    static let menuBarIconConfigChanged = Notification.Name("menuBarIconConfigChanged")

    /// Posted when credentials are added, removed, or changed (Claude.ai or API Console)
    static let credentialsChanged = Notification.Name("credentialsChanged")

    /// Posted when the setup wizard should be shown manually (for testing)
    static let showSetupWizard = Notification.Name("showSetupWizard")
}
