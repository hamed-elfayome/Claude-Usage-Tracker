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

        XCTAssertEqual(decoded.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.profiles.count, 1)
        XCTAssertEqual(decoded.profiles[0].name, "Test")
        XCTAssertEqual(decoded.profiles[0].provider, .claude)
        XCTAssertEqual(decoded.profiles[0].sessionPercentage, 42, accuracy: 0.01)
        // ISO8601 has second precision; anything closer is fine
        XCTAssertEqual(
            try XCTUnwrap(decoded.profiles[0].sessionResetTime).timeIntervalSince1970,
            try XCTUnwrap(snapshot.profiles[0].sessionResetTime).timeIntervalSince1970,
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

    func testWriteUsesOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotPermissions-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try WidgetSnapshot(generatedAt: Date(), profiles: [makeEntry()]).write(to: url)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let directoryMode = try XCTUnwrap(directoryAttributes[.posixPermissions] as? NSNumber).intValue
        let fileMode = try XCTUnwrap(fileAttributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
    }

    func testLoadRejectsOversizedSnapshotBeforeDecoding() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotOversized-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: WidgetSnapshot.maximumFileSize + 1).write(to: url)

        XCTAssertNil(WidgetSnapshot.load(from: url))
    }

    func testWriteRejectsUnsafeNumericValues() {
        let unsafe = makeEntry(sessionPercentage: Double.greatestFiniteMagnitude)
        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: [unsafe])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotUnsafe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try snapshot.write(to: directory.appendingPathComponent("snapshot.json")))
    }

    func testLoadRejectsUnsafeDecodedValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotUntrusted-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let unsafe = makeEntry(sessionPercentage: 10_001)
        let snapshot = WidgetSnapshot(generatedAt: Date(), profiles: [unsafe])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url)

        XCTAssertNil(WidgetSnapshot.load(from: url))
    }

    func testStalenessStartsAtExactBoundary() {
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let interval: TimeInterval = 900
        let snapshot = WidgetSnapshot(generatedAt: generatedAt, profiles: [])
        let profile = WidgetSnapshot.ProfileEntry(
            id: UUID(),
            name: "Test",
            isActive: true,
            isDisplayed: true,
            sessionPercentage: 42,
            sessionResetTime: nil,
            weeklyPercentage: nil,
            weeklyResetTime: nil,
            lastUpdated: generatedAt
        )

        XCTAssertFalse(snapshot.isStale(at: generatedAt.addingTimeInterval(interval - 0.001), interval: interval))
        XCTAssertTrue(snapshot.isStale(at: generatedAt.addingTimeInterval(interval), interval: interval))
        XCTAssertFalse(profile.isStale(at: generatedAt.addingTimeInterval(interval - 0.001), interval: interval))
        XCTAssertTrue(profile.isStale(at: generatedAt.addingTimeInterval(interval), interval: interval))
    }
}
