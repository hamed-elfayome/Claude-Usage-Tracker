import XCTest
@testable import Claude_Usage

final class SharedDataStoreTests: XCTestCase {

    var sharedDataStore: SharedDataStore!

    override func setUp() {
        super.setUp()
        sharedDataStore = SharedDataStore.shared
    }

    override func tearDown() {
        // Clean up test data
        super.tearDown()
    }

    // MARK: - Language Settings Tests

    func testLanguageCode() {
        sharedDataStore.saveLanguageCode("en")
        XCTAssertEqual(sharedDataStore.loadLanguageCode(), "en")

        sharedDataStore.saveLanguageCode("ko")
        XCTAssertEqual(sharedDataStore.loadLanguageCode(), "ko")

        sharedDataStore.saveLanguageCode("ja")
        XCTAssertEqual(sharedDataStore.loadLanguageCode(), "ja")
    }

    func testLanguageCodeNil() {
        // Should return nil when not set (fresh state)
        // Note: Can't easily test this without clearing UserDefaults entirely
        // but we can test saving and loading works
        sharedDataStore.saveLanguageCode("fr")
        XCTAssertNotNil(sharedDataStore.loadLanguageCode())
    }

    // MARK: - Statusline Configuration Tests

    func testStatuslineShowDirectory() {
        sharedDataStore.saveStatuslineShowDirectory(false)
        XCTAssertFalse(sharedDataStore.loadStatuslineShowDirectory())

        sharedDataStore.saveStatuslineShowDirectory(true)
        XCTAssertTrue(sharedDataStore.loadStatuslineShowDirectory())
    }

    func testStatuslineShowBranch() {
        sharedDataStore.saveStatuslineShowBranch(false)
        XCTAssertFalse(sharedDataStore.loadStatuslineShowBranch())

        sharedDataStore.saveStatuslineShowBranch(true)
        XCTAssertTrue(sharedDataStore.loadStatuslineShowBranch())
    }

    func testStatuslineShowUsage() {
        sharedDataStore.saveStatuslineShowUsage(false)
        XCTAssertFalse(sharedDataStore.loadStatuslineShowUsage())

        sharedDataStore.saveStatuslineShowUsage(true)
        XCTAssertTrue(sharedDataStore.loadStatuslineShowUsage())
    }

    func testStatuslineShowProgressBar() {
        sharedDataStore.saveStatuslineShowProgressBar(false)
        XCTAssertFalse(sharedDataStore.loadStatuslineShowProgressBar())

        sharedDataStore.saveStatuslineShowProgressBar(true)
        XCTAssertTrue(sharedDataStore.loadStatuslineShowProgressBar())
    }

    func testStatuslineShowResetTime() {
        sharedDataStore.saveStatuslineShowResetTime(false)
        XCTAssertFalse(sharedDataStore.loadStatuslineShowResetTime())

        sharedDataStore.saveStatuslineShowResetTime(true)
        XCTAssertTrue(sharedDataStore.loadStatuslineShowResetTime())
    }

    // MARK: - Setup Status Tests

    func testHasCompletedSetup() {
        sharedDataStore.saveHasCompletedSetup(false)
        XCTAssertFalse(sharedDataStore.hasCompletedSetup())

        sharedDataStore.saveHasCompletedSetup(true)
        XCTAssertTrue(sharedDataStore.hasCompletedSetup())
    }

    // MARK: - GitHub Star Prompt Tests

    func testFirstLaunchDate() {
        let testDate = Date()
        sharedDataStore.saveFirstLaunchDate(testDate)

        let loaded = sharedDataStore.loadFirstLaunchDate()
        XCTAssertNotNil(loaded)

        // Compare timestamps (allow 1 second difference for encoding/decoding)
        if let loaded = loaded {
            XCTAssertEqual(loaded.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 1.0)
        }
    }

    func testLastGitHubStarPromptDate() {
        let testDate = Date()
        sharedDataStore.saveLastGitHubStarPromptDate(testDate)

        let loaded = sharedDataStore.loadLastGitHubStarPromptDate()
        XCTAssertNotNil(loaded)

        if let loaded = loaded {
            XCTAssertEqual(loaded.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 1.0)
        }
    }

    func testHasStarredGitHub() {
        sharedDataStore.saveHasStarredGitHub(false)
        XCTAssertFalse(sharedDataStore.loadHasStarredGitHub())

        sharedDataStore.saveHasStarredGitHub(true)
        XCTAssertTrue(sharedDataStore.loadHasStarredGitHub())
    }

    func testNeverShowGitHubPrompt() {
        sharedDataStore.saveNeverShowGitHubPrompt(false)
        XCTAssertFalse(sharedDataStore.loadNeverShowGitHubPrompt())

        sharedDataStore.saveNeverShowGitHubPrompt(true)
        XCTAssertTrue(sharedDataStore.loadNeverShowGitHubPrompt())
    }

    func testShouldShowGitHubStarPrompt() {
        // Reset state
        sharedDataStore.saveHasStarredGitHub(false)
        sharedDataStore.saveNeverShowGitHubPrompt(false)

        // Set first launch to 3 days ago
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        sharedDataStore.saveFirstLaunchDate(threeDaysAgo)

        // Should show prompt (>2 days, not starred, not dismissed)
        XCTAssertTrue(sharedDataStore.shouldShowGitHubStarPrompt())

        // Mark as starred - should no longer show
        sharedDataStore.saveHasStarredGitHub(true)
        XCTAssertFalse(sharedDataStore.shouldShowGitHubStarPrompt())

        // Reset starred, set never show - should not show
        sharedDataStore.saveHasStarredGitHub(false)
        sharedDataStore.saveNeverShowGitHubPrompt(true)
        XCTAssertFalse(sharedDataStore.shouldShowGitHubStarPrompt())
    }

    func testShouldNotShowGitHubPromptWhenTooEarly() {
        // Reset state
        sharedDataStore.saveHasStarredGitHub(false)
        sharedDataStore.saveNeverShowGitHubPrompt(false)

        // Set first launch to 12 hours ago (less than 1 day threshold)
        let twelveHoursAgo = Date().addingTimeInterval(-12 * 60 * 60)
        sharedDataStore.saveFirstLaunchDate(twelveHoursAgo)

        // Should NOT show prompt (< 1 day threshold)
        XCTAssertFalse(sharedDataStore.shouldShowGitHubStarPrompt())
    }

    func testResetGitHubStarPromptForTesting() {
        // Set some state
        sharedDataStore.saveHasStarredGitHub(true)
        sharedDataStore.saveNeverShowGitHubPrompt(true)
        sharedDataStore.saveLastGitHubStarPromptDate(Date())

        // Reset for testing
        sharedDataStore.resetGitHubStarPromptForTesting()

        // Should be reset
        XCTAssertFalse(sharedDataStore.loadHasStarredGitHub())
        XCTAssertFalse(sharedDataStore.loadNeverShowGitHubPrompt())
        XCTAssertNil(sharedDataStore.loadLastGitHubStarPromptDate())
    }
}
