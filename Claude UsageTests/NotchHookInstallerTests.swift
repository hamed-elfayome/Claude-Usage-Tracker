import XCTest
@testable import Claude_Usage

final class NotchHookInstallerTests: XCTestCase {

    private var tempDir: URL!
    private var settingsURL: URL!
    private var installer: NotchHookInstaller!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-installer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        settingsURL = tempDir.appendingPathComponent("settings.json")
        installer = NotchHookInstaller(settingsURL: settingsURL, pathToken: { "testtoken" })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeSettings(_ json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: settingsURL)
    }

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func allOurURLs(in settings: [String: Any]) -> [String] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
        var urls: [String] = []
        for (_, value) in hooks {
            for group in (value as? [[String: Any]]) ?? [] {
                for hook in (group["hooks"] as? [[String: Any]]) ?? [] {
                    if let url = hook["url"] as? String, url.contains("19847") {
                        urls.append(url)
                    }
                }
            }
        }
        return urls
    }

    func testFreshInstallCreatesEightTokenedHooks() throws {
        XCTAssertEqual(installer.checkStatus(), .notInstalled)
        XCTAssertNoThrow(try installer.install().get())

        let settings = try readSettings()
        let urls = allOurURLs(in: settings)
        XCTAssertEqual(urls.count, 8)
        XCTAssertTrue(urls.allSatisfy { $0.contains("/hook/testtoken/") })
        XCTAssertFalse(urls.contains { $0.contains("permission-request") })
        XCTAssertEqual(installer.checkStatus(), .installed)
    }

    func testInstallPreservesForeignSettingsAndHooks() throws {
        try writeSettings([
            "model": "opus",
            "statusLine": ["type": "command", "command": "bash x.sh"],
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "/usr/local/bin/lint.sh"]]]
                ]
            ],
        ])

        XCTAssertNoThrow(try installer.install().get())
        let settings = try readSettings()

        XCTAssertEqual(settings["model"] as? String, "opus")
        XCTAssertNotNil(settings["statusLine"])

        let hooks = settings["hooks"] as! [String: Any]
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        // Foreign matcher group intact + our new group appended
        XCTAssertEqual(preToolUse.count, 2)
        let foreign = preToolUse.first { ($0["matcher"] as? String) == "Bash" }
        XCTAssertNotNil(foreign)
    }

    func testLegacyTenHookConfigDetectedAndReplaced() throws {
        // Mirrors the abandoned branch's tokenless 10-hook set (incl. the
        // blocking PermissionRequest hook) as found on real machines.
        func legacyEntry(_ suffix: String, timeout: Int = 3) -> [String: Any] {
            ["matcher": "", "hooks": [["type": "http",
                                       "url": "http://127.0.0.1:19847/hook/\(suffix)",
                                       "timeout": timeout]]]
        }
        try writeSettings([
            "hooks": [
                "SessionStart": [legacyEntry("session-start")],
                "SessionEnd": [legacyEntry("session-end")],
                "PreToolUse": [legacyEntry("pre-tool-use")],
                "PostToolUse": [legacyEntry("post-tool-use")],
                "PostToolUseFailure": [legacyEntry("post-tool-use-failure")],
                "UserPromptSubmit": [legacyEntry("user-prompt-submit")],
                "Stop": [legacyEntry("stop")],
                "Notification": [legacyEntry("notification")],
                "SubagentStart": [legacyEntry("subagent-start")],
                "PermissionRequest": [legacyEntry("permission-request", timeout: 30)],
            ]
        ])

        XCTAssertEqual(installer.checkStatus(), .legacyDetected)
        XCTAssertNoThrow(try installer.install().get())

        let settings = try readSettings()
        let urls = allOurURLs(in: settings)
        XCTAssertEqual(urls.count, 8, "legacy hooks must be fully replaced")
        XCTAssertTrue(urls.allSatisfy { $0.contains("/hook/testtoken/") })
        let hooks = settings["hooks"] as! [String: Any]
        XCTAssertNil(hooks["PermissionRequest"], "blocking legacy hook must be gone")
        XCTAssertNil(hooks["SubagentStart"])
        XCTAssertEqual(installer.checkStatus(), .installed)
    }

    func testUninstallRemovesOnlyOurHooks() throws {
        try writeSettings([
            "hooks": [
                "PreToolUse": [
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "lint.sh"]]]
                ]
            ]
        ])
        XCTAssertNoThrow(try installer.install().get())
        XCTAssertNoThrow(try installer.uninstall().get())

        let settings = try readSettings()
        XCTAssertTrue(allOurURLs(in: settings).isEmpty)
        let hooks = settings["hooks"] as! [String: Any]
        XCTAssertNotNil(hooks["PreToolUse"], "foreign hook must survive uninstall")
        XCTAssertNil(hooks["SessionStart"])
        XCTAssertEqual(installer.checkStatus(), .notInstalled)
    }

    func testUninstallOnMissingFileSucceeds() {
        XCTAssertNoThrow(try installer.uninstall().get())
    }

    func testPartialDetection() throws {
        XCTAssertNoThrow(try installer.install().get())
        // Remove one event to simulate manual tampering
        var settings = try readSettings()
        var hooks = settings["hooks"] as! [String: Any]
        hooks.removeValue(forKey: "Stop")
        settings["hooks"] = hooks
        try writeSettings(settings)

        XCTAssertEqual(installer.checkStatus(), .partial)
    }
}
