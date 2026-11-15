import XCTest
@testable import Claude_Usage

final class AccountRulesTests: XCTestCase {
    private let pid = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_799_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func org(_ id: String, status: PairStatus = .member, firstSeen: TimeInterval = 0,
                     lastSeen: TimeInterval? = nil, missing: Int = 0, usage: ClaudeUsage? = nil,
                     seat: SeatFingerprint? = nil, pending: PendingChange? = nil,
                     failure: TimeInterval? = nil, key: String? = nil) -> TrackedOrg {
        TrackedOrg(orgId: id, name: "Team \(id)", status: status, historyKey: key ?? "\(pid.uuidString)_\(id)",
                   seat: seat, lastUsage: usage, lastSampleAt: nil, firstSeenAt: at(firstSeen),
                   lastSeenInListAt: lastSeen.map(at), missingFromListCount: missing,
                   lastMembershipFailureAt: failure.map(at), pending: pending, baselineStartedAt: at(firstSeen),
                   roundReading: nil)
    }

    private func state(_ orgs: [TrackedOrg], lastList: TimeInterval? = nil, legacy: Bool = true) -> OrgTrackingState {
        var s = OrgTrackingState.empty
        s.orgs = orgs
        s.lastOrgListAt = lastList.map(at)
        s.legacyHistoryKeyAssigned = legacy
        return s
    }

    private func entry(_ id: String, canChat: Bool = true, seat: SeatFingerprint? = nil) -> OrgListEntry {
        OrgListEntry(orgId: id, name: "Team \(id)", seat: seat, canChat: canChat)
    }

    private func run(_ obs: AccountObservation, _ s: OrgTrackingState, followed: String? = nil) -> AccountResult {
        AccountRules.apply(obs, to: s, profileId: pid, profileName: "Me", followedOrgId: followed)
    }

    private func u(_ session: Double, _ weekly: Double, sessionReset: Date = TeamFixtures.defaultSessionReset,
                   weeklyReset: Date = TeamFixtures.defaultWeeklyReset) throws -> ClaudeUsage {
        try TeamFixtures.usage(session: session, weekly: weekly, sessionReset: sessionReset, weeklyReset: weeklyReset)
    }

    private func kinds(_ r: AccountResult) -> [TeamEvent.Kind] { r.events.map(\.kind) }
    private func status(_ r: AccountResult, _ id: String) -> PairStatus? { r.state.org(id)?.status }

    // AC1
    func testAdminMoveAfterThreeLists() {
        var s = state([org("A", firstSeen: 0), org("B", firstSeen: 100)])
        var r = run(AccountObservation(now: at(1000), orgList: [entry("A"), entry("B")]), s)
        s = r.state
        r = run(AccountObservation(now: at(1100), orgList: [entry("B")]), s, followed: "A")
        XCTAssertTrue(r.events.isEmpty)
        s = r.state
        r = run(AccountObservation(now: at(1200), orgList: [entry("B")]), s, followed: "A")
        XCTAssertEqual(kinds(r), [.adminMove(profileId: pid, from: "A", to: "B")])
        XCTAssertEqual(status(r, "A"), .old)
        XCTAssertEqual(r.state.org("A")?.historyKey, "\(pid.uuidString)_A")
        XCTAssertEqual(r.followedOrgId, "B")
        XCTAssertEqual(r.confirmedRemovals, [ConfirmedRemoval(orgId: "A", movedTo: "B")])
    }

    // AC2
    func testMembershipFailureConfirmsImmediately() {
        let s = state([org("A", lastSeen: 0, failure: 600), org("B", firstSeen: 100)], lastList: 900)
        let r = run(AccountObservation(now: at(900), orgList: [entry("B")]), s)
        XCTAssertEqual(kinds(r), [.adminMove(profileId: pid, from: "A", to: "B")])
    }

    func testUsageMembershipFailureIsRecorded() {
        let s = state([org("A"), org("B")])
        let r = run(AccountObservation(now: at(500), usageMembershipFailures: ["A"]), s)
        XCTAssertEqual(r.state.org("A")?.lastMembershipFailureAt, at(500))
    }

    // AC3
    func testPeerConfirmedRemoval() {
        let s = state([org("A", lastSeen: 0), org("B", firstSeen: 10)])
        let r = run(AccountObservation(now: at(100), orgList: [entry("B")], peerConfirmedRemovals: ["A"]), s)
        XCTAssertEqual(status(r, "A"), .old)
        XCTAssertEqual(kinds(r), [.adminMove(profileId: pid, from: "A", to: "B")])
    }

