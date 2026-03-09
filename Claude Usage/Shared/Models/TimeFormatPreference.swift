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

enum PopoverTimeDisplay: String, CaseIterable {
    case resetTime      // "Resets Today 3:59pm"
    case remainingTime  // "Resets in 3h 45m"
    case both           // "Resets in 3h 45m (Today 3:59pm)"
}
