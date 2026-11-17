import XCTest
@testable import Claude_Usage

/// MT-7: team events become notifications (NotificationManager: TeamEventNotifying).
@MainActor
final class TeamEventNotificationTests: XCTestCase {
    private let p = UUID()
    private let q = UUID()

    private func profile(_ id: UUID, notifications: Bool) -> Profile {
        Profile(id: id, name: "P", notificationSettings: NotificationSettings(enabled: notifications))
    }

    private func allKinds() -> [TeamEvent.Kind] {
        let ref = PairRef(profileId: p, orgId: "a")
        return [
            .nowOn(ref, from: nil, manual: false),
            .nowOn(ref, from: PairRef(profileId: q, orgId: "b"), manual: true),
            .adminMove(profileId: p, from: "a", to: "b"),
            .groupMove(from: "a", to: "b", moves: [p: "b"], notMoved: [q], unchecked: []),
            .groupMove(from: "a", to: nil, moves: [p: nil], notMoved: [], unchecked: [q]),
            .teamRemoved(profileId: p, org: "a"),
            .teamChanged(profileId: p, from: "a", to: "b"),
            .teamAdded(profileId: p, org: "a"),
            .teamRejoined(profileId: p, org: "a"),
            .seatChange(ref, from: "x", to: nil, inferred: true),
            .seatChange(ref, from: "x", to: "y", inferred: false),
            .earlyReset(ref, window: .weekly, fromPercent: 80, toPercent: 2),
            .loginLost(profileId: p, reason: "401"),
            .loginRestored(profileId: p),
            .oldTeamDeleted(profileId: p, org: "a", manual: true),
        ]
    }

    // AC6
    func testAdminMoveContent() {
        let id = UUID()
        let e = TeamEvent(kind: .adminMove(profileId: p, from: "a", to: "b"),
                          names: ["a": "A", "b": "B", p.uuidString: "Work"], id: id)
        let c = NotificationManager.teamEventContent(e)
        XCTAssertEqual(c.identifier, "team-event-\(id.uuidString)")
        XCTAssertEqual(c.title, "Moved by admin: A → B")
        XCTAssertEqual(c.body, e.body)
        XCTAssertFalse(c.body.isEmpty)
    }

    func testEveryKindHasNonEmptyTitle() {
        for k in allKinds() {
            let c = NotificationManager.teamEventContent(TeamEvent(kind: k, names: ["a": "A", "b": "B"]))
            XCTAssertFalse(c.title.isEmpty, "\(k)")
            XCTAssertFalse(c.title.hasPrefix("multiteam.event."), "unlocalized title for \(k)")
        }
    }

    // AC7
    func testNonNotifyingEventIsNotPosted() {
        let e = TeamEvent(kind: .teamAdded(profileId: p, org: "a"), names: [:])
        XCTAssertFalse(e.notifies)
        XCTAssertFalse(NotificationManager.shouldPostTeamEvent(e, profiles: [profile(p, notifications: true)]))
        let manual = TeamEvent(kind: .nowOn(PairRef(profileId: p, orgId: "a"), from: nil, manual: true), names: [:])
        XCTAssertFalse(NotificationManager.shouldPostTeamEvent(manual, profiles: [profile(p, notifications: true)]))
    }

    func testEveryInvolvedProfileDisabledIsNotPosted() {
        let e = TeamEvent(kind: .groupMove(from: "a", to: "b", moves: [p: "b", q: "b"], notMoved: [], unchecked: []),
                          names: [:])
        XCTAssertTrue(e.notifies)
        XCTAssertFalse(NotificationManager.shouldPostTeamEvent(
            e, profiles: [profile(p, notifications: false), profile(q, notifications: false)]))
    }

    func testNotifyingEventWithEnabledProfileIsPosted() {
        let e = TeamEvent(kind: .adminMove(profileId: p, from: "a", to: "b"), names: [:])
        XCTAssertTrue(NotificationManager.shouldPostTeamEvent(e, profiles: [profile(p, notifications: true)]))
    }

