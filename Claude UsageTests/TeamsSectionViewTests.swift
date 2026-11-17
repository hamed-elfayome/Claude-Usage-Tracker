import XCTest
import SwiftUI
import AppKit
@testable import Claude_Usage

@MainActor
final class TeamsSectionViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func row(_ org: String, state: TeamRow.State = .ok, current: Bool = false, profile: String = "P",
                     view: PairView = PairView(sessionPercent: 40, weeklyPercent: 30, sessionLeft: 60, weeklyLeft: 70, headroom: 60),
                     sampled: Date? = nil, days: Int? = nil) -> TeamRow {
        let pair = PairRef(profileId: UUID(), orgId: org)
        return TeamRow(id: org, pair: pair, profileName: profile, orgName: org, isCurrent: current, view: view,
                       lastSampleAt: sampled ?? now, state: state, deleteAfterDays: days)
    }

    private func layout(_ rows: [TeamRow], events: [TeamEvent]) -> NSSize {
        let v = TeamsSectionView(rows: rows, events: events, now: now, onMakeCurrent: { _ in }, onDelete: { _ in })
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 10)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private func events(_ n: Int) -> [TeamEvent] {
        (0..<n).map { TeamEvent(kind: .loginRestored(profileId: UUID()), names: [:], date: now.addingTimeInterval(Double(-$0 * 60))) }
    }

    func testThreeRowsTwoEventsLayOut() {
        var projected = PairView(sessionPercent: 0, weeklyPercent: 30, sessionProjected: true, sessionLeft: 100, weeklyLeft: 70, headroom: 70)
        projected.weeklyProjected = false
        let rows = [row("a", current: true), row("b", view: projected, sampled: now.addingTimeInterval(-3600)),
                    row("c", state: .old, days: 3)]
        let size = layout(rows, events: events(2))
        XCTAssertLessThanOrEqual(size.width, 280)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testNeedsLoginNoEventsAndNilHeadroom() {
        let size = layout([row("a", state: .needsLogin, view: PairView()), row("b", view: PairView())], events: [])
        XCTAssertLessThanOrEqual(size.width, 280)
    }

    func testVeryLongNamesStayWithinWidth() {
        let long = String(repeating: "VeryLongName", count: 20)
        let size = layout([row(long, profile: long)], events: events(7))
        XCTAssertLessThanOrEqual(size.width, 280)
    }

    func testCanMakeCurrent() {
        XCTAssertTrue(TeamsSectionView.canMakeCurrent(row("a")))
        XCTAssertFalse(TeamsSectionView.canMakeCurrent(row("a", current: true)))
        for s in [TeamRow.State.old, .needsLogin, .notSignedIn, .unreachable] {
            XCTAssertFalse(TeamsSectionView.canMakeCurrent(row("a", state: s)), "\(s)")
        }
    }

    func testCanDelete() {
        XCTAssertTrue(TeamsSectionView.canDelete(row("a", state: .old)))
        XCTAssertTrue(TeamsSectionView.canDelete(row("a", state: .unreachable)))
        for s in [TeamRow.State.ok, .needsLogin, .notSignedIn] {
            XCTAssertFalse(TeamsSectionView.canDelete(row("a", state: s)), "\(s)")
        }
    }

    func testDetailText() {
        XCTAssertEqual(TeamsSectionView.detail(row("a", state: .needsLogin), now: now), ["Log in again"])
        XCTAssertEqual(TeamsSectionView.detail(row("a", state: .old, days: 4), now: now), ["Old team · deleted in 4 days"])
        XCTAssertEqual(TeamsSectionView.detail(row("a", state: .unreachable), now: now), ["Old team"])
        let stale = TeamsSectionView.detail(row("a", sampled: now.addingTimeInterval(-1800)), now: now)
        XCTAssertEqual(stale, ["5h 60% left", "Week 70% left", "30 min ago"])
        let noSession = TeamsSectionView.detail(row("a", view: PairView(weeklyPercent: 10, weeklyLeft: 90, headroom: 90)), now: now)
        XCTAssertEqual(noSession, ["Week 90% left"])
        var p = PairView(sessionPercent: 0, weeklyPercent: 0, sessionLeft: 100, weeklyLeft: 100, headroom: 100)
        p.sessionProjected = true
        XCTAssertTrue(TeamsSectionView.detail(row("a", view: p), now: now).contains("projected"))
    }

    // MARK: history picker

    private func tracked(_ id: String, _ status: PairStatus) -> TrackedOrg {
        TrackedOrg(orgId: id, name: "Team \(id)", status: status, historyKey: "k-\(id)", seat: nil, lastUsage: nil,
                   lastSampleAt: nil, firstSeenAt: now, lastSeenInListAt: nil, missingFromListCount: 0,
                   lastMembershipFailureAt: nil, pending: nil, baselineStartedAt: now, roundReading: nil)
    }

    private func profile(_ orgs: [TrackedOrg], followed: String?, tracking: Bool = true) -> Profile {
        var st = OrgTrackingState.empty
        st.orgs = orgs
        return Profile(name: "P", organizationId: followed, orgTracking: tracking ? st : nil)
    }

    func testHistoryChoices() {
        let two = TeamsSectionView.historyChoices(for: profile([tracked("a", .member), tracked("b", .old)], followed: "a"))
        XCTAssertEqual(two.map(\.key), ["k-a", "k-b"])
        XCTAssertEqual(two.map(\.label), ["Team a", "Team b (old)"])
        XCTAssertTrue(TeamsSectionView.historyChoices(for: profile([tracked("a", .member)], followed: "a")).isEmpty)
        XCTAssertTrue(TeamsSectionView.historyChoices(for: profile([], followed: nil, tracking: false)).isEmpty)
    }

    func testDefaultHistoryKeyIsFollowedOrg() {
        let orgs = [tracked("a", .member), tracked("b", .member)]
        XCTAssertEqual(TeamsSectionView.defaultHistoryKey(for: profile(orgs, followed: "b")), "k-b")
        XCTAssertEqual(TeamsSectionView.defaultHistoryKey(for: profile(orgs, followed: "zzz")), "k-a")
        XCTAssertNil(TeamsSectionView.defaultHistoryKey(for: profile([tracked("a", .member)], followed: "a")))
    }

    // MARK: strings

    func testUIKeysExistInEveryLocalization() throws {
        let bundle = Bundle(for: ProfileManager.self)
        let langs = bundle.localizations.filter { $0 != "Base" }
        XCTAssertGreaterThanOrEqual(langs.count, 15)
        for lang in langs {
            let path = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: lang), lang)
            let dict = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], lang)
            for key in Self.uiKeys {
                XCTAssertNotNil(dict[key], "\(lang) missing \(key)")
            }
            for (key, value) in dict where key.hasPrefix("multiteam.ui.") {
                XCTAssertFalse(value.contains("%d"), "\(lang) \(key) uses bare %d")
            }
            for key in ["multiteam.ui.five_hour_left", "multiteam.ui.week_left", "multiteam.ui.min_ago", "multiteam.ui.old_days"] {
                XCTAssertTrue(dict[key]?.contains("%ld") == true, "\(lang) \(key) lacks %ld")
            }
        }
    }

    private static let uiKeys = [
        "multiteam.ui.teams", "multiteam.ui.now", "multiteam.ui.five_hour_left", "multiteam.ui.week_left",
        "multiteam.ui.projected", "multiteam.ui.min_ago", "multiteam.ui.old_days", "multiteam.ui.old",
        "multiteam.ui.make_current", "multiteam.ui.delete", "multiteam.ui.cancel", "multiteam.ui.delete_confirm",
        "multiteam.ui.history_team", "multiteam.ui.history_old_suffix", "multiteam.ui.tracking_title",
        "multiteam.ui.tracking_description", "multiteam.ui.google_hint",
    ]

    func testUIKeyListHas17Keys() {
        XCTAssertEqual(Set(Self.uiKeys).count, 17)
    }

    // FU-3 AC5: .ok row without usage has empty detail and still lays out.
    func testOkRowWithNoUsageHasEmptyDetailAndLaysOut() {
        let empty = row("a", view: PairView())
        XCTAssertEqual(TeamsSectionView.detail(empty, now: now), [])
        let emptySize = layout([empty], events: [])
        let fullSize = layout([row("a")], events: [])
        XCTAssertLessThanOrEqual(emptySize.width, 280)
        XCTAssertLessThan(emptySize.height, fullSize.height, "empty detail line must not take space")
    }

    func testToggleKey() {
        XCTAssertEqual(TeamTrackingSettings.enabledKey, "multiTeam.enabled")
    }
}
