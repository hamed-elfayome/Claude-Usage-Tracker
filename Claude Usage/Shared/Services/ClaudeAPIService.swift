import Foundation

/// Service for fetching usage data directly from Claude's API
class ClaudeAPIService: APIServiceProtocol {
    // MARK: - Types

    /// Authentication method for API requests
    private enum AuthenticationType {
        case claudeAISession(String)      // Cookie: sessionKey=...
        case cliOAuth(String)              // Authorization: Bearer ... (with anthropic-beta header)
        case consoleAPISession(String)     // Cookie: sessionKey=... (different endpoint)
    }

    // MARK: - Properties

    private let sessionKeyPath: URL
    private let sessionKeyValidator: SessionKeyValidator
    let baseURL = Constants.APIEndpoints.claudeBase
    let consoleBaseURL = Constants.APIEndpoints.consoleBase

    // MARK: - Initialization

    init(sessionKeyPath: URL? = nil, sessionKeyValidator: SessionKeyValidator = SessionKeyValidator()) {
        // Default path: ~/.claude-session-key
        self.sessionKeyPath = sessionKeyPath ?? Constants.ClaudePaths.homeDirectory
            .appendingPathComponent(".claude-session-key")
        self.sessionKeyValidator = sessionKeyValidator
    }

    // MARK: - Session Key Management

    /// Reads and validates the session key from active profile
    private func readSessionKey() throws -> String {
        do {
            // Load from active profile only
            guard let activeProfile = ProfileManager.shared.activeProfile else {
                LoggingService.shared.logError("ClaudeAPIService.readSessionKey: No active profile")
                throw AppError.sessionKeyNotFound()
            }

            LoggingService.shared.log("ClaudeAPIService.readSessionKey: Profile '\(activeProfile.name)'")
            LoggingService.shared.log("  - claudeSessionKey: \(activeProfile.claudeSessionKey == nil ? "NIL" : "EXISTS (len: \(activeProfile.claudeSessionKey!.count))")")

            guard let key = activeProfile.claudeSessionKey else {
                LoggingService.shared.logError("ClaudeAPIService.readSessionKey: Profile has NIL claudeSessionKey - throwing sessionKeyNotFound")
                throw AppError.sessionKeyNotFound()
            }

            let validatedKey = try sessionKeyValidator.validate(key)
            LoggingService.shared.log("ClaudeAPIService.readSessionKey: Key validated successfully")
            return validatedKey

        } catch let error as SessionKeyValidationError {
            // Convert validation errors to AppError
            throw AppError.wrap(error)
        } catch let error as AppError {
            // Re-throw AppError as-is
            throw error
        } catch {
            let appError = AppError(
                code: .storageReadFailed,
                message: "Failed to read session key from profile",
                technicalDetails: error.localizedDescription,
                underlyingError: error,
                isRecoverable: true,
                recoverySuggestion: "Please check your session key configuration in the active profile"
            )
            ErrorLogger.shared.log(appError)
            throw appError
        }
    }

    /// Gets the best available authentication method with fallback support
    /// Priority: 1) claude.ai session → 2) saved CLI OAuth → 3) system Keychain CLI OAuth
    /// Note: Console API session is NOT used as fallback (it only provides billing data, not usage)
    private func getAuthentication() throws -> AuthenticationType {
        guard let activeProfile = ProfileManager.shared.activeProfile else {
            LoggingService.shared.logError("ClaudeAPIService.getAuthentication: No active profile")
            throw AppError.sessionKeyNotFound()
        }

        // Try claude.ai session key first
        if let sessionKey = activeProfile.claudeSessionKey {
            do {
                let validatedKey = try sessionKeyValidator.validate(sessionKey)
                LoggingService.shared.log("ClaudeAPIService: Using claude.ai session key")
                return .claudeAISession(validatedKey)
            } catch {
                LoggingService.shared.logError("ClaudeAPIService: claude.ai session key validation failed: \(error.localizedDescription)")
            }
        }

        // Fall back to saved CLI OAuth token if available and not expired
        if let cliJSON = activeProfile.cliCredentialsJSON {
            if !ClaudeCodeSyncService.shared.isTokenExpired(cliJSON),
               let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: cliJSON) {
                LoggingService.shared.log("ClaudeAPIService: Falling back to saved CLI OAuth token")
                return .cliOAuth(accessToken)
            } else {
                LoggingService.shared.log("ClaudeAPIService: Saved CLI OAuth token is expired or invalid")
            }
        }

        // Fall back to reading CLI credentials directly from system Keychain
        do {
            if let systemCredentials = try ClaudeCodeSyncService.shared.readSystemCredentials() {
                LoggingService.shared.log("ClaudeAPIService: Found CLI credentials in system Keychain")

                // Validate token is not expired
                if ClaudeCodeSyncService.shared.isTokenExpired(systemCredentials) {
                    LoggingService.shared.log("ClaudeAPIService: System Keychain CLI token is expired")
                } else if let accessToken = ClaudeCodeSyncService.shared.extractAccessToken(from: systemCredentials) {
                    LoggingService.shared.log("ClaudeAPIService: Using CLI credentials from system Keychain")
                    return .cliOAuth(accessToken)
                } else {
                    LoggingService.shared.log("ClaudeAPIService: Could not extract access token from system Keychain credentials")
                }
            } else {
                LoggingService.shared.log("ClaudeAPIService: No CLI credentials found in system Keychain")
            }
        } catch {
            LoggingService.shared.log("ClaudeAPIService: Could not read system CLI credentials: \(error.localizedDescription)")
        }

