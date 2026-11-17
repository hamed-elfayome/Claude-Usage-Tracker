import XCTest
@testable import Claude_Usage

/// MT-7 tester: edge cases of the menu bar / notification wiring and the cross-module chain
/// AnthropicUsageProvider handler → TeamTracker → MenuBarManager plans → NotificationManager.
@MainActor
final class MenuBarTeamWiringEdgeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_799_980_000)
    private var store: FakeTeamStore!
    private var fetcher: FakeTeamFetcher!
    private var creds: FakeTeamCredentials!
    private var notifier: RecordingNotifier!
    private var defaults: UserDefaults!
    private var clock: ClockBox!
    private var tracker: TeamTracker!

    /// Keeps the profiles the tracker hands to `post`, so the real early-return rule can be applied.
    final class RecordingNotifier: TeamEventNotifying {
        var posts: [(event: TeamEvent, profiles: [Profile])] = []
        func post(_ event: TeamEvent, profiles: [Profile]) { posts.append((event, profiles)) }
        var wouldPost: [Bool] { posts.map { NotificationManager.shouldPostTeamEvent($0.event, profiles: $0.profiles) } }
    }

    override func setUp() async throws {
        store = FakeTeamStore()
        fetcher = FakeTeamFetcher()
        creds = FakeTeamCredentials()
        notifier = RecordingNotifier()
        defaults = UserDefaults(suiteName: "MenuBarTeamWiringEdgeTests-\(UUID().uuidString)")
        clock = ClockBox(t0)   // stays at t0 unless a test moves it
        try await Task.sleep(nanoseconds: 5_000_000)
    }

    // MARK: Helpers

    private func tracked(_ pid: UUID, _ org: String) -> TrackedOrg {
        TrackedOrg(orgId: org, name: "Team \(org.suffix(1).uppercased())", status: .member,
                   historyKey: TeamTrackingMigration.pairHistoryKey(profileId: pid, orgId: org), seat: nil,
                   lastUsage: nil, lastSampleAt: nil, firstSeenAt: t0.addingTimeInterval(-86_400 * 30),
                   lastSeenInListAt: t0.addingTimeInterval(-60), missingFromListCount: 0,
                   lastMembershipFailureAt: nil, pending: nil, baselineStartedAt: t0.addingTimeInterval(-86_400 * 30),
                   roundReading: nil)
    }

    private func member(_ name: String, org: String, notifications: Bool = true, id: UUID = UUID()) -> Profile {
        var p = Profile(id: id, name: name, claudeSessionKey: "k-\(name)", organizationId: org,
                        notificationSettings: NotificationSettings(enabled: notifications))
        var st = OrgTrackingState.empty
        st.orgs = [tracked(id, org)]
        st.legacyHistoryKeyAssigned = true
        p.orgTracking = st
        return p
    }

    private func build(_ profiles: [Profile], current: PairRef?, enabled: Bool = true) {
        store.profiles = profiles
        var g = TeamTrackingGlobalState.empty
        g.current = current
        TeamTrackingGlobalStore(defaults: defaults).save(g)
        let box = clock!
        tracker = TeamTracker(store: store, fetcher: fetcher, credentials: creds, history: FakeTeamHistory(),
                              notifier: notifier, globalStore: TeamTrackingGlobalStore(defaults: defaults),
                              clock: { box.now }, random: { 0 }, isEnabled: { enabled }, runsLoop: false)
        tracker.start()
    }

    private func fireHandler(_ id: UUID) async throws {
        let t = tracker!
        let before = notifier.posts.count
        let handler = AnthropicUsageProvider.refreshRejectedHandler(profileId: id) { t.reportRefreshRejected(profileId: $0) }
        handler()
        for _ in 0..<50 where notifier.posts.count == before { try await Task.sleep(nanoseconds: 2_000_000) }
    }

    /// Profiles whose claude.ai usage a multi-mode pass fetches (the loop visits the others for
    /// console billing only).
    private func usageFetched(_ plan: MenuBarManager.MultiFetchPlan) -> [UUID] {
        plan.profiles.map(\.id).filter { !plan.usageSkip.contains($0) }
    }

    private func needsLogin(_ id: UUID) -> Profile {
        var p = Profile(id: id, name: "N", provider: .codex)
        var st = OrgTrackingState.empty
        st.authState = .needsLogin(reason: "invalid_grant", since: t0)
        p.orgTracking = st
        return p
    }

    // MARK: Pure helpers (gaps in the builder's tests)

    func testMenuBarProfileRunningWithoutActiveProfile() {
        let b = member("B", org: "org-b")
        let cur = PairRef(profileId: b.id, orgId: "org-b")
        XCTAssertEqual(MenuBarManager.menuBarProfile(running: true, current: cur, profiles: [b], active: nil)?.id, b.id)
        XCTAssertNil(MenuBarManager.menuBarProfile(running: true, current: nil, profiles: [b], active: nil))
        XCTAssertNil(MenuBarManager.menuBarProfile(running: false, current: cur, profiles: [b], active: nil))
    }

    /// No active profile at all: the shown account is fetched per profile (fetchUsageForActiveProfile
    /// would read the active profile's credentials).
    func testShownFetchPlanWithoutActiveProfileFetchesByProfile() {
        let b = member("B", org: "org-b")
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: b, activeId: nil, running: true, target: (b, "org-b")),
                       .tracked(orgId: "org-b", byProfile: true))
    }

    /// The current account already selected is fetched once, first, from the live profile list
    /// (not the possibly stale tracker copy); selection order of the others is kept.
    func testMultiFetchPlanNoDuplicateAndUsesLiveProfileCopy() {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        let x = Profile(name: "X", provider: .codex), y = Profile(name: "Y", provider: .codex)
        var fresh = b
        fresh.name = "B-fresh"
        let plan = MenuBarManager.multiFetchPlan(selected: [x, a, b, y], allProfiles: [a, fresh, x, y],
                                                 running: true, target: (b, "org-b"))
        XCTAssertEqual(plan.profiles.map(\.id), [b.id, x.id, a.id, y.id])
        XCTAssertEqual(usageFetched(plan), [b.id, x.id, y.id])
        XCTAssertEqual(plan.profiles.first?.name, "B-fresh")
        XCTAssertEqual(plan.liveOrgIds, [b.id: "org-b"])
        XCTAssertTrue(plan.consoleSkip.isEmpty)
    }

    /// Codex profiles never change: still fetched when the tracker runs without a live target.
    func testMultiFetchPlanWithoutTargetKeepsCodexProfiles() {
        let a = member("A", org: "org-a")
        let x = Profile(name: "X", provider: .codex), y = Profile(name: "Y", provider: .codex)
        let plan = MenuBarManager.multiFetchPlan(selected: [a, x, y], allProfiles: [a, x, y], running: true, target: nil)
        XCTAssertEqual(usageFetched(plan), [x.id, y.id])
        XCTAssertEqual(plan.usageSkip, [a.id])
        XCTAssertTrue(plan.liveOrgIds.isEmpty)
    }

    /// The banner is anthropic-only even when a Codex profile carries a needsLogin state, and an
    /// anthropic profile without tracking state shows nothing.
    func testTeamLoginMessageProviderAndStateGuards() {
        XCTAssertNil(MenuBarManager.teamLoginMessage(for: needsLogin(UUID())))
        XCTAssertNil(MenuBarManager.teamLoginMessage(for: Profile(name: "Plain", claudeSessionKey: "k")))
        var ok = member("A", org: "org-a")
        ok.orgTracking?.authState = .ok
        XCTAssertNil(MenuBarManager.teamLoginMessage(for: ok))
    }

    /// The early-return rule follows `notifies` for every kind, and never posts without a profile.
    func testShouldPostFollowsNotifiesForEveryKind() {
        let p = UUID(), q = UUID()
        let ref = PairRef(profileId: p, orgId: "a")
        let table: [(TeamEvent.Kind, Bool)] = [
            (.nowOn(ref, from: nil, manual: false), true),
            (.nowOn(ref, from: nil, manual: true), false),
            (.adminMove(profileId: p, from: "a", to: "b"), true),
            (.groupMove(from: "a", to: "b", moves: [p: "b"], notMoved: [q], unchecked: []), true),
            (.teamRemoved(profileId: p, org: "a"), true),
            (.teamChanged(profileId: p, from: "a", to: "b"), true),
            (.teamAdded(profileId: p, org: "a"), false),
            (.teamRejoined(profileId: p, org: "a"), false),
            (.seatChange(ref, from: "x", to: "y", inferred: false), true),
            (.earlyReset(ref, window: .weekly, fromPercent: 80, toPercent: 2), true),
            (.loginLost(profileId: p, reason: "invalid_grant"), true),
            (.loginRestored(profileId: p), false),
            (.oldTeamDeleted(profileId: p, org: "a", manual: false), false),
        ]
        let on = Profile(id: p, name: "P", notificationSettings: NotificationSettings(enabled: true))
        for (kind, expected) in table {
            let e = TeamEvent(kind: kind, names: [:])
            XCTAssertEqual(NotificationManager.shouldPostTeamEvent(e, profiles: [on]), expected, "\(kind)")
            XCTAssertFalse(NotificationManager.shouldPostTeamEvent(e, profiles: []), "no profiles: \(kind)")
        }
    }

    func testTeamEventContentIdentifierIsPerEvent() {
        let kind = TeamEvent.Kind.loginLost(profileId: UUID(), reason: "invalid_grant")
        let e1 = TeamEvent(kind: kind, names: [:]), e2 = TeamEvent(kind: kind, names: [:])
        XCTAssertNotEqual(NotificationManager.teamEventContent(e1).identifier,
                          NotificationManager.teamEventContent(e2).identifier)
        XCTAssertEqual(NotificationManager.teamEventContent(e1).identifier,
                       NotificationManager.teamEventContent(e1).identifier)
    }

    // MARK: Integration (real TeamTracker with fakes)

    /// invalid_grant through the provider handler → tracker marks needsLogin → the single-mode plan
    /// skips the fetch, multi mode drops the account, the banner says "Log in again", and the
    /// loginLost event passes the notification rule.
    func testRefreshRejectedFlowsToSkipBannerAndNotification() async throws {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        creds.fingerprints[b.id] = "fp-b"
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: b, activeId: a.id, running: tracker.isRunning,
                                                     target: tracker.liveTarget()),
                       .tracked(orgId: "org-b", byProfile: true))

        try await fireHandler(b.id)

        let shown = MenuBarManager.menuBarProfile(running: tracker.isRunning, current: tracker.global.current,
                                                  profiles: store.profiles, active: a)
        XCTAssertEqual(shown?.id, b.id)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: shown!, activeId: a.id, running: tracker.isRunning,
                                                     target: tracker.liveTarget()), .skip)
        XCTAssertEqual(MenuBarManager.teamLoginMessage(for: shown), "Log in again")
        let multi = MenuBarManager.multiFetchPlan(selected: store.profiles, allProfiles: store.profiles,
                                                  running: tracker.isRunning, target: tracker.liveTarget())
        XCTAssertTrue(usageFetched(multi).isEmpty)
        XCTAssertEqual(multi.usageSkip, [a.id, b.id])
        guard case .loginLost = notifier.posts.last?.event.kind else { return XCTFail("expected loginLost post") }
        XCTAssertEqual(notifier.posts.last?.profiles.map(\.id), [b.id])
        XCTAssertEqual(notifier.wouldPost.last, true)
    }

    /// An involved account with notifications off is not posted, even when another (uninvolved)
    /// account has them on.
    func testLoginLostForDisabledAccountIsNotPostedDespiteOtherEnabledAccount() async throws {
        let a = member("A", org: "org-a", notifications: true), b = member("B", org: "org-b", notifications: false)
        creds.fingerprints[b.id] = "fp-b"
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        try await fireHandler(b.id)
        XCTAssertEqual(notifier.posts.count, 1)
        XCTAssertEqual(notifier.wouldPost, [false])
    }

    /// Tracker off: the handler is ignored, and every helper falls back to today's active-profile path.
    func testTrackerOffIgnoresHandlerAndKeepsLegacyPath() async throws {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"), enabled: false)
        XCTAssertFalse(tracker.isRunning)
        let t = tracker!
        AnthropicUsageProvider.refreshRejectedHandler(profileId: b.id) { t.reportRefreshRejected(profileId: $0) }()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(notifier.posts.isEmpty)
        XCTAssertEqual(store.profile(b.id).orgTracking?.authState, .ok)
        let shown = MenuBarManager.menuBarProfile(running: tracker.isRunning, current: tracker.global.current,
                                                  profiles: store.profiles, active: a)
        XCTAssertEqual(shown?.id, a.id)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: shown!, activeId: a.id, running: tracker.isRunning,
                                                     target: tracker.liveTarget()), .legacy)
        XCTAssertEqual(MenuBarManager.multiFetchPlan(selected: [a, b], allProfiles: [a, b], running: tracker.isRunning,
                                                     target: tracker.liveTarget()), MenuBarManager.MultiFetchPlan(profiles: [a, b]))
    }

    // MARK: Retest round 1 (verdict "Tests to add")

    /// Verdict line 1 with a real running tracker: a Codex active profile stays shown and on today's
    /// path, both with a live anthropic target and after that target is lost (no `.skip`, no banner),
    /// and the single-mode popover keeps the live console data for it (it is the active profile).
    func testCodexActiveStaysShownAndLegacyWithRealTrackerBeforeAndAfterTargetLoss() async throws {
        let b = member("B", org: "org-b")
        let c = Profile(name: "C", provider: .codex)
        creds.fingerprints[b.id] = "fp-b"
        build([b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        XCTAssertNotNil(tracker.liveTarget())
        let live = APIUsage(currentSpendCents: 7, resetsAt: t0, prepaidCreditsCents: 0, currency: "USD",
                            apiTokenCostCents: nil, apiCostByModel: nil, costBySource: nil, dailyCostCents: nil)

        for phase in ["live target", "target lost"] {
            if phase == "target lost" {
                try await fireHandler(b.id)
                XCTAssertNil(tracker.liveTarget(), phase)
            }
            let shown = try XCTUnwrap(MenuBarManager.menuBarProfile(running: tracker.isRunning, current: tracker.global.current,
                                                                    profiles: [c] + store.profiles, active: c), phase)
            XCTAssertEqual(shown.id, c.id, phase)
            XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: shown, activeId: c.id, running: tracker.isRunning,
                                                         target: tracker.liveTarget()), .legacy, phase)
            XCTAssertNil(MenuBarManager.teamLoginMessage(for: shown), phase)
            XCTAssertEqual(MenuBarManager.shownAPIUsage(shown: shown, activeId: c.id, live: live), live, phase)
        }
    }

    /// Verdict line 2, unselected current account: the selected anthropic accounts (one with console
    /// credentials) stay in the loop for console billing without a usage fetch; only the unselected
    /// current account is usage-fetched and it gets no console billing.
    func testMultiPlanUnselectedCurrentKeepsSelectedAccountsForConsoleBilling() {
        var a = member("A", org: "org-a")
        a.apiSessionKey = "sk-ant-console-a"
        a.apiOrganizationId = "console-org-a"
        let b = member("B", org: "org-b"), c = member("C", org: "org-c")
        let plan = MenuBarManager.multiFetchPlan(selected: [a, b], allProfiles: [a, b, c], running: true,
                                                 target: (c, "org-c"))
        XCTAssertEqual(plan.profiles.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(usageFetched(plan), [c.id])
        XCTAssertEqual(plan.usageSkip, [a.id, b.id])
        XCTAssertEqual(plan.consoleSkip, [c.id])
        let consoleVisited = plan.profiles.map(\.id).filter { !plan.consoleSkip.contains($0) }
        XCTAssertEqual(consoleVisited, [a.id, b.id])
    }

    // MARK: Fix round 2 (verdict: a Codex active profile starved the current pair)

    private func usage(_ session: Double) throws -> ClaudeUsage { try TeamFixtures.usage(session: session, weekly: 20) }

    /// One single-mode loop pass with the Codex profile `c` shown, `at` seconds after t0: the
    /// production helper picks the background target and the production poll fetches it (the fake
    /// fetch answers `result`). Returns the ids of the profiles fetched.
    private func codexPass(_ c: Profile, at: TimeInterval, _ result: Result<ClaudeUsage, Error>) async -> [UUID] {
        clock.now = t0.addingTimeInterval(at)
        XCTAssertEqual(MenuBarManager.shownFetchPlan(subject: c, activeId: c.id, running: tracker.isRunning,
                                                     target: tracker.liveTarget()), .legacy)
        guard let target = MenuBarManager.backgroundLiveTarget(subject: c, running: tracker.isRunning,
                                                               target: tracker.liveTarget()) else { return [] }
        var fetched: [UUID] = []
        await MenuBarManager.pollLiveTarget(target, tracker: tracker, store: store) { p in
            fetched.append(p.id)
            return try result.get()
        }
        return fetched
    }

    private func probeRound(at: TimeInterval) async {
        clock.now = t0.addingTimeInterval(at)
        await tracker.tick(now: clock.now)
    }

    /// Codex active, tracked A and B, current B. The loop polls B in the background (20% at t0+10,
    /// 50% at t0+300) while the probe rounds (t0+15, t0+315) see A go 10% → 12%: B keeps current.
    /// Without the background poll B has no live reading and A's 2-point rise takes over.
    func testCodexActiveLoopPollsCurrentPairSoItDefends() async throws {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        let c = Profile(name: "C", provider: .codex)
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"))
        store.activeProfileId = c.id
        await tracker.tick(now: t0)

        var fetched = await codexPass(c, at: 10, .success(try usage(20)))
        fetcher.setUsage("k-A", org: "org-a", try usage(10))
        await probeRound(at: 15)
        fetched += await codexPass(c, at: 300, .success(try usage(50)))
        fetcher.setUsage("k-A", org: "org-a", try usage(12))
        await probeRound(at: 315)

        XCTAssertEqual(fetcher.callCount(prefix: "usage:k-A|org-a"), 2)   // both probe rounds ran and saw A
        XCTAssertEqual(fetched, [b.id, b.id])                             // the current account, never Codex
        XCTAssertEqual(tracker.global.current, PairRef(profileId: b.id, orgId: "org-b"))
        XCTAssertEqual(store.profile(b.id).orgTracking?.org("org-b")?.lastSampleAt, t0.addingTimeInterval(300))
        XCTAssertEqual(store.savedUsage.filter { $0.0 == b.id }.map { $0.1.sessionPercentage }, [20, 50])
    }

    /// The background poll hands a failure to the tracker: a 429 backs the current account off, so
    /// the next pass has no live target and fetches nothing (the cached value stays).
    func testCodexActiveBackgroundPollFailureReachesTrackerAndNextPassSkips() async throws {
        let b = member("B", org: "org-b")
        let c = Profile(name: "C", provider: .codex)
        build([b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        let limited = AppError(code: .apiRateLimited, message: "test", technicalDetails: "Retry-After: 120")

        let first = await codexPass(c, at: 10, .failure(limited))
        XCTAssertEqual(first, [b.id])
        XCTAssertNil(tracker.liveTarget())
        let second = await codexPass(c, at: 40, .success(try usage(30)))
        XCTAssertEqual(second, [])
        XCTAssertTrue(store.savedUsage.isEmpty)
        XCTAssertNil(store.profile(b.id).orgTracking?.org("org-b")?.lastSampleAt)
    }

    /// A provider fall-back to the account's cached reading is no sample: nothing saved or recorded.
    func testCodexActiveBackgroundPollCachedReadingIsNoSample() async throws {
        var b = member("B", org: "org-b")
        let cached = try usage(40)
        b.claudeUsage = cached
        let c = Profile(name: "C", provider: .codex)
        build([b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)

        let fetched = await codexPass(c, at: 10, .success(cached))
        XCTAssertEqual(fetched, [b.id])
        XCTAssertTrue(store.savedUsage.isEmpty)
        XCTAssertNil(store.profile(b.id).orgTracking?.org("org-b")?.lastSampleAt)
        XCTAssertNotNil(tracker.liveTarget())
    }
}
