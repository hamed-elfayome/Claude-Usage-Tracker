//
//  TimeFormatPreference.swift
//  Claude Usage
//

import Foundation

enum TimeFormatPreference: String, CaseIterable {
    case system        // Follow macOS system setting
    case twelveHour    // Always use 12-hour (3:59 PM)
    case twentyFourHour // Always use 24-hour (15:59)
}