    // Edge: group event where only one involved profile has notifications on → posted.
    func testGroupEventWithOneEnabledProfileIsPosted() {
        let e = TeamEvent(kind: .groupMove(from: "a", to: "b", moves: [p: "b"], notMoved: [q], unchecked: []),
                          names: [:])
        XCTAssertTrue(NotificationManager.shouldPostTeamEvent(
            e, profiles: [profile(p, notifications: false), profile(q, notifications: true)]))
    }

    // Edge: event naming a deleted profile. The tracker passes only profiles that still exist.
    func testEventNamingDeletedProfile() {
        let e = TeamEvent(kind: .teamRemoved(profileId: p, org: "a"), names: ["a": "Team A", p.uuidString: "Gone"])
        XCTAssertFalse(NotificationManager.shouldPostTeamEvent(e, profiles: []))
        let c = NotificationManager.teamEventContent(e)
        XCTAssertTrue(c.title.contains("Team A"), c.title)
        XCTAssertTrue(c.body.contains("Gone"), c.body)
        let group = TeamEvent(kind: .groupMove(from: "a", to: "b", moves: [p: "b", q: "b"], notMoved: [], unchecked: []),
                              names: [:])
        XCTAssertTrue(NotificationManager.shouldPostTeamEvent(group, profiles: [profile(q, notifications: true)]))
    }
}

/// MT-7: the menu bar loop follows the current pair only while Team tracking runs.
@MainActor
final class MenuBarTeamWiringTests: XCTestCase {
    private func anthropic(_ name: String, id: UUID = UUID(), needsLogin: Bool = false) -> Profile {
        var p = Profile(id: id, name: name, claudeSessionKey: "sk-\(name)", organizationId: "org-a")
        var st = OrgTrackingState.empty
        if needsLogin { st.authState = .needsLogin(reason: "invalid_grant", since: Date()) }
        p.orgTracking = st
        return p
    }

    private func codex(_ name: String) -> Profile { Profile(name: name, provider: .codex) }

    /// Profiles whose claude.ai usage a multi-mode pass fetches (the loop visits the others for
    /// console billing only).
    private func usageFetched(_ plan: MenuBarManager.MultiFetchPlan) -> [UUID] {
        plan.profiles.map(\.id).filter { !plan.usageSkip.contains($0) }
    }

    private func apiUsage(_ spendCents: Int) -> APIUsage {
        APIUsage(currentSpendCents: spendCents, resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
                 prepaidCreditsCents: 1_000, currency: "USD", apiTokenCostCents: nil, apiCostByModel: nil,
                 costBySource: nil, dailyCostCents: nil)
    }

    // menuBarProfile: current account while running, active profile otherwise.
    func testMenuBarProfileFollowsCurrentOnlyWhileRunning() {
        let a = anthropic("A"), b = anthropic("B")
        let cur = PairRef(profileId: b.id, orgId: "org-a")
        XCTAssertEqual(MenuBarManager.menuBarProfile(running: true, current: cur, profiles: [a, b], active: a)?.id, b.id)
        XCTAssertEqual(MenuBarManager.menuBarProfile(running: false, current: cur, profiles: [a, b], active: a)?.id, a.id)
        XCTAssertEqual(MenuBarManager.menuBarProfile(running: true, current: nil, profiles: [a, b], active: a)?.id, a.id)
        // current points at a deleted profile → active profile
        XCTAssertEqual(MenuBarManager.menuBarProfile(running: true, current: cur, profiles: [a], active: a)?.id, a.id)
    }

