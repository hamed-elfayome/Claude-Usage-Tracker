import XCTest
import AppKit
@testable import Claude_Usage

final class CodexProPresentationTests: XCTestCase {
    @MainActor
    private func withProfile(_ profile: Profile, perform body: () throws -> Void) rethrows {
        let manager = ProfileManager.shared
        let previousProfile = manager.activeProfile
        let key = Constants.UserDefaultsKeys.menuBarIconConfiguration
        let previousConfig = UserDefaults.standard.object(forKey: key)
        manager.activeProfile = profile
        DataStore.shared.saveMenuBarIconConfiguration(profile.iconConfig)
        defer {
            manager.activeProfile = previousProfile
            if let previousConfig {
                UserDefaults.standard.set(previousConfig, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    @MainActor
    private func usage(plan: String? = "pro") -> ClaudeUsage {
        var usage = ClaudeUsage.empty
        usage.planType = plan
        usage.sessionPercentage = 99
        usage.sessionResetTime = Date().addingTimeInterval(3600)
        usage.weeklyPercentage = 17
        usage.weeklyResetTime = Date().addingTimeInterval(3 * 86400)
        return usage
    }

    @MainActor
    private func pixels(_ image: NSImage?) throws -> Data {
        let image = try XCTUnwrap(image)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try XCTUnwrap(cgImage.dataProvider?.data) as Data
    }

    @MainActor
    func testSessionOnlyConfigurationRendersWeeklyUsageWithoutChangingSettings() throws {
        for style in MenuBarIconStyle.allCases {
            for remaining in [false, true] {
                var config = MenuBarIconConfiguration.default
                config.metrics[0].iconStyle = style
                config.metrics[0].showNextSessionTime = true
                config.showRemainingPercentage = remaining
                // Include weekly time/pace markers and colors in the comparison.
                let profile = Profile(name: "Pro", provider: .codex, iconConfig: config)
                try withProfile(profile) {
                    let ui = StatusBarUIManager()
                    defer { ui.cleanup() }
                    ui.setup(target: self, action: #selector(NSObject.description), config: config)
                    let usage = usage()
                    ui.updateButton(for: .session, usage: usage, apiUsage: nil)
                    let button = try XCTUnwrap(ui.button(for: .session))
                    var weeklyConfig = config.metrics[0]
                    weeklyConfig.metricType = .week
                    let expected = MenuBarIconRenderer().createImage(
                        for: .week, config: weeklyConfig, globalConfig: config,
                        usage: usage, apiUsage: nil,
                        isDarkMode: button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                        colorMode: config.colorMode, singleColorHex: config.singleColorHex,
                        showIconName: config.showIconNames, showNextSessionTime: false
                    )
                    XCTAssertEqual(try pixels(button.image), try pixels(expected), "\(style), remaining=\(remaining)")
                    XCTAssertTrue(ui.primaryButton === button)
                    XCTAssertEqual(ProfileManager.shared.activeProfile?.iconConfig, config)
                }
            }
        }
    }

    @MainActor
    func testDuplicateSessionIconHidesAndReturnsWhenSwitchingAwayFromPro() throws {
        var config = MenuBarIconConfiguration.default
        config.metrics[1].isEnabled = true
        let profile = Profile(name: "Codex", provider: .codex, codexCredentialsJSON: "{}", iconConfig: config)
        try withProfile(profile) {
            let ui = StatusBarUIManager()
            defer { ui.cleanup() }
            ui.setup(target: self, action: #selector(NSObject.description), config: config)
            ui.updateAllButtons(usage: usage(), apiUsage: nil)
            let sessionButton = try XCTUnwrap(ui.button(for: .session))
            let weekButton = try XCTUnwrap(ui.button(for: .week))
            XCTAssertTrue(ui.primaryButton === weekButton, "Keyboard shortcuts must anchor to a visible icon")
            XCTAssertNil(sessionButton.image)
            XCTAssertNotNil(weekButton.image)

            for plan in ["plus", nil] {
                ui.updateAllButtons(usage: usage(plan: plan), apiUsage: nil)
                XCTAssertTrue(ui.primaryButton === sessionButton)
                XCTAssertNotNil(sessionButton.image)
                ui.updateAllButtons(usage: usage(), apiUsage: nil)
                XCTAssertTrue(ui.primaryButton === weekButton)
            }
            XCTAssertEqual(ProfileManager.shared.activeProfile?.iconConfig, config)
        }
    }

    @MainActor
    func testRemovingCredentialsRestoresDefaultLogoAfterHidingSessionIcon() {
        var config = MenuBarIconConfiguration.default
        config.metrics[1].isEnabled = true
        let profile = Profile(name: "Codex", provider: .codex, codexCredentialsJSON: "{}", iconConfig: config)
        withProfile(profile) {
            let ui = StatusBarUIManager()
            defer { ui.cleanup() }
            ui.setup(target: self, action: #selector(NSObject.description), config: config)
            ui.updateAllButtons(usage: usage(), apiUsage: nil)
            ProfileManager.shared.activeProfile = nil
            ui.updateAllButtons(usage: .empty, apiUsage: nil)
            XCTAssertTrue(ui.primaryButton === ui.button(for: .session))
            XCTAssertNotNil(ui.primaryButton?.image)
        }
    }

    @MainActor
    func testMultiProfileIconsUseWeeklyUsageAndIgnoreStaleSessionWindow() throws {
        let ui = StatusBarUIManager()
        defer { ui.cleanup() }
        var proUsage = usage()
        var pro = Profile(name: "Pro", provider: .codex, claudeUsage: proUsage)
        let plus = Profile(name: "Plus", provider: .codex, claudeUsage: usage(plan: "plus"))
        ui.setupMultiProfile(profiles: [pro, plus], target: self, action: #selector(NSObject.description))
        for style in MultiProfileIconStyle.allCases {
            for label in [false, true] {
                for remaining in [false, true] {
                    var config = MultiProfileDisplayConfig.default
                    config.iconStyle = style
                    config.showProfileLabel = label
                    config.showRemainingPercentage = remaining
                    config.showActiveProfileIndicator = false
                    config.showWeek = true
                    ui.updateMultiProfileButtons(profiles: [pro, plus], config: config)
                    let proButton = try XCTUnwrap(ui.button(for: pro.id))
                    let plusButton = try XCTUnwrap(ui.button(for: plus.id))
                    let initialPro = try pixels(proButton.image)
                    let initialPlus = try pixels(plusButton.image)
                    // Changing the stale five-hour values must not change Pro pixels.
                    proUsage.sessionPercentage = 1
                    proUsage.sessionResetTime = Date().addingTimeInterval(18000)
                    pro.claudeUsage = proUsage
                    ui.updateMultiProfileButtons(profiles: [pro, plus], config: config)
                    XCTAssertEqual(try pixels(proButton.image), initialPro)
                    XCTAssertEqual(try pixels(plusButton.image), initialPlus)
                    // Disabling the secondary weekly metric must not change Pro's
                    // single weekly indicator, including the concentric inner ring.
                    config.showWeek = false
                    ui.updateMultiProfileButtons(profiles: [pro, plus], config: config)
                    XCTAssertEqual(try pixels(proButton.image), initialPro)
                    if style != .compact {
                        XCTAssertNotEqual(try pixels(plusButton.image), initialPlus)
                    }
                    proUsage.weeklyPercentage = 81
                    pro.claudeUsage = proUsage
                    ui.updateMultiProfileButtons(profiles: [pro, plus], config: config)
                    XCTAssertNotEqual(try pixels(proButton.image), initialPro)
                    proUsage = usage()
                    pro.claudeUsage = proUsage
                }
            }
        }
    }

    @MainActor
    func testProClearsSessionNotificationTracking() {
        let key = "sentNotifications"
        let previous = UserDefaults.standard.object(forKey: key)
        let name = "Pro-\(UUID().uuidString)"
        let other = "Other-\(UUID().uuidString)_sessionCritical_95"
        UserDefaults.standard.set(["\(name)_sessionCritical_95", other], forKey: key)
        defer {
            NotificationManager.shared.clearNotificationsForProfile(name)
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        NotificationManager.shared.checkAndNotify(usage: usage(), profileName: name, settings: NotificationSettings())
        XCTAssertEqual(UserDefaults.standard.array(forKey: key) as? [String], [other])
    }

    @MainActor
    func testProHistorySkipsSessionRecordsButPreservesWeeklyRecords() {
        let id = UUID()
        let service = UsageHistoryService.shared
        defer { service.deleteHistory(for: id) }
        let proUsage = usage()
        service.recordSessionPeriodic(for: id, usage: proUsage, provider: .codex)
        service.recordSessionReset(for: id, previousUsage: proUsage, resetTime: Date(), provider: .codex)
        XCTAssertTrue(service.getSessionSnapshots(for: id).isEmpty)
        service.recordWeeklyPeriodic(for: id, usage: proUsage, provider: .codex)
        service.recordWeeklyReset(for: id, previousUsage: proUsage, resetTime: Date(), provider: .codex)
        XCTAssertEqual(service.getWeeklySnapshots(for: id).count, 2)
        service.recordSessionPeriodic(for: id, usage: usage(plan: "plus"), provider: .codex)
        XCTAssertEqual(service.getSessionSnapshots(for: id).count, 1)
    }
}