        LoggingService.shared.logError("ClaudeAPIService.getAuthentication: No valid credentials for usage data")
        throw AppError.sessionKeyNotFound()
    }

    /// Builds an authenticated request with the appropriate headers for the auth type
    private func buildAuthenticatedRequest(url: URL, auth: AuthenticationType) -> URLRequest {
        var request = URLRequest(url: url)

        switch auth {
        case .claudeAISession(let sessionKey):
            // Existing claude.ai authentication
            request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")

        case .cliOAuth(let accessToken):
            // CLI OAuth authentication (requires specific headers)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("claude-code/2.1.5", forHTTPHeaderField: "User-Agent")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        case .consoleAPISession(let apiKey):
            // Console API authentication
            request.setValue("sessionKey=\(apiKey)", forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        return request
    }

    /// Saves a session key with smart org ID preservation
    /// Only clears org ID if the key actually changed
    func saveSessionKey(_ key: String, preserveOrgIfUnchanged: Bool = true) throws {
        do {
            // Validate the key before saving
            let validatedKey = try sessionKeyValidator.validate(key)

            guard let profileId = ProfileManager.shared.activeProfile?.id else {
                throw AppError(
                    code: .storageWriteFailed,
                    message: "No active profile found",
                    technicalDetails: "Cannot save session key without an active profile",
                    isRecoverable: true,
                    recoverySuggestion: "Please ensure a profile is active"
                )
            }

            // Check if key actually changed (for smart org clearing)
            var shouldClearOrg = true
            if preserveOrgIfUnchanged {
                let existingKey = ProfileManager.shared.activeProfile?.claudeSessionKey
                shouldClearOrg = (existingKey != validatedKey)
            }

            // Save to active profile
            var credentials = (try? ProfileManager.shared.loadCredentials(for: profileId)) ?? ProfileCredentials()
            credentials.claudeSessionKey = validatedKey
            try ProfileManager.shared.saveCredentials(for: profileId, credentials: credentials)

            LoggingService.shared.log("Session key saved to active profile")

            // Only clear org ID if key actually changed
            if shouldClearOrg {
                clearOrganizationIdCache()
                ProfileManager.shared.updateOrganizationId(nil, for: profileId)
                LoggingService.shared.log("Session key changed - cleared organization ID")
            } else {
                LoggingService.shared.log("Session key unchanged - preserving organization ID")
            }

        } catch let error as SessionKeyValidationError {
            // Convert validation errors to AppError
            throw AppError.wrap(error)
        } catch {
            // Keychain errors
            let appError = AppError(
                code: .sessionKeyStorageFailed,
                message: "Failed to save session key",
                technicalDetails: error.localizedDescription,
                underlyingError: error,
                isRecoverable: true,
                recoverySuggestion: "Please check Keychain access and try again"
            )
            ErrorLogger.shared.log(appError)
            throw appError
        }
    }

    // MARK: - Organization ID Caching

    /// Cache organization ID to reduce API calls
    private var cachedOrgId: String?
    private var cachedOrgIdSessionKey: String?

    /// Clears the cached organization ID (call when session key changes)
    func clearOrganizationIdCache() {
        cachedOrgId = nil
        cachedOrgIdSessionKey = nil
    }

    // MARK: - API Requests

    /// Fetches all organizations for the authenticated user
    func fetchAllOrganizations(sessionKey: String? = nil) async throws -> [AccountInfo] {
        return try await ErrorRecovery.shared.executeWithRetry(maxAttempts: 3) {
            let sessionKey = try sessionKey ?? self.readSessionKey()

            // Build URL safely
            let url: URL
            do {
                url = try URLBuilder(baseURL: self.baseURL)
                    .appendingPath("/organizations")
                    .build()
            } catch {
                throw AppError.wrap(error)
            }

            var request = URLRequest(url: url)
            request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
            request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
            request.httpMethod = "GET"
            request.timeoutInterval = 30

            let startTime = Date()
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                // Network errors
                let duration = Date().timeIntervalSince(startTime)
                NetworkLoggerService.shared.logRequest(
                    url: url.absoluteString,
                    method: "GET",
                    requestBody: request.httpBody,
                    responseData: nil,
                    statusCode: nil,
                    duration: duration,
                    error: error
                )

                let appError = AppError(
                    code: .networkGenericError,
                    message: "Failed to connect to Claude API",
                    technicalDetails: error.localizedDescription,
                    underlyingError: error,
                    isRecoverable: true,
                    recoverySuggestion: "Please check your internet connection and try again"
                )
                ErrorLogger.shared.log(appError)
                throw appError
            }

            let duration = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError(
                    code: .apiInvalidResponse,
                    message: "Invalid response from server",
                    isRecoverable: true
                )
            }

            // Log to NetworkLoggerService
            NetworkLoggerService.shared.logRequest(
                url: url.absoluteString,
                method: "GET",
                requestBody: request.httpBody,
                responseData: data,
                statusCode: httpResponse.statusCode,
                duration: duration,
                error: nil
            )

            switch httpResponse.statusCode {
            case 200:
                // Parse organizations array
                do {
                    let organizations = try JSONDecoder().decode([AccountInfo].self, from: data)
                    guard !organizations.isEmpty else {
                        throw AppError(
                            code: .apiParsingFailed,
                            message: "No organizations found",
                            technicalDetails: "Organizations array is empty",
                            isRecoverable: false,
                            recoverySuggestion: "Please ensure your Claude account has access to organizations"
                        )
                    }

                    // Log all available organizations for debugging
                    LoggingService.shared.logInfo("Found \(organizations.count) organization(s):")
                    for (index, org) in organizations.enumerated() {
                        LoggingService.shared.logInfo("  [\(index)] \(org.name) (ID: \(org.uuid))")
                    }

                    return organizations
                } catch {
                    let appError = AppError(
                        code: .apiParsingFailed,
                        message: "Failed to parse organizations",
                        technicalDetails: error.localizedDescription,
                        underlyingError: error,
                        isRecoverable: false
                    )
                    ErrorLogger.shared.log(appError)
                    throw appError
                }

            case 401, 403:
                throw AppError.apiUnauthorized()

            case 429:
                throw AppError.apiRateLimited()

            case 500...599:
                throw AppError.apiServerError(statusCode: httpResponse.statusCode)

            default:
                throw AppError(
                    code: .apiGenericError,
                    message: "Unexpected API response",
                    technicalDetails: "HTTP \(httpResponse.statusCode)",
                    isRecoverable: true
                )
            }
        }
    }

    // MARK: - Read-Only Testing

    /// testSessionKey with retry for freshly issued keys: a new sessionKey can
    /// take a moment to propagate on Anthropic's side, so the first request may
    /// get a transient 401 (E3000) even though the key is valid. Retries only
    /// on .apiUnauthorized, with a growing delay (1.5s, 3s, 4.5s).
    func testSessionKeyWithRetry(_ key: String, maxAttempts: Int = 4) async throws -> [AccountInfo] {
        var attempt = 1
        while true {
            do {
                return try await testSessionKey(key)
            } catch {
                guard AppError.wrap(error).code == .apiUnauthorized, attempt < maxAttempts else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                attempt += 1
            }
        }
    }

    /// Tests a session key without saving to Keychain
    /// Returns available organizations if successful
    func testSessionKey(_ key: String) async throws -> [AccountInfo] {
        // Validate using professional validator
        let validatedKey = try sessionKeyValidator.validate(key)

        // Fetch organizations using the test key (don't save it)
        let organizations = try await fetchAllOrganizations(sessionKey: validatedKey)

        LoggingService.shared.logInfo("Tested session key - found \(organizations.count) organization(s)")

        return organizations
    }

    /// Fetches the organization ID for the authenticated user
    /// Uses stored org ID if available, otherwise fetches all orgs and auto-selects
    func fetchOrganizationId(sessionKey: String? = nil) async throws -> String {
        let sessionKey = try sessionKey ?? self.readSessionKey()

        // Check for stored organization ID in active profile first
        if let storedOrgId = ProfileManager.shared.activeProfile?.organizationId {
            LoggingService.shared.logInfo("Using stored organization ID from profile: \(storedOrgId)")
            return storedOrgId
        }

        // No stored org ID - fetch all organizations
        LoggingService.shared.logInfo("No stored organization ID - fetching all organizations")
        let organizations = try await fetchAllOrganizations(sessionKey: sessionKey)

        // Auto-select organization (prefer first one for now - user can change later)
        let selectedOrg = organizations.first!
        LoggingService.shared.logInfo("Auto-selected organization: \(selectedOrg.name) (ID: \(selectedOrg.uuid))")

        // Store the selected org ID in active profile
        if let profileId = ProfileManager.shared.activeProfile?.id {
            ProfileManager.shared.updateOrganizationId(selectedOrg.uuid, for: profileId)
        }

        return selectedOrg.uuid
    }

    /// Fetches usage data for a specific profile using provided credentials
    /// - Parameters:
    ///   - sessionKey: The Claude.ai session key
    ///   - organizationId: The organization ID
    /// - Returns: ClaudeUsage data for the profile
    func fetchUsageData(sessionKey: String, organizationId: String) async throws -> ClaudeUsage {
        async let usageDataTask = performRequest(endpoint: "/organizations/\(organizationId)/usage", sessionKey: sessionKey)
        async let overageDataTask: Data? = performRequest(endpoint: "/organizations/\(organizationId)/overage_spend_limit", sessionKey: sessionKey)
        async let creditGrantTask: Data? = performRequest(endpoint: "/organizations/\(organizationId)/overage_credit_grant", sessionKey: sessionKey)
        async let personalSpendTask = fetchPersonalSpend(organizationId: organizationId, sessionKey: sessionKey)

        let usageData = try await usageDataTask
        var claudeUsage = try parseUsageResponse(usageData)

        if let data = try? await overageDataTask,
           let overage = try? JSONDecoder().decode(OverageSpendLimitResponse.self, from: data),
           overage.isEnabled == true {
            claudeUsage.costUsed = overage.usedCredits
            claudeUsage.costLimit = overage.monthlyCreditLimit
            claudeUsage.costCurrency = overage.currency
        }

        if let creditData = try? await creditGrantTask,
           let creditGrant = try? JSONDecoder().decode(OverageCreditGrantResponse.self, from: creditData) {
            claudeUsage.overageBalance = creditGrant.remainingBalance
            claudeUsage.overageBalanceCurrency = creditGrant.currency
        }

        if let personal = await personalSpendTask {
            claudeUsage.personalSpendUsed = personal.usedMinorUnits
            claudeUsage.personalSpendCurrency = personal.currency
        }

        return claudeUsage
    }

    /// Fetches usage data via OAuth access token (CLI credential flow)
    func fetchUsageData(oauthAccessToken: String) async throws -> ClaudeUsage {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw AppError(code: .urlMalformed, message: "Invalid OAuth usage endpoint", isRecoverable: false)
        }

        var request = buildAuthenticatedRequest(url: url, auth: .cliOAuth(oauthAccessToken))
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(code: .apiInvalidResponse, message: "Invalid response from OAuth endpoint", isRecoverable: true)
        }

        guard httpResponse.statusCode == 200 else {
            throw AppError(
                code: httpResponse.statusCode == 401 || httpResponse.statusCode == 403
                    ? .apiUnauthorized : .apiGenericError,
                message: "OAuth fetch failed (status \(httpResponse.statusCode))",
                isRecoverable: true
            )
        }

        return try parseUsageResponse(data)
    }

    /// Fetches real usage data from Claude's API
    func fetchUsageData() async throws -> ClaudeUsage {
        let auth = try getAuthentication()

        switch auth {
        case .claudeAISession(let sessionKey):
            // Use existing claude.ai flow
            let orgId = try await fetchOrganizationId(sessionKey: sessionKey)

            async let usageDataTask = performRequest(endpoint: "/organizations/\(orgId)/usage", sessionKey: sessionKey)

            // Use active profile's checkOverageLimitEnabled setting
            let checkOverage = ProfileManager.shared.activeProfile?.checkOverageLimitEnabled ?? true
            async let overageDataTask: Data? = checkOverage ? performRequest(endpoint: "/organizations/\(orgId)/overage_spend_limit", sessionKey: sessionKey) : nil
            async let creditGrantTask: Data? = checkOverage ? performRequest(endpoint: "/organizations/\(orgId)/overage_credit_grant", sessionKey: sessionKey) : nil
            async let personalSpendTask = fetchPersonalSpend(organizationId: orgId, sessionKey: sessionKey)

            let usageData = try await usageDataTask
            var claudeUsage = try parseUsageResponse(usageData)

            if checkOverage,
               let data = try? await overageDataTask,
               let overage = try? JSONDecoder().decode(OverageSpendLimitResponse.self, from: data),
               overage.isEnabled == true {
                claudeUsage.costUsed = overage.usedCredits
                claudeUsage.costLimit = overage.monthlyCreditLimit
                claudeUsage.costCurrency = overage.currency
            }

            if checkOverage,
               let creditData = try? await creditGrantTask,
               let creditGrant = try? JSONDecoder().decode(OverageCreditGrantResponse.self, from: creditData) {
                claudeUsage.overageBalance = creditGrant.remainingBalance
                claudeUsage.overageBalanceCurrency = creditGrant.currency
            }

            if let personal = await personalSpendTask {
                claudeUsage.personalSpendUsed = personal.usedMinorUnits
                claudeUsage.personalSpendCurrency = personal.currency
            }

            return claudeUsage

        case .cliOAuth:
            // The dedicated OAuth usage endpoint (api.anthropic.com/api/oauth/usage) is disabled.
            // Instead, make a minimal Messages API call and extract usage from response headers.
            LoggingService.shared.log("ClaudeAPIService: Fetching usage via Messages API headers (OAuth)")

            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                throw AppError(
                    code: .urlMalformed,
                    message: "Invalid Messages API endpoint",
                    isRecoverable: false
                )
            }

            var request = buildAuthenticatedRequest(url: url, auth: auth)
            request.httpMethod = "POST"
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 30

            // Minimal request: cheapest model, 1 token, to get rate limit headers
            let body: [String: Any] = [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let startTime = Date()
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                NetworkLoggerService.shared.logRequest(
                    url: url.absoluteString,
                    method: "POST",
                    requestBody: request.httpBody,
                    responseData: nil,
                    statusCode: nil,
                    duration: duration,
                    error: error
                )
                throw error
            }

            let duration = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError(
                    code: .apiInvalidResponse,
                    message: "Invalid response from Messages API",
                    isRecoverable: true
                )
            }

            // Log to NetworkLoggerService
            NetworkLoggerService.shared.logRequest(
                url: url.absoluteString,
                method: "POST",
                requestBody: request.httpBody,
                responseData: data,
                statusCode: httpResponse.statusCode,
                duration: duration,
                error: nil
            )

            // A 429 means the account is at its rate limit — which is exactly
            // what we're here to measure. The unified rate-limit headers are
            // still present on 429 responses, so parse them instead of
            // failing the refresh right when the user most needs the data.
            let has429UsageHeaders = httpResponse.statusCode == 429
                && httpResponse.value(forHTTPHeaderField: "anthropic-ratelimit-unified-5h-utilization") != nil

            guard httpResponse.statusCode == 200 || has429UsageHeaders else {
                let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
                throw AppError(
                    code: httpResponse.statusCode == 429 ? .apiRateLimited : .apiUnauthorized,
                    message: httpResponse.statusCode == 429
                        ? "Rate limited by Claude API"
                        : "OAuth Messages API request failed",
                    technicalDetails: "Status: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                    isRecoverable: true,
                    recoverySuggestion: httpResponse.statusCode == 429
                        ? "Usage is at its limit — data will refresh once the rate limit window resets"
                        : "Please re-sync your CLI account in Settings"
                )
            }

            return parseUsageFromRateLimitHeaders(httpResponse)

        case .consoleAPISession:
            // Console API is for billing/credits only, not usage data
            throw AppError(
                code: .sessionKeyNotFound,
                message: "No valid credentials for usage data",
                technicalDetails: "Console API only provides billing data, not usage statistics",
                isRecoverable: true,
                recoverySuggestion: "Please add a claude.ai session key or sync your CLI account"
            )
        }
    }

    private func performRequest(endpoint: String, sessionKey: String) async throws -> Data {
        // Build URL safely
        let url = try URLBuilder(baseURL: baseURL)
            .appendingPath(endpoint)
            .build()

        var request = URLRequest(url: url)
        // Include Cloudflare clearance cookies captured by the sign-in webview
        // (shared cookie storage) — without them claude.ai intermittently
        // answers with a 403 "Just a moment..." challenge page.
        var cookiePairs = ["sessionKey=\(sessionKey)"]
        if let stored = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in stored where ["cf_clearance", "__cf_bm"].contains(cookie.name) {
                cookiePairs.append("\(cookie.name)=\(cookie.value)")
            }
        }
        request.setValue(cookiePairs.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        LoggingService.shared.logAPIRequest(endpoint)

        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Network-level errors
            let duration = Date().timeIntervalSince(startTime)
            NetworkLoggerService.shared.logRequest(
                url: url.absoluteString,
                method: "GET",
                requestBody: request.httpBody,
                responseData: nil,
                statusCode: nil,
                duration: duration,
                error: error
            )

            LoggingService.shared.logAPIError(endpoint, error: error)
            let appError = AppError(
                code: .networkGenericError,
                message: "Failed to connect to Claude API",
                technicalDetails: "Endpoint: \(endpoint)\nError: \(error.localizedDescription)",
                underlyingError: error,
                isRecoverable: true,
                recoverySuggestion: "Please check your internet connection and try again"
            )
            throw appError
        }

        let duration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(
                code: .apiInvalidResponse,
                message: "Invalid response from server",
                technicalDetails: "Endpoint: \(endpoint)",
                isRecoverable: true
            )
        }

        LoggingService.shared.logAPIResponse(endpoint, statusCode: httpResponse.statusCode)

        // Log to NetworkLoggerService
        NetworkLoggerService.shared.logRequest(
            url: url.absoluteString,
            method: "GET",
            requestBody: request.httpBody,
            responseData: data,
            statusCode: httpResponse.statusCode,
            duration: duration,
            error: nil
        )

        // Log raw response if debug logging is enabled
        if DataStore.shared.loadDebugAPILoggingEnabled() {
            if let responseString = String(data: data, encoding: .utf8) {
                // Truncate to first 500 chars to avoid huge logs
                let truncated = responseString.prefix(500)
                LoggingService.shared.logDebug("API Response [\(endpoint)]: \(truncated)...")
            }
        }

        switch httpResponse.statusCode {
        case 200:
            return data

        case 401, 403:
            // Include response body in error for debugging
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"

            // Cloudflare bot challenge, not an actual auth failure — the
            // session key is fine, the request just got challenged.
            if responsePreview.contains("Just a moment") || responsePreview.contains("cf-mitigated") {
                throw AppError(
                    code: .apiUnauthorized,
                    message: "Request blocked by Cloudflare protection.",
                    technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nCloudflare challenge page returned",
                    isRecoverable: true,
                    recoverySuggestion: "Your session key is likely still valid — this usually resolves on the next refresh. If it persists, re-sign-in via Settings to refresh Cloudflare cookies."
                )
            }

            throw AppError(
                code: .apiUnauthorized,
                message: "Unauthorized. Your session key may have expired.",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true,
                recoverySuggestion: "Please update your session key in Settings"
            )

        case 429:
            throw AppError(
                code: .apiRateLimited,
                message: "Rate limited by Claude API",
                technicalDetails: "Endpoint: \(endpoint)",
                isRecoverable: true,
                recoverySuggestion: "Please wait a few minutes before trying again"
            )

        case 500...599:
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
            throw AppError(
                code: .apiServerError,
                message: "Claude API server error",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true,
                recoverySuggestion: "Please try again later"
            )

        default:
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
            throw AppError(
                code: .apiGenericError,
                message: "Unexpected API response",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true
            )
        }
    }

    // MARK: - Response Parsing

    /// Fetches the authenticated member's OWN month-to-date spend from
    /// `/organizations/{org}/usage/spend`. The URL is org-scoped but claude.ai
    /// returns only the calling member's figures (the same number shown on
    /// claude.ai/settings/usage), provided the org has "individual usage
    /// analytics" enabled. Non-throwing: any failure (no such endpoint for the
    /// plan, analytics disabled, network/parse error) resolves to `nil` so it can
    /// never break the primary usage fetch. Returns spend in minor units (cents).
    func fetchPersonalSpend(organizationId: String, sessionKey: String) async -> (usedMinorUnits: Double, currency: String)? {
        do {
            let calendar = Calendar.current
            let now = Date()
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return nil
            }

            // Match claude.ai's Settings → Usage query: calendar month-to-date.
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let url = try URLBuilder(baseURL: baseURL)
                .appendingPathComponents(["/organizations", organizationId, "/usage/spend"])
                .addingQueryParameter(name: "start_date", value: dateFormatter.string(from: startOfMonth))
                .addingQueryParameter(name: "end_date", value: dateFormatter.string(from: now))
                .addingQueryParameter(name: "group_by", value: "product_surface")
                .addingQueryParameter(name: "granularity", value: "daily")
                .build()

            var request = buildAuthenticatedRequest(url: url, auth: .claudeAISession(sessionKey))
            request.httpMethod = "GET"
            request.timeoutInterval = 30

            LoggingService.shared.logAPIRequest("/organizations/\(organizationId)/usage/spend")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            guard let spend = try? JSONDecoder().decode(UsageSpendResponse.self, from: data),
                  let totals = spend.totals, !totals.isEmpty else {
                return nil
            }

            // Sum across every group (e.g. all product surfaces) for the grand total.
            let usedMinorUnits = totals.reduce(0.0) { $0 + ($1.costMinorUnits ?? 0) }
            return (usedMinorUnits, spend.currency?.uppercased() ?? "USD")
        } catch {
            LoggingService.shared.logAPIError("/organizations/\(organizationId)/usage/spend", error: error)
            return nil
        }
    }

    private func parseUsageResponse(_ data: Data) throws -> ClaudeUsage {
        // Parse Claude's actual API response structure

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // One shared formatter for every resets_at field in this response —
            // ISO8601DateFormatter construction is expensive.
            let resetTimeFormatter = ISO8601DateFormatter()
            resetTimeFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Extract session usage (five_hour)
            var sessionPercentage = 0.0
            var sessionResetTime = Date().addingTimeInterval(5 * 3600)
            if let fiveHour = json["five_hour"] as? [String: Any] {
                if let utilization = fiveHour["utilization"] {
                    sessionPercentage = parseUtilization(utilization)
                }
                if let resetsAt = fiveHour["resets_at"] as? String {
                    sessionResetTime = resetTimeFormatter.date(from: resetsAt) ?? sessionResetTime
                }
            }

            // Extract weekly usage (seven_day)
            var weeklyPercentage = 0.0
            var weeklyResetTime = Date().nextMonday1259pm()
            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let utilization = sevenDay["utilization"] {
                    weeklyPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDay["resets_at"] as? String {
                    weeklyResetTime = resetTimeFormatter.date(from: resetsAt) ?? weeklyResetTime
                }
            }

            // Extract Opus weekly usage (seven_day_opus)
            var opusPercentage = 0.0
            if let sevenDayOpus = json["seven_day_opus"] as? [String: Any] {
                if let utilization = sevenDayOpus["utilization"] {
                    opusPercentage = parseUtilization(utilization)
                }
            }

            // Extract Sonnet weekly usage (seven_day_sonnet)
            var sonnetPercentage = 0.0
            var sonnetResetTime: Date? = nil
            if let sevenDaySonnet = json["seven_day_sonnet"] as? [String: Any] {
                if let utilization = sevenDaySonnet["utilization"] {
                    sonnetPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDaySonnet["resets_at"] as? String {
                    sonnetResetTime = resetTimeFormatter.date(from: resetsAt)
                }
            }

            // Extract Design weekly usage (seven_day_design)
            var designPercentage = 0.0
            var designResetTime: Date? = nil
            if let sevenDayDesign = json["seven_day_omelette"] as? [String: Any] {
                if let utilization = sevenDayDesign["utilization"] {
                    designPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDayDesign["resets_at"] as? String {
                    designResetTime = resetTimeFormatter.date(from: resetsAt)
                }
            }

            // Extract Fable weekly usage (seven_day_fable)
            var fablePercentage = 0.0
            var fableResetTime: Date? = nil
            if let sevenDayFable = json["seven_day_fable"] as? [String: Any] {
                if let utilization = sevenDayFable["utilization"] {
                    fablePercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDayFable["resets_at"] as? String {
                    fableResetTime = resetTimeFormatter.date(from: resetsAt)
                }
            }

            // Newer API responses null out the legacy seven_day_* per-model
            // fields and report per-model usage in a "limits" array instead:
            // {"kind":"weekly_scoped","percent":73,"resets_at":...,
            //  "scope":{"model":{"id":null,"display_name":"Fable"}}}
            // limits[] is therefore the source of truth: when an entry is
            // present it overrides whatever the legacy fields said.
            if let limits = json["limits"] as? [[String: Any]] {
                for limit in limits {
                    guard limit["kind"] as? String == "weekly_scoped",
                          let scope = limit["scope"] as? [String: Any],
                          let model = scope["model"] as? [String: Any],
                          let percentValue = limit["percent"] else { continue }
                    let percent = parseUtilization(percentValue)
                    let resetTime = (limit["resets_at"] as? String).flatMap { resetTimeFormatter.date(from: $0) }

                    // Match on the stable model id when the API provides one;
                    // display_name is a rename-prone human label kept as fallback.
                    let modelId = (model["id"] as? String)?.lowercased() ?? ""
                    let name = (model["display_name"] as? String)?.lowercased() ?? ""
                    func matches(_ keys: String...) -> Bool {
                        keys.contains { name == $0 || modelId.contains($0) }
                    }

                    if matches("fable", "mythos") {
                        fablePercentage = percent
                        fableResetTime = resetTime ?? fableResetTime
                    } else if matches("opus") {
                        opusPercentage = percent
                    } else if matches("sonnet") {
                        sonnetPercentage = percent
                        sonnetResetTime = resetTime ?? sonnetResetTime
                    } else if matches("design", "omelette") {
                        designPercentage = percent
                        designResetTime = resetTime ?? designResetTime
                    }
                }
            }

            // We don't know user's plan, so we use 0 for limits we can't determine
            let weeklyLimit = Constants.weeklyLimit

            // Calculate token counts from percentages (using weekly limit as reference)
            let sessionTokens = 0  // Can't calculate without knowing plan
            let sessionLimit = 0   // Unknown without plan
            let weeklyTokens = Int(Double(weeklyLimit) * (weeklyPercentage / 100.0))
            let opusTokens = Int(Double(weeklyLimit) * (opusPercentage / 100.0))
            let sonnetTokens = Int(Double(weeklyLimit) * (sonnetPercentage / 100.0))
            let designTokens = Int(Double(weeklyLimit) * (designPercentage / 100.0))
            let fableTokens = Int(Double(weeklyLimit) * (fablePercentage / 100.0))

            let usage = ClaudeUsage(
                sessionTokensUsed: sessionTokens,
                sessionLimit: sessionLimit,
                sessionPercentage: sessionPercentage,
                sessionResetTime: sessionResetTime,
                weeklyTokensUsed: weeklyTokens,
                weeklyLimit: weeklyLimit,
                weeklyPercentage: weeklyPercentage,
                weeklyResetTime: weeklyResetTime,
                opusWeeklyTokensUsed: opusTokens,
                opusWeeklyPercentage: opusPercentage,
                sonnetWeeklyTokensUsed: sonnetTokens,
                sonnetWeeklyPercentage: sonnetPercentage,
                sonnetWeeklyResetTime: sonnetResetTime,
                designWeeklyTokensUsed: designTokens,
                designWeeklyPercentage: designPercentage,
                designWeeklyResetTime: designResetTime,
                fableWeeklyTokensUsed: fableTokens,
                fableWeeklyPercentage: fablePercentage,
                fableWeeklyResetTime: fableResetTime,
                costUsed: nil,
                costLimit: nil,
                costCurrency: nil,
                lastUpdated: Date(),
                userTimezone: .current
            )

            return usage
        }

        // Log the actual response for debugging
        if DataStore.shared.loadDebugAPILoggingEnabled() {
            if let responseString = String(data: data, encoding: .utf8) {
                LoggingService.shared.logDebug("Failed to parse usage response: \(responseString)")
            }
        }

        throw AppError(
            code: .apiParsingFailed,
            message: "Failed to parse usage data",
            technicalDetails: "Unable to parse JSON response structure",
            isRecoverable: false,
            recoverySuggestion: "Please check the error log and report this issue"
        )
    }

    // MARK: - Rate Limit Header Parsing

    /// Parses usage data from Messages API rate limit response headers.
    /// Headers use format: anthropic-ratelimit-unified-{window}-{field}
    /// Utilization values are 0.0-1.0 (converted to 0-100 percentage).
    private func parseUsageFromRateLimitHeaders(_ response: HTTPURLResponse) -> ClaudeUsage {
        func headerDouble(_ name: String) -> Double? {
            if let value = response.value(forHTTPHeaderField: name) {
                return Double(value)
            }
            return nil
        }

        // Session (5h) usage — utilization is 0.0-1.0, convert to 0-100
        let sessionUtilization = headerDouble("anthropic-ratelimit-unified-5h-utilization") ?? 0
        var sessionPercentage = sessionUtilization * 100.0

        let sessionResetTimestamp = headerDouble("anthropic-ratelimit-unified-5h-reset") ?? 0
        let sessionResetTime = sessionResetTimestamp > 0
            ? Date(timeIntervalSince1970: sessionResetTimestamp)
            : Date().addingTimeInterval(5 * 3600)

        // If the 5-hour window has already expired, the session has reset
        if sessionResetTime < Date() {
            sessionPercentage = 0.0
        }

        // Weekly (7d) usage
        let weeklyUtilization = headerDouble("anthropic-ratelimit-unified-7d-utilization") ?? 0
        let weeklyPercentage = weeklyUtilization * 100.0

        let weeklyResetTimestamp = headerDouble("anthropic-ratelimit-unified-7d-reset") ?? 0
        let weeklyResetTime = weeklyResetTimestamp > 0
            ? Date(timeIntervalSince1970: weeklyResetTimestamp)
            : Date().nextMonday1259pm()

        // Per-model breakdowns not available in rate limit headers
        let weeklyLimit = Constants.weeklyLimit
        let weeklyTokens = Int(Double(weeklyLimit) * (weeklyPercentage / 100.0))

        LoggingService.shared.log("ClaudeAPIService: Parsed usage from headers - session: \(String(format: "%.1f", sessionPercentage))%, weekly: \(String(format: "%.1f", weeklyPercentage))%")

        return ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 0,
            sessionPercentage: sessionPercentage,
            sessionResetTime: sessionResetTime,
            weeklyTokensUsed: weeklyTokens,
            weeklyLimit: weeklyLimit,
            weeklyPercentage: weeklyPercentage,
            weeklyResetTime: weeklyResetTime,
            opusWeeklyTokensUsed: 0,
            opusWeeklyPercentage: 0,
            sonnetWeeklyTokensUsed: 0,
            sonnetWeeklyPercentage: 0,
            sonnetWeeklyResetTime: nil,
            designWeeklyTokensUsed: 0,
            designWeeklyPercentage: 0,
            designWeeklyResetTime: nil,
            fableWeeklyTokensUsed: 0,
            fableWeeklyPercentage: 0,
            fableWeeklyResetTime: nil,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            overageBalance: nil,
            overageBalanceCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }

    // MARK: - Parsing Helpers

    /// Robust utilization parser that handles Int, Double, or String types
    /// - Parameter value: The utilization value from API (can be Int, Double, or String)
    /// - Returns: Parsed percentage as Double, or 0.0 if parsing fails
    private func parseUtilization(_ value: Any) -> Double {
        // Try Int first (most common)
        if let intValue = value as? Int {
            return Double(intValue)
        }

        // Try Double
        if let doubleValue = value as? Double {
            return doubleValue
        }

        // Try String
        if let stringValue = value as? String {
            // Remove any percentage symbols or whitespace
            let cleaned = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")

            if let parsed = Double(cleaned) {
                return parsed
            }
        }

        // Log warning if we couldn't parse
        LoggingService.shared.logWarning("Failed to parse utilization value: \(value) (type: \(type(of: value)))")
        return 0.0
    }

    // MARK: - Session Initialization

    /// Sends a minimal message to Claude to initialize a new session
    /// Uses Claude 3.5 Haiku (cheapest model)
    /// Creates a temporary conversation that is deleted after initialization to avoid cluttering chat history
    func sendInitializationMessage() async throws {
        let sessionKey = try readSessionKey()
        let orgId = try await fetchOrganizationId(sessionKey: sessionKey)

        // Create a new conversation
        let conversationURL = try URLBuilder(baseURL: baseURL)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations"])
            .build()

        var conversationRequest = URLRequest(url: conversationURL)
        conversationRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        conversationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        conversationRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        conversationRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        conversationRequest.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        conversationRequest.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        conversationRequest.httpMethod = "POST"

        let conversationBody: [String: Any] = [
            "uuid": UUID().uuidString.lowercased(),
            "name": ""
        ]
        conversationRequest.httpBody = try JSONSerialization.data(withJSONObject: conversationBody)

        let startTime1 = Date()
        let (conversationData, conversationResponse) = try await URLSession.shared.data(for: conversationRequest)
        let duration1 = Date().timeIntervalSince(startTime1)

        guard let httpResponse = conversationResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        NetworkLoggerService.shared.logRequest(
            url: conversationURL.absoluteString,
            method: "POST",
            requestBody: conversationRequest.httpBody,
            responseData: conversationData,
            statusCode: httpResponse.statusCode,
            duration: duration1,
            error: nil
        )

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        // Parse conversation UUID
        guard let json = try? JSONSerialization.jsonObject(with: conversationData) as? [String: Any],
              let conversationUUID = json["uuid"] as? String else {
            throw APIError.invalidResponse
        }

        // Send a minimal "Hi" message to initialize the session
        let messageURL = try URLBuilder(baseURL: baseURL)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations", conversationUUID, "/completion"])
            .build()

        var messageRequest = URLRequest(url: messageURL)
        messageRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        messageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        messageRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        messageRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        messageRequest.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        messageRequest.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        messageRequest.httpMethod = "POST"

        let messageBody: [String: Any] = [
            "prompt": "Hi",
            "model": "claude-haiku-4-5-20251001",
            "timezone": "UTC"
        ]
        messageRequest.httpBody = try JSONSerialization.data(withJSONObject: messageBody)

        let startTime2 = Date()
        let (messageData, messageResponse) = try await URLSession.shared.data(for: messageRequest)
        let duration2 = Date().timeIntervalSince(startTime2)

        guard let messageHTTPResponse = messageResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        NetworkLoggerService.shared.logRequest(
            url: messageURL.absoluteString,
            method: "POST",
            requestBody: messageRequest.httpBody,
            responseData: messageData,
            statusCode: messageHTTPResponse.statusCode,
            duration: duration2,
            error: nil
        )

        guard messageHTTPResponse.statusCode == 200 else {
            throw APIError.serverError(statusCode: messageHTTPResponse.statusCode)
        }

        // Delete the conversation to keep it out of chat history (incognito mode)
        let deleteURL = try URLBuilder(baseURL: baseURL)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations", conversationUUID])
            .build()

        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        deleteRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        deleteRequest.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        deleteRequest.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        deleteRequest.httpMethod = "DELETE"

        // Attempt to delete, but don't fail if deletion fails
        // The session is already initialized, which is the primary goal
        do {
            let startTime3 = Date()
            let (deleteData, deleteResponse) = try await URLSession.shared.data(for: deleteRequest)
            let duration3 = Date().timeIntervalSince(startTime3)

            if let deleteHTTPResponse = deleteResponse as? HTTPURLResponse {
                NetworkLoggerService.shared.logRequest(
                    url: deleteURL.absoluteString,
                    method: "DELETE",
                    requestBody: deleteRequest.httpBody,
                    responseData: deleteData,
                    statusCode: deleteHTTPResponse.statusCode,
                    duration: duration3,
                    error: nil
                )
            }
        } catch {
            // Silently ignore deletion errors - session is already initialized
        }
    }

}
