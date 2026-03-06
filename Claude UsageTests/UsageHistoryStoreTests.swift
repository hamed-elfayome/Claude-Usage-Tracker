import XCTest
@testable import Claude_Usage

final class UsageHistoryStoreTests: XCTestCase {

    private var store: UsageHistoryStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        store = UsageHistoryStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - UsageSnapshot Codable Tests

    func testSnapshotEncodeDecode() throws {
        let now = Date()
        let snapshot = UsageSnapshot(date: now, percentage: 42.5)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded.percentage, 42.5)
        // ISO8601 loses sub-second precision, compare to nearest second
        XCTAssertEqual(decoded.date.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate, accuracy: 1.0)
    }

    func testSnapshotEquality() {
        let date = Date()
        let a = UsageSnapshot(date: date, percentage: 50.0)
        let b = UsageSnapshot(date: date, percentage: 50.0)
        let c = UsageSnapshot(date: date, percentage: 75.0)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Recording Tests

    func testRecordAndRetrieve() {
        store.record(25.0, for: .session)
        store.record(50.0, for: .session)

        let snapshots = store.snapshots(for: .session)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].percentage, 25.0)
        XCTAssertEqual(snapshots[1].percentage, 50.0)
    }

    func testRecordAllFromUsage() {
        let usage = ClaudeUsage(
            sessionTokensUsed: 500,
            sessionLimit: 1000,
            sessionPercentage: 50.0,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyTokensUsed: 200,
            weeklyLimit: 1000,
            weeklyPercentage: 20.0,
            weeklyResetTime: Date().addingTimeInterval(86400),
            opusWeeklyTokensUsed: 100,
            opusWeeklyPercentage: 10.0,
            sonnetWeeklyTokensUsed: 50,
            sonnetWeeklyPercentage: 5.0,
            sonnetWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )

        store.recordAll(from: usage)

        XCTAssertEqual(store.snapshots(for: .session).count, 1)
        XCTAssertEqual(store.snapshots(for: .session).first?.percentage, 50.0)
        XCTAssertEqual(store.snapshots(for: .weekly).first?.percentage, 20.0)
        XCTAssertEqual(store.snapshots(for: .opus).first?.percentage, 10.0)
        XCTAssertEqual(store.snapshots(for: .sonnet).first?.percentage, 5.0)
    }

    func testMetricsAreIsolated() {
        store.record(10.0, for: .session)
        store.record(90.0, for: .weekly)

        XCTAssertEqual(store.snapshots(for: .session).count, 1)
        XCTAssertEqual(store.snapshots(for: .session).first?.percentage, 10.0)
        XCTAssertEqual(store.snapshots(for: .weekly).count, 1)
        XCTAssertEqual(store.snapshots(for: .weekly).first?.percentage, 90.0)
        XCTAssertEqual(store.snapshots(for: .opus).count, 0)
    }

    // MARK: - Pruning Tests

    func testSessionPruningRemovesOldSnapshots() {
        let old = Date().addingTimeInterval(-(Constants.sessionWindow + 60))
        let recent = Date().addingTimeInterval(-60)

        store.record(10.0, for: .session, at: old)
        store.record(20.0, for: .session, at: recent)

        let snapshots = store.snapshots(for: .session)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.percentage, 20.0)
    }

    func testWeeklyPruningRemovesOldSnapshots() {
        let old = Date().addingTimeInterval(-(Constants.weeklyWindow + 60))
        let recent = Date().addingTimeInterval(-60)

        store.record(30.0, for: .weekly, at: old)
        store.record(60.0, for: .weekly, at: recent)

        let snapshots = store.snapshots(for: .weekly)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.percentage, 60.0)
    }

    func testBoundaryPruningKeepsExactEdge() {
        // Snapshot exactly at the window boundary should be kept
        let atBoundary = Date().addingTimeInterval(-Constants.sessionWindow + 1)
        store.record(15.0, for: .session, at: atBoundary)

        let snapshots = store.snapshots(for: .session)
        XCTAssertEqual(snapshots.count, 1)
    }

    func testBoundaryPruningRemovesJustPast() {
        // Snapshot just past the window should be removed
        let pastBoundary = Date().addingTimeInterval(-Constants.sessionWindow - 1)
        store.record(15.0, for: .session, at: pastBoundary)

        let snapshots = store.snapshots(for: .session)
        XCTAssertEqual(snapshots.count, 0)
    }

    // MARK: - Persistence Tests

    func testPersistenceAcrossInstances() {
        // Record data and wait for async persist to complete
        store.record(33.0, for: .session)
        store.flush()

        // Verify it was persisted by reading the JSON file directly,
        // avoiding a second UsageHistoryStore instance (which triggers a
        // Swift runtime dealloc crash in the test host environment).
        let fileURL = tempDir.appendingPathComponent("session_history.json")
        let data = try? Data(contentsOf: fileURL)
        XCTAssertNotNil(data, "History file should exist on disk")

        if let data = data {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshots = try? decoder.decode([UsageSnapshot].self, from: data)
            XCTAssertEqual(snapshots?.count, 1)
            XCTAssertEqual(snapshots?.first?.percentage, 33.0)
        }
    }

    // MARK: - Empty State Tests

    func testEmptyHistoryReturnsEmptyArray() {
        XCTAssertEqual(store.snapshots(for: .session), [])
        XCTAssertEqual(store.snapshots(for: .weekly), [])
        XCTAssertEqual(store.snapshots(for: .opus), [])
        XCTAssertEqual(store.snapshots(for: .sonnet), [])
    }

    func testClearAllRemovesEverything() {
        store.record(10.0, for: .session)
        store.record(20.0, for: .weekly)
        store.clearAll()

        XCTAssertEqual(store.snapshots(for: .session), [])
        XCTAssertEqual(store.snapshots(for: .weekly), [])
    }

    // MARK: - Edge Cases

    func testZeroPercentage() {
        store.record(0.0, for: .session)
        XCTAssertEqual(store.snapshots(for: .session).first?.percentage, 0.0)
    }

    func testHundredPercentage() {
        store.record(100.0, for: .session)
        XCTAssertEqual(store.snapshots(for: .session).first?.percentage, 100.0)
    }

    func testDeduplicationSkipsSamePercentage() {
        store.record(50.0, for: .session)
        store.record(50.0, for: .session)
        store.record(50.0, for: .session)

        XCTAssertEqual(store.snapshots(for: .session).count, 1)
    }

    func testDeduplicationRecordsDifferentPercentage() {
        store.record(50.0, for: .session)
        store.record(51.0, for: .session)
        store.record(51.0, for: .session)

        XCTAssertEqual(store.snapshots(for: .session).count, 2)
    }
}
