//
//  ClearanceCookieTests.swift
//  Claude UsageTests
//
//  Cloudflare's cf_clearance is a partitioned cookie, which
//  HTTPCookieStorage.cookies(for:) does not return. These tests pin the jar
//  scan that puts it back into the claude.ai Cookie header.
//

import XCTest
@testable import Claude_Usage

final class ClearanceCookieTests: XCTestCase {
    private let host = "claude.ai"

    private func cookie(
        _ name: String,
        domain: String = ".claude.ai",
        value: String = "v",
        expires: Date? = Date().addingTimeInterval(3600),
        created: Double? = nil
    ) -> HTTPCookie {
        var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"]
        if let expires { props[.expires] = expires }
        if let created { props[HTTPCookiePropertyKey("Created")] = created }
        return HTTPCookie(properties: props)!
    }

    func testClearanceCookiesAreTakenFromTheJar() {
        let jar = [cookie("__cf_bm"), cookie("anthropic-device-id", domain: "claude.ai"), cookie("sessionKey"), cookie("cf_clearance")]
        let names = ClaudeAPIService.clearanceCookies(host: host, in: jar).map(\.name)
        XCTAssertEqual(names, ["__cf_bm", "anthropic-device-id", "cf_clearance"])
    }

    func testForeignDomainsAndExpiredCookiesAreIgnored() {
        let jar = [
            cookie("cf_clearance", domain: ".notclaude.ai"),
            cookie("cf_clearance", domain: "evil-claude.ai"),
            cookie("cf_clearance", expires: Date().addingTimeInterval(-60)),
            cookie("__cf_bm", domain: ".google.com"),
        ]
        XCTAssertTrue(ClaudeAPIService.clearanceCookies(host: host, in: jar).isEmpty)
    }

    func testCreationTimeBeatsExpiryWhenChoosingBetweenDuplicates() {
        let older = cookie("cf_clearance", value: "old", expires: Date().addingTimeInterval(7200), created: 100)
        let newer = cookie("cf_clearance", value: "new", expires: Date().addingTimeInterval(3600), created: 200)
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: host, in: [older, newer]).map(\.value), ["new"])
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: host, in: [newer, older]).map(\.value), ["new"])
    }

    func testLaterExpiryBreaksCreationTimeTies() {
        let shorter = cookie("cf_clearance", value: "short", expires: Date().addingTimeInterval(3600), created: 100)
        let longer = cookie("cf_clearance", value: "long", expires: Date().addingTimeInterval(7200), created: 100)
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: host, in: [shorter, longer]).map(\.value), ["long"])
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: host, in: [longer, shorter]).map(\.value), ["long"])
    }

    func testSessionKeyIsNeverPulledFromTheJar() {
        XCTAssertTrue(ClaudeAPIService.clearanceCookies(host: host, in: [cookie("sessionKey", value: "stale")]).isEmpty)
    }

    func testSubdomainMatchesDomainCookieButNotHostOnlyCookie() {
        let domainCookie = [cookie("cf_clearance", domain: ".claude.ai")]
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: "api.claude.ai", in: domainCookie).count, 1)
        let hostOnlyCookie = [cookie("cf_clearance", domain: "claude.ai")]
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: "api.claude.ai", in: hostOnlyCookie).count, 0)
        XCTAssertEqual(ClaudeAPIService.clearanceCookies(host: "claude.ai", in: hostOnlyCookie).count, 1)
    }

    /// End-to-end through `sessionCookieHeader` with a private jar. A Secure
    /// cookie queried through an http:// URL is a deterministic public stand-in
    /// for "present in the jar, absent from `cookies(for:)`" — exactly the
    /// shape of the partitioned cf_clearance bug.
    func testHeaderCarriesClearanceThatCookiesForURLWouldHide() throws {
        let storage = try XCTUnwrap(URLSessionConfiguration.ephemeral.httpCookieStorage)
        storage.setCookie(cookie("cf_clearance", value: "clearance"))
        storage.setCookie(cookie("__cf_bm", value: "bm"))
        let url = try XCTUnwrap(URL(string: "http://claude.ai/api/organizations"))
        // Precondition for the stand-in: the URL view must hide them.
        XCTAssertEqual(storage.cookies(for: url)?.count ?? 0, 0)

        let header = ClaudeAPIService.sessionCookieHeader(sessionKey: "sk-test", url: url, storage: storage)
        XCTAssertEqual(header, "sessionKey=sk-test; __cf_bm=bm; cf_clearance=clearance")
    }
}
