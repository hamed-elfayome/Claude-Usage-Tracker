//
//  NotificationSettings.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool
    var threshold75Enabled: Bool
    var threshold90Enabled: Bool
    var threshold95Enabled: Bool

    init(
        enabled: Bool = true,
        threshold75Enabled: Bool = true,
        threshold90Enabled: Bool = true,
        threshold95Enabled: Bool = true
    ) {
        self.enabled = enabled
        self.threshold75Enabled = threshold75Enabled
        self.threshold90Enabled = threshold90Enabled
        self.threshold95Enabled = threshold95Enabled
    }
}
