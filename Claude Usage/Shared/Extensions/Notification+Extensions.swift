//
//  Notification+Extensions.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

extension Notification.Name {
    /// Posted when the menu bar icon style preference changes
    static let menuBarIconStyleChanged = Notification.Name("menuBarIconStyleChanged")

    /// Posted when the menu bar icon configuration changes (metrics enabled/disabled, order, etc.)
    static let menuBarIconConfigChanged = Notification.Name("menuBarIconConfigChanged")

    /// Posted when a session key is saved/updated (triggers immediate data refresh)
    static let sessionKeyUpdated = Notification.Name("sessionKeyUpdated")
}
