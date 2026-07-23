import XCTest
@testable import Claude_Usage

// MARK: - HookHTTPParser

final class HookHTTPParserTests: XCTestCase {

    private func request(_ method: String = "POST", path: String = "/hook/x/stop",
                         body: String = "{}", contentLength: Int? = nil) -> Data {
        let length = contentLength ?? body.utf8.count
        return Data("\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(length)\r\n\r\n\(body)".utf8)
    }

    func testCompleteRequestSinglePacket() {
        var parser = HookHTTPParser()
        let result = parser.feed(request(body: #"{"session_id":"s1"}"#))
        XCTAssertEqual(result, .request(method: "POST", path: "/hook/x/stop",
                                        body: Data(#"{"session_id":"s1"}"#.utf8)))
    }

    func testMultiPacketBody() {
        var parser = HookHTTPParser()
        let full = request(body: #"{"session_id":"s1","prompt":"hello world"}"#)
        // Feed byte-by-byte — must only complete at the end.
        var final: HookHTTPParser.ParseResult = .needMoreData
        for byte in full {
            final = parser.feed(Data([byte]))
            if case .request = final { break }
            XCTAssertEqual(final, .needMoreData)
        }
        guard case let .request(_, _, body) = final else {
            return XCTFail("expected complete request, got \(final)")
        }
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"session_id":"s1","prompt":"hello world"}"#)
    }

    func testNonPOSTRejected() {
        var parser = HookHTTPParser()
        XCTAssertEqual(parser.feed(request("GET", body: "")), .error(status: 405))
    }

    func testMissingContentLengthRejected() {
        var parser = HookHTTPParser()
        let raw = Data("POST /hook/x/stop HTTP/1.1\r\nHost: h\r\n\r\n{}".utf8)
        XCTAssertEqual(parser.feed(raw), .error(status: 400))
    }

    func testOversizedBodyRejected() {
        var parser = HookHTTPParser()
        let result = parser.feed(request(body: "{}", contentLength: 1_000_000))
        XCTAssertEqual(result, .error(status: 413))
    }

    func testOversizedHeaderRejected() {
        var parser = HookHTTPParser(maxHeaderBytes: 128, maxBodyBytes: 1024)
        let big = "POST /hook HTTP/1.1\r\nX-Junk: " + String(repeating: "a", count: 300)
        XCTAssertEqual(parser.feed(Data(big.utf8)), .error(status: 431))
    }
}

// MARK: - ToolActivityMapper

final class ToolActivityMapperTests: XCTestCase {

    func testBashMapsToRunningCommandWithTruncatedCommand() {
        let long = String(repeating: "x", count: 100)
        let result = ToolActivityMapper.map(toolName: "Bash", toolInput: ["command": long])
        XCTAssertEqual(result.status, .runningCommand)
        XCTAssertEqual(result.task.count, 60)
    }

    func testEditorToolsMapToWritingCode() {
        for tool in ["Write", "Edit", "MultiEdit", "NotebookEdit"] {
            let result = ToolActivityMapper.map(toolName: tool, toolInput: ["file_path": "/a/b/File.swift"])
            XCTAssertEqual(result.status, .writingCode, tool)
            XCTAssertTrue(result.task.contains("File.swift"), tool)
        }
    }

    func testReadToolsMapToReadingFiles() {
        XCTAssertEqual(ToolActivityMapper.map(toolName: "Read", toolInput: nil).status, .readingFiles)
        XCTAssertEqual(ToolActivityMapper.map(toolName: "Glob", toolInput: nil).status, .readingFiles)
        XCTAssertEqual(ToolActivityMapper.map(toolName: "Grep", toolInput: nil).status, .readingFiles)
    }

    func testUnknownToolFallsBackToThinkingWithToolName() {
        let result = ToolActivityMapper.map(toolName: "SomeMCPTool", toolInput: nil)
        XCTAssertEqual(result.status, .thinking)
        XCTAssertEqual(result.task, "SomeMCPTool")
    }
}

// MARK: - NotchHookEvent decoding

final class NotchHookEventTests: XCTestCase {

    func testEventRequiresSessionId() {
        XCTAssertNil(NotchHookEvent.from(pathSuffix: "stop", payload: [:]))
        XCTAssertNil(NotchHookEvent.from(pathSuffix: "stop", payload: ["session_id": ""]))
    }

    func testUnknownPathReturnsNil() {
        XCTAssertNil(NotchHookEvent.from(pathSuffix: "permission-request", payload: ["session_id": "s"]))
    }

    func testKnownEventsDecode() {
        XCTAssertEqual(NotchHookEvent.from(pathSuffix: "session-start",
                                           payload: ["session_id": "s", "cwd": "/p"]),
                       .sessionStart(id: "s", cwd: "/p"))
        XCTAssertEqual(NotchHookEvent.from(pathSuffix: "stop", payload: ["session_id": "s"]),
                       .stop(id: "s", cwd: nil))
        XCTAssertEqual(NotchHookEvent.from(pathSuffix: "notification",
                                           payload: ["session_id": "s", "message": "waiting"]),
                       .notification(id: "s", cwd: nil, message: "waiting"))
    }
}

// MARK: - NotchSessionStore reducer

@MainActor
final class NotchSessionStoreTests: XCTestCase {

    private var store: NotchSessionStore!

    override func setUp() async throws {
        store = NotchSessionStore()
    }

    func testOutOfOrderPreToolUseAutoCreatesSession() {
        store.apply(.preToolUse(id: "s1", cwd: "/proj", status: .runningCommand, task: "git status"))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].status, .runningCommand)
        XCTAssertEqual(store.sessions[0].displayName, "proj")
    }

    func testLateObservedSessionIsNamedFromAnyEventCwd() {
        // Sessions first seen mid-flight (tracker restart, sub-process without
        // a SessionStart) must not be stuck as "Session XXXXX".
        store.apply(.notification(id: "late", cwd: "/Users/dev/webapp", message: "waiting"))
        XCTAssertEqual(store.sessions[0].displayName, "webapp")

        store.apply(.stop(id: "sub", cwd: "/Users/dev/api-server"))
        XCTAssertEqual(store.sessions[1].displayName, "api-server")
    }

    func testNotificationSetsAttentionAndNextActivityClearsIt() {
        store.apply(.sessionStart(id: "s1", cwd: "/p"))
        store.apply(.notification(id: "s1", cwd: nil, message: "Claude needs your permission"))
        XCTAssertEqual(store.sessions[0].status, .needsAttention)

        store.apply(.preToolUse(id: "s1", cwd: nil, status: .runningCommand, task: "ls"))
        XCTAssertEqual(store.sessions[0].status, .runningCommand)
    }

    func testNotificationAfterStopKeepsSessionIdle() {
        store.apply(.sessionStart(id: "s1", cwd: nil))
        store.apply(.stop(id: "s1", cwd: nil))
        XCTAssertEqual(store.sessions[0].status, .idle)

        // Claude Code's "waiting for your input" nudge fires ~60s after Stop.
        // A finished session must stay idle so auto keep-awake doesn't re-arm
        // and hold the Mac awake until the terminal closes.
        store.apply(.notification(id: "s1", cwd: nil, message: "Claude is waiting for your input"))
        XCTAssertEqual(store.sessions[0].status, .idle)
    }

    func testStopSetsIdleAndSessionEndRemoves() {
        store.apply(.sessionStart(id: "s1", cwd: nil))
        store.apply(.stop(id: "s1", cwd: nil))
        XCTAssertEqual(store.sessions[0].status, .idle)
        store.apply(.sessionEnd(id: "s1"))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testToolFailureSetsErrorFlagAndPostToolUseClearsIt() {
        store.apply(.sessionStart(id: "s1", cwd: nil))
        store.apply(.toolFailure(id: "s1", cwd: nil))
        XCTAssertTrue(store.sessions[0].hasRecentError)
        store.apply(.postToolUse(id: "s1", cwd: nil))
        XCTAssertFalse(store.sessions[0].hasRecentError)
    }

    func testPrimarySessionPrefersAttention() {
        store.apply(.preToolUse(id: "busy", cwd: nil, status: .runningCommand, task: "build"))
        store.apply(.sessionStart(id: "waiting", cwd: nil))
        store.apply(.notification(id: "waiting", cwd: nil, message: "input needed"))
        XCTAssertEqual(store.primarySession?.id, "waiting")
    }

    func testStaleSweepRemovesOldSessionsWithAttentionGrace() {
        var fakeNow = Date()
        store.now = { fakeNow }

        store.apply(.sessionStart(id: "old", cwd: nil))
        store.apply(.sessionStart(id: "attention", cwd: nil))
        store.apply(.notification(id: "attention", cwd: nil, message: "waiting"))

        // 3 minutes later: normal session swept (120s), attention survives (600s grace)
        fakeNow = fakeNow.addingTimeInterval(180)
        store.sweepStaleSessions()
        XCTAssertEqual(store.sessions.map(\.id), ["attention"])

        // 11 minutes later: attention swept too
        fakeNow = fakeNow.addingTimeInterval(11 * 60)
        store.sweepStaleSessions()
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testPromptTruncatedTo80() {
        store.apply(.userPromptSubmit(id: "s1", cwd: nil, prompt: String(repeating: "p", count: 200)))
        XCTAssertEqual(store.sessions[0].lastUserPrompt?.count, 80)
    }
}
