//
//  MenuBarAppearanceTracker.swift
//  Claude Usage
//
//  Pure bookkeeping for "which light/dark appearance was each status bar
//  button last rendered with?". Kept AppKit-free so it can be unit tested.
//

import Foundation

/// Tracks the resolved light/dark appearance each menu bar button was last
/// drawn with, and decides whether a re-read appearance warrants a redraw.
///
/// The menu bar's tint can flip independently of the system theme (a light
/// wallpaper on one Space, a dark one on the next). Per-button
/// `effectiveAppearance` KVO catches that. Comparing the *settled* appearance
/// against the value actually baked into the last render is what keeps the
/// observation from becoming a redraw loop: assigning `button.image` fires
/// the same KVO, but the appearance it settles on is the one we just drew.
struct MenuBarAppearanceTracker {
    private var lastRenderedIsDark: [ObjectIdentifier: Bool] = [:]

    /// Record the appearance a button was just rendered with.
    mutating func recordRender(for buttonId: ObjectIdentifier, isDark: Bool) {
        lastRenderedIsDark[buttonId] = isDark
    }

    /// Whether a button's current appearance differs from what it shows.
    /// A button that has never been rendered is left to the normal render
    /// path (returns `false`) so observation alone can't trigger work.
    func needsRedraw(for buttonId: ObjectIdentifier, currentIsDark: Bool) -> Bool {
        guard let rendered = lastRenderedIsDark[buttonId] else { return false }
        return rendered != currentIsDark
    }

    func isTracking(_ buttonId: ObjectIdentifier) -> Bool {
        lastRenderedIsDark[buttonId] != nil
    }

    /// Drop bookkeeping for buttons that no longer exist.
    mutating func retain(only liveButtonIds: Set<ObjectIdentifier>) {
        lastRenderedIsDark = lastRenderedIsDark.filter { liveButtonIds.contains($0.key) }
    }

    var trackedCount: Int { lastRenderedIsDark.count }
}