    // AC4
    func testNilOrEmptyListChangesNothing() {
        let s = state([org("A", missing: 1), org("B")], lastList: 0)
        for list in [nil, [OrgListEntry]()] {
            let r = run(AccountObservation(now: at(1000), orgList: list), s)
            XCTAssertTrue(r.events.isEmpty)
            XCTAssertEqual(r.state.orgs, s.orgs)
        }
    }

    // AC5
    func testTeamRemovedWithoutTarget() {
        let s = state([org("A", lastSeen: 0, missing: 1), org("B", firstSeen: -10 * 86_400)], lastList: 0)
        // B is listed but older than A.lastSeen - 24h, so it is not a move target.
        let r = run(AccountObservation(now: at(100), orgList: [entry("B")]), s, followed: "A")
        XCTAssertEqual(kinds(r), [.teamRemoved(profileId: pid, org: "A")])
        XCTAssertEqual(r.confirmedRemovals, [ConfirmedRemoval(orgId: "A", movedTo: nil)])
        XCTAssertEqual(r.followedOrgId, "B")
    }

    // AC6
    func testRejoin() {
        let s = state([org("A", status: .old, lastSeen: -1000, key: "KEY")])
        let r = run(AccountObservation(now: at(0), orgList: [entry("A")]), s)
        XCTAssertEqual(kinds(r), [.teamRejoined(profileId: pid, org: "A")])
        XCTAssertFalse(r.events[0].notifies)
        XCTAssertEqual(status(r, "A"), .member)
        XCTAssertEqual(r.state.org("A")?.historyKey, "KEY")
    }

    // AC7
    func testNewOrgAdded() {
        let s = state([org("A")])
        let r = run(AccountObservation(now: at(0), orgList: [entry("A"), entry("C")]), s)
        XCTAssertEqual(kinds(r), [.teamAdded(profileId: pid, org: "C")])
        XCTAssertFalse(r.events[0].notifies)
        XCTAssertEqual(status(r, "C"), .member)
        XCTAssertEqual(r.state.org("C")?.historyKey, "\(pid.uuidString)_C")
    }

    func testFirstPairGetsLegacyKeyOnce() {
        let r = run(AccountObservation(now: at(0), orgList: [entry("A"), entry("B")]), state([], legacy: false))
        XCTAssertEqual(r.state.org("A")?.historyKey, pid.uuidString)
        XCTAssertEqual(r.state.org("B")?.historyKey, "\(pid.uuidString)_B")
        XCTAssertTrue(r.state.legacyHistoryKeyAssigned)
    }

    // AC8
    func testOAuthOnlyTeamChange() {
        var s = state([org("A")])
        s.credentialOrgId = "A"
        let r = run(AccountObservation(now: at(0), hasSessionKey: false, credentialOrgId: "B"), s, followed: "A")
        XCTAssertEqual(kinds(r), [.teamChanged(profileId: pid, from: "A", to: "B")])
        XCTAssertEqual(status(r, "A"), .unreachable)
        XCTAssertEqual(status(r, "B"), .member)
        XCTAssertEqual(r.followedOrgId, "B")
        XCTAssertEqual(r.state.credentialOrgId, "B")
    }

    // AC9
    func testSeatChangeFingerprint() {
        let std = SeatFingerprint(source: .orgList, value: "std")
        let premium = SeatFingerprint(source: .orgList, value: "premium")
        let s = state([org("A", seat: std)])
        let r = run(AccountObservation(now: at(0), orgList: [entry("A", seat: premium)]), s)
        XCTAssertEqual(kinds(r), [.seatChange(PairRef(profileId: pid, orgId: "A"), from: "std", to: "premium", inferred: false)])
        XCTAssertEqual(r.state.org("A")?.seat, premium)
    }

    func testSeatSourceChangeIsSilent() {
        let cred = SeatFingerprint(source: .credentials, value: "std")
        let list = SeatFingerprint(source: .orgList, value: "premium")
        let r = run(AccountObservation(now: at(0), orgList: [entry("A", seat: list)]), state([org("A", seat: cred)]))
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(r.state.org("A")?.seat, list)
    }

