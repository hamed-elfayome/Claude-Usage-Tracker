//
//  NotificationSettings.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-07.
//

import Foundation
import UserNotifications

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool
    var threshold75Enabled: Bool
    var threshold90Enabled: Bool
    var threshold95Enabled: Bool
    var soundName: String
    var customThresholds: [Int]

    /// All active thresholds (built-in + custom), sorted ascending
    var sortedThresholds: [Int] {
        var thresholds: [Int] = []
        if threshold75Enabled { thresholds.append(75) }
        if threshold90Enabled { thresholds.append(90) }
        if threshold95Enabled { thresholds.append(95) }
        thresholds.append(contentsOf: customThresholds)
        return Array(Set(thresholds)).sorted()
    }

    /// Resolved notification sound based on soundName
    var notificationSound: UNNotificationSound? {
        switch soundName {
        case "none":
            return nil
        case "default":
            return .default
        default:
            return UNNotificationSound(named: UNNotificationSoundName(soundName))
        }
    }

    init(
        enabled: Bool = true,
        threshold75Enabled: Bool = true,
        threshold90Enabled: Bool = true,
        threshold95Enabled: Bool = true,
        soundName: String = "default",
        customThresholds: [Int] = []
    ) {
        self.enabled = enabled
        self.threshold75Enabled = threshold75Enabled
        self.threshold90Enabled = threshold90Enabled
        self.threshold95Enabled = threshold95Enabled
        self.soundName = soundName
        self.customThresholds = customThresholds
    }

    // Backwards-compatible decoding for existing saved settings
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        threshold75Enabled = try container.decode(Bool.self, forKey: .threshold75Enabled)
        threshold90Enabled = try container.decode(Bool.self, forKey: .threshold90Enabled)
        threshold95Enabled = try container.decode(Bool.self, forKey: .threshold95Enabled)
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName) ?? "default"
        customThresholds = try container.decodeIfPresent([Int].self, forKey: .customThresholds) ?? []
    }
}
