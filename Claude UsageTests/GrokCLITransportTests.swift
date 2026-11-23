import Darwin
import XCTest
@testable import Claude_Usage

@MainActor
final class GrokCLITransportTests: XCTestCase {
    func testBillingWaitsForInitializeAndIgnoresUnrelatedIDs() async throws {
        let cli = try executable("""
        IFS= read -r request
        case "$request" in *'"method":"initialize"'*) ;; *) exit 1 ;; esac
        case "$request" in *'"protocolVersion":1,'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"jsonrpc":"2.0","id":true,"error":{"message":"bad id"}}'
        printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"message":"not initialized"}}'
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        IFS= read -r request
        case "$request" in *'"method":"_x.ai/billing"'*) ;; *) exit 1 ;; esac
        printf '%s\\n' '{"jsonrpc":"2.0","method":"event","params":{"id":2}}'
        printf '%s\\n' '{"jsonrpc":"2.0","id":"2","error":{"message":"bad id"}}'
        printf '%s\\n' '{"jsonrpc":"2.0","id":12,"result":{"id":2}}'
        printf '%s\\n' '{"jsonrpc":"2.0", "id"   :   2, "result":{"config":{"creditUsagePercent":17,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}}'
        """)
        let payload = try await GrokCLIClient(executable: cli, home: cli.deletingLastPathComponent()).fetchBillingPayload()
        XCTAssertEqual(GrokBillingParser.quota(from: payload)?.usedPercent, 17)
    }

    func testConcurrentProfilesReadOnlyTheirOwnHome() async throws {
        let parentHome = ProcessInfo.processInfo.environment["GROK_HOME"]
        let cli = try executable(#"""
        [ "$*" = "agent --no-leader stdio" ] || exit 1
        [ -z "${XAI_API_KEY+x}" ] || exit 1
        IFS= read -r percent < "$GROK_HOME/quota" || exit 1
        IFS= read -r request || exit 1
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        IFS= read -r request || exit 1
        printf '{"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":%s,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}}\n' "$percent"
        """#)
        func home(_ name: String, percent: Int) throws -> URL {
            let url = cli.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try "\(percent)\n".write(to: url.appendingPathComponent("quota"), atomically: true, encoding: .utf8)
            return url
        }
        let first = GrokCLIClient(executable: cli, home: try home("first account", percent: 17))
        let second = GrokCLIClient(executable: cli, home: try home("second account", percent: 83))
        async let firstFetch = first.fetchBillingPayload()
        async let secondFetch = second.fetchBillingPayload()
        let (firstPayload, secondPayload) = try await (firstFetch, secondFetch)

        XCTAssertEqual(GrokBillingParser.quota(from: firstPayload)?.usedPercent, 17)
        XCTAssertEqual(GrokBillingParser.quota(from: secondPayload)?.usedPercent, 83)
        XCTAssertEqual(ProcessInfo.processInfo.environment["GROK_HOME"], parentHome)
    }

    func testAuthenticationErrorDuringBilling() async throws {
        let cli = try executable("""
        IFS= read -r init
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        IFS= read -r billing
        printf '%s\\n' '{"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"Run grok login to authenticate"}}'
        """)
        await assertFailure(.authenticationRequired, cli: cli)
    }

    func testInitializeErrorStopsBeforeBilling() async throws {
        let cli = try executable("""
        IFS= read -r init
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"error":{"message":"Authentication required"}}'
        IFS= read -r billing && printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{}}'
        """)
        await assertFailure(.authenticationRequired, cli: cli)
    }

    func testExitWithoutReplyIsUnavailable() async throws {
        await assertFailure(.unavailable, cli: try executable("exit 0"))
    }

    func testClosedInputBeforeBillingIsUnavailable() async throws {
        let cli = try executable("""
        IFS= read -r init
        exec 0<&-
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        exec /bin/sleep 60
        """)
        await assertFailure(.unavailable, cli: cli)
    }

    func testPendingNotificationsTimeOutAndChildIsReaped() async throws {
        let cli = try executable("""
        IFS= read -r init
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        IFS= read -r billing
        printf '%s\\n' '{"jsonrpc":"2.0","method":"event","params":{"id":2}}'
        \(unresponsiveChild)
        """)
        await assertFailure(.timedOut, cli: cli, timeout: 1)
        try assertChildExited(cli)
    }

    func testCancelReapsRunningChild() async throws {
        let cli = try executable(unresponsiveChild)
        let pidFile = cli.appendingPathExtension("pid")
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { @Sendable _, _ in
            FileManager.default.fileExists(atPath: pidFile.path)
        }, object: nil)
        let request = Task { try await GrokCLIClient(timeout: 30, executable: cli, home: cli.deletingLastPathComponent()).fetchBillingPayload() }
        await fulfillment(of: [started], timeout: 5)
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            try assertChildExited(cli)
        }
    }

    func testBooleanPercentIsNotNumericZeroOrOne() {
        func percent(_ literal: String) -> Double? {
            let data = Data("""
            {"config":{"creditUsagePercent":\(literal),"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}
            """.utf8)
            return GrokBillingParser.quota(from: data)?.usedPercent
        }
        XCTAssertNil(percent("false"))
        XCTAssertNil(percent("true"))
        XCTAssertEqual(percent("0"), 0)
        XCTAssertEqual(percent("1"), 1)
    }

    private var unresponsiveChild: String {
        """
        trap '' TERM INT
        printf '%s\\n' "$$" > "$0.pid"
        exec /bin/sleep 60
        """
    }

    private func executable(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("grok")
        try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func assertFailure(_ expected: GrokCLIError, cli: URL, timeout: TimeInterval = 5,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await GrokCLIClient(timeout: timeout, executable: cli, home: cli.deletingLastPathComponent()).fetchBillingPayload()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GrokCLIError, expected, file: file, line: line)
        }
    }

    private func assertChildExited(_ cli: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try String(contentsOf: cli.appendingPathExtension("pid"), encoding: .utf8)
        let pid = try XCTUnwrap(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        let status = kill(pid, 0)
        let error = errno
        XCTAssertEqual(status, -1, file: file, line: line)
        XCTAssertEqual(error, ESRCH, file: file, line: line)
    }
}