    // AC10
    func testInferredSeatChangeConfirmed() throws {
        let prev = try u(40, 20)
        let s = state([org("A", usage: prev)])
        var r = run(AccountObservation(now: at(0), samples: ["A": try u(10, 5)]), s)
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertNotNil(r.state.org("A")?.pending)
        r = run(AccountObservation(now: at(300), samples: ["A": try u(11, 5)]), r.state)
        XCTAssertEqual(kinds(r), [.seatChange(PairRef(profileId: pid, orgId: "A"), from: nil, to: nil, inferred: true)])
        XCTAssertNil(r.state.org("A")?.pending)
    }

    func testInferredSeatChangeDiscarded() throws {
        var r = run(AccountObservation(now: at(0), samples: ["A": try u(10, 5)]), state([org("A", usage: try u(40, 20))]))
        r = run(AccountObservation(now: at(300), samples: ["A": try u(40, 20)]), r.state)
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertNil(r.state.org("A")?.pending)
    }

    // AC11
    func testEarlyResetConfirmed() throws {
        let prev = try u(60, 20)
        var r = run(AccountObservation(now: at(0), samples: ["A": try u(5, 20)]), state([org("A", usage: prev)]))
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertTrue(r.resetSnapshots.isEmpty)
        r = run(AccountObservation(now: at(300), samples: ["A": try u(6, 20)]), r.state)
        XCTAssertEqual(kinds(r), [.earlyReset(PairRef(profileId: pid, orgId: "A"), window: .session, fromPercent: 60, toPercent: 6)])
        XCTAssertEqual(r.resetSnapshots, [ResetSnapshot(orgId: "A", window: .session, previous: prev)])
    }

    func testEarlyResetBounceBack() throws {
        var r = run(AccountObservation(now: at(0), samples: ["A": try u(5, 20)]), state([org("A", usage: try u(60, 20))]))
        r = run(AccountObservation(now: at(300), samples: ["A": try u(61, 20)]), r.state)
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertTrue(r.resetSnapshots.isEmpty)
        XCTAssertNil(r.state.org("A")?.pending)
    }

    // AC12
    func testNaturalResetSnapshotOnly() throws {
        let prev = try u(60, 20, sessionReset: at(240))
        let new = try u(0, 20, sessionReset: at(240 + 5 * 3600))
        let r = run(AccountObservation(now: at(250), samples: ["A": new]), state([org("A", usage: prev)]))
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(r.resetSnapshots, [ResetSnapshot(orgId: "A", window: .session, previous: prev)])
    }

    // AC13
    func testResetTimeMovedWithoutDropIsQuiet() throws {
        let prev = try u(60, 20)
        let new = try u(61, 20, sessionReset: TeamFixtures.defaultSessionReset.addingTimeInterval(7200))
        let r = run(AccountObservation(now: at(0), samples: ["A": new]), state([org("A", usage: prev)]))
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertTrue(r.resetSnapshots.isEmpty)
        XCTAssertNil(r.state.org("A")?.pending)
        XCTAssertEqual(r.state.org("A")?.lastUsage, new)
    }

    // AC14
    func testNoFiveHourSampleGivesNoSessionEvent() throws {
        let noFive = try ClaudeAPIService().parseUsageResponse(Data(TeamFixtures.usageNoFiveHour.utf8))
        XCTAssertFalse(noFive.hasSessionLimit)
        let r = run(AccountObservation(now: at(0), samples: ["A": noFive]), state([org("A", usage: try u(60, 20))]))
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertTrue(r.resetSnapshots.isEmpty)
        XCTAssertNil(r.state.org("A")?.pending)
    }

    // AC15
    func testStalePendingDiscarded() throws {
        let baseline = try u(60, 20)
        let pending = PendingChange(kind: .earlyReset(.session), baseline: baseline, candidate: try u(5, 20),
                                    detectedAt: at(-1801))
        let r = run(AccountObservation(now: at(0), samples: ["A": try u(6, 20)]),
                    state([org("A", usage: try u(5, 20), pending: pending)]))
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertNil(r.state.org("A")?.pending)
    }

