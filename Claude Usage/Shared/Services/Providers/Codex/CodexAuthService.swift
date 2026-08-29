//
//  CodexAuthService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-07-15.
//
//  Reads (and refreshes) the OpenAI Codex CLI's OAuth credentials from
//  `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`). Parsing, refresh, and
//  write-back behavior mirrors the Codex CLI itself, as implemented by the
//  MIT-licensed CodexBar project (github.com/steipete/codexbar).
//

import Foundation

/// Parsed Codex credentials. Two auth.json shapes exist:
/// - OAuth: `tokens.{access_token, refresh_token, id_token, account_id}` +
///   top-level `last_refresh` (keys may be snake_case or camelCase)
/// - API key: top-level `OPENAI_API_KEY` only (never refreshed)
struct CodexCredentials {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountId: String?
    var lastRefresh: Date?

    /// The Codex CLI refreshes tokens when the last refresh is older than
    /// 8 days (not based on JWT expiry).
    var needsRefresh: Bool {
        guard !refreshToken.isEmpty else { return false }
        guard let lastRefresh else { return true }
        let eightDays: TimeInterval = 8 * 24 * 60 * 60
        return Date().timeIntervalSince(lastRefresh) > eightDays
    }

    /// Account id for the `ChatGPT-Account-Id` header: explicit `account_id`,
    /// else the `chatgpt_account_id` JWT claim from the id/access token.
    var resolvedAccountId: String? {
        if let accountId, !accountId.isEmpty { return accountId }
        for token in [idToken, accessToken].compactMap({ $0 }) {
            if let claims = CodexAuthService.decodeJWTPayload(token) {
                if let id = claims["chatgpt_account_id"] as? String, !id.isEmpty { return id }
                if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
                   let id = auth["chatgpt_account_id"] as? String, !id.isEmpty { return id }
            }
        }
        return nil
    }

    /// Signed-in email from the id token, for display.
    var email: String? {
        for token in [idToken, accessToken].compactMap({ $0 }) {
            if let claims = CodexAuthService.decodeJWTPayload(token),
               let email = claims["email"] as? String, !email.isEmpty {
                return email
            }
        }
        return nil
    }
}

final class CodexAuthService {
    static let shared = CodexAuthService()

    private init() {}

    // MARK: - auth.json location

