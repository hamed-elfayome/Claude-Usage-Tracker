import XCTest
@testable import Claude_Usage

final class TeamTrackingModelsTests: XCTestCase {
    private let p = UUID()
    private let q = UUID()

    private func allKinds() -> [TeamEvent.Kind] {
        let ref = PairRef(profileId: p, orgId: "a")
        return [
            .nowOn(ref, from: nil, manual: false),
            .nowOn(ref, from: PairRef(profileId: q, orgId: "b"), manual: true),
            .adminMove(profileId: p, from: "a", to: "b"),
            .groupMove(from: "a", to: "b", moves: [p: "b", q: nil], notMoved: [q], unchecked: [p]),
            .teamRemoved(profileId: p, org: "a"),
            .teamChanged(profileId: p, from: "a", to: "b"),
            .teamAdded(profileId: p, org: "a"),
            .teamRejoined(profileId: p, org: "a"),
            .seatChange(ref, from: "x", to: nil, inferred: true),
            .earlyReset(ref, window: .weekly, fromPercent: 80, toPercent: 2),
            .loginLost(profileId: p, reason: "401"),
            .loginRestored(profileId: p),
            .oldTeamDeleted(profileId: p, org: "a", manual: true),
        ]
    }

    // AC1
    func testLegacyProfileDecodesWithoutOrgTracking() throws {
        let original = Profile(name: "Legacy", organizationId: "org-a")
        let data = try TeamFixtures.legacyProfileJSON(original)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertNil(decoded.orgTracking)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertEqual(decoded.organizationId, "org-a")
    }

    // AC2
    func testCorruptOrgTrackingKeepsProfile() throws {
        let data = try TeamFixtures.legacyProfileJSON()
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj["orgTracking"] = ["orgs": "not an array", "bogus": 1]
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(decoded.orgTracking)
        XCTAssertEqual(decoded.name, "Legacy")
    }

    func testOrgTrackingRoundTripsOnProfile() throws {
        var profile = Profile(name: "X")
        profile.orgTracking = TeamTrackingMigration.migrate(profile).orgTracking
        XCTAssertNotNil(profile.orgTracking)
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(back.orgTracking, profile.orgTracking)
    }

    // AC3
    func testGlobalStateRoundTripEveryKind() throws {
        var state = TeamTrackingGlobalState.empty
        state.current = PairRef(profileId: p, orgId: "a")
        for k in allKinds() { state.appendEvent(TeamEvent(kind: k, names: ["a": "A"])) }
        XCTAssertEqual(state.events.count, 13)
        let back = try JSONDecoder().decode(TeamTrackingGlobalState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back, state)
    }

    // AC4
    func testAppendEventCapsAtFiftyNewestFirst() {
        var state = TeamTrackingGlobalState.empty
        var ids: [UUID] = []
        for _ in 0..<51 {
            let e = TeamEvent(kind: .loginRestored(profileId: p), names: [:])
            ids.append(e.id)
            state.appendEvent(e)
        }
        XCTAssertEqual(state.events.count, 50)
        XCTAssertEqual(state.events.first?.id, ids.last)
        XCTAssertEqual(state.events.last?.id, ids[1])
    }

    // AC5
    func testCorruptGlobalStoreReturnsEmpty() {
        let suite = "TeamTrackingModelsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        d.set(Data("not json".utf8), forKey: "multiTeam.globalState")
        XCTAssertEqual(TeamTrackingGlobalStore(defaults: d).load(), .empty)
    }

    func testGlobalStoreSaveLoad() {
        let suite = "TeamTrackingModelsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        var state = TeamTrackingGlobalState.empty
        state.manualPickAt = Date(timeIntervalSince1970: 100)
        let store = TeamTrackingGlobalStore(defaults: d)
        store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    // AC14
    func testAdminMoveTitleAndNotifies() {
        let e = TeamEvent(kind: .adminMove(profileId: p, from: "a", to: "b"), names: ["a": "A", "b": "B"])
        XCTAssertEqual(e.title, "Moved by admin: A → B")
        XCTAssertTrue(e.notifies)
        let added = TeamEvent(kind: .teamAdded(profileId: p, org: "a"), names: [:])
        XCTAssertFalse(added.notifies)
        XCTAssertFalse(TeamEvent(kind: .nowOn(PairRef(profileId: p, orgId: "a"), from: nil, manual: true), names: [:]).notifies)
        XCTAssertTrue(TeamEvent(kind: .nowOn(PairRef(profileId: p, orgId: "a"), from: nil, manual: false), names: [:]).notifies)
    }

    func testUnknownOrgIdFallsBackToPrefix() {
        let e = TeamEvent(kind: .teamRemoved(profileId: p, org: "0123456789abcdef"), names: [:])
        XCTAssertEqual(e.title, "Removed from team 01234567")
    }

    func testGroupMoveBodyOmitsEmptyParts() {
        let none = TeamEvent(kind: .groupMove(from: "a", to: "b", moves: [p: "b"], notMoved: [], unchecked: []),
                             names: [p.uuidString: "Alice", "a": "A", "b": "B"])
        XCTAssertEqual(none.title, "1 accounts moved: A → B")
        XCTAssertEqual(none.body, "")

        let full = TeamEvent(kind: .groupMove(from: "a", to: "b", moves: [p: "c"], notMoved: [q], unchecked: [q]),
                             names: [p.uuidString: "Alice", q.uuidString: "Bob", "a": "A", "b": "B", "c": "C"])
        XCTAssertTrue(full.body.contains("Alice → C"))
        XCTAssertTrue(full.body.contains("Not moved: Bob"))
        XCTAssertTrue(full.body.contains("Not checked: Bob"))
    }

    func testEveryKindHasTitleAndBody() {
        for k in allKinds() {
            let e = TeamEvent(kind: k, names: [:])
            XCTAssertFalse(e.title.isEmpty)
            XCTAssertFalse(e.title.hasPrefix("multiteam."), "missing string for \(k)")
            XCTAssertFalse(e.body.hasPrefix("multiteam."), "missing string for \(k)")
        }
    }

    func testOrgHelpers() throws {
        var s = TeamTrackingMigration.migrate(Profile(name: "X", organizationId: "a")).orgTracking!
        XCTAssertNotNil(s.org("a"))
        XCTAssertNil(s.org("zzz"))
        s.updateOrg("a") { $0.missingFromListCount = 3 }
        XCTAssertEqual(s.org("a")?.missingFromListCount, 3)
        s.updateOrg("zzz") { $0.missingFromListCount = 9 }
        XCTAssertEqual(s.orgs.count, 1)
    }

    // AC15
    func testFixtureUsageParses() throws {
        let u = try TeamFixtures.usage(session: 40, weekly: 20)
        XCTAssertEqual(u.sessionPercentage, 40)
        XCTAssertEqual(u.weeklyPercentage, 20)
        let none = try ClaudeAPIService().parseUsageResponse(Data(TeamFixtures.usageNoFiveHour.utf8))
        XCTAssertFalse(none.hasSessionLimit)
    }

    // AC16
    func testSettingsDefaultOff() {
        let suite = "TeamTrackingModelsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(TeamTrackingSettings.isEnabled(d))
        d.set(true, forKey: TeamTrackingSettings.enabledKey)
        XCTAssertTrue(TeamTrackingSettings.isEnabled(d))
    }
}