    // AC16
    func testRefreshRejectedThenRestored() throws {
        var s = state([org("A")])
        s.credentialFingerprint = "fp1"
        var r = run(AccountObservation(now: at(0), credentialFingerprint: "fp1", refreshRejected: true), s)
        guard case .needsLogin = r.state.authState else { return XCTFail("expected needsLogin") }
        XCTAssertEqual(kinds(r), [.loginLost(profileId: pid, reason: "Claude Code login was revoked")])
        // Same fingerprint, no sample, no list: still blocked.
        let still = run(AccountObservation(now: at(10), credentialFingerprint: "fp1", orgList: nil), r.state)
        XCTAssertTrue(still.events.isEmpty)
        XCTAssertTrue(still.acceptedSamples.isEmpty)
        r = run(AccountObservation(now: at(20), credentialFingerprint: "fp2", samples: ["A": try u(1, 1)]), r.state)
        XCTAssertEqual(r.state.authState, .ok)
        XCTAssertEqual(kinds(r), [.loginRestored(profileId: pid)])
        XCTAssertFalse(r.events[0].notifies)
        XCTAssertEqual(r.acceptedSamples.count, 1)
    }

    // AC17
    func testListAuthFailedNeedsLogin() {
        let r = run(AccountObservation(now: at(0), orgListAuthFailed: true), state([org("A")]))
        XCTAssertEqual(r.state.authState, .needsLogin(reason: "claude.ai session expired", since: at(0)))
    }

    func testOAuthUnauthorizedTwice() {
        var s = state([org("A")])
        var r = run(AccountObservation(now: at(0), hasSessionKey: false, oauthUnauthorized: true), s)
        XCTAssertEqual(r.state.authState, .ok)
        XCTAssertEqual(r.state.consecutiveOAuthUnauthorized, 1)
        s = r.state
        r = run(AccountObservation(now: at(30), hasSessionKey: false, oauthUnauthorized: true), s)
        XCTAssertEqual(r.state.authState, .needsLogin(reason: "Log in again", since: at(30)))
    }

    func testL3LockoutClearedByNewFingerprint() {
        var s = state([org("A")])
        s.credentialFingerprint = "fp1"
        s.consecutiveOAuthUnauthorized = 1
        var r = run(AccountObservation(now: at(0), hasSessionKey: false, credentialFingerprint: "fp1", oauthUnauthorized: true), s)
        guard case .needsLogin = r.state.authState else { return XCTFail("expected needsLogin") }
        r = run(AccountObservation(now: at(30), hasSessionKey: false, credentialFingerprint: "fp2"), r.state)
        XCTAssertEqual(r.state.authState, .ok)
        XCTAssertEqual(r.state.consecutiveOAuthUnauthorized, 0)
        XCTAssertEqual(kinds(r), [.loginRestored(profileId: pid)])
    }

    func testSuccessfulSampleRestoresLogin() throws {
        var s = state([org("A")])
        s.authState = .needsLogin(reason: "x", since: at(-10))
        let r = run(AccountObservation(now: at(0), samples: ["A": try u(1, 1)]), s)
        XCTAssertEqual(r.state.authState, .ok)
        XCTAssertEqual(kinds(r), [.loginRestored(profileId: pid)])
    }

    func testEarlyResetPendingClearedWhenWindowAbsent() throws {
        let baseline = try u(60, 20)
        let pending = PendingChange(kind: .earlyReset(.session), baseline: baseline, candidate: try u(5, 20),
                                    detectedAt: at(-60))
        var weeklyOnly = try u(0, 20); weeklyOnly.hasSessionLimit = false
        let r = run(AccountObservation(now: at(0), samples: ["A": weeklyOnly]),
                    state([org("A", usage: try u(5, 20), pending: pending)]))
        XCTAssertNil(r.state.org("A")?.pending)
    }

    func testSeatFingerprintClearsInferredPending() throws {
        let pending = PendingChange(kind: .seatInferred, baseline: try u(60, 20), candidate: try u(20, 7),
                                    detectedAt: at(-60))
        let seat = SeatFingerprint(source: .orgList, value: "s1")
        let o = org("A", usage: try u(20, 7), seat: seat, pending: pending)
        let r = run(AccountObservation(now: at(0), orgList: [entry("A", seat: seat)]), state([o]))
        XCTAssertNil(r.state.org("A")?.pending)
    }

    func testOAuthUnauthorizedResetByAcceptedSample() throws {
        var s = state([org("A")])
        s.consecutiveOAuthUnauthorized = 1
        let r = run(AccountObservation(now: at(0), hasSessionKey: false, samples: ["A": try u(1, 1)]), s)
        XCTAssertEqual(r.state.consecutiveOAuthUnauthorized, 0)
    }

