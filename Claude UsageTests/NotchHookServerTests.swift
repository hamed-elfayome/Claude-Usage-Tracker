import XCTest
@testable import Claude_Usage

/// Live-socket integration tests for NotchHookServer. Skipped when the port is
/// occupied (e.g. a running copy of the app).
@MainActor
final class NotchHookServerTests: XCTestCase {

    private var token: String { SharedDataStore.shared.notchHUDPathToken() }
    private var base: String { "http://127.0.0.1:\(Constants.NotchHUD.port)" }

    override func setUp() async throws {
        NotchSessionStore.shared.reset()
        NotchHookServer.shared.start()
        // Wait for the listener to come up (or fail on a busy port).
        for _ in 0..<40 {
            if NotchSessionStore.shared.serverStatus == .running { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try XCTSkipUnless(NotchSessionStore.shared.serverStatus == .running,
                          "port \(Constants.NotchHUD.port) unavailable — another instance running?")
    }

    override func tearDown() async throws {
        NotchHookServer.shared.stop()
        NotchSessionStore.shared.reset()
    }

    private func post(_ path: String, json: String) async throws -> Int {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(json.utf8)
        request.timeoutInterval = 3
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as! HTTPURLResponse).statusCode
    }

    func testTokenedEventReachesStore() async throws {
        let sessionId = "itest-\(UUID().uuidString.prefix(6))"
        let status = try await post("/hook/\(token)/session-start",
                                    json: #"{"session_id":"\#(sessionId)","cwd":"/tmp/proj"}"#)
        XCTAssertEqual(status, 200)

        // Event delivery hops to the main actor; give it a beat.
        for _ in 0..<20 where !NotchSessionStore.shared.sessions.contains(where: { $0.id == sessionId }) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let session = NotchSessionStore.shared.sessions.first { $0.id == sessionId }
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.displayName, "proj")
    }

    func testLegacyTokenlessPathGets404AndIsDropped() async throws {
        let status = try await post("/hook/session-start",
                                    json: #"{"session_id":"legacy-spoof"}"#)
        XCTAssertEqual(status, 404)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(NotchSessionStore.shared.sessions.contains { $0.id == "legacy-spoof" })
    }

    func testWrongTokenGets404() async throws {
        let status = try await post("/hook/wrongtoken/stop", json: #"{"session_id":"x"}"#)
        XCTAssertEqual(status, 404)
    }

    func testGETRejected405() async throws {
        var request = URLRequest(url: URL(string: base + "/hook/\(token)/stop")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 405)
    }

    func testMalformedJSONStillGets200() async throws {
        let status = try await post("/hook/\(token)/stop", json: "{not json")
        XCTAssertEqual(status, 200, "malformed bodies must never punish Claude Code")
    }

    func testOversizeBodyGets200AndIsDropped() async throws {
        // Over the 1 MiB cap. The server must drain the wire and answer 200
        // (a 413 here is what used to paint hook errors into Claude Code
        // sessions on every large file Read), and the event must not land.
        let sessionId = "oversize-\(UUID().uuidString.prefix(6))"
        let padding = String(repeating: "a", count: Int(Constants.NotchHUD.maxBodyBytes) + 65_536)
        let status = try await post("/hook/\(token)/session-start",
                                    json: #"{"session_id":"\#(sessionId)","junk":"\#(padding)"}"#)
        XCTAssertEqual(status, 200, "over-cap bodies from an authorized sender must be acknowledged, not errored")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(NotchSessionStore.shared.sessions.contains { $0.id == sessionId },
                       "over-cap event must be dropped, not processed")
    }
}
