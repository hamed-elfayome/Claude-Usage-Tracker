import Foundation
import WidgetKit

// Compile alongside the actual shared snapshot and timeline provider:
// swiftc WidgetShared/WidgetSnapshot.swift ClaudeUsageWidget/UsageTimelineProvider.swift \
//   scripts/WidgetTimelineFreshnessTests.swift -o /tmp/widget-freshness-tests
// /tmp/widget-freshness-tests
@main
enum WidgetTimelineFreshnessTests {
    static func main() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = WidgetSnapshot.ProfileEntry(
            id: UUID(), name: "Fixture", isActive: true, isDisplayed: true,
            sessionPercentage: 42, sessionResetTime: start.addingTimeInterval(3600),
            weeklyPercentage: 61, weeklyResetTime: start.addingTimeInterval(86400),
            lastUpdated: start
        )
        let snapshot = WidgetSnapshot(generatedAt: start, profiles: [profile])
        var failures = 0
        for (age, expected) in [(899.0, false), (900.0, true), (901.0, true)] {
            let date = start.addingTimeInterval(age)
            let entry = UsageEntry(date: date, snapshot: snapshot)
            // A fresh heartbeat must not hide an independently stale profile.
            let fresh = WidgetSnapshot(generatedAt: date, profiles: [profile])
            let profileEntry = UsageEntry(date: date, snapshot: fresh)
            for (label, actual) in [
                ("snapshot", entry.isStale),
                ("profile", profileEntry.isProfileStale(profile))
            ] {
                if actual != expected {
                    print("FAIL: \(label) at \(age)s: \(actual), expected \(expected)")
                    failures += 1
                }
            }
        }
        if !UsageEntry(date: start, snapshot: nil).isStale {
            print("FAIL: missing snapshot must be stale")
            failures += 1
        }
        if failures > 0 { exit(1) }
        print("Widget timeline freshness: 7 checks passed")
    }
}