    func testSessionKeyAccountIgnoresOAuthUnauthorizedCount() {
        var s = state([org("A")])
        s.consecutiveOAuthUnauthorized = 1
        let r = run(AccountObservation(now: at(0), hasSessionKey: true, oauthUnauthorized: true), s)
        XCTAssertEqual(r.state.authState, .ok)
    }

    // AC18
    func testOldTeamExpiry() {
        let day: TimeInterval = 86_400
        let now = at(100 * day)
        let s = state([
            org("old15", status: .old, lastSeen: 100 * day - 15 * day - 1),
            org("old14", status: .old, lastSeen: 100 * day - 14 * day),
            org("member", status: .member, lastSeen: 100 * day - 60 * day),
            org("unreach", status: .unreachable, lastSeen: 100 * day - 60 * day),
        ])
        let r = run(AccountObservation(now: now), s)
        XCTAssertNil(r.state.org("old15"))
        XCTAssertNotNil(r.state.org("old14"))
        XCTAssertNotNil(r.state.org("member"))
        XCTAssertNotNil(r.state.org("unreach"))
        XCTAssertEqual(r.deletedHistoryKeys, ["\(pid.uuidString)_old15"])
        XCTAssertEqual(kinds(r), [.oldTeamDeleted(profileId: pid, org: "old15", manual: false)])
        XCTAssertFalse(r.events[0].notifies)
    }

    // AC19
    func testUnknownOrgRenamed() {
        let s = state([org(TrackedOrg.unknownOrgId, key: "K")])
        let r = run(AccountObservation(now: at(0), orgList: [entry("A"), entry("X", canChat: false)]), s, followed: TrackedOrg.unknownOrgId)
        XCTAssertNil(r.state.org(TrackedOrg.unknownOrgId))
        XCTAssertEqual(r.state.org("A")?.historyKey, "K")
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(r.followedOrgId, "A")
    }

    func testUnknownOrgDroppedWhenTargetTracked() {
        let s = state([org(TrackedOrg.unknownOrgId), org("A")])
        let r = run(AccountObservation(now: at(0), credentialOrgId: "A"), s)
        XCTAssertEqual(r.state.orgs.map(\.orgId), ["A"])
    }

    // AC20
    func testSampleForOldOrgIgnored() throws {
        let prev = try u(10, 10)
        let r = run(AccountObservation(now: at(0), samples: ["A": try u(20, 20)]),
                    state([org("A", status: .old, usage: prev)]))
        XCTAssertEqual(r.state.org("A")?.lastUsage, prev)
        XCTAssertEqual(status(r, "A"), .old)
        XCTAssertTrue(r.acceptedSamples.isEmpty)
    }

    func testAcceptedSampleRecorded() throws {
        let sample = try u(10, 10)
        let r = run(AccountObservation(now: at(7), samples: ["A": sample]), state([org("A")]))
        XCTAssertEqual(r.state.org("A")?.lastUsage, sample)
        XCTAssertEqual(r.state.org("A")?.lastSampleAt, at(7))
        XCTAssertEqual(r.acceptedSamples["A"], sample)
    }

    // Edge cases
    func testApiOnlyListChangesNothing() {
        let s = state([org("A")])
        let r = run(AccountObservation(now: at(1000), orgList: [entry("A", canChat: false)]), s, followed: "A")
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(status(r, "A"), .member)
        XCTAssertEqual(r.state.org("A")?.missingFromListCount, 0)
    }

    func testNewestOrgIsMoveTarget() {
        let s = state([org("A", firstSeen: 0, lastSeen: 0, failure: 0)], lastList: 0)
        // two members already tracked, B newer than C
        var s2 = s
        s2.orgs.append(org("B", firstSeen: 50))
        s2.orgs.append(org("C", firstSeen: 80))
        let r = run(AccountObservation(now: at(100), orgList: [entry("B"), entry("C")]), s2)
        XCTAssertEqual(kinds(r), [.adminMove(profileId: pid, from: "A", to: "C")])
    }

    func testCollapsedMoveAToC() {
        let s = state([org("A", firstSeen: 0, lastSeen: 0, missing: 1)], lastList: 0)
        let r = run(AccountObservation(now: at(100), orgList: [entry("C")]), s)
        XCTAssertEqual(kinds(r), [.teamAdded(profileId: pid, org: "C"), .adminMove(profileId: pid, from: "A", to: "C")])
    }

