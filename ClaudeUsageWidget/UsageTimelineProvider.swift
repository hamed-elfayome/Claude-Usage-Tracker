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
    /// Evaluated against the entry's own date so that a boundary entry in
    /// the timeline flips the dimming at the right moment.
    var isStale: Bool {
        guard let snapshot else { return true }
        return snapshot.isStale(at: date, interval: Self.staleInterval)
    }

    /// Per-profile staleness. The single-profile refresh path only updates
    /// the active profile, so other profiles can be stale even while the
    /// snapshot itself is fresh.
    func isProfileStale(_ profile: WidgetSnapshot.ProfileEntry) -> Bool {
        isStale || profile.isStale(at: date, interval: Self.staleInterval)
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
    private static let refreshInterval: TimeInterval = 15 * 60

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
        let snapshot = WidgetSnapshot.load()
        let now = Date()
        let refresh = now.addingTimeInterval(Self.refreshInterval)

        // Besides the immediate entry, add entries at the moments the
        // rendering changes on its own: staleness boundaries (dimming) and
        // reset times (countdown disappears). Without them those transitions
        // would lag until the next reload, up to `refreshInterval` late.
        var dates: Set<Date> = [now]
        if let snapshot {
            var boundaries = [snapshot.generatedAt.addingTimeInterval(UsageEntry.staleInterval)]
            for profile in snapshot.profiles {
                boundaries.append(profile.lastUpdated.addingTimeInterval(UsageEntry.staleInterval))
                if let sessionResetTime = profile.sessionResetTime {
                    boundaries.append(sessionResetTime)
                }
                if let weeklyResetTime = profile.weeklyResetTime {
                    boundaries.append(weeklyResetTime)
                }
            }
            for boundary in boundaries where boundary > now && boundary < refresh {
                dates.insert(boundary)
            }
        }

        let entries = dates.sorted().map { UsageEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}
