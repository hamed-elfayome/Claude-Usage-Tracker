import XCTest
@testable import Claude_Usage

final class WidgetSnapshotTests: XCTestCase {

    private func makeEntry(
        name: String = "Test",
        isActive: Bool = true,
        isDisplayed: Bool = true,
        sessionPercentage: Double = 42,
        weeklyPercentage: Double = 61
    ) -> WidgetSnapshot.ProfileEntry {
        WidgetSnapshot.ProfileEntry(
            id: UUID(),
            name: name,
            isActive: isActive,
            isDisplayed: isDisplayed,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyPercentage: weeklyPercentage,
            weeklyResetTime: Date().addingTimeInterval(86400),
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

        XCTAssertEqual(decoded.schemaVersion, 1)
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

        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: [makeEntry(name: "RoundTrip")])
        try snapshot.write(to: url)

        let loaded = WidgetSnapshot.load(from: url)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.profiles.first?.name, "RoundTrip")
    }
}
