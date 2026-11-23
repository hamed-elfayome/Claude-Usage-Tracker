import XCTest
@testable import Claude_Usage

final class WidgetSnapshotTests: XCTestCase {

    private func makeEntry(
        name: String = "Test",
        isActive: Bool = true,
        isDisplayed: Bool = true,
        sessionPercentage: Double = 42,
        weeklyPercentage: Double = 61,
        weeklyResetTime: Date? = Date(timeIntervalSince1970: 1_700_080_000)
    ) -> WidgetSnapshot.ProfileEntry {
        WidgetSnapshot.ProfileEntry(
            id: UUID(),
            name: name,
            isActive: isActive,
            isDisplayed: isDisplayed,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyPercentage: weeklyPercentage,
            weeklyResetTime: weeklyResetTime,
            lastUpdated: Date()
        )
    }

    // MARK: - Codable round trip

    func testSnapshotRoundTrip() throws {
        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: [makeEntry()])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].name, "Test")
        XCTAssertEqual(decoded.profiles[0].sessionPercentage, 42, accuracy: 0.01)
        // ISO8601 has second precision; anything closer is fine
        XCTAssertEqual(
            decoded.profiles[0].sessionResetTime.timeIntervalSince1970,
            snapshot.profiles[0].sessionResetTime.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    // MARK: - Snapshot location

    func testSnapshotURLIsOutsideAnyContainer() {
        // The widget reads via a home-relative-path exception entitlement, so
        // the path must resolve against the real user home, never a sandbox
        // container translocation.
        let path = WidgetSnapshot.snapshotURL.path
        XCTAssertFalse(path.contains("/Containers/"))
        XCTAssertTrue(path.hasSuffix("Library/Application Support/Claude Usage/widget/snapshot.json"))
    }

    // MARK: - Schema version

    func testLoadPreservesWeeklyDateFromVersionTwo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let fixture = """
            {"schemaVersion":2,"generatedAt":"2023-11-14T22:13:20Z","profiles":[{
              "id":"00000000-0000-0000-0000-000000000001","name":"Fixture","isActive":true,"isDisplayed":true,
              "sessionPercentage":0,"sessionResetTime":"2023-11-14T22:13:20Z","hasSessionLimit":false,
              "weeklyPercentage":23,"weeklyResetTime":"2023-11-14T22:13:20Z","lastUpdated":"2023-11-14T22:13:20Z"
            }]}
            """
        try Data(fixture.utf8).write(to: url)
        XCTAssertEqual(WidgetSnapshot.load(from: url)?.profiles.first?.weeklyResetTime,
                       Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testLoadRejectsUnknownSchemaVersion() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)")
            .appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var snapshot = WidgetSnapshot(generatedAt: Date(), profiles: [makeEntry()])
        snapshot.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        try snapshot.write(to: url)

        XCTAssertNil(WidgetSnapshot.load(from: url))
    }

    // MARK: - Write and load

    func testWriteAndLoad() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotTests-\(UUID().uuidString)")
            .appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: [makeEntry(name: "RoundTrip", weeklyResetTime: nil)])
        try snapshot.write(to: url)

        let loaded = WidgetSnapshot.load(from: url)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.profiles.first?.name, "RoundTrip")
        XCTAssertNil(loaded?.profiles.first?.weeklyResetTime)
    }
}
