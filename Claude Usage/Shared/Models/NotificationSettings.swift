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

    init(
        enabled: Bool = true,
        threshold75Enabled: Bool = true,
        threshold90Enabled: Bool = true,
        threshold95Enabled: Bool = true,
        soundName: String = "default",
        customThresholds: [Int] = [75, 90, 95]
    ) {
        self.enabled = enabled
        self.threshold75Enabled = threshold75Enabled
        self.threshold90Enabled = threshold90Enabled
        self.threshold95Enabled = threshold95Enabled
        self.soundName = soundName
        self.customThresholds = customThresholds
    }

    // MARK: - Codable (backwards compatibility)

    enum CodingKeys: String, CodingKey {
        case enabled, threshold75Enabled, threshold90Enabled, threshold95Enabled
        case soundName, customThresholds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        threshold75Enabled = try container.decode(Bool.self, forKey: .threshold75Enabled)
        threshold90Enabled = try container.decode(Bool.self, forKey: .threshold90Enabled)
        threshold95Enabled = try container.decode(Bool.self, forKey: .threshold95Enabled)
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName) ?? "default"

        // Migrate from legacy booleans if customThresholds not present
        if let thresholds = try container.decodeIfPresent([Int].self, forKey: .customThresholds) {
            customThresholds = thresholds
        } else {
            // Build from legacy booleans
            var migrated: [Int] = []
            if threshold75Enabled { migrated.append(75) }
            if threshold90Enabled { migrated.append(90) }
            if threshold95Enabled { migrated.append(95) }
            customThresholds = migrated
        }
    }

    /// Sorted thresholds for notification checking (highest first)
    var sortedThresholds: [Int] {
        customThresholds.sorted(by: >)
    }

    /// Resolve to UNNotificationSound
    var notificationSound: UNNotificationSound {
        switch soundName {
        case "default":
            return .default
        case "none":
            return .default
        default:
            return UNNotificationSound(named: UNNotificationSoundName(soundName))
        }
    }

    /// Whether sound is disabled
    var isSoundDisabled: Bool {
        soundName == "none"
    }
}
