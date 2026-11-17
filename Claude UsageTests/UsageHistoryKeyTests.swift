import XCTest
@testable import Claude_Usage

@MainActor
final class UsageHistoryKeyTests: XCTestCase {
    private var dir: URL!
    private var suite: String!
    private var defaults: UserDefaults!
    private var service: UsageHistoryService!

    override func setUp() async throws {
        try await super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("UsageHistoryKeyTests-\(UUID().uuidString)")
        suite = "UsageHistoryKeyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        service = UsageHistoryService(defaults: defaults, directory: dir)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
        try await super.tearDown()
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    private func usage() throws -> ClaudeUsage { try TeamFixtures.usage(session: 30, weekly: 10) }

    // AC10
    func testUUIDMethodWritesLegacyFileName() throws {
        let id = UUID()
        service.recordSessionPeriodic(for: id, usage: try usage())
        XCTAssertTrue(exists("usageHistory_\(id.uuidString).json"))
        XCTAssertEqual(service.getSessionSnapshots(for: id).count, 1)
    }

    // AC11
    func testKeyedMethodWritesPairFileOnly() throws {
        let id = UUID()
        service.recordSessionPeriodic(for: id, usage: try usage())
        let uuidFile = dir.appendingPathComponent("usageHistory_\(id.uuidString).json")
        let before = try Data(contentsOf: uuidFile)

        service.recordSessionPeriodic(forKey: "U_orgB", usage: try usage())
        XCTAssertTrue(exists("usageHistory_U_orgB.json"))
        XCTAssertEqual(try Data(contentsOf: uuidFile), before)
        XCTAssertEqual(service.getSessionSnapshots(forKey: "U_orgB").count, 1)
        XCTAssertEqual(service.getSessionSnapshots(for: id).count, 1)
    }

    // AC12
    func testThrottleIsPerKey() throws {
        let u = try usage()
        service.recordSessionPeriodic(forKey: "k1", usage: u)
        service.recordSessionPeriodic(forKey: "k2", usage: u)
        service.recordSessionPeriodic(forKey: "k1", usage: u)  // throttled
        XCTAssertEqual(service.getSessionSnapshots(forKey: "k1").count, 1)
        XCTAssertEqual(service.getSessionSnapshots(forKey: "k2").count, 1)
        service.recordWeeklyPeriodic(forKey: "k1", usage: u)
        service.recordWeeklyPeriodic(forKey: "k2", usage: u)
        XCTAssertEqual(service.getWeeklySnapshots(forKey: "k1").count, 1)
        XCTAssertEqual(service.getWeeklySnapshots(forKey: "k2").count, 1)
    }

    // AC13
    func testDeleteHistoryForKeyLeavesOthers() throws {
        let u = try usage()
        let key = "\(UUID().uuidString)-x_y"
        service.recordSessionPeriodic(forKey: key, usage: u)
        service.recordWeeklyPeriodic(forKey: key, usage: u)
        service.recordSessionPeriodic(forKey: "other", usage: u)
        service.recordWeeklyPeriodic(forKey: "other", usage: u)
        XCTAssertNotNil(defaults.object(forKey: "lastSessionRecordTime_\(key)"))

        service.deleteHistory(forKey: key)

        XCTAssertFalse(exists("usageHistory_\(key).json"))
        XCTAssertNil(defaults.object(forKey: "lastSessionRecordTime_\(key)"))
        XCTAssertNil(defaults.object(forKey: "lastWeeklyRecordTime_\(key)"))
        XCTAssertTrue(service.getSessionSnapshots(forKey: key).isEmpty)
        XCTAssertTrue(exists("usageHistory_other.json"))
        XCTAssertNotNil(defaults.object(forKey: "lastSessionRecordTime_other"))
        XCTAssertEqual(service.getSessionSnapshots(forKey: "other").count, 1)
    }

    func testResetRecordingByKey() throws {
        let u = try usage()
        service.recordSessionReset(forKey: "kr", previousUsage: u, resetTime: Date())
        service.recordWeeklyReset(forKey: "kr", previousUsage: u, resetTime: Date())
        XCTAssertEqual(service.getSessionSnapshots(forKey: "kr").count, 1)
        XCTAssertEqual(service.getWeeklySnapshots(forKey: "kr").count, 1)
        XCTAssertTrue(exists("usageHistory_kr.json"))
    }

    // MARK: FU-3 effectiveHistoryKey

    private func org(_ id: String) -> TrackedOrg {
        TrackedOrg(orgId: id, name: id, status: .member, historyKey: "k-\(id)", seat: nil, lastUsage: nil,
                   lastSampleAt: nil, firstSeenAt: Date(), lastSeenInListAt: nil, missingFromListCount: 0,
                   lastMembershipFailureAt: nil, pending: nil, baselineStartedAt: Date(), roundReading: nil)
    }

    private func profile(_ ids: [String], followed: String) -> Profile {
        var st = OrgTrackingState.empty
        st.orgs = ids.map(org)
        return Profile(name: "P", organizationId: followed, orgTracking: st)
    }

    func testDeletedSelectedKeyFallsBackToDefault() {
        // {A, B} with B selected, then B deleted (A and C remain).
        let p = profile(["A", "C"], followed: "A")
        XCTAssertEqual(TeamsSectionView.effectiveHistoryKey(selected: "k-B", profile: p), "k-A")
    }

    func testValidSelectedKeyIsKept() {
        let p = profile(["A", "B"], followed: "A")
        XCTAssertEqual(TeamsSectionView.effectiveHistoryKey(selected: "k-B", profile: p), "k-B")
        XCTAssertEqual(TeamsSectionView.effectiveHistoryKey(selected: nil, profile: p), "k-A")
    }

    func testSinglePairReturnsNil() {
        let p = profile(["A"], followed: "A")
        XCTAssertNil(TeamsSectionView.effectiveHistoryKey(selected: "k-B", profile: p))
        XCTAssertNil(TeamsSectionView.effectiveHistoryKey(selected: "k-A", profile: p))
    }
}
