//
//  KeepAwakeServiceTests.swift
//  Claude UsageTests
//
//  State-machine tests for KeepAwakeService using an injected clock and fake
//  assertion closures, mirroring the NotchSessionStore test idiom.
//

import XCTest
@testable import Claude_Usage

@MainActor
final class KeepAwakeServiceTests: XCTestCase {

    private var store: NotchSessionStore!
    private var service: KeepAwakeService!
    private var fakeNow: Date!
    private var createdModes: [KeepAwakeService.SleepMode] = []
    private var releasedIDs: [IOPMAssertionID] = []
    private var nextAssertionID: IOPMAssertionID = 0

    override func setUp() async throws {
        store = NotchSessionStore()
        service = KeepAwakeService(sessionStore: store)
        fakeNow = Date()
        createdModes = []
        releasedIDs = []
        nextAssertionID = 0

        store.now = { [unowned self] in fakeNow }
        service.now = { [unowned self] in fakeNow }
        service.createAssertion = { [unowned self] mode in
            createdModes.append(mode)
            nextAssertionID += 1
            return nextAssertionID
        }
        service.releaseAssertion = { [unowned self] id in
            releasedIDs.append(id)
        }
        // Neutral defaults; individual tests override via configure().
        configure(autoEnabled: false, sleepMode: .allowDisplaySleep, defaultDuration: 0, gracePeriod: 15 * 60)
        service.start()
    }

    private func configure(
        autoEnabled: Bool,
        sleepMode: KeepAwakeService.SleepMode = .allowDisplaySleep,
        defaultDuration: TimeInterval = 0,
        gracePeriod: TimeInterval = 15 * 60
    ) {
        service.loadSettings = {
            (autoEnabled: autoEnabled, sleepMode: sleepMode,
             defaultDuration: defaultDuration, gracePeriod: gracePeriod)
        }
        service.settingsChanged()
    }

    private func advance(_ seconds: TimeInterval) {
        fakeNow = fakeNow.addingTimeInterval(seconds)
    }

    // MARK: - Manual toggle

    func testManualOnCreatesOneAssertionWithDefaultMode() {
        service.setManual(on: true)

        XCTAssertTrue(service.isAssertionHeld)
        XCTAssertEqual(createdModes, [.allowDisplaySleep])
        XCTAssertNil(service.manualExpiry, "indefinite by default")

        service.setManual(on: false)
        XCTAssertFalse(service.isAssertionHeld)
        XCTAssertEqual(releasedIDs, [1])
    }

    func testReconcileIsIdempotent() {
        service.setManual(on: true)
        service.reconcile()
        service.reconcile()

        XCTAssertEqual(createdModes.count, 1, "repeated reconcile must not stack assertions")
        XCTAssertTrue(releasedIDs.isEmpty)
    }

    func testManualUsesPreventDisplaySleepWhenConfigured() {
        configure(autoEnabled: false, sleepMode: .preventDisplaySleep)
        service.setManual(on: true)
        XCTAssertEqual(createdModes, [.preventDisplaySleep])
    }

    // MARK: - Timed manual hold

    func testTimedManualExpiresAndReleases() {
        configure(autoEnabled: false, defaultDuration: 15 * 60)
        service.setManual(on: true)
        XCTAssertEqual(service.manualExpiry, fakeNow.addingTimeInterval(15 * 60))
        XCTAssertTrue(service.isAssertionHeld)

        advance(14 * 60)
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld, "still inside the window")