    func testWeeklyOnlyPlanNoSeatInference() throws {
        var prev = try u(0, 40); prev.hasSessionLimit = false
        var new = try u(0, 10); new.hasSessionLimit = false
        let r = run(AccountObservation(now: at(0), samples: ["A": new]), state([org("A", usage: prev)]))
        // The drop is only an early-reset candidate; one window never qualifies as a seat change.
        XCTAssertEqual(r.state.org("A")?.pending?.kind, .earlyReset(.weekly))
        XCTAssertTrue(r.events.isEmpty)
    }

    func testMoveAndSessionDropOnlyMove() throws {
        let s = state([org("A", lastSeen: 0, missing: 1), org("B", firstSeen: 10, usage: try u(60, 20))], lastList: 0)
        let r = run(AccountObservation(now: at(100), orgList: [entry("B")], samples: ["B": try u(5, 20)]), s)
        XCTAssertEqual(kinds(r), [.adminMove(profileId: pid, from: "A", to: "B")])
        XCTAssertNil(r.state.org("B")?.pending)
        XCTAssertEqual(r.state.org("B")?.lastUsage?.sessionPercentage, 5)
    }

    func testEventNames() {
        let s = state([org("A", lastSeen: 0, failure: 0), org("B", firstSeen: 1)], lastList: 0)
        let r = run(AccountObservation(now: at(10), orgList: [entry("B")]), s)
        XCTAssertEqual(r.events[0].names["A"], "Team A")
        XCTAssertEqual(r.events[0].names[pid.uuidString], "Me")
    }

    // MARK: Tester additions (MT-2 test round)

    // Boundary of the 60 s list debounce: a list less than 60 s after the previous one adds no miss; exactly 60 s does.
    func testMissingDebounceBoundary() {
        let s = state([org("A"), org("B")], lastList: 0)
        var r = run(AccountObservation(now: at(59), orgList: [entry("B")]), s, followed: "A")
        XCTAssertEqual(r.state.org("A")?.missingFromListCount, 0)
        XCTAssertTrue(r.events.isEmpty)
        r = run(AccountObservation(now: at(119), orgList: [entry("B")]), r.state, followed: "A")
        XCTAssertEqual(r.state.org("A")?.missingFromListCount, 1)   // exactly 60 s after the previous list
        XCTAssertTrue(r.events.isEmpty)
        r = run(AccountObservation(now: at(179), orgList: [entry("B")]), r.state, followed: "A")
        XCTAssertEqual(kinds(r), [.adminMove(profileId: pid, from: "A", to: "B")])
    }

    // The membership failure counts for 10 min exactly (inclusive); one second later it no longer confirms a removal.
    func testMembershipFailureWindowBoundary() {
        for (age, confirmed) in [(600.0, true), (601.0, false)] {
            let s = state([org("A", failure: 0), org("B")])
            let r = run(AccountObservation(now: at(age), orgList: [entry("B")]), s)
            XCTAssertEqual(kinds(r).contains(.adminMove(profileId: pid, from: "A", to: "B")), confirmed, "age \(age)s")
        }
    }

    // R6 thresholds: candidate needs prev >= 10, new <= prev * 0.5 (inclusive) and a drop of at least 10 points.
    func testEarlyResetCandidateThresholds() throws {
        let cases: [(prev: Double, new: Double, candidate: Bool)] = [
            (60, 30, true),    // exactly half
            (60, 31, false),   // just above half
            (20, 10, true),    // drop of exactly 10 points
            (15, 7, false),    // halved, but drop of 8 points
        ]
        for c in cases {
            let r = run(AccountObservation(now: at(0), samples: ["A": try u(c.new, 20)]),
                        state([org("A", usage: try u(c.prev, 20))]))
            XCTAssertEqual(r.state.org("A")?.pending?.kind == .earlyReset(.session), c.candidate, "\(c.prev) -> \(c.new)")
        }
    }

