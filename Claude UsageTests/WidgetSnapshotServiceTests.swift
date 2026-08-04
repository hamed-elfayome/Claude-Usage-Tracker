import XCTest
@testable import Claude_Usage

final class WidgetSnapshotServiceTests: XCTestCase {

    /// Fixed reference clock so heartbeat/throttle behavior is deterministic.
    private var currentDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var writtenSnapshots: [WidgetSnapshot] = []
    private var reloadCount = 0

    private func makeService(
        heartbeatInterval: TimeInterval = 300,
        reloadInterval: TimeInterval = 60
    ) -> WidgetSnapshotService {
        WidgetSnapshotService(
            now: { self.currentDate },
            writeSnapshot: { self.writtenSnapshots.append($0) },
            requestReload: { self.reloadCount += 1 },
            heartbeatInterval: heartbeatInterval,
            reloadInterval: reloadInterval
        )
    }

    private func makeEntry(
        id: UUID = UUID(),
        name: String = "Test",
        sessionPercentage: Double = 42,
        weeklyPercentage: Double = 61
    ) -> WidgetSnapshot.ProfileEntry {
        WidgetSnapshot.ProfileEntry(
            id: id,
            name: name,
            isActive: true,
            isDisplayed: true,
            sessionPercentage: sessionPercentage,
            sessionResetTime: Date(timeIntervalSince1970: 1_700_010_000),
            weeklyPercentage: weeklyPercentage,
            weeklyResetTime: Date(timeIntervalSince1970: 1_700_080_000),
            lastUpdated: currentDate
        )
    }

    // MARK: - Change detection

    func testFirstPublishWritesAndReloads() {
        let service = makeService()
        service.publish(entries: [makeEntry()])

        XCTAssertEqual(writtenSnapshots.count, 1)
        XCTAssertEqual(reloadCount, 1)
    }

    func testSubPercentJitterDoesNotRewrite() {
        let service = makeService()
        let id = UUID()
        service.publish(entries: [makeEntry(id: id, sessionPercentage: 42.2)])
        currentDate += 30
        service.publish(entries: [makeEntry(id: id, sessionPercentage: 42.8)])

        XCTAssertEqual(writtenSnapshots.count, 1)
        XCTAssertEqual(reloadCount, 1)
    }

    func testWholePercentChangeRewrites() {
        let service = makeService()
        let id = UUID()
        service.publish(entries: [makeEntry(id: id, sessionPercentage: 42)])
        currentDate += 90
        service.publish(entries: [makeEntry(id: id, sessionPercentage: 43)])

        XCTAssertEqual(writtenSnapshots.count, 2)
        XCTAssertEqual(reloadCount, 2)
    }

    // MARK: - Heartbeat

    func testHeartbeatRewritesWithoutReload() {
        let service = makeService(heartbeatInterval: 300)
        service.publish(entries: [makeEntry()])
        let entry = writtenSnapshots[0].profiles[0]

        currentDate += 301
        service.publish(entries: [entry])

        XCTAssertEqual(writtenSnapshots.count, 2, "heartbeat must rewrite the snapshot")
        XCTAssertEqual(reloadCount, 1, "an unchanged heartbeat write must not spend a reload")
        XCTAssertEqual(writtenSnapshots[1].generatedAt, currentDate)
    }

    func testUnchangedBeforeHeartbeatDoesNotRewrite() {
        let service = makeService(heartbeatInterval: 300)
        service.publish(entries: [makeEntry()])
        let entry = writtenSnapshots[0].profiles[0]

        currentDate += 120
        service.publish(entries: [entry])

        XCTAssertEqual(writtenSnapshots.count, 1)
    }

    // MARK: - Reload throttling

    func testThrottledReloadIsDeferredNotDropped() {
        // Real (non-mocked) delay: the deferred reload is scheduled with
        // DispatchQueue.asyncAfter, so use a short real interval.
        let service = makeService(reloadInterval: 0.2)
        let id = UUID()
        service.publish(entries: [makeEntry(id: id, sessionPercentage: 10)])
        XCTAssertEqual(reloadCount, 1)

        // Meaningful change inside the throttle window: snapshot written,
        // reload deferred instead of dropped.
        service.publish(entries: [makeEntry(id: id, sessionPercentage: 50)])
        XCTAssertEqual(writtenSnapshots.count, 2)
        XCTAssertEqual(reloadCount, 1)

        let deadline = Date().addingTimeInterval(2)
        while reloadCount < 2 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(reloadCount, 2, "throttled reload must fire once the window reopens")
    }

    // MARK: - Profile name sanitization

    func testEmailShapedNameKeepsOnlyLocalPart() {
        XCTAssertEqual(WidgetSnapshotService.sanitizedProfileName("user@example.com"), "user")
    }

    func testPlainNameIsUnchanged() {
        XCTAssertEqual(WidgetSnapshotService.sanitizedProfileName("Work laptop"), "Work laptop")
    }

    func testAtWithoutDomainDotIsNotTreatedAsEmail() {
        XCTAssertEqual(WidgetSnapshotService.sanitizedProfileName("team@lab"), "team@lab")
    }

    func testLeadingAtIsNotTreatedAsEmail() {
        XCTAssertEqual(WidgetSnapshotService.sanitizedProfileName("@handle.dev"), "@handle.dev")
    }

    func testControlCharactersAreStrippedAndLengthCapped() {
        let raw = "bad\u{0000}name\n" + String(repeating: "x", count: 100)
        let sanitized = WidgetSnapshotService.sanitizedProfileName(raw)
        XCTAssertFalse(sanitized.contains("\u{0000}"))
        XCTAssertFalse(sanitized.contains("\n"))
        XCTAssertEqual(sanitized.count, 64)
        XCTAssertTrue(sanitized.hasPrefix("badname"))
    }
}