        advance(2 * 60)
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
        XCTAssertFalse(service.isManualOn)
        XCTAssertNil(service.manualExpiry)
        XCTAssertEqual(releasedIDs, [1])
    }

    func testCustomThreeHourDurationHonored() {
        configure(autoEnabled: false, defaultDuration: 3 * 60 * 60)
        service.setManual(on: true)

        advance(2 * 60 * 60 + 59 * 60)
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        advance(2 * 60)
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    // MARK: - Auto mode

    func testAutoHoldsWhileSessionActive() {
        configure(autoEnabled: true)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()

        XCTAssertTrue(service.isAssertionHeld)
        XCTAssertTrue(service.isAutoHolding)
    }

    func testAutoDisabledIgnoresSessions() {
        configure(autoEnabled: false)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testIdleSessionHeldThroughGraceThenReleased() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        store.apply(.stop(id: "s1"))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld, "grace period keeps the hold")

        advance(14 * 60)
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        advance(2 * 60)
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
        XCTAssertFalse(service.isAutoHolding)
    }

    func testSessionEndUsesGraceToo() {
        configure(autoEnabled: true, gracePeriod: 10 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()

        store.apply(.sessionEnd(id: "s1"))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        advance(11 * 60)
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testZeroGraceReleasesImmediately() {
        configure(autoEnabled: true, gracePeriod: 0)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        store.apply(.stop(id: "s1"))
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testCustomOneHourGraceHonored() {
        configure(autoEnabled: true, gracePeriod: 60 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        store.apply(.sessionEnd(id: "s1"))
        service.reconcile()

        advance(59 * 60)
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        advance(2 * 60)
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testActivityResumingMidGraceCancelsRelease() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        store.apply(.stop(id: "s1"))
        service.reconcile()

        advance(10 * 60)
        store.apply(.preToolUse(id: "s1", cwd: nil, status: .runningCommand, task: "build"))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        // Old grace deadline passes; hold survives because activity resumed.
        advance(6 * 60)
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)
        XCTAssertEqual(createdModes.count, 1, "hold never dropped, so never re-created")
    }

    // MARK: - Manual + auto composition

    func testManualOutlivesAutoGoingIdle() {
        configure(autoEnabled: true, gracePeriod: 0)
        service.setManual(on: true)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()

        store.apply(.stop(id: "s1"))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld, "manual keeps holding after auto drops")
        XCTAssertFalse(service.isAutoHolding)

        service.setManual(on: false)
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testAutoOutlivesManualTurningOff() {
        configure(autoEnabled: true, gracePeriod: 0)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        service.setManual(on: true)

        service.setManual(on: false)
        XCTAssertTrue(service.isAssertionHeld, "auto keeps holding after manual off")
        XCTAssertTrue(service.isAutoHolding)

        store.apply(.sessionEnd(id: "s1"))
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testOverlapNeverDoubleCreates() {
        configure(autoEnabled: true, gracePeriod: 0)
        service.setManual(on: true)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        service.reconcile()

        XCTAssertEqual(createdModes.count, 1)
        XCTAssertTrue(releasedIDs.isEmpty)
    }

    // MARK: - Smart toggle (popover button)

    func testSmartToggleStartsManualWhenIdle() {
        service.smartToggle()
        XCTAssertTrue(service.isManualOn)
        XCTAssertTrue(service.isAssertionHeld)
    }

    func testSmartToggleTurnsOffManual() {
        service.setManual(on: true)
        service.smartToggle()
        XCTAssertFalse(service.isManualOn)
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testSmartToggleDismissesAutoHoldUntilNextActivity() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        XCTAssertTrue(service.isAutoHolding)

        service.smartToggle()
        XCTAssertFalse(service.isAssertionHeld)

        // The same continuous burst of work stays dismissed…
        store.apply(.preToolUse(id: "s1", cwd: nil, status: .runningCommand, task: "build"))
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)

        // …including its grace window after it stops…
        store.apply(.stop(id: "s1"))
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)

        // …but Claude picking work back up resumes auto mode.
        store.apply(.preToolUse(id: "s1", cwd: nil, status: .writingCode, task: "edit"))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)
        XCTAssertTrue(service.isAutoHolding)
    }

    func testSmartToggleCycleResumesAutoHoldNotManual() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        XCTAssertTrue(service.isAutoHolding)

        service.smartToggle()
        XCTAssertFalse(service.isAssertionHeld)

        service.smartToggle()
        XCTAssertTrue(service.isAutoHolding, "cycling off/on returns to the auto hold")
        XCTAssertFalse(service.isManualOn, "no manual hold should be created")
    }

    func testSmartToggleCycleResumesAutoGraceWindow() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        store.apply(.stop(id: "s1"))
        service.reconcile()
        XCTAssertNotNil(service.autoGraceExpiry)

        service.smartToggle()
        XCTAssertFalse(service.isAssertionHeld)

        advance(5 * 60)
        service.smartToggle()
        XCTAssertTrue(service.isAutoHolding, "still inside the grace window → auto resumes")
        XCTAssertFalse(service.isManualOn)
    }

    func testSmartToggleFallsBackToManualWhenAutoHasNothingToHold() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        store.apply(.stop(id: "s1"))
        service.reconcile()

        service.smartToggle()
        advance(16 * 60)
        service.smartToggle()
        XCTAssertTrue(service.isManualOn, "grace expired while dismissed → manual hold")
        XCTAssertTrue(service.isAssertionHeld)
    }

    func testMenuDurationOverridesDefault() {
        configure(autoEnabled: false, defaultDuration: 0)
        service.setManual(on: true, duration: 3600)
        XCTAssertEqual(service.manualExpiry, fakeNow.addingTimeInterval(3600))

        advance(61 * 60)
        service.reconcile()
        XCTAssertFalse(service.isAssertionHeld)
    }

    func testAutoGraceExpiryPublishedDuringGraceOnly() {
        configure(autoEnabled: true, gracePeriod: 15 * 60)
        store.apply(.sessionStart(id: "s1", cwd: nil))
        service.reconcile()
        XCTAssertNil(service.autoGraceExpiry, "nil while actively working")

        store.apply(.stop(id: "s1"))
        service.reconcile()
        XCTAssertEqual(service.autoGraceExpiry, fakeNow.addingTimeInterval(15 * 60))
    }

    // MARK: - Sleep-mode change

    func testSleepModeChangeWhileHeldReacquiresOnce() {
        service.setManual(on: true)
        XCTAssertEqual(createdModes, [.allowDisplaySleep])

        configure(autoEnabled: false, sleepMode: .preventDisplaySleep)

        XCTAssertEqual(createdModes, [.allowDisplaySleep, .preventDisplaySleep])
        XCTAssertEqual(releasedIDs, [1], "exactly one release + one re-create")
        XCTAssertTrue(service.isAssertionHeld)
    }

    // MARK: - Stale sweep integration

    func testStaleSweepReleasesCrashedSessionHold() {
        configure(autoEnabled: true, gracePeriod: 0)
        store.apply(.sessionStart(id: "crashed", cwd: nil))
        service.reconcile()
        XCTAssertTrue(service.isAssertionHeld)

        // Session process died without sessionEnd: no events ever again.
        advance(Constants.NotchHUD.staleSessionTimeout + 60)
        store.sweepStaleSessions()
        service.reconcile()

        XCTAssertFalse(service.isAssertionHeld, "sweep must not leave the Mac awake forever")
    }

    // MARK: - Lifecycle

    func testStopReleasesEverything() {
        service.setManual(on: true)
        service.stop()

        XCTAssertFalse(service.isAssertionHeld)
        XCTAssertFalse(service.isManualOn)
        XCTAssertEqual(releasedIDs, [1])
    }
}
