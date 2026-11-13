import XCTest
@testable import Claude_Usage

/// Runs the statusline script that gets installed, against a throwaway HOME,
/// to check the Fable weekly segment (#323) and the settings.json check (#191).
final class StatuslineFableSegmentTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("statusline-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func runScript(showFable: String?, cache: [String]) throws -> String {
        let claudeDir = home.appendingPathComponent(".claude")
        var config = ["SHOW_USAGE=1", "SHOW_USAGE_LABEL=1", "COLOR_MODE=monochrome"]
        if let showFable { config.append("SHOW_FABLE=\(showFable)") }
        try config.joined(separator: "\n").write(to: claudeDir.appendingPathComponent("statusline-config.txt"), atomically: true, encoding: .utf8)
        try cache.joined(separator: "\n").write(to: claudeDir.appendingPathComponent(".statusline-usage-cache"), atomically: true, encoding: .utf8)
        let script = claudeDir.appendingPathComponent("statusline-command.sh")
        try StatuslineService.shared.bashScript.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data("{}".utf8))
        stdin.fileHandleForWriting.closeFile()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    private func freshCache(_ extra: [String] = []) -> [String] {
        ["UTILIZATION=12", "RESETS_AT=2030-01-01T00:00:00Z", "TIMESTAMP=\(Int(Date().timeIntervalSince1970))"] + extra
    }

    func testFableSegmentIsShownWhenEnabledAndReported() throws {
        let output = try runScript(showFable: "1", cache: freshCache(["FABLE_UTILIZATION=24"]))
        XCTAssertTrue(output.contains("Fable: 24%"), output)
        XCTAssertTrue(output.contains("12%"), output)
    }

    func testFableSegmentIsHiddenWhenSwitchedOff() throws {
        XCTAssertFalse(try runScript(showFable: "0", cache: freshCache(["FABLE_UTILIZATION=24"])).contains("Fable"))
    }

    func testConfigWrittenBeforeTheOptionExistedKeepsItHidden() throws {
        XCTAssertFalse(try runScript(showFable: nil, cache: freshCache(["FABLE_UTILIZATION=24"])).contains("Fable"))
    }

    func testFableSegmentIsHiddenWhenTheAccountReportsNoFableLimit() throws {
        XCTAssertFalse(try runScript(showFable: "1", cache: freshCache()).contains("Fable"))
    }

    func testFableSegmentIsHiddenWhenTheCacheIsStale() throws {
        let stale = ["UTILIZATION=12", "RESETS_AT=2030-01-01T00:00:00Z",
                     "TIMESTAMP=\(Int(Date().timeIntervalSince1970) - 3600)", "FABLE_UTILIZATION=24"]
        XCTAssertFalse(try runScript(showFable: "1", cache: stale).contains("Fable"))
    }

    // MARK: - settings.json check (#191)

    func testOnlyOurStatuslineCommandCountsAsEnabled() {
        XCTAssertTrue(StatuslineService.statusLineUsesOurScript(
            ["statusLine": ["type": "command", "command": "bash /Users/me/.claude/statusline-command.sh"]]))
        XCTAssertFalse(StatuslineService.statusLineUsesOurScript(
            ["statusLine": ["type": "command", "command": "~/.config/my-statusline.sh"]]))
        XCTAssertFalse(StatuslineService.statusLineUsesOurScript([:]))
    }
}
