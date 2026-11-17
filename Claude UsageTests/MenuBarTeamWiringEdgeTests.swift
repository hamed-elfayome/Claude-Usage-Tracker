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

    // MARK: FU-2 (one tracker live fetch in flight at a time)

    private var gate = LivePollGate()
    private var gatedFetched: [UUID] = []
    private var parked: [CheckedContinuation<ClaudeUsage, Error>] = []

    /// One Codex-shown pass through the production gate helper: the fake fetch records the profile and
    /// suspends until the test resumes it. Nil when the pass was skipped (gate busy or no target).
    private func gatedCodexPass(_ c: Profile) -> Task<Void, Never>? {
        guard let target = MenuBarManager.backgroundLiveTarget(subject: c, running: tracker.isRunning,
                                                               target: tracker.liveTarget()) else { return nil }
        let t = tracker!, s = store!
        return MenuBarManager.startGatedLivePoll(gate: &gate, release: { [unowned self] in self.gate.end() }) {
            await MenuBarManager.pollLiveTarget(target, tracker: t, store: s) { p in
                self.gatedFetched.append(p.id)
                return try await withCheckedThrowingContinuation { self.parked.append($0) }
            }
        }
    }

    /// Lets started passes run until `count` fetches are suspended.
    private func waitParked(_ count: Int) async throws {
        for _ in 0..<200 where parked.count < count { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(parked.count, count)
    }

    private func resumeAll(_ result: Result<ClaudeUsage, Error>) {
        let all = parked
        parked = []
        all.forEach { $0.resume(with: result) }
    }

    private func gatedSetUp() async -> Profile {
        gate = LivePollGate()
        gatedFetched = []
        parked = []
        let b = member("B", org: "org-b")
        build([b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        return Profile(name: "C", provider: .codex)
    }

    func testLivePollGateBeginEnd() {
        var g = LivePollGate()
        XCTAssertFalse(g.inFlight)
        XCTAssertTrue(g.begin())
        XCTAssertTrue(g.inFlight)
        XCTAssertFalse(g.begin())
        g.end()
        XCTAssertFalse(g.inFlight)
        XCTAssertTrue(g.begin())
    }

    /// The timer pass and an onCurrentChanged pass back to back while the first fetch is suspended:
    /// one request only. Once it ends, the next pass fetches again.
    func testSecondLivePassWhileFirstInFlightDoesNotFetch() async throws {
        let c = await gatedSetUp()
        let first = gatedCodexPass(c)
        XCTAssertNotNil(first)
        XCTAssertNil(gatedCodexPass(c))          // started before the first Task even ran
        try await waitParked(1)
        XCTAssertNil(gatedCodexPass(c))          // the first fetch is suspended
        XCTAssertEqual(gatedFetched.count, 1)

        resumeAll(.success(try usage(20)))
        await first?.value
        XCTAssertFalse(gate.inFlight)
        XCTAssertEqual(store.savedUsage.map { $0.1.sessionPercentage }, [20])

        let third = gatedCodexPass(c)
        XCTAssertNotNil(third)
        try await waitParked(1)
        XCTAssertEqual(gatedFetched.count, 2)
        resumeAll(.success(try usage(30)))
        await third?.value
    }

    /// A fetch that throws still releases the gate: the next pass fetches.
    func testLivePassFailureReleasesGate() async throws {
        let c = await gatedSetUp()
        let first = gatedCodexPass(c)
        try await waitParked(1)
        resumeAll(.failure(URLError(.timedOut)))
        await first?.value
        XCTAssertFalse(gate.inFlight)
        XCTAssertNotNil(tracker.liveTarget())

        let second = gatedCodexPass(c)
        XCTAssertNotNil(second)
        try await waitParked(1)
        XCTAssertEqual(gatedFetched.count, 2)
        resumeAll(.success(try usage(30)))
        await second?.value
    }

    /// Toggle off while a fetch is in flight (the menu bar resets the gate, as in
    /// `teamTrackingSettingChanged`), then on: the next pass fetches without waiting for the old one.
    func testToggleOffWhileInFlightThenOnFetchesAgain() async throws {
        let c = await gatedSetUp()
        let first = gatedCodexPass(c)
        try await waitParked(1)

        tracker.stop()
        gate = LivePollGate()
        XCTAssertNil(MenuBarManager.backgroundLiveTarget(subject: c, running: tracker.isRunning,
                                                         target: tracker.liveTarget()))
        tracker.start()

        let second = gatedCodexPass(c)
        XCTAssertNotNil(second)
        try await waitParked(2)
        XCTAssertEqual(gatedFetched.count, 2)
        resumeAll(.success(try usage(30)))
        await first?.value
        await second?.value
    }

    // MARK: FU-2 tester (gate edge cases the builder's tests leave open)

    /// A busy pass must neither run its poll nor call `release`: releasing there would free the gate
    /// the in-flight fetch still holds and let the next pass send a duplicate request.
    func testGatedLivePollBusyRunsNothingAndKeepsHolderGate() async throws {
        var g = LivePollGate()
        XCTAssertTrue(g.begin())
        var polls = 0, releases = 0
        let t = MenuBarManager.startGatedLivePoll(gate: &g, release: { releases += 1 }) { polls += 1 }
        XCTAssertNil(t)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(polls, 0)
        XCTAssertEqual(releases, 0)
        XCTAssertTrue(g.inFlight)
    }

    /// The gate stays held for the whole suspended fetch and is released once, after the poll returns.
    func testGatedLivePollReleasesOnceAfterPollReturns() async throws {
        var g = LivePollGate()
        var releases = 0
        var waiting: CheckedContinuation<Void, Never>?
        let t = MenuBarManager.startGatedLivePoll(gate: &g, release: { releases += 1 }) {
            await withCheckedContinuation { waiting = $0 }
        }
        XCTAssertNotNil(t)
        for _ in 0..<200 where waiting == nil { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertNotNil(waiting)
        XCTAssertTrue(g.inFlight)
        XCTAssertEqual(releases, 0)
        waiting?.resume()
        await t?.value
        XCTAssertEqual(releases, 1)
    }

    /// A pass whose Task is cancelled mid-fetch releases the gate: the next pass fetches.
    func testCancelledLivePassReleasesGate() async throws {
        let c = await gatedSetUp()
        guard let target = MenuBarManager.backgroundLiveTarget(subject: c, running: tracker.isRunning,
                                                               target: tracker.liveTarget()) else {
            return XCTFail("no live target")
        }
        let t = tracker!, s = store!
        let first = MenuBarManager.startGatedLivePoll(gate: &gate, release: { [unowned self] in self.gate.end() }) {
            await MenuBarManager.pollLiveTarget(target, tracker: t, store: s) { p in
                self.gatedFetched.append(p.id)
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return try TeamFixtures.usage(session: 99, weekly: 20)
            }
        }
        for _ in 0..<200 where gatedFetched.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(gatedFetched.count, 1)
        XCTAssertTrue(gate.inFlight)
        first?.cancel()
        await first?.value
        XCTAssertFalse(gate.inFlight)
        XCTAssertTrue(store.savedUsage.isEmpty)

        let second = gatedCodexPass(c)
        XCTAssertNotNil(second)
        try await waitParked(1)
        XCTAssertEqual(gatedFetched.count, 2)
        resumeAll(.success(try usage(30)))
        await second?.value
    }

    /// The motivating case: a 429 backs the current account off. The gate is still released, so once
    /// the backoff ends the next pass fetches (no stuck gate on top of the backoff).
    func testRateLimitedLivePassReleasesGateAndFetchesAfterBackoff() async throws {
        let c = await gatedSetUp()
        clock.now = t0.addingTimeInterval(10)
        let first = gatedCodexPass(c)
        try await waitParked(1)
        resumeAll(.failure(AppError(code: .apiRateLimited, message: "test", technicalDetails: "Retry-After: 120")))
        await first?.value
        XCTAssertFalse(gate.inFlight)
        XCTAssertNil(tracker.liveTarget())
        XCTAssertNil(gatedCodexPass(c))           // backed off: no target, gate untouched
        XCTAssertFalse(gate.inFlight)

        clock.now = t0.addingTimeInterval(10 + 121)
        let second = gatedCodexPass(c)
        XCTAssertNotNil(second)
        try await waitParked(1)
        XCTAssertEqual(gatedFetched.count, 2)
        resumeAll(.success(try usage(30)))
        await second?.value
        XCTAssertFalse(gate.inFlight)
    }

    /// Tracker off, or an anthropic subject (its fetch goes through `shownFetchPlan`): the background
    /// site has no target, so it never takes the gate and never fetches.
    func testBackgroundSiteNeverTakesGateWithoutTarget() async throws {
        let c = await gatedSetUp()
        let anthropic = store.profiles[0]
        XCTAssertNil(MenuBarManager.backgroundLiveTarget(subject: anthropic, running: tracker.isRunning,
                                                         target: tracker.liveTarget()))
        tracker.stop()
        XCTAssertNil(gatedCodexPass(c))
        XCTAssertFalse(gate.inFlight)
        XCTAssertTrue(gatedFetched.isEmpty)
        // Multi mode takes the gate only for a non-empty liveOrgIds: empty with the tracker off.
        let a = member("A", org: "org-a")
        XCTAssertTrue(MenuBarManager.multiFetchPlan(selected: [a, c], allProfiles: [a, c], running: false,
                                                    target: (a, "org-a")).liveOrgIds.isEmpty)
    }

    /// The multi-mode site releases the gate in the loop's usage block of the account in `liveOrgIds`.
    /// That is only reached when that account is in `profiles` and not in `usageSkip`, and it must be
    /// the only key so the gate is released once. Pinned for every selection shape.
    func testMultiFetchPlanLiveAccountIsReleasable() {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b"), d = member("D", org: "org-d")
        let x = Profile(name: "X", provider: .codex)
        let selections: [[Profile]] = [[], [b], [a, b], [a, d, b], [x, a], [b, x, a, d]]
        for selected in selections {
            let plan = MenuBarManager.multiFetchPlan(selected: selected, allProfiles: [a, b, d, x],
                                                     running: true, target: (b, "org-b"))
            let names = selected.map(\.name)
            XCTAssertEqual(plan.liveOrgIds, [b.id: "org-b"], "\(names)")
            XCTAssertEqual(plan.profiles.first?.id, b.id, "\(names)")
            XCTAssertEqual(plan.profiles.filter { $0.id == b.id }.count, 1, "\(names)")
            XCTAssertFalse(plan.usageSkip.contains(b.id), "\(names)")
        }
    }

    // MARK: FU-2 fix round 1 (verdict: the gate dropped the new current pair's pass)

    private var reruns: [Task<Void, Never>?] = []
    private var changePasses: [Task<Void, Never>?] = []
    private var startedPairs: [PairRef] = []
    private var fetchesInFlight = 0
    private var maxFetchesInFlight = 0

    /// One Codex-shown pass as the production background site runs it: the gate, the poll, and on release
    /// `endGatedLivePoll`, whose re-run starts this pass again (production: `refreshUsage()`). The fake
    /// fetch suspends until the test resumes it and counts the fetches in flight.
    private func rerunningPass(_ c: Profile) -> Task<Void, Never>? {
        guard let target = MenuBarManager.backgroundLiveTarget(subject: c, running: tracker.isRunning,
                                                               target: tracker.liveTarget()) else { return nil }
        let t = tracker!, s = store!
        let fetched = PairRef(profileId: target.profile.id, orgId: target.orgId)
        return MenuBarManager.startGatedLivePoll(gate: &gate, release: { [unowned self] in
            MenuBarManager.endGatedLivePoll(fetched: fetched, tracker: t, release: { self.gate.end() }) {
                let next = self.rerunningPass(c)
                self.reruns.append(next)
            }
        }) {
            self.startedPairs.append(fetched)
            await MenuBarManager.pollLiveTarget(target, tracker: t, store: s) { p in
                self.gatedFetched.append(p.id)
                self.fetchesInFlight += 1
                self.maxFetchesInFlight = max(self.maxFetchesInFlight, self.fetchesInFlight)
                defer { self.fetchesInFlight -= 1 }
                return try await withCheckedThrowingContinuation { self.parked.append($0) }
            }
        }
    }

    /// Production `onCurrentChanged` calls `refreshUsage()`, which starts this same pass.
    private func passOnCurrentChanged(_ c: Profile) {
        tracker.onCurrentChanged = { [unowned self] _ in
            let pass = self.rerunningPass(c)
            self.changePasses.append(pass)
        }
    }

    /// The user makes A current while B's fetch is in flight: A's pass finds the gate busy and is dropped.
    /// B's release re-runs it, so A is fetched once with no new timer pass, and never alongside B.
    func testCurrentMovedWhileFetchInFlightFetchesNewPairOnceAfterRelease() async throws {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        let c = Profile(name: "C", provider: .codex)
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        passOnCurrentChanged(c)

        let first = rerunningPass(c)
        XCTAssertNotNil(first)
        try await waitParked(1)
        tracker.makeCurrent(PairRef(profileId: a.id, orgId: "org-a"))
        XCTAssertEqual(changePasses.map { $0 == nil }, [true])   // dropped: B still holds the gate
        XCTAssertEqual(gatedFetched, [b.id])

        resumeAll(.success(try usage(20)))
        await first?.value
        XCTAssertEqual(reruns.count, 1)
        try await waitParked(1)
        XCTAssertEqual(gatedFetched, [b.id, a.id])
        XCTAssertEqual(startedPairs, [PairRef(profileId: b.id, orgId: "org-b"), PairRef(profileId: a.id, orgId: "org-a")])
        XCTAssertEqual(maxFetchesInFlight, 1)

        resumeAll(.success(try usage(30)))
        let rerun = try XCTUnwrap(reruns.first ?? nil)
        await rerun.value
        XCTAssertEqual(reruns.count, 1)                           // A's own release: same pair, no re-run
        XCTAssertEqual(gatedFetched, [b.id, a.id])
        XCTAssertEqual(store.savedUsage.map { $0.1.sessionPercentage }, [20, 30])   // B's reading still saved
        XCTAssertFalse(gate.inFlight)
    }

    /// A live sample that moves the current pair: B is OAuth-only and its token now names org-a, so
    /// `ingestLive` follows it and fires `onCurrentChanged` while B's pass still holds the gate.
    /// After the release the new pair is fetched once.
    func testLiveSampleSwitchFetchesNewPairOnceAfterRelease() async throws {
        let id = UUID()
        var b = Profile(id: id, name: "B", claudeSessionKey: nil, organizationId: nil,
                        cliCredentialsJSON: TeamFixtures.credentialsOrgB)
        var st = OrgTrackingState.empty
        st.orgs = [tracked(id, "org-b")]
        st.legacyHistoryKeyAssigned = true
        st.credentialOrgId = "org-b"
        b.orgTracking = st
        let c = Profile(name: "C", provider: .codex)
        build([b], current: PairRef(profileId: id, orgId: "org-b"))
        await tracker.tick(now: t0)
        passOnCurrentChanged(c)

        let first = rerunningPass(c)
        XCTAssertNotNil(first)
        try await waitParked(1)
        store.profiles[0].cliCredentialsJSON = TeamFixtures.credentialsOrgA   // logged in to team A meanwhile
        resumeAll(.success(try usage(20)))
        await first?.value

        XCTAssertEqual(tracker.global.current, PairRef(profileId: id, orgId: "org-a"))
        XCTAssertEqual(changePasses.map { $0 == nil }, [true])   // fired inside ingestLive: gate still held
        XCTAssertEqual(reruns.count, 1)
        try await waitParked(1)
        XCTAssertEqual(startedPairs, [PairRef(profileId: id, orgId: "org-b"), PairRef(profileId: id, orgId: "org-a")])
        XCTAssertEqual(maxFetchesInFlight, 1)

        resumeAll(.success(try usage(30)))
        let rerun = try XCTUnwrap(reruns.first ?? nil)
        await rerun.value
        XCTAssertEqual(reruns.count, 1)
        XCTAssertEqual(gatedFetched, [id, id])
        XCTAssertEqual(store.profile(id).orgTracking?.org("org-a")?.lastSampleAt, t0)
        XCTAssertFalse(gate.inFlight)
    }

    /// A second pass for the pair in flight stays dropped, and the release does not re-run it: the fix
    /// must not turn the dropped duplicate into a delayed one.
    func testSamePairPassWhileInFlightStaysDroppedWithoutRerun() async throws {
        let c = await gatedSetUp()
        let b = store.profiles[0]
        let first = rerunningPass(c)
        XCTAssertNotNil(first)
        try await waitParked(1)
        XCTAssertNil(rerunningPass(c))                            // the timer pass while B is in flight

        resumeAll(.success(try usage(20)))
        await first?.value
        XCTAssertTrue(reruns.isEmpty)
        XCTAssertFalse(gate.inFlight)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(gatedFetched, [b.id])
        XCTAssertTrue(parked.isEmpty)
    }

    /// Single-mode stale-write guard with the real tracker: B's tracker-owned reading reaches the menu bar
    /// while B is shown, not once A is made current mid-fetch, nor once tracking stops and the active
    /// profile A is shown. Today's path (tracker off when the pass started) is never filtered.
    func testTrackedReadingReachesMenuBarOnlyWhileItsAccountIsShown() async throws {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        func shows(_ fetched: Profile) -> Bool {
            let shown = MenuBarManager.menuBarProfile(running: tracker.isRunning, current: tracker.global.current,
                                                      profiles: store.profiles, active: a)
            return MenuBarManager.showsFetchedReading(trackerOwned: true, fetchedId: fetched.id, shownId: shown?.id)
        }
        XCTAssertTrue(shows(b))
        XCTAssertFalse(shows(a))
        tracker.makeCurrent(PairRef(profileId: a.id, orgId: "org-a"))
        XCTAssertFalse(shows(b))
        XCTAssertTrue(shows(a))
        tracker.makeCurrent(PairRef(profileId: b.id, orgId: "org-b"))
        XCTAssertTrue(shows(b))
        tracker.stop()                                            // toggle off mid-fetch: active A is shown
        XCTAssertFalse(shows(b))
        XCTAssertFalse(MenuBarManager.showsFetchedReading(trackerOwned: true, fetchedId: b.id, shownId: nil))
        XCTAssertTrue(MenuBarManager.showsFetchedReading(trackerOwned: false, fetchedId: b.id, shownId: a.id))
    }

    // MARK: FU-2 tester, retest round 1 (re-run edge cases the fix round's tests leave open)

    /// B parked, then A made current through the production onCurrentChanged hop (dropped).
    private func movedWhileInFlight() async throws -> (a: Profile, b: Profile, first: Task<Void, Never>?) {
        gate = LivePollGate()
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        let c = Profile(name: "C", provider: .codex)
        build([a, b], current: PairRef(profileId: b.id, orgId: "org-b"))
        await tracker.tick(now: t0)
        passOnCurrentChanged(c)
        let first = rerunningPass(c)
        XCTAssertNotNil(first)
        try await waitParked(1)
        tracker.makeCurrent(PairRef(profileId: a.id, orgId: "org-a"))
        XCTAssertEqual(changePasses.map { $0 == nil }, [true])
        return (a, b, first)
    }

    /// The re-run must not depend on B's fetch succeeding: a timeout, a cancellation and a 429 on B all
    /// end in the release path, and A (another account, not backed off) is fetched once after it.
    func testMovedWhileInFlightRerunsNewPairAfterFailedFetch() async throws {
        let failures: [(String, Error)] = [
            ("timeout", URLError(.timedOut)),
            ("cancelled", CancellationError()),
            ("429", AppError(code: .apiRateLimited, message: "test", technicalDetails: "Retry-After: 120")),
        ]
        for (name, error) in failures {
            reruns = []; changePasses = []; startedPairs = []; gatedFetched = []; parked = []
            fetchesInFlight = 0; maxFetchesInFlight = 0
            let saved = store.savedUsage.count
            let (a, b, first) = try await movedWhileInFlight()
            resumeAll(.failure(error))
            await first?.value
            XCTAssertEqual(reruns.count, 1, name)
            XCTAssertNotNil(reruns.first ?? nil, "\(name): the re-run found the gate busy")
            try await waitParked(1)
            XCTAssertEqual(gatedFetched, [b.id, a.id], name)
            XCTAssertEqual(maxFetchesInFlight, 1, name)
            XCTAssertEqual(store.savedUsage.count, saved, name)          // B's failure saved nothing
            resumeAll(.success(try usage(30)))
            await (reruns.first ?? nil)?.value
            XCTAssertEqual(reruns.count, 1, name)
            XCTAssertFalse(gate.inFlight, name)
        }
    }

    /// The current pair moves away and back while B is in flight: at the release the target is B again,
    /// the pair just fetched, so nothing re-runs (the fix must not add a duplicate request for B).
    func testMovedAwayAndBackWhileInFlightDoesNotRerun() async throws {
        let (_, b, first) = try await movedWhileInFlight()
        tracker.makeCurrent(PairRef(profileId: b.id, orgId: "org-b"))
        XCTAssertEqual(changePasses.map { $0 == nil }, [true, true])   // both passes dropped
        resumeAll(.success(try usage(20)))
        await first?.value
        XCTAssertTrue(reruns.isEmpty)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(gatedFetched, [b.id])
        XCTAssertTrue(parked.isEmpty)
        XCTAssertFalse(gate.inFlight)
    }

    /// Tracking turned off while B is in flight (after A was made current): the release still frees the
    /// gate, and with no live target it starts nothing.
    func testTrackerStoppedWhileInFlightReleasesWithoutRerun() async throws {
        let (_, b, first) = try await movedWhileInFlight()
        tracker.stop()
        resumeAll(.success(try usage(20)))
        await first?.value
        XCTAssertTrue(reruns.isEmpty)
        XCTAssertFalse(gate.inFlight)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(gatedFetched, [b.id])
        XCTAssertTrue(parked.isEmpty)
    }

    /// A chain: while A's re-run is in flight the current moves back to B. A's release re-runs B once,
    /// and B's release (same pair) ends the chain. Never two fetches in flight.
    func testRerunItselfRerunsWhenCurrentMovesAgain() async throws {
        let (a, b, first) = try await movedWhileInFlight()
        resumeAll(.success(try usage(20)))
        await first?.value
        try await waitParked(1)                                    // A's re-run fetch
        tracker.makeCurrent(PairRef(profileId: b.id, orgId: "org-b"))
        XCTAssertEqual(changePasses.map { $0 == nil }, [true, true])   // dropped: A holds the gate
        resumeAll(.success(try usage(30)))
        await (reruns.first ?? nil)?.value
        XCTAssertEqual(reruns.count, 2)
        XCTAssertNotNil(reruns.last ?? nil)
        try await waitParked(1)
        XCTAssertEqual(gatedFetched, [b.id, a.id, b.id])
        resumeAll(.success(try usage(40)))
        await (reruns.last ?? nil)?.value
        XCTAssertEqual(reruns.count, 2)
        XCTAssertEqual(maxFetchesInFlight, 1)
        XCTAssertFalse(gate.inFlight)
    }

    /// `endGatedLivePoll` frees the gate before the re-run (the re-run must be able to take it), and
    /// calls `release` exactly once whether or not it re-runs.
    func testEndGatedLivePollReleasesFirstAndOnce() async throws {
        let a = member("A", org: "org-a"), b = member("B", org: "org-b")
        build([a, b], current: PairRef(profileId: a.id, orgId: "org-a"))
        await tracker.tick(now: t0)
        var calls: [String] = []
        MenuBarManager.endGatedLivePoll(fetched: PairRef(profileId: b.id, orgId: "org-b"), tracker: tracker,
                                        release: { calls.append("release") }, rerun: { calls.append("rerun") })
        XCTAssertEqual(calls, ["release", "rerun"])
        calls = []
        MenuBarManager.endGatedLivePoll(fetched: PairRef(profileId: a.id, orgId: "org-a"), tracker: tracker,
                                        release: { calls.append("release") }, rerun: { calls.append("rerun") })
        XCTAssertEqual(calls, ["release"])
    }
}
