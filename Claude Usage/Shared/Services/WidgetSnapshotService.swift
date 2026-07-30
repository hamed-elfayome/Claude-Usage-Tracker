import Foundation
import WidgetKit

/// Publishes the current usage of the display-selected profiles (plus the
/// active profile) to the WidgetKit extension.
///
/// Mirrors `StatuslineService.writeUsageCache`: after each refresh cycle the
/// app serializes a small JSON snapshot to Application Support and asks
/// WidgetKit to reload timelines. Timeline reloads only happen on meaningful
/// changes, but the snapshot itself is rewritten at least every
/// `heartbeatInterval` — the widget uses `generatedAt` as an app-alive
/// signal, so a healthy app with flat usage must still refresh it.
final class WidgetSnapshotService {
    static let shared = WidgetSnapshotService()

    private var lastPublishedProfiles: [WidgetSnapshot.ProfileEntry]?
    private var lastWriteTime: Date = .distantPast
    private var lastReloadTime: Date = .distantPast

    /// Maximum age of the on-disk snapshot while the app is running. Must be
    /// comfortably below the widget's stale threshold (15 min).
    private static let heartbeatInterval: TimeInterval = 5 * 60

    /// Minimum spacing between WidgetKit reload requests, so frequent
    /// refresh cycles don't exhaust the system's reload budget.
    private static let reloadInterval: TimeInterval = 60

    private init() {}

    /// Builds a snapshot from the given profiles and publishes it if it
    /// differs from the last published one or the heartbeat is due.
    func publish(profiles: [Profile], activeProfileId: UUID?) {
        let entries: [WidgetSnapshot.ProfileEntry] = profiles.compactMap { profile in
            let isActive = profile.id == activeProfileId
            // The active profile is always included so the small widget can
            // show it even when it is deselected from menu bar display.
            guard profile.isSelectedForDisplay || isActive else { return nil }
            guard let usage = profile.claudeUsage else { return nil }
            return WidgetSnapshot.ProfileEntry(
                id: profile.id,
                name: profile.name,
                isActive: isActive,
                isDisplayed: profile.isSelectedForDisplay,
                sessionPercentage: usage.effectiveSessionPercentage,
                sessionResetTime: usage.sessionResetTime,
                weeklyPercentage: usage.weeklyPercentage,
                weeklyResetTime: usage.weeklyResetTime,
                lastUpdated: usage.lastUpdated
            )
        }

        // An empty entries list is still published: it clears the widget to
        // its no-data state (e.g. after the last credentials were removed).
        // Old data must not linger on disk until the stale threshold.
        let changed = hasMeaningfulChange(entries)
        let heartbeatDue = Date().timeIntervalSince(lastWriteTime) >= Self.heartbeatInterval
        guard changed || heartbeatDue else { return }

        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: entries)
        do {
            try snapshot.write()
            lastWriteTime = Date()
            lastPublishedProfiles = entries
            if changed, Date().timeIntervalSince(lastReloadTime) >= Self.reloadInterval {
                lastReloadTime = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            LoggingService.shared.log("WidgetSnapshotService: Failed to write snapshot - \(error.localizedDescription)")
        }
    }

    /// Whole-percent or reset-time changes are worth a widget reload;
    /// sub-percent jitter is not.
    private func hasMeaningfulChange(_ entries: [WidgetSnapshot.ProfileEntry]) -> Bool {
        guard let previous = lastPublishedProfiles, previous.count == entries.count else {
            return true
        }
        for (old, new) in zip(previous, entries) {
            let identityChanged = old.id != new.id || old.name != new.name
                || old.isActive != new.isActive || old.isDisplayed != new.isDisplayed
            let sessionChanged = Int(old.sessionPercentage) != Int(new.sessionPercentage)
                || Int(old.sessionResetTime.timeIntervalSince1970) != Int(new.sessionResetTime.timeIntervalSince1970)
            let weeklyChanged = Int(old.weeklyPercentage) != Int(new.weeklyPercentage)
                || Int(old.weeklyResetTime.timeIntervalSince1970) != Int(new.weeklyResetTime.timeIntervalSince1970)
            if identityChanged || sessionChanged || weeklyChanged {
                return true
            }
        }
        return false
    }
}