    // R natural = now >= prev reset - 5 min (inclusive): at the edge the drop is a reset; 1 s earlier it is a candidate.
    func testNaturalResetBoundary() throws {
        let prev = try u(60, 20, sessionReset: at(1000))
        let moved = try u(0, 20, sessionReset: at(1000 + 5 * 3600))
        let edge = run(AccountObservation(now: at(700), samples: ["A": moved]), state([org("A", usage: prev)]))
        XCTAssertEqual(edge.resetSnapshots, [ResetSnapshot(orgId: "A", window: .session, previous: prev)])
        XCTAssertNil(edge.state.org("A")?.pending)
        let early = run(AccountObservation(now: at(699), samples: ["A": moved]), state([org("A", usage: prev)]))
        XCTAssertTrue(early.resetSnapshots.isEmpty)
        XCTAssertEqual(early.state.org("A")?.pending?.kind, .earlyReset(.session))
    }

    // S2 direction and spread: all ratios lean the same way, and max/min ratio must be at most 1.3.
    func testSeatCandidateDirectionAndSpread() throws {
        let cases: [(name: String, prev: (Double, Double), new: (Double, Double), candidate: Bool)] = [
            ("upgrade, both windows double", (20, 10), (40, 20), true),
            ("mixed directions", (40, 20), (10, 32), false),
            ("spread 1.67 above 1.3", (40, 20), (20, 6), false),
            ("spread 1.25 within 1.3", (40, 20), (20, 8), true),
        ]
        for c in cases {
            let r = run(AccountObservation(now: at(0), samples: ["A": try u(c.new.0, c.new.1)]),
                        state([org("A", usage: try u(c.prev.0, c.prev.1))]))
            XCTAssertEqual(r.state.org("A")?.pending?.kind == .seatInferred, c.candidate, c.name)
        }
    }

    // S2 reset guard: a session reset moved by more than 5 min disqualifies the seat candidate; 5 min exactly does not.
    func testSeatCandidateResetTimeTolerance() throws {
        for (shift, candidate) in [(300.0, true), (301.0, false)] {
            let moved = try u(10, 5, sessionReset: TeamFixtures.defaultSessionReset.addingTimeInterval(shift))
            let r = run(AccountObservation(now: at(0), samples: ["A": moved]),
                        state([org("A", usage: try u(40, 20))]))
            XCTAssertEqual(r.state.org("A")?.pending?.kind == .seatInferred, candidate, "shift \(shift)s")
        }
    }

    // needsLogin is left by a successful non-empty list (spec L); an empty list is not a success.
    func testListRestoresLoginOnlyWhenNonEmpty() {
        var s = state([org("A")])
        s.credentialFingerprint = "fp1"
        s.authState = .needsLogin(reason: "x", since: at(-10))
        let blocked = run(AccountObservation(now: at(0), credentialFingerprint: "fp1", orgList: []), s)
        XCTAssertNotEqual(blocked.state.authState, .ok)
        XCTAssertTrue(blocked.events.isEmpty)
        let restored = run(AccountObservation(now: at(10), credentialFingerprint: "fp1", orgList: [entry("A")]), blocked.state)
        XCTAssertEqual(restored.state.authState, .ok)
        XCTAssertEqual(kinds(restored), [.loginRestored(profileId: pid)])
    }

    // R13: a peer's confirmation only removes a pair that is missing from this account's own list.
    func testPeerRemovalIgnoredWhenStillListed() {
        let s = state([org("A"), org("B")])
        let r = run(AccountObservation(now: at(100), orgList: [entry("A"), entry("B")], peerConfirmedRemovals: ["A"]),
                    s, followed: "A")
        XCTAssertTrue(r.events.isEmpty)
        XCTAssertEqual(status(r, "A"), .member)
        XCTAssertTrue(r.confirmedRemovals.isEmpty)
        XCTAssertNil(r.followedOrgId)
    }

    // Two new orgs in one list share firstSeenAt = now, so the move target tie goes to the first listed org.
    func testTwoNewOrgsTieGoesToFirstListed() {
        let s = state([org("A", lastSeen: 0, missing: 1)], lastList: 0)
        let r = run(AccountObservation(now: at(100), orgList: [entry("B"), entry("C")]), s, followed: "A")
        XCTAssertTrue(kinds(r).contains(.adminMove(profileId: pid, from: "A", to: "B")))
        XCTAssertEqual(r.confirmedRemovals, [ConfirmedRemoval(orgId: "A", movedTo: "B")])
        XCTAssertEqual(r.followedOrgId, "B")
    }

