//
//  DateRangeSelection.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-28.
//

import Foundation

/// Date range selection for filtering history
struct DateRangeSelection: Equatable {
    var startDate: Date
    var endDate: Date
    var preset: DateRangePreset?

    init(startDate: Date, endDate: Date, preset: DateRangePreset? = nil) {
        self.startDate = startDate
        self.endDate = endDate
        self.preset = preset
    }

    /// Create from preset
    init(preset: DateRangePreset) {
        let now = Date()
        let calendar = Calendar.current

        switch preset {
        case .today:
            // Last 24 hours (not since midnight)
            self.startDate = now.addingTimeInterval(-24 * 3600)
            self.endDate = now
        case .last7Days:
            self.startDate = now.addingTimeInterval(-7 * 24 * 3600)
            self.endDate = now
        case .last30Days:
            self.startDate = now.addingTimeInterval(-30 * 24 * 3600)
            self.endDate = now
        case .thisWeek:
            self.startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            self.endDate = now
        case .thisMonth:
            self.startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            self.endDate = now
        case .custom:
            self.startDate = now.addingTimeInterval(-7 * 24 * 3600)
            self.endDate = now
        }

        self.preset = preset
    }

    /// Filter snapshots by date range
    func snapshots(from history: UsageHistoryData) -> [UsageSnapshot] {
        history.snapshots.filter { snapshot in
            snapshot.timestamp >= startDate && snapshot.timestamp <= endDate
        }
    }

    /// Check if date range is valid
    var isValid: Bool {
        endDate >= startDate
    }

    /// Formatted range string
    var formattedRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        if let preset = preset, preset != .custom {
            return preset.displayName
        }

        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    /// Default range (last 7 days)
    static var `default`: DateRangeSelection {
        DateRangeSelection(preset: .last7Days)
    }
}

/// Date range preset options
enum DateRangePreset: String, CaseIterable, Hashable {
    case today = "Today"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case custom = "Custom"

    var displayName: String {
        rawValue
    }
}
