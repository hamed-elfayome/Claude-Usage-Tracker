import XCTest
@testable import Claude_Usage

final class TeamTrackingMigrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // AC6
    func testMigratesKnownOrgWithUsage() throws {
        let usage = try TeamFixtures.usage(session: 10, weekly: 5)
        let profile = Profile(name: "P", organizationId: "A", claudeUsage: usage)
        let m = TeamTrackingMigration.migrate(profile, now: now)
        let state = try XCTUnwrap(m.orgTracking)
        XCTAssertEqual(state.orgs.count, 1)
        let org = state.orgs[0]
        XCTAssertEqual(org.orgId, "A")
        XCTAssertEqual(org.status, .member)
        XCTAssertEqual(org.historyKey, profile.id.uuidString)
        XCTAssertEqual(org.lastUsage, usage)
        XCTAssertTrue(state.legacyHistoryKeyAssigned)
        XCTAssertEqual(org.name, "Team")
    }

    // AC7
    func testOrgFromOAuthAccount() throws {
        let profile = Profile(name: "P", oauthAccountJSON: TeamFixtures.oauthAccountOrgA)
        let org = try XCTUnwrap(TeamTrackingMigration.migrate(profile, now: now).orgTracking?.orgs.first)
        XCTAssertEqual(org.orgId, "org-a")
        XCTAssertEqual(org.name, "Team A")
        XCTAssertNil(org.lastUsage)
    }

    func testNestedOAuthAccount() throws {
        let json = #"{"oauthAccount":{"organizationUuid":"org-a","organizationName":"Team A"}}"#
        let org = try XCTUnwrap(TeamTrackingMigration.migrate(Profile(name: "P", oauthAccountJSON: json)).orgTracking?.orgs.first)
        XCTAssertEqual(org.orgId, "org-a")
        XCTAssertEqual(org.name, "Team A")
    }

    func testOrganizationIdWinsAndNameOnlyWhenIdsMatch() throws {
        let profile = Profile(name: "P", organizationId: "other", oauthAccountJSON: TeamFixtures.oauthAccountOrgA)
        let org = try XCTUnwrap(TeamTrackingMigration.migrate(profile).orgTracking?.orgs.first)
        XCTAssertEqual(org.orgId, "other")
        XCTAssertEqual(org.name, "Team")
    }

    // AC8
    func testNothingKnownUsesUnknownOrg() throws {
        let org = try XCTUnwrap(TeamTrackingMigration.migrate(Profile(name: "P")).orgTracking?.orgs.first)
        XCTAssertEqual(org.orgId, TrackedOrg.unknownOrgId)
        XCTAssertEqual(org.name, "Team")
    }

    func testMalformedAndEmptyOAuthJSONNeverThrow() throws {
        for json in ["", "{", "[1,2]", "null", #"{"organizationUuid":5}"#] {
            let org = try XCTUnwrap(TeamTrackingMigration.migrate(Profile(name: "P", oauthAccountJSON: json)).orgTracking?.orgs.first)
            XCTAssertEqual(org.orgId, TrackedOrg.unknownOrgId, json)
        }
    }

    // AC9
    func testIdempotentAndCodexUntouched() {
        let once = TeamTrackingMigration.migrate(Profile(name: "P", organizationId: "A"), now: now)
        let twice = TeamTrackingMigration.migrate(once, now: now.addingTimeInterval(500))
        XCTAssertEqual(once, twice)

        let codex = Profile(name: "C", provider: .codex)
        let migrated = TeamTrackingMigration.migrate(codex)
        XCTAssertEqual(migrated, codex)
        XCTAssertNil(migrated.orgTracking)
    }

    func testPairHistoryKey() {
        let id = UUID()
        XCTAssertEqual(TeamTrackingMigration.pairHistoryKey(profileId: id, orgId: "org-b_1"), "\(id.uuidString)_org-b_1")
    }
}