    // AC4 / "Codex profiles never change": a Codex active profile stays shown while tracking runs and
    // keeps today's fetch path; it is never swapped for the current anthropic account.
    func testCodexActiveProfileStaysShownWhileRunning() throws {
        let c = codex("C"), b = anthropic("B")
        let cur = PairRef(profileId: b.id, orgId: "org-a")
        let shown = try XCTUnwrap(MenuBarManager.menuBarProfile(running: true, current: cur, profiles: [c, b], active: c))
        XCTAssertEqual(shown.id, c.id)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: shown, activeId: c.id, running: true, target: (b, "org-a")),
                       .legacy)
    }

    // AC2 / spec §7, fix round 2: with a Codex shown profile (on today's path) the pass also polls the
    // current pair, which the tracker never probes. Never with the tracker off or without a live
    // target, and never for an anthropic subject (shownFetchPlan already fetches it: no second fetch).
    func testBackgroundLiveTargetOnlyForNonAnthropicSubjectWhileRunning() throws {
        let c = codex("C"), b = anthropic("B")
        let target = try XCTUnwrap(MenuBarManager.backgroundLiveTarget(subject: c, running: true, target: (b, "org-b")))
        XCTAssertEqual(target.profile.id, b.id)
        XCTAssertEqual(target.orgId, "org-b")
        XCTAssertNil(MenuBarManager.backgroundLiveTarget(subject: c, running: true, target: nil))
        XCTAssertNil(MenuBarManager.backgroundLiveTarget(subject: c, running: false, target: (b, "org-b")))
        XCTAssertNil(MenuBarManager.backgroundLiveTarget(subject: b, running: true, target: (b, "org-b")))
    }

    // The single-mode popover shows `apiUsage` (the active profile's console data) only when the shown
    // profile is the active one; another shown account gets its own saved data, or nothing.
    func testShownAPIUsageNeverShowsActiveConsoleDataForAnotherAccount() {
        let a = anthropic("A"), live = apiUsage(500)
        var b = anthropic("B")
        b.apiUsage = apiUsage(42)
        XCTAssertEqual(MenuBarManager.shownAPIUsage(shown: b, activeId: a.id, live: live), apiUsage(42))
        XCTAssertNil(MenuBarManager.shownAPIUsage(shown: anthropic("C"), activeId: a.id, live: live))
        // Shown profile is the active one (always so with tracking off) → today's live value.
        XCTAssertEqual(MenuBarManager.shownAPIUsage(shown: a, activeId: a.id, live: live), live)
        XCTAssertEqual(MenuBarManager.shownAPIUsage(shown: nil, activeId: nil, live: live), live)
    }

    // AC2: current account != active → per-profile fetch (never activated).
    func testSingleModeFetchesCurrentByProfileWhenNotActive() {
        let a = anthropic("A"), b = anthropic("B")
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: b, activeId: a.id, running: true, target: (b, "org-x")),
                       .tracked(orgId: "org-x", byProfile: true))
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: a, activeId: a.id, running: true, target: (a, "org-x")),
                       .tracked(orgId: "org-x", byProfile: false))
    }

    // AC3: no live target (or another account's) → no fetch this pass.
    func testSingleModeSkipsWithoutLiveTarget() {
        let a = anthropic("A"), b = anthropic("B")
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: a, activeId: a.id, running: true, target: nil), .skip)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: a, activeId: a.id, running: true, target: (b, "org-a")), .skip)
    }

    // AC1/AC4: tracker off, or a Codex profile → today's path.
    func testSingleModeLegacyWhenOffOrCodex() {
        let a = anthropic("A"), c = codex("C")
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: a, activeId: a.id, running: false, target: (a, "org-a")), .legacy)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: c, activeId: c.id, running: true, target: (a, "org-a")), .legacy)
    }

    // AC5: 3 selected anthropic profiles → only the current account's usage is fetched.
    func testMultiModeFetchesOnlyCurrentAccount() {
        let a = anthropic("A"), b = anthropic("B"), c = anthropic("C"), x = codex("X")
        let plan = MenuBarManager.multiFetchPlan(selected: [a, b, c, x], allProfiles: [a, b, c, x], running: true,
                                                 target: (b, "org-b"))
        XCTAssertEqual(usageFetched(plan), [b.id, x.id])
        XCTAssertEqual(plan.usageSkip, [a.id, c.id])
        XCTAssertEqual(plan.liveOrgIds, [b.id: "org-b"])
    }

    // Console billing is out of scope: a selected anthropic account the tracker keeps is still visited
    // for its console-billing fetch; only its claude.ai usage fetch is skipped.
    func testMultiModeKeepsConsoleBillingForUsageSkippedAccounts() {
        var a = anthropic("A")
        a.apiSessionKey = "sk-ant-console-a"
        a.apiOrganizationId = "console-org-a"
        let b = anthropic("B")
        let plan = MenuBarManager.multiFetchPlan(selected: [a, b], allProfiles: [a, b], running: true, target: (b, "org-b"))
        XCTAssertEqual(plan.profiles.map(\.id), [b.id, a.id])
        XCTAssertTrue(plan.consoleSkip.isEmpty)
        XCTAssertEqual(plan.usageSkip, [a.id])
        XCTAssertEqual(usageFetched(plan), [b.id])
    }

    func testMultiModeFetchesUnselectedCurrentAndSkipsWithoutTarget() {
        let a = anthropic("A"), b = anthropic("B"), c = anthropic("C")
        let unselected = MenuBarManager.multiFetchPlan(selected: [a, b], allProfiles: [a, b, c], running: true,
                                                       target: (c, "org-c"))
        XCTAssertEqual(usageFetched(unselected), [c.id])
        XCTAssertEqual(unselected.liveOrgIds, [c.id: "org-c"])
        // Fetched for its usage only: no console billing for a profile that is not selected (as today).
        XCTAssertEqual(unselected.consoleSkip, [c.id])
        let none = MenuBarManager.multiFetchPlan(selected: [a, b, c], allProfiles: [a, b, c], running: true, target: nil)
        XCTAssertTrue(usageFetched(none).isEmpty)
        XCTAssertTrue(none.liveOrgIds.isEmpty)
        // No usage fetch, but all three stay in the loop for console billing.
        XCTAssertEqual(none.profiles.map(\.id), [a.id, b.id, c.id])
        XCTAssertTrue(none.consoleSkip.isEmpty)
    }

    func testMultiModeUnchangedWhenTrackerOff() {
        let a = anthropic("A"), b = anthropic("B"), x = codex("X")
        let plan = MenuBarManager.multiFetchPlan(selected: [a, b, x], allProfiles: [a, b, x], running: false,
                                                 target: (a, "org-a"))
        XCTAssertEqual(plan.profiles.map(\.id), [a.id, b.id, x.id])
        XCTAssertTrue(plan.liveOrgIds.isEmpty)
        XCTAssertEqual(plan, MenuBarManager.MultiFetchPlan(profiles: [a, b, x]))  // nothing skipped
    }

    // AC9: shown account needs login → "Log in again".
    func testNeedsLoginShowsLogInAgain() {
        XCTAssertEqual(MenuBarManager.teamLoginMessage(for: anthropic("A", needsLogin: true)), "Log in again")
        XCTAssertNil(MenuBarManager.teamLoginMessage(for: anthropic("A")))
        XCTAssertNil(MenuBarManager.teamLoginMessage(for: codex("C")))
        XCTAssertNil(MenuBarManager.teamLoginMessage(for: nil))
    }

    // AC8: the onRefreshRejected handler hops to the main actor and reports the profile.
    func testRefreshRejectedHandlerReportsProfile() async throws {
        let id = UUID()
        var reported: [UUID] = []
        let handler = AnthropicUsageProvider.refreshRejectedHandler(profileId: id) { reported.append($0) }
        handler()
        for _ in 0..<50 where reported.isEmpty { try await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(reported, [id])
    }
}
