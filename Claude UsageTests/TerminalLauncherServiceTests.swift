import XCTest
@testable import Claude_Usage

final class TerminalLauncherServiceTests: XCTestCase {

    private var tempHome: URL!
    private var service: TerminalLauncherService!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        service = TerminalLauncherService(homeDirectory: tempHome)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    // MARK: - Slugs

    func testSlugLowercasesAndDashesNonAlphanumerics() {
        let id = UUID()
        XCTAssertEqual(service.slug(for: "My Work Acct!", profileId: id), "my-work-acct")
        XCTAssertEqual(service.slug(for: "Xtnd", profileId: id), "xtnd")
        XCTAssertEqual(service.slug(for: "  spaced   out  ", profileId: id), "spaced-out")
        XCTAssertEqual(service.slug(for: "a__b--c", profileId: id), "a-b-c")
    }

    func testSlugFallsBackToIdForUnusableNames() {
        let id = UUID()
        let slug = service.slug(for: "日本語のみ", profileId: id)
        XCTAssertEqual(slug, String(id.uuidString.prefix(8)).lowercased())
        XCTAssertFalse(slug.isEmpty)
    }

    // MARK: - Install / uninstall

    func testInstallWritesExecutableScriptWithConfigDirAndMarker() throws {
        let profile = Profile(name: "Work Account")
        let slug = try service.install(for: profile)
        XCTAssertEqual(slug, "work-account")

        let script = service.scriptURL(forSlug: slug)
        let content = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(content.contains("CLAUDE_CONFIG_DIR=\"\(service.configDirectory(forSlug: slug).path)\""))
        XCTAssertTrue(content.contains(profile.id.uuidString), "marker must identify the owning profile")
        XCTAssertTrue(content.contains("exec claude \"$@\""))

        let attrs = try FileManager.default.attributesOfItem(atPath: script.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertEqual(perms & 0o777, 0o755)

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: service.configDirectory(forSlug: slug).path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testIsInstalledTracksMarkerOwnership() throws {
        var profile = Profile(name: "Alpha")
        profile.terminalLauncherSlug = try service.install(for: profile)
        XCTAssertTrue(service.isInstalled(profile))

        // A different profile claiming the same slug is NOT "installed".
        var impostor = Profile(name: "Alpha")
        impostor.terminalLauncherSlug = profile.terminalLauncherSlug
        XCTAssertFalse(service.isInstalled(impostor))
    }

    func testCollidingNamesGetIdSuffixedSlug() throws {
        let first = Profile(name: "Team")
        _ = try service.install(for: first)

        let second = Profile(name: "Team")
        let slug = service.availableSlug(for: second)
        XCTAssertNotEqual(slug, "team")
        XCTAssertTrue(slug.hasPrefix("team-"))
    }

    func testUninstallRemovesOnlyOwnScriptAndKeepsConfigDir() throws {
        var profile = Profile(name: "Keep My Login")
        let slug = try service.install(for: profile)
        profile.terminalLauncherSlug = slug

        service.uninstall(profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.scriptURL(forSlug: slug).path))
        // The config dir holds the profile's Claude Code login — never deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.configDirectory(forSlug: slug).path))
    }

    // MARK: - Keychain mapping

    func testExpectedKeychainServiceUsesPinnedHashAlgorithm() {
        let slug = "xtnd"
        let path = service.configDirectory(forSlug: slug).path
        let expectedHash = ClaudeCodeSyncService.shared.sha256HexPrefix(path, length: 8)
        XCTAssertEqual(service.expectedKeychainService(forSlug: slug),
                       "Claude Code-credentials-\(expectedHash)")
    }

    // MARK: - Profile model round trip

    func testTerminalLauncherSlugSurvivesEncodeDecode() throws {
        var profile = Profile(name: "Round Trip")
        profile.terminalLauncherSlug = "round-trip"
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded.terminalLauncherSlug, "round-trip")
    }
}
