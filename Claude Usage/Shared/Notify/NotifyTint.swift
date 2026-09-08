//
//  NotifyTint.swift
//  Claude Usage
//
//  The colors and symbols sent to Notify!.
//

import Foundation

extension NotifyQuotaStatus {
    /// The accent color sent to Notify! for this status.
    ///
    /// These are the system colors the menu bar icon already uses, written as
    /// hex because the gateway wants `#RRGGBB` and Foundation has no view layer
    /// here. Keeping them in step means a quota that looks critical in the menu
    /// bar looks critical on the Lock Screen.
    var notifyTintHex: String {
        switch self {
        case .healthy: return "#34C759"   // systemGreen
        case .warning: return "#FF9500"   // systemOrange
        case .critical: return "#FF3B30"  // systemRed
        case .depleted: return "#D70015"  // a darker red, for a window with nothing left
        }
    }
}

/// SF Symbols we ask Notify! to draw. Named here rather than inline so the tile
/// and the widget cannot drift apart.
enum NotifySymbol {
    /// The tile and widget icon. A gauge reads correctly at both sizes and does
    /// not imply a direction of travel the way an arrow would.
    static let quota = "gauge.with.needle"
}
