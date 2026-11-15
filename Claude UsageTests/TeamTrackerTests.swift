import XCTest
@testable import Claude_Usage

@MainActor
final class TeamTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_799_980_000)
    private var store: FakeTeamStore!
    private var fetcher: FakeTeamFetcher!
    private var creds: FakeTeamCredentials!
    private var history: FakeTeamHistory!
    private var notifier: FakeTeamNotifier!
    private var clock: ClockBox!
    private var defaults: UserDefaults!
    private var tracker: TeamTracker!

    override func setUp() async throws {
        store = FakeTeamStore()
        fetcher = FakeTeamFetcher()
        creds = FakeTeamCredentials()
        history = FakeTeamHistory()
        notifier = FakeTeamNotifier()
        clock = ClockBox(t0)
        defaults = UserDefaults(suiteName: "TeamTrackerTests-\(UUID().uuidString)")
        try await Task.sleep(nanoseconds: 5_000_000)
    }

    // MARK: Helpers

    private func tracked(_ pid: UUID, _ org: String, status: PairStatus = .member, lastSeen: Date? = nil,
                         missing: Int = 0) -> TrackedOrg {
        TrackedOrg(orgId: org, name: "Team \(org.suffix(1).uppercased())", status: status,
                   historyKey: TeamTrackingMigration.pairHistoryKey(profileId: pid, orgId: org), seat: nil,
                   lastUsage: nil, lastSampleAt: nil, firstSeenAt: t0.addingTimeInterval(-86_400 * 30),
                   lastSeenInListAt: lastSeen ?? t0.addingTimeInterval(-60), missingFromListCount: missing,
                   lastMembershipFailureAt: nil, pending: nil, baselineStartedAt: t0.addingTimeInterval(-86_400 * 30),
                   roundReading: nil)
    }

    private func profile(_ name: String, key: String?, orgs: [TrackedOrg]? = nil, ids: [String] = [],
                         followed: String? = nil, id: UUID = UUID(), cli: String? = nil) -> Profile {
        let list = orgs ?? ids.map { tracked(id, $0) }
        var p = Profile(id: id, name: name, claudeSessionKey: key,
                        organizationId: followed ?? (key == nil ? nil : list.first?.orgId), cliCredentialsJSON: cli)
        var st = OrgTrackingState.empty
        st.orgs = list
        st.legacyHistoryKeyAssigned = true
        p.orgTracking = st
        return p
    }

    private func build(_ profiles: [Profile], current: PairRef? = nil, enabled: Bool = true) {
        store.profiles = profiles
        var g = TeamTrackingGlobalState.empty
        g.current = current
        TeamTrackingGlobalStore(defaults: defaults).save(g)
        let box = clock!
        tracker = TeamTracker(store: store, fetcher: fetcher, credentials: creds, history: history, notifier: notifier,
                              globalStore: TeamTrackingGlobalStore(defaults: defaults), clock: { box.now },
                              random: { 0 }, isEnabled: { enabled }, runsLoop: false)
        tracker.start()
    }

    private func boot() async { await tracker.tick(now: t0) }

    private func round(_ n: Int) async {
        clock.now = t0.addingTimeInterval(15 + 300 * Double(n))
        await tracker.tick(now: clock.now)
    }

    private func u(_ session: Double, weekly: Double = 20, reset: Date? = nil) throws -> ClaudeUsage {
        try TeamFixtures.usage(session: session, weekly: weekly, sessionReset: reset ?? TeamFixtures.defaultSessionReset)
    }

    private func ref(_ p: Profile, _ org: String) -> PairRef { PairRef(profileId: p.id, orgId: org) }
    private func err(_ code: ErrorCode, _ details: String? = nil) -> AppError {
        AppError(code: code, message: "test", technicalDetails: details)
    }
    private var events: [TeamEvent] { tracker.global.events }
    private func state(_ p: Profile) -> OrgTrackingState { store.profile(p.id).orgTracking! }

    // MARK: 1 detected switch

    func testDetectedSwitchNotifiesOnceThenFlapGuard() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-a", "org-b"], followed: "org-a")
        let p3 = profile("P3", key: "k3", ids: ["org-c"])
        build([p1, p2, p3], current: ref(p1, "org-a"))
        fetcher.setUsage("k2", org: "org-b", try u(10))
        fetcher.setUsage("k3", org: "org-c", try u(5))
        await boot()
        await round(0)
        fetcher.setUsage("k2", org: "org-b", try u(14))
        await round(1)
        XCTAssertEqual(tracker.global.current, ref(p2, "org-b"))
        XCTAssertEqual(store.profile(p2.id).organizationId, "org-b")
        XCTAssertEqual(notifier.posted.count, 1)
        guard case .nowOn(_, _, false) = notifier.posted[0].kind else { return XCTFail("expected nowOn") }

        fetcher.setUsage("k3", org: "org-c", try u(9))
        await round(2)   // 300 s after the first switch
        XCTAssertEqual(tracker.global.current, ref(p3, "org-c"))
        XCTAssertEqual(events.filter { if case .nowOn = $0.kind { return true } else { return false } }.count, 2)
        XCTAssertEqual(notifier.posted.count, 1)
    }

    // MARK: 2 manual pick

    func testManualPickHoldsOneRound() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-b"])
        let p3 = profile("P3", key: "k3", ids: ["org-c"])
        build([p1, p2, p3], current: ref(p2, "org-b"))
        fetcher.setUsage("k1", org: "org-a", try u(5))
        await boot()
        await round(0)
        clock.now = t0.addingTimeInterval(20)
        tracker.makeCurrent(ref(p3, "org-c"))
        XCTAssertEqual(tracker.global.current, ref(p3, "org-c"))
        XCTAssertTrue(notifier.posted.isEmpty)
        fetcher.setUsage("k1", org: "org-a", try u(9))
        await round(1)
        XCTAssertEqual(tracker.global.current, ref(p3, "org-c"))
        fetcher.setUsage("k1", org: "org-a", try u(13))
        await round(2)
        XCTAssertEqual(tracker.global.current, ref(p1, "org-a"))
        XCTAssertEqual(notifier.posted.count, 1)
    }

    func testSessionKeyAddedAfterFirstTickGetsOrgListAndConfirmsMove() async throws {
        let id = UUID()
        let p1 = profile("P1", key: nil, orgs: [tracked(id, "org-a")], id: id, cli: TeamFixtures.credentialsOrgB)
        let p2 = profile("P2", key: "k2", ids: ["org-z"])
        build([p1, p2], current: ref(p2, "org-z"))
        await boot()
        store.profiles[0].claudeSessionKey = "k1"
        fetcher.setUsage("k1", org: "org-a", error: err(.apiNotFound))
        fetcher.setList("k1", json: TeamFixtures.orgsB)
        await round(0)
        XCTAssertEqual(state(p1).org("org-a")?.status, .old)
        XCTAssertEqual(store.profile(id).organizationId, "org-b")
        guard case .adminMove(_, "org-a", "org-b") = notifier.posted.last?.kind else { return XCTFail("expected adminMove") }
    }

    // MARK: 3 admin move

    func testAdminMoveFromProbe() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-z"])
        build([p1, p2], current: ref(p2, "org-z"))
        await boot()
        fetcher.setUsage("k1", org: "org-a", error: err(.apiNotFound))
        fetcher.setList("k1", json: TeamFixtures.orgsB)
        await round(0)
        XCTAssertEqual(state(p1).org("org-a")?.status, .old)
        XCTAssertEqual(store.profile(p1.id).organizationId, "org-b")
        XCTAssertEqual(notifier.posted.count, 1)
        guard case .adminMove(_, "org-a", "org-b") = notifier.posted[0].kind else { return XCTFail("expected adminMove") }
        await round(1)
        XCTAssertEqual(fetcher.callCount(prefix: "usage:k1|org-a"), 1)
    }

    func testAdminMoveCurrentFollowsViaLiveFailure() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        build([p1], current: ref(p1, "org-a"))
        await boot()
        fetcher.setList("k1", json: TeamFixtures.orgsB)
        var changes = 0
        tracker.onCurrentChanged = { _ in changes += 1 }
        tracker.ingestLive(profileId: p1.id, orgId: "org-a", result: .failure(err(.apiNotFound)), isCachedReading: false)
        await tracker.backgroundTask?.value
        XCTAssertEqual(tracker.global.current, ref(p1, "org-b"))
        XCTAssertEqual(store.profile(p1.id).organizationId, "org-b")
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(events.filter { if case .nowOn = $0.kind { return true } else { return false } }.count, 0)
    }

    // MARK: 4 and 5 group move

    private func fiveAccounts(_ orgFor: (Int, UUID) -> [TrackedOrg]? = { _, _ in nil }) -> [Profile] {
        (1...5).map { i in
            let id = UUID()
            return profile("P\(i)", key: "k\(i)", orgs: orgFor(i, id) ?? [tracked(id, "org-a")], id: id)
        }
    }

    func testGroupMoveOneNotificationAndNotMoved() async throws {
        let ps = fiveAccounts { i, id in i == 1 ? [self.tracked(id, "org-a", missing: 1)] : nil }
        var p1 = ps[0]
        p1.orgTracking?.lastOrgListAt = t0.addingTimeInterval(-1000)
        store.profiles = ps
        build([p1] + ps.dropFirst())
        for k in ["k1", "k2", "k3", "k4"] { fetcher.setList(k, json: TeamFixtures.orgsB) }
        fetcher.setList("k5", json: TeamFixtures.orgsAB)
        await boot()
        let group = events.compactMap { e -> (TeamEvent, [UUID: String?], [UUID])? in
            if case let .groupMove(_, to, moves, notMoved, _) = e.kind, to == "org-b" { return (e, moves, notMoved) }
            return nil
        }
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(Set(group[0].1.keys), Set(ps.prefix(4).map(\.id)))
        XCTAssertEqual(group[0].2, [ps[4].id])
        XCTAssertEqual(notifier.posted.count, 1)
        XCTAssertEqual(notifier.posted[0].id, group[0].0.id)
        XCTAssertFalse(events.contains { if case .adminMove = $0.kind { return true } else { return false } })
    }

    func testGroupMovePeerBackingOffIsUnchecked() async throws {
        let ps = fiveAccounts { i, id in i == 1 ? [self.tracked(id, "org-a", missing: 1)] : nil }
        let three = Array(ps.prefix(3))
        build(three)
        fetcher.setUsage("k2", org: "org-a", error: err(.apiRateLimited, "Retry-After: 3000"))
        fetcher.setList("k1", json: TeamFixtures.orgsB)
        fetcher.setList("k3", json: TeamFixtures.orgsB)
        await boot()
        await round(0)
        clock.now = t0.addingTimeInterval(915)
        await tracker.tick(now: clock.now)
        guard let unchecked = events.compactMap({ e -> [UUID]? in
            if case let .groupMove(_, _, _, _, unchecked) = e.kind { return unchecked } else { return nil }
        }).first else { return XCTFail("no group move") }
        XCTAssertEqual(unchecked, [three[1].id])
    }

    // MARK: 6 seat change

    func testSeatChangeNotifiesOnce() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        build([p1], current: ref(p1, "org-a"))
        fetcher.setList("k1", json: TeamFixtures.orgsAStandard)
        await boot()
        XCTAssertTrue(notifier.posted.isEmpty)
        fetcher.setList("k1", json: TeamFixtures.orgsAPremium)
        clock.now = t0.addingTimeInterval(900)
        await tracker.tick(now: clock.now)
        XCTAssertEqual(notifier.posted.count, 1)
        guard case .seatChange(_, _, _, false) = notifier.posted[0].kind else { return XCTFail("expected seatChange") }
    }

    // MARK: 7 early reset

    func testEarlyResetViaIngestLiveRecordsHistory() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        build([p1], current: ref(p1, "org-a"))
        let reset = t0.addingTimeInterval(3 * 3600)
        for (i, s) in [60.0, 5, 6].enumerated() {
            clock.now = t0.addingTimeInterval(30 * Double(i))
            tracker.ingestLive(profileId: p1.id, orgId: "org-a", result: .success(try u(s, reset: reset)), isCachedReading: false)
        }
        XCTAssertEqual(notifier.posted.count, 1)
        guard case .earlyReset(_, .session, _, _) = notifier.posted[0].kind else { return XCTFail("expected earlyReset") }
        XCTAssertEqual(history.sessionResets.count, 1)
        XCTAssertEqual(history.sessionResets[0].key, TeamTrackingMigration.pairHistoryKey(profileId: p1.id, orgId: "org-a"))
        XCTAssertEqual(history.sessionResets[0].previous?.sessionPercentage, 60)
    }

    // MARK: 8 rate limit

    func testRateLimitedAccountSkippedAndLiveTargetNil() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-b"])
        build([p1, p2], current: ref(p1, "org-a"))
        fetcher.setUsage("k2", org: "org-b", error: err(.apiRateLimited, "Retry-After: 3000"))
        await boot()
        await round(0)
        await round(1)
        XCTAssertEqual(fetcher.callCount(prefix: "usage:k2|"), 1)
        clock.now = t0.addingTimeInterval(915)
        await tracker.tick(now: clock.now)
        XCTAssertEqual(fetcher.callCount(prefix: "list:k2"), 1)   // the boot list only
        XCTAssertNotNil(tracker.liveTarget())
        tracker.ingestLive(profileId: p1.id, orgId: "org-a",
                           result: .failure(err(.apiRateLimited, "Retry-After: 120")), isCachedReading: false)
        XCTAssertNil(tracker.liveTarget())
    }

    // MARK: 9 login loss

    func testLoginLossAndRestoreByFingerprint() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a", "org-b"], followed: "org-a")
        let p3 = profile("P3", key: "k3", ids: ["org-c"])
        creds.fingerprints[p1.id] = "fp1"
        build([p1, p3], current: ref(p1, "org-a"))
        await boot()
        tracker.reportRefreshRejected(profileId: p1.id)
        XCTAssertEqual(notifier.posted.count, 1)
        guard case .needsLogin = state(p1).authState else { return XCTFail("expected needsLogin") }
        XCTAssertNil(tracker.liveTarget())
        let before = fetcher.calls.count
        await round(0)
        XCTAssertFalse(fetcher.calls.dropFirst(before).contains { $0.contains("k1") })

        creds.fingerprints[p1.id] = "fp2"
        await round(1)
        XCTAssertEqual(state(p1).authState, .ok)
        guard case .loginRestored = events[0].kind else { return XCTFail("expected loginRestored") }
        XCTAssertEqual(notifier.posted.count, 1)
        await round(2)
        XCTAssertEqual(fetcher.callCount(prefix: "usage:k1|org-b"), 1)
        XCTAssertNotNil(tracker.liveTarget())
    }

    // MARK: 10 migration

    func testLegacyProfileRecordsHistoryUnderUuid() async throws {
        var p1 = profile("P1", key: "k1", ids: [])
        p1.organizationId = "org-a"
        p1.orgTracking = nil
        build([p1], current: PairRef(profileId: p1.id, orgId: "org-a"))
        await boot()
        XCTAssertNotNil(store.profile(p1.id).orgTracking)
        tracker.ingestLive(profileId: p1.id, orgId: "org-a", result: .success(try u(10)), isCachedReading: false)
        XCTAssertEqual(history.sessionPeriodic, [p1.id.uuidString])
        XCTAssertEqual(history.weeklyPeriodic, [p1.id.uuidString])
    }

    // MARK: 11 old team

    func testOldTeamExpiryAndManualDelete() async throws {
        let id1 = UUID(), id2 = UUID()
        let old = tracked(id1, "org-a", status: .old, lastSeen: t0.addingTimeInterval(-16 * 86_400))
        let p1 = profile("P1", key: "k1", orgs: [old, tracked(id1, "org-b")], id: id1)
        let p2 = profile("P2", key: "k2", orgs: [tracked(id2, "org-c", status: .old), tracked(id2, "org-d")], id: id2)
        build([p1, p2], current: PairRef(profileId: id1, orgId: "org-b"))
        await boot()
        await round(0)
        XCTAssertNil(state(p1).org("org-a"))
        XCTAssertEqual(history.deleted, [old.historyKey])
        XCTAssertTrue(notifier.posted.isEmpty)

        XCTAssertFalse(tracker.deleteOldPair(PairRef(profileId: id1, orgId: "org-b")))
        XCTAssertTrue(tracker.deleteOldPair(PairRef(profileId: id2, orgId: "org-c")))
        XCTAssertEqual(history.deleted.last, TeamTrackingMigration.pairHistoryKey(profileId: id2, orgId: "org-c"))
        guard case .oldTeamDeleted(_, _, true) = events[0].kind else { return XCTFail("expected manual delete event") }
    }

    // MARK: 12 invariant 3

    func testProbeOfFollowedOrgSavesClaudeUsageOthersDoNot() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-a", "org-b"], followed: "org-a")
        build([p1, p2], current: ref(p1, "org-a"))
        fetcher.setUsage("k2", org: "org-a", try u(11))
        fetcher.setUsage("k2", org: "org-b", try u(30))
        var sampled: [(UUID, Double)] = []
        tracker.onSample = { sampled.append(($0, $1.sessionPercentage)) }
        await boot()
        await round(0)
        let saved = store.savedUsage.filter { $0.0 == p2.id }
        XCTAssertEqual(saved.map { $0.1.sessionPercentage }, [11])
        XCTAssertEqual(sampled.map { $0.1 }, [11])
        tracker.ingestLive(profileId: p1.id, orgId: "org-a", result: .success(try u(40)), isCachedReading: false)
        XCTAssertTrue(store.savedUsage.filter { $0.0 == p1.id }.isEmpty)
    }

    // MARK: 13 stop during a round

    private func oauthProfile() -> Profile {
        let id = UUID()
        var p = profile("OAuth", key: nil, orgs: [tracked(id, "org-b")], id: id, cli: TeamFixtures.credentialsOrgB)
        p.orgTracking?.credentialOrgId = "org-b"
        return p
    }

    private func waitBlocked() async {
        for _ in 0..<400 where !fetcher.isBlocked { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    func testStopDuringRoundPersistsNothing() async throws {
        let p = oauthProfile()
        build([p])
        fetcher.blockOAuth()
        await boot()
        let writes = store.trackingWrites
        let task = Task { await self.tracker.tick(now: self.t0.addingTimeInterval(15)) }
        await waitBlocked()
        XCTAssertTrue(fetcher.isBlocked)
        tracker.stop()
        fetcher.releaseOAuth()
        await task.value
        XCTAssertEqual(store.trackingWrites, writes)
        XCTAssertNil(tracker.global.lastRoundAt)
        XCTAssertTrue(history.sessionPeriodic.isEmpty)
        XCTAssertNil(TeamTrackingGlobalStore(defaults: defaults).load().lastRoundAt)
        XCTAssertFalse(tracker.isRunning)
    }

    // MARK: 14 disabled

    func testDisabledStartDoesNothing() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        build([p1], current: ref(p1, "org-a"), enabled: false)
        XCTAssertFalse(tracker.isRunning)
        XCTAssertNil(tracker.liveTarget())
        await boot()
        await round(0)
        XCTAssertTrue(fetcher.calls.isEmpty)
        XCTAssertEqual(store.trackingWrites, 0)
    }

    // MARK: Edge cases

    func testProfileDeletedWhileProbeInFlightWritesNothing() async throws {
        let p = oauthProfile()
        build([p])
        fetcher.blockOAuth()
        await boot()
        let task = Task { await self.tracker.tick(now: self.t0.addingTimeInterval(15)) }
        await waitBlocked()
        store.profiles.removeAll()
        fetcher.releaseOAuth()
        await task.value
        XCTAssertEqual(store.trackingWrites, 0)
        XCTAssertTrue(store.savedUsage.isEmpty)
        XCTAssertTrue(history.sessionPeriodic.isEmpty)
    }

    func testCloudflareOnProbeIsIgnored() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-b"])
        build([p1, p2], current: ref(p1, "org-a"))
        await boot()
        fetcher.setUsage("k2", org: "org-b", error: err(.apiServiceUnavailable))
        await round(0)
        XCTAssertEqual(fetcher.callCount(prefix: "usage:k2|"), 1)
        XCTAssertEqual(fetcher.callCount(prefix: "list:k2"), 1)   // boot only: no forced list
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(state(p2).org("org-b")?.status, .member)
    }

    func testSameOrgIdOnTwoProfilesStaysIndependent() async throws {
        let p1 = profile("P1", key: "k1", ids: ["org-a"])
        let p2 = profile("P2", key: "k2", ids: ["org-a"])
        let p3 = profile("P3", key: "k3", ids: ["org-z"])
        build([p1, p2, p3], current: ref(p3, "org-z"))
        fetcher.setUsage("k1", org: "org-a", try u(11))
        fetcher.setUsage("k2", org: "org-a", try u(22))
        await boot()
        await round(0)
        XCTAssertEqual(state(p1).org("org-a")?.lastUsage?.sessionPercentage, 11)
        XCTAssertEqual(state(p2).org("org-a")?.lastUsage?.sessionPercentage, 22)
    }

    func testNoAnthropicProfilesTickIsNoOp() async throws {
        build([])
        await boot()
        await round(0)
        XCTAssertTrue(fetcher.calls.isEmpty)
        XCTAssertEqual(store.trackingWrites, 0)
        XCTAssertNil(tracker.global.lastRoundAt)
    }
}