    // Org ids match exactly: a Cyrillic look-alike of a tracked id is a different org, never the same pair.
    func testConfusableOrgIdIsADifferentOrg() {
        let lookalike = "org-\u{0430}"   // CYRILLIC SMALL LETTER A, tracked id; the list carries LATIN a
        let s = state([org(lookalike)], lastList: 0)
        let r = run(AccountObservation(now: at(10), orgList: [entry("org-a")]), s, followed: lookalike)
        XCTAssertEqual(kinds(r), [.teamAdded(profileId: pid, org: "org-a")])
        XCTAssertEqual(status(r, lookalike), .member)
        XCTAssertEqual(r.state.org(lookalike)?.missingFromListCount, 0)   // 10 s after the list: no miss counted
        XCTAssertNil(r.followedOrgId)
    }

    func testUnresolvedPlaceholderIsNeverConfirmedGone() {
        var s = state([org(TrackedOrg.unknownOrgId)])
        s.legacyHistoryKeyAssigned = true
        var r = run(AccountObservation(now: at(1000), orgList: [entry("A"), entry("B")]), s, followed: TrackedOrg.unknownOrgId)
        XCTAssertEqual(kinds(r), [.teamAdded(profileId: pid, org: "A"), .teamAdded(profileId: pid, org: "B")])
        XCTAssertNil(r.followedOrgId)
        XCTAssertTrue(r.confirmedRemovals.isEmpty)
        for t in [1100.0, 1200.0] {
            r = run(AccountObservation(now: at(t), orgList: [entry("A"), entry("B")]), r.state, followed: TrackedOrg.unknownOrgId)
            XCTAssertTrue(r.events.isEmpty)
            XCTAssertEqual(status(r, TrackedOrg.unknownOrgId), .member)
            XCTAssertNil(r.followedOrgId)
            XCTAssertTrue(r.confirmedRemovals.isEmpty)
        }
    }

    // Fallback follow target must skip the legacy placeholder even when it comes first in state order.
    func testFollowedFallbackNeverPicksPlaceholder() {
        let day: TimeInterval = 86_400
        let s = state([org(TrackedOrg.unknownOrgId), org("A", lastSeen: 5 * day), org("B"), org("C")], lastList: 5 * day)
        var r = run(AccountObservation(now: at(5 * day + 100), orgList: [entry("B"), entry("C")]), s, followed: "A")
        XCTAssertTrue(r.events.isEmpty)
        r = run(AccountObservation(now: at(5 * day + 200), orgList: [entry("B"), entry("C")]), r.state, followed: "A")
        XCTAssertEqual(kinds(r), [.teamRemoved(profileId: pid, org: "A")])
        XCTAssertEqual(r.followedOrgId, "B")
        XCTAssertEqual(status(r, TrackedOrg.unknownOrgId), .member)
    }

    func testMaxToProShapeIsSeatCandidate() throws {
        let prev = try TeamFixtures.usage(session: 40, weekly: 20, opus: 30)
        let s = state([org("A", usage: prev)])
        var r = run(AccountObservation(now: at(100), samples: ["A": try TeamFixtures.usage(session: 10, weekly: 5, opus: nil)]), s)
        XCTAssertEqual(r.state.org("A")?.pending?.kind, .seatInferred)
        XCTAssertTrue(r.events.isEmpty)
        r = run(AccountObservation(now: at(130), samples: ["A": try TeamFixtures.usage(session: 10, weekly: 5, opus: nil)]), r.state)
        XCTAssertEqual(kinds(r), [.seatChange(PairRef(profileId: pid, orgId: "A"), from: nil, to: nil, inferred: true)])
    }

    func testPerModelWindowsQualifyWhenPresent() throws {
        let prev = try TeamFixtures.usage(session: 40, weekly: 20, opus: 30)
        let r = run(AccountObservation(now: at(0), samples: ["A": try TeamFixtures.usage(session: 20, weekly: 8, opus: 12)]),
                    state([org("A", usage: prev)]))
        XCTAssertEqual(r.state.org("A")?.pending?.kind, .seatInferred)
        // The present Opus window takes part in the spread check: 30 -> 2 is far outside 1.3, so no seat candidate.
        let wide = AccountRules.apply(AccountObservation(now: at(0), samples: ["A": try TeamFixtures.usage(session: 20, weekly: 8, opus: 2)]),
                                      to: state([org("A", usage: prev)]), profileId: pid, profileName: "Me", followedOrgId: nil)
        XCTAssertNotEqual(wide.state.org("A")?.pending?.kind, .seatInferred)
    }
}
