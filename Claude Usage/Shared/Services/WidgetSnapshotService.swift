import Foundation
import WidgetKit

/// Publishes the current usage of all display-selected profiles to the
/// WidgetKit extension.
///
/// Mirrors `StatuslineService.writeUsageCache`: after each refresh cycle the
/// app serializes a small JSON snapshot to Application Support and asks
/// WidgetKit to reload timelines. Writes are skipped when nothing meaningful
/// changed so the WidgetKit reload budget is not burned on identical data.
final class WidgetSnapshotService {
    static let shared = WidgetSnapshotService()

    private var lastPublishedProfiles: [WidgetSnapshot.ProfileEntry]?
    private var lastReloadTime: Date = .distantPast

    /// Minimum spacing between WidgetKit reload requests, so frequent
    /// refresh cycles don't exhaust the system's reload budget.
    private static let reloadInterval: TimeInterval = 60

    private init() {}

    /// Builds a snapshot from the given profiles and publishes it if it
    /// differs from the last published one.
    func publish(profiles: [Profile], activeProfileId: UUID?) {
        let entries: [WidgetSnapshot.ProfileEntry] = profiles
            .filter { $0.isSelectedForDisplay }
            .compactMap { profile in
                guard let usage = profile.claudeUsage else { return nil }
                return WidgetSnapshot.ProfileEntry(
                    id: profile.id,
                    name: profile.name,
                    isActive: profile.id == activeProfileId,
                    sessionPercentage: usage.effectiveSessionPercentage,
                    sessionResetTime: usage.sessionResetTime,
                    weeklyPercentage: usage.weeklyPercentage,
                    weeklyResetTime: usage.weeklyResetTime,
                    lastUpdated: usage.lastUpdated
                )
            }

        guard !entries.isEmpty else { return }
        guard hasMeaningfulChange(entries) else { return }

        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: entries)
        do {
            try snapshot.write()
            lastPublishedProfiles = entries
            if Date().timeIntervalSince(lastReloadTime) >= Self.reloadInterval {
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
            let identityChanged = old.id != new.id || old.name != new.name || old.isActive != new.isActive
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