    /// `$CODEX_HOME/auth.json` when CODEX_HOME is set and non-empty,
    /// otherwise `~/.codex/auth.json`.
    func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        codexHomeURL(env: env).appendingPathComponent("auth.json")
    }

    func codexHomeURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let codexHome, !codexHome.isEmpty {
            return URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    func authFileExists() -> Bool {
        FileManager.default.fileExists(atPath: authFileURL().path)
    }

    // MARK: - Loading

    /// Loads credentials for a profile: a manually pasted JSON blob wins,
    /// otherwise the live auth.json file is read.
    func loadCredentials(for profile: Profile) throws -> CodexCredentials {
        if let manualJSON = profile.codexCredentialsJSON {
            guard let credentials = Self.parse(Data(manualJSON.utf8)) else {
                throw AppError(
                    code: .providerCredentialsNotFound,
                    message: "error.codex_credentials_invalid".localized,
                    technicalDetails: "Pasted Codex credentials could not be parsed",
                    isRecoverable: true,
                    recoverySuggestion: "error.codex_credentials_invalid.suggestion".localized
                )
            }
            return credentials
        }
        return try loadFromAuthFile()
    }

    func loadFromAuthFile() throws -> CodexCredentials {
        let url = authFileURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let credentials = Self.parse(data) else {
            throw AppError(
                code: .providerCredentialsNotFound,
                message: "error.codex_credentials_not_found".localized,
                technicalDetails: "No usable credentials at \(url.path)",
                isRecoverable: true,
                recoverySuggestion: "error.codex_credentials_not_found.suggestion".localized
            )
        }
        return credentials
    }

    /// Parses either auth.json shape. Returns nil when neither shape yields
    /// a usable access token.
    static func parse(_ data: Data) -> CodexCredentials? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        // Shape 1: API key only
        if let apiKey = json["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           json["tokens"] == nil {
            return CodexCredentials(accessToken: apiKey, refreshToken: "", idToken: nil, accountId: nil, lastRefresh: nil)
        }

        // Shape 2: OAuth tokens (snake_case or camelCase keys)
        guard let tokens = json["tokens"] as? [String: Any],
              let accessToken = stringValue(in: tokens, "access_token", "accessToken"),
              !accessToken.isEmpty else {
            // API key fallback even when an (empty) tokens dict exists
            if let apiKey = json["OPENAI_API_KEY"] as? String,
               !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CodexCredentials(accessToken: apiKey, refreshToken: "", idToken: nil, accountId: nil, lastRefresh: nil)
            }
            return nil
        }

        return CodexCredentials(
            accessToken: accessToken,
            refreshToken: stringValue(in: tokens, "refresh_token", "refreshToken") ?? "",
            idToken: stringValue(in: tokens, "id_token", "idToken"),
            accountId: stringValue(in: tokens, "account_id", "accountId"),
            lastRefresh: parseLastRefresh(json["last_refresh"])
        )
    }

    // MARK: - Refresh

    /// Refreshes credentials when stale (or when `force` is set, e.g. after a
    /// 401). Refreshed tokens are persisted: back to auth.json for file-based
    /// profiles (the Codex CLI rotates refresh tokens — keeping a rotated
    /// token only in memory could strand the CLI with a revoked one), or back
    /// to the profile's keychain field for manually pasted credentials.
    func refreshIfNeeded(
        _ credentials: CodexCredentials,
        for profile: Profile,
        force: Bool = false
    ) async throws -> CodexCredentials {
        guard (credentials.needsRefresh || force), !credentials.refreshToken.isEmpty else {
            return credentials
        }

        // Serialize refreshes per refresh token: OpenAI treats a second POST
        // with the same rotated refresh token as reuse and revokes the whole
        // token family — which would log out the user's Codex CLI. Concurrent
        // callers (background refresh + Test Connection, or two profiles
        // sharing auth.json) join the same in-flight task instead.
        let refreshTask: Task<CodexCredentials, Error> = await MainActor.run {
            if let existing = inflightRefreshes[credentials.refreshToken] {
                return existing
            }
            let task = Task<CodexCredentials, Error> {
                defer {
                    Task { @MainActor in
                        self.inflightRefreshes.removeValue(forKey: credentials.refreshToken)
                    }
                }
                let refreshed = try await self.refresh(credentials)
                self.persistRefreshed(refreshed, for: profile)
                return refreshed
            }
            inflightRefreshes[credentials.refreshToken] = task
            return task
        }

        return try await refreshTask.value
    }

    /// In-flight refresh tasks keyed by the refresh token being rotated.
    /// MainActor-confined for exclusive access.
    @MainActor private var inflightRefreshes: [String: Task<CodexCredentials, Error>] = [:]

    private func refresh(_ credentials: CodexCredentials) async throws -> CodexCredentials {
        var request = URLRequest(
            url: URL(string: Constants.APIEndpoints.codexTokenRefresh)!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": Self.oauthClientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        NetworkLoggerService.shared.logRequest(
            url: Constants.APIEndpoints.codexTokenRefresh,
            method: "POST",
            requestBody: nil,  // never log the refresh token
            responseData: nil,
            statusCode: statusCode,
            duration: Date().timeIntervalSince(startTime),
            error: nil
        )

        guard statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Self.refreshFailureError(statusCode: statusCode, data: data)
        }

        return CodexCredentials(
            accessToken: json["access_token"] as? String ?? credentials.accessToken,
            refreshToken: json["refresh_token"] as? String ?? credentials.refreshToken,
            idToken: json["id_token"] as? String ?? credentials.idToken,
            accountId: credentials.accountId,
            lastRefresh: Date()
        )
    }

    /// The Codex CLI's own OAuth client id (public; ships in the CLI).
    private static let oauthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private static func refreshFailureError(statusCode: Int?, data: Data) -> AppError {
        var errorCode: String?
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
                errorCode = code
            } else if let error = json["error"] as? String {
                errorCode = error
            } else {
                errorCode = json["code"] as? String
            }
        }

        let expiredCodes = ["refresh_token_expired", "refresh_token_reused", "invalid_grant", "refresh_token_invalidated"]
        if let errorCode, expiredCodes.contains(errorCode.lowercased()) {
            return AppError(
                code: .providerAuthExpired,
                message: "error.codex_auth_expired".localized,
                technicalDetails: "Token refresh rejected: \(errorCode)",
                isRecoverable: true,
                recoverySuggestion: "error.codex_auth_expired.suggestion".localized
            )
        }
        if statusCode == 401 {
            return AppError(
                code: .providerAuthExpired,
                message: "error.codex_auth_expired".localized,
                technicalDetails: "Token refresh returned 401",
                isRecoverable: true,
                recoverySuggestion: "error.codex_auth_expired.suggestion".localized
            )
        }
        return AppError(
            code: .providerAuthRefreshFailed,
            message: "error.codex_auth_refresh_failed".localized,
            technicalDetails: "Token refresh returned status \(statusCode.map(String.init) ?? "nil")",
            isRecoverable: true,
            recoverySuggestion: "error.codex_auth_expired.suggestion".localized
        )
    }

    // MARK: - Persisting refreshed tokens

    private func persistRefreshed(_ credentials: CodexCredentials, for profile: Profile) {
        if profile.codexCredentialsJSON != nil {
            // Manual-paste profile: persist to the profile's keychain field.
            // Serialization failure must NOT nil out the stored credentials,
            // and the write must patch the CURRENT profile (looked up by id
            // on the main actor) — `profile` is a value-type snapshot taken
            // before the network refresh, and writing it back wholesale would
            // clobber any name/settings edits made while the refresh was in
            // flight.
            guard let serialized = Self.serializeAuthJSON(credentials, mergingInto: profile.codexCredentialsJSON) else {
                LoggingService.shared.logError("Codex: failed to serialize refreshed tokens; keeping stored credentials")
                return
            }
            let profileId = profile.id
            Task { @MainActor in
                guard var current = ProfileManager.shared.profiles.first(where: { $0.id == profileId }) else { return }
                current.codexCredentialsJSON = serialized
                ProfileManager.shared.updateProfile(current)
            }
        } else {
            // File-based profile: write back to auth.json like the Codex CLI does.
            do {
                try writeBackToAuthFile(credentials)
            } catch {
                LoggingService.shared.logError("Codex: failed to write refreshed tokens to auth.json (non-fatal)", error: error)
            }
        }
    }

    /// Atomic write-back preserving unknown top-level keys: stage to a
    /// same-directory temp file with 0600 permissions, then rename over
    /// auth.json (matching the Codex CLI / CodexBar discipline).
    func writeBackToAuthFile(_ credentials: CodexCredentials) throws {
        let url = authFileURL()
        let existingData = try? Data(contentsOf: url)
        guard let serialized = Self.serializeAuthJSON(credentials, mergingInto: existingData.flatMap { String(data: $0, encoding: .utf8) }) else {
            throw AppError(code: .storageEncodingFailed, message: "Failed to serialize Codex credentials", isRecoverable: false)
        }
        let data = Data(serialized.utf8)

        let stagedURL = url.deletingLastPathComponent()
            .appendingPathComponent(".auth.json.claude-usage-staged-\(UUID().uuidString)")
        FileManager.default.createFile(
            atPath: stagedURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        do {
            let result = rename(stagedURL.path, url.path)
            guard result == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: stagedURL)
            throw error
        }
    }

    /// Serializes credentials into auth.json shape, merging into existing JSON
    /// so unknown top-level keys written by the Codex CLI are preserved.
    static func serializeAuthJSON(_ credentials: CodexCredentials, mergingInto existingJSON: String?) -> String? {
        var json: [String: Any] = [:]
        if let existingJSON,
           let existing = (try? JSONSerialization.jsonObject(with: Data(existingJSON.utf8))) as? [String: Any] {
            json = existing
        }

        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
        ]
        if let idToken = credentials.idToken { tokens["id_token"] = idToken }
        if let accountId = credentials.accountId { tokens["account_id"] = accountId }

        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: credentials.lastRefresh ?? Date())

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helpers

    /// Base64url-decodes a JWT's payload segment (no signature verification —
    /// we only read display metadata from tokens we already trust locally).
    static func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.components(separatedBy: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func stringValue(in dict: [String: Any], _ snakeKey: String, _ camelKey: String) -> String? {
        if let value = dict[snakeKey] as? String, !value.isEmpty { return value }
        if let value = dict[camelKey] as? String, !value.isEmpty { return value }
        return nil
    }

    private static func parseLastRefresh(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
