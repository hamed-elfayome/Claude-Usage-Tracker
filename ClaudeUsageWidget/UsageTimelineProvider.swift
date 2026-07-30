import Foundation
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// Data older than this is rendered dimmed — the app is probably not
    /// running (or a profile stopped refreshing), so the numbers can no
    /// longer be trusted. The app writes a heartbeat snapshot every 5 min.
    static let staleInterval: TimeInterval = 15 * 60

    /// Whole-snapshot staleness: the app stopped publishing entirely.
    var isStale: Bool {
        guard let snapshot else { return true }
        return Date().timeIntervalSince(snapshot.generatedAt) > Self.staleInterval
    }

    /// Per-profile staleness. The single-profile refresh path only updates
    /// the active profile, so other profiles can be stale even while the
    /// snapshot itself is fresh.
    func isProfileStale(_ profile: WidgetSnapshot.ProfileEntry) -> Bool {
        isStale || Date().timeIntervalSince(profile.lastUpdated) > Self.staleInterval
    }

    static func placeholderSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Date(),
            profiles: [
                WidgetSnapshot.ProfileEntry(
                    id: UUID(),
                    name: "Claude",
                    isActive: true,
                    isDisplayed: true,
                    sessionPercentage: 42,
                    sessionResetTime: Date().addingTimeInterval(3 * 3600),
                    weeklyPercentage: 61,
                    weeklyResetTime: Date().addingTimeInterval(2 * 86400),
                    lastUpdated: Date()
                )
            ]
        )
    }
}

/// Reads the snapshot the main app publishes to Application Support.
///
/// The app requests a timeline reload after every refresh cycle, so entries
/// here only need a coarse fallback cadence for the case where the app quit.
struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: UsageEntry.placeholderSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = context.isPreview
            ? UsageEntry.placeholderSnapshot()
            : WidgetSnapshot.load()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: WidgetSnapshot.load())
        let refresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}
