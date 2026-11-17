import XCTest
@testable import Claude_Usage

final class TeamRowsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func org(_ id: String, session: Double, weekly: Double, status: PairStatus = .member,
                     lastSeen: Date? = nil, firstSeen: Date? = nil) throws -> TrackedOrg {
        let u = try TeamFixtures.usage(session: session, weekly: weekly,
                                       sessionReset: now.addingTimeInterval(3600), weeklyReset: now.addingTimeInterval(day))
        return TrackedOrg(orgId: id, name: id.uppercased(), status: status, historyKey: "k-\(id)", seat: nil,
                          lastUsage: u, lastSampleAt: now, firstSeenAt: firstSeen ?? now, lastSeenInListAt: lastSeen,
                          missingFromListCount: 0, lastMembershipFailureAt: nil, pending: nil,
                          baselineStartedAt: now, roundReading: nil)
    }

    private func profile(_ name: String, _ orgs: [TrackedOrg], auth: AuthState = .ok, provider: Provider = .anthropic, tracking: Bool = true) -> Profile {
        var st = OrgTrackingState.empty
        st.orgs = orgs
        st.authState = auth
        return Profile(name: name, provider: provider, orgTracking: tracking ? st : nil)
    }

    private func build(_ ps: [Profile], current: PairRef? = nil, cred: @escaping (Profile) -> Bool = { _ in true }) -> [TeamRow] {
        var g = TeamTrackingGlobalState.empty
        g.current = current
        return TeamRow.build(profiles: ps, global: g, hasCredential: cred, now: now)
    }

    func testCurrentFirstThenHeadroomThenWeeklyLeft() throws {
        let p = profile("P", [try org("x", session: 90, weekly: 90), try org("y", session: 50, weekly: 50),
                              try org("z", session: 70, weekly: 70), try org("w", session: 50, weekly: 20)])
        let rows = build([p], current: PairRef(profileId: p.id, orgId: "x"))
        // x current; w and y both headroom 50, w has more weekly left; z headroom 30
        XCTAssertEqual(rows.map(\.pair.orgId), ["x", "w", "y", "z"])
        XCTAssertEqual(rows.map(\.isCurrent), [true, false, false, false])
        XCTAssertEqual(rows[0].id, "\(p.id)_x")
    }

    func testNeedsLoginAfterOkAndOldLastWithDeleteDays() throws {
        let ok = profile("Ok", [try org("a", session: 99, weekly: 99)])
        let lost = profile("Lost", [try org("b", session: 0, weekly: 0)], auth: .needsLogin(reason: "401", since: now))
        let old = profile("Old", [try org("c", session: 0, weekly: 0, status: .old, lastSeen: now.addingTimeInterval(-12 * day))])
        let rows = build([old, lost, ok])
        XCTAssertEqual(rows.map(\.state), [.ok, .needsLogin, .old])
        XCTAssertEqual(rows.last?.deleteAfterDays, 3)
        XCTAssertNil(rows[0].deleteAfterDays)
    }

    func testNotSignedInAndOldFallsBackToFirstSeen() throws {
        let anon = profile("Anon", [try org("a", session: 0, weekly: 0)])
        XCTAssertEqual(build([anon], cred: { _ in false }).first?.state, .notSignedIn)
        let old = profile("Old", [try org("c", session: 0, weekly: 0, status: .old, lastSeen: nil, firstSeen: now.addingTimeInterval(-20 * day))])
        XCTAssertEqual(build([old]).first?.deleteAfterDays, 0)
    }

    func testCodexAndUntrackedProfilesHaveNoRows() throws {
        let codex = profile("Codex", [try org("a", session: 1, weekly: 1)], provider: .codex)
        let plain = profile("Plain", [], tracking: false)
        XCTAssertTrue(build([codex, plain]).isEmpty)
    }

    func testRecentEventsLimitAndNewestFirst() {
        var g = TeamTrackingGlobalState.empty
        let pid = UUID()
        for i in 0..<8 {
            g.appendEvent(TeamEvent(kind: .loginRestored(profileId: pid), names: [:], date: Date(timeIntervalSince1970: Double(i))))
        }
        let ev = TeamRow.recentEvents(g)
        XCTAssertEqual(ev.count, 5)
        XCTAssertEqual(ev.map { $0.date.timeIntervalSince1970 }, [7, 6, 5, 4, 3])
    }
}
