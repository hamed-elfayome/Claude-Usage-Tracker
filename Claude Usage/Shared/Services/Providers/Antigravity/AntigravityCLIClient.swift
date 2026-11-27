//
//  AntigravityCLIClient.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-11-27.
//
//  Reads Antigravity quota by running the user's own `agy` CLI:
//
//      agy --print /usage --output-format json --print-timeout 30s
//
//  `/usage` in print mode runs no model turn (num_turns 0, 0 tokens) and
//  re-reads the quota from Google's backend on every new process. `agy` owns
//  its Google login; this app stores no Antigravity credential.
//
//  Observed behavior this client relies on (spike, 2026-11-27):
//  - Logged out, agy prints "Authentication required. Please visit the URL…"
//    on stderr, writes {"status":"ERROR",…} at the print timeout, and then
//    KEEPS WAITING for a browser login. So stderr is watched and the process
//    is stopped as soon as that line appears.
//  - stdout can contain the account email (the text `response` field), so it
//    is never logged; only status, exit code and byte counts are.
//

import Foundation

/// Fetches the raw `/usage` response. A protocol so the provider's shared
/// cache can be tested with a fake.
protocol AntigravityUsageFetching {
    func fetchUsage() async throws -> AntigravityUsageResponse
}

struct AntigravityCLIClient: AntigravityUsageFetching {

    var locator: AntigravityCLILocator = .shared
    /// Hard deadline for the whole process. A call takes ~4 s; a logged-out
    /// agy is stopped as soon as it prints its sign-in prompt.
    var timeout: TimeInterval = 30
    /// Passed to agy so it gives up (and answers) before our deadline.
    var printTimeoutSeconds: Int = 20
    /// Fixed working directory, so agy does not register a new workspace per run.
    var workingDirectory: URL = AntigravityCLIClient.defaultWorkingDirectory

    static var defaultWorkingDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Claude Usage/AgyProbe", isDirectory: true)
    }

    var arguments: [String] {
        ["--print", "/usage", "--output-format", "json", "--print-timeout", "\(printTimeoutSeconds)s"]
    }

    func fetchUsage() async throws -> AntigravityUsageResponse {
        guard let executable = await locator.resolve() else {
            throw Self.cliNotFoundError()
        }
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let result: AntigravityProcessResult
        do {
            result = try await AntigravityProcessRunner.run(
                executable: executable,
                arguments: arguments,
                currentDirectory: workingDirectory,
                timeout: timeout,
                stopWhen: { _, stderr in AntigravityOutputMarkers.containsAuthRequired(stderr) }
            )
        } catch {
            throw Self.cliNotFoundError(details: "launch failed: \(error)")
        }

        LoggingService.shared.logInfo(
            "Antigravity: agy /usage exit=\(result.exitCode.map(String.init) ?? "signal") "
            + "timedOut=\(result.timedOut) stoppedEarly=\(result.stoppedEarly) "
            + "stdout=\(result.stdout.count)B stderr=\(result.stderr.count)B"
        )
        return try Self.interpret(result)
    }

    // MARK: - Interpretation (pure, tested)

    static func interpret(_ result: AntigravityProcessResult) throws -> AntigravityUsageResponse {
        if AntigravityOutputMarkers.containsAuthRequired(result.stderr) {
            throw authRequiredError()
        }

        let response = try? JSONDecoder().decode(AntigravityUsageResponse.self, from: result.stdout)

        if let response {
            if response.isSuccess {
                guard !response.groups.isEmpty else {
                    throw AppError(
                        code: .apiParsingFailed,
                        message: "error.antigravity_unexpected_output".localized,
                        technicalDetails: "agy /usage returned SUCCESS without quota groups",
                        isRecoverable: true
                    )
                }
                return response
            }
            let errorText = response.error ?? ""
            if errorText.localizedCaseInsensitiveContains("authentication") {
                throw authRequiredError()
            }
            throw AppError(
                code: .apiGenericError,
                message: "error.antigravity_cli_failed".localized,
                technicalDetails: "agy /usage status=\(response.status ?? "nil") error=\(errorText.prefix(200))",
                isRecoverable: true
            )
        }

        if result.timedOut {
            throw AppError(
                code: .networkTimeout,
                message: "error.antigravity_timeout".localized,
                technicalDetails: "agy /usage did not finish in time",
                isRecoverable: true
            )
        }
        throw AppError(
            code: .apiParsingFailed,
            message: "error.antigravity_unexpected_output".localized,
            technicalDetails: "agy /usage exit=\(result.exitCode.map(String.init) ?? "signal"), stdout not JSON (\(result.stdout.count)B)",
            isRecoverable: true
        )
    }

    static func cliNotFoundError(details: String = "agy not found in AGY_BIN, ~/.local/bin, /opt/homebrew/bin, /usr/local/bin or the login shell PATH") -> AppError {
        AppError(
            code: .providerCredentialsNotFound,
            message: "error.antigravity_cli_not_found".localized,
            technicalDetails: details,
            isRecoverable: true,
            recoverySuggestion: "error.antigravity_cli_not_found.suggestion".localized
        )
    }

    static func authRequiredError() -> AppError {
        AppError(
            code: .providerAuthExpired,
            message: "error.antigravity_auth_required".localized,
            technicalDetails: "agy reported that authentication is required",
            isRecoverable: true,
            recoverySuggestion: "error.antigravity_auth_required.suggestion".localized
        )
    }
}
