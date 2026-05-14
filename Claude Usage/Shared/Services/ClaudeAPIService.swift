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
            applyAnthropicWebHeaders(to: &request)

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

        // Auto-populate accountUuid on first successful fetch
        if ProfileManager.shared.activeProfile?.accountUuid == nil,
           var updatedProfile = ProfileManager.shared.activeProfile {
            updatedProfile.accountUuid = selectedOrg.uuid
            ProfileManager.shared.updateProfile(updatedProfile)
        }

        return selectedOrg.uuid
    }

    /// Fetches usage data for a specific profile using provided credentials
    /// - Parameters:
    ///   - sessionKey: The Claude.ai session key
    ///   - organizationId: The organization ID
    /// - Returns: ClaudeUsage data for the profile
    func fetchUsageData(sessionKey: String, organizationId: String) async throws -> ClaudeUsage {
        let checkOverage = ProfileManager.shared.activeProfile?.checkOverageLimitEnabled ?? true

        let accountUuid = ProfileManager.shared.activeProfile?.accountUuid
        let personalEndpoint = personalOverageEndpoint(organizationId: organizationId, accountUuid: accountUuid)
        let orgEndpoint = "/organizations/\(organizationId)/overage_spend_limit"

        async let usageDataTask = performRequest(endpoint: "/organizations/\(organizationId)/usage", sessionKey: sessionKey)
        async let overageDataTask: Data?        = (checkOverage && personalEndpoint != nil) ? performRequest(endpoint: personalEndpoint ?? "", sessionKey: sessionKey) : nil
        async let orgOverageTask: Data?         = checkOverage ? performRequest(endpoint: orgEndpoint, sessionKey: sessionKey) : nil
        async let creditGrantTask: Data?        = checkOverage ? performRequest(endpoint: "/organizations/\(organizationId)/overage_credit_grant", sessionKey: sessionKey) : nil
        async let runBudgetTask: RunBudgetResponse? = checkOverage ? fetchRunBudget(sessionKey: sessionKey, organizationId: organizationId) : nil

        let usageData = try await usageDataTask
        var claudeUsage = try parseUsageResponse(usageData)

        if checkOverage {
            applyPersonalOverage(to: &claudeUsage, data: try? await overageDataTask)
            applyOrganizationOverage(to: &claudeUsage, data: try? await orgOverageTask)
        }

        if checkOverage,
           let creditData = try? await creditGrantTask,
           let creditGrant = try? JSONDecoder().decode(OverageCreditGrantResponse.self, from: creditData) {
            claudeUsage.overageBalance = creditGrant.remainingBalance
            claudeUsage.overageBalanceCurrency = creditGrant.currency
        }

        // NEW: CCR Routine Runs
        if checkOverage,
           let runBudget = try? await runBudgetTask,
           runBudget.unifiedBillingEnabled {
            claudeUsage.routineRunsUsed = runBudget.usedRuns
            claudeUsage.routineRunsLimit = runBudget.limitRuns
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
            let accountUuid = ProfileManager.shared.activeProfile?.accountUuid
            let personalEndpoint = personalOverageEndpoint(organizationId: orgId, accountUuid: accountUuid)
            let orgEndpoint = "/organizations/\(orgId)/overage_spend_limit"

            async let overageDataTask: Data? = (checkOverage && personalEndpoint != nil) ? performRequest(endpoint: personalEndpoint ?? "", sessionKey: sessionKey) : nil
            async let orgOverageTask: Data? = checkOverage ? performRequest(endpoint: orgEndpoint, sessionKey: sessionKey) : nil
            async let creditGrantTask: Data? = checkOverage ? performRequest(endpoint: "/organizations/\(orgId)/overage_credit_grant", sessionKey: sessionKey) : nil
            async let runBudgetTask: RunBudgetResponse? = checkOverage ? fetchRunBudget(sessionKey: sessionKey, organizationId: orgId) : nil

            let usageData = try await usageDataTask
            var claudeUsage = try parseUsageResponse(usageData)

            if checkOverage {
                applyPersonalOverage(to: &claudeUsage, data: try? await overageDataTask)
                applyOrganizationOverage(to: &claudeUsage, data: try? await orgOverageTask)
            }

            if checkOverage,
               let creditData = try? await creditGrantTask,
               let creditGrant = try? JSONDecoder().decode(OverageCreditGrantResponse.self, from: creditData) {
                claudeUsage.overageBalance = creditGrant.remainingBalance
                claudeUsage.overageBalanceCurrency = creditGrant.currency
            }

            // NEW: CCR Routine Runs
            if checkOverage,
               let runBudget = try? await runBudgetTask,
               runBudget.unifiedBillingEnabled {
                claudeUsage.routineRunsUsed = runBudget.usedRuns
                claudeUsage.routineRunsLimit = runBudget.limitRuns
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

            guard httpResponse.statusCode == 200 else {
                let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
                throw AppError(
                    code: .apiUnauthorized,
                    message: "OAuth Messages API request failed",
                    technicalDetails: "Status: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                    isRecoverable: true,
                    recoverySuggestion: "Please re-sync your CLI account in Settings"
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
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        applyAnthropicWebHeaders(to: &request)
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

    // MARK: - Overage Spend Limit

    /// Returns the overage_spend_limit endpoint for personal data, or nil if no account UUID is set.
    /// Without account_uuid the endpoint returns team/org data; with it, personal data scoped to the user.
    private func personalOverageEndpoint(organizationId: String, accountUuid: String?) -> String? {
        guard let uuid = accountUuid, !uuid.isEmpty else { return nil }
        return "/organizations/\(organizationId)/overage_spend_limit?account_uuid=\(uuid)"
    }

    /// Applies the personal overage_spend_limit response to the usage model.
    /// Personal cost fields take precedence from /usage's extra_usage block; this only fills gaps.
    /// Always maps disabled state and organization name regardless of cost-field precedence.
    private func applyPersonalOverage(to usage: inout ClaudeUsage, data: Data?) {
        guard let data = data,
              let overage = try? JSONDecoder().decode(OverageSpendLimitResponse.self, from: data),
              overage.isEnabled == true else { return }

        if usage.costUsed == nil {
            usage.costLimit = overage.monthlyCreditLimit
            usage.costUsed = overage.usedCredits
            usage.costCurrency = overage.currency
        }
        if let reason = overage.disabledReason, !reason.isEmpty {
            usage.budgetDisabledReason = reason
        } else if overage.outOfCredits == true {
            usage.budgetDisabledReason = "out_of_credits"
        }
        if let name = overage.groupName, !name.isEmpty {
            usage.organizationName = name
        }
    }

    /// Applies the organization-level overage_spend_limit response (fetched without account_uuid).
    /// The org pool is what all members share; personal caps are sub-limits within it.
    private func applyOrganizationOverage(to usage: inout ClaudeUsage, data: Data?) {
        guard let data = data,
              let overage = try? JSONDecoder().decode(OverageSpendLimitResponse.self, from: data),
              overage.isEnabled == true else { return }

        usage.organizationCostLimit = overage.monthlyCreditLimit
        usage.organizationCostUsed = overage.usedCredits
        usage.organizationCostCurrency = overage.currency
        if usage.organizationName == nil, let name = overage.groupName, !name.isEmpty {
            usage.organizationName = name
        }
    }

    // MARK: - CCR Run Budget

    /// Fetches the personal Claude Code Routines monthly budget.
    ///
    /// Endpoint: GET https://claude.ai/v1/code/routines/run-budget
    /// (Note: uses claudeBase — no /api prefix.)
    ///
    /// Required extra headers beyond standard session headers:
    ///   - anthropic-beta: ccr-triggers-2026-01-30
    ///   - x-organization-uuid: {organizationId}
    ///
    /// - Parameters:
    ///   - sessionKey: The Claude.ai session cookie value (same as used in performRequest)
    ///   - organizationId: The org UUID for the x-organization-uuid header
    /// - Returns: Decoded `RunBudgetResponse`; throws on non-200 or decode failure
    private func fetchRunBudget(sessionKey: String, organizationId: String) async throws -> RunBudgetResponse {
        let endpoint = "/v1/code/routines/run-budget"
        let url = try URLBuilder.claudeBase(endpoint: endpoint).build()

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("ccr-triggers-2026-01-30", forHTTPHeaderField: "anthropic-beta")
        request.setValue(organizationId, forHTTPHeaderField: "x-organization-uuid")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        applyAnthropicWebHeaders(to: &request)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        LoggingService.shared.logAPIRequest(endpoint)

        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            NetworkLoggerService.shared.logRequest(
                url: url.absoluteString,
                method: "GET",
                requestBody: nil,
                responseData: nil,
                statusCode: nil,
                duration: duration,
                error: error
            )
            LoggingService.shared.logAPIError(endpoint, error: error)
            throw error
        }

        let duration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(
                code: .apiInvalidResponse,
                message: "Invalid response from run-budget endpoint",
                technicalDetails: "Endpoint: \(endpoint)",
                isRecoverable: true
            )
        }

        LoggingService.shared.logAPIResponse(endpoint, statusCode: httpResponse.statusCode)

        NetworkLoggerService.shared.logRequest(
            url: url.absoluteString,
            method: "GET",
            requestBody: nil,
            responseData: data,
            statusCode: httpResponse.statusCode,
            duration: duration,
            error: nil
        )

        if DataStore.shared.loadDebugAPILoggingEnabled(),
           let responseString = String(data: data, encoding: .utf8) {
            let truncated = responseString.prefix(500)
            LoggingService.shared.logDebug("API Response [\(endpoint)]: \(truncated)...")
        }

        guard httpResponse.statusCode == 200 else {
            let responsePreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "Unable to read response"
            throw AppError(
                code: (httpResponse.statusCode == 401 || httpResponse.statusCode == 403)
                    ? .apiUnauthorized : .apiGenericError,
                message: "run-budget request failed (HTTP \(httpResponse.statusCode))",
                technicalDetails: "Endpoint: \(endpoint)\nStatus: \(httpResponse.statusCode)\nResponse: \(responsePreview)",
                isRecoverable: true
            )
        }

        return try JSONDecoder().decode(RunBudgetResponse.self, from: data)
    }

    // MARK: - Response Parsing

    func parseUsageResponse(_ data: Data) throws -> ClaudeUsage {
        // Parse Claude's actual API response structure

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Extract session usage (five_hour)
            var sessionPercentage = 0.0
            var sessionResetTime = Date().addingTimeInterval(5 * 3600)
            if let fiveHour = json["five_hour"] as? [String: Any] {
                if let utilization = fiveHour["utilization"] {
                    sessionPercentage = parseUtilization(utilization)
                }
                if let resetsAt = fiveHour["resets_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    sessionResetTime = formatter.date(from: resetsAt) ?? sessionResetTime
                }
            }

            // Extract weekly usage (seven_day)
            var weeklyPercentage = 0.0
            var weeklyResetTime = Date().nextMonday1259pm()
            let hasSevenDay = (json["seven_day"] as? [String: Any]) != nil
            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let utilization = sevenDay["utilization"] {
                    weeklyPercentage = parseUtilization(utilization)
                }
                if let resetsAt = sevenDay["resets_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    weeklyResetTime = formatter.date(from: resetsAt) ?? weeklyResetTime
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
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    sonnetResetTime = formatter.date(from: resetsAt)
                }
            }

            // We don't know user's plan, so we use 0 for limits we can't determine.
            // 0 when API omits seven_day (plans without a weekly cap) so the UI can hide the row.
            let weeklyLimit = hasSevenDay ? Constants.weeklyLimit : 0

            // Calculate token counts from percentages (using weekly limit as reference)
            let sessionTokens = 0  // Can't calculate without knowing plan
            let sessionLimit = 0   // Unknown without plan
            let weeklyTokens = Int(Double(weeklyLimit) * (weeklyPercentage / 100.0))
            let opusTokens = Int(Double(weeklyLimit) * (opusPercentage / 100.0))
            let sonnetTokens = Int(Double(weeklyLimit) * (sonnetPercentage / 100.0))

            // Extract extra_usage (cost data embedded in /usage response).
            // If present, this takes PRECEDENCE over the separate overage_spend_limit endpoint.
            var extraCostUsed: Double? = nil
            var extraCostLimit: Double? = nil
            var extraCostCurrency: String? = nil
            var extraCostUtilization: Double? = nil

            if let extraUsage = json["extra_usage"] as? [String: Any] {
                if let used = extraUsage["used_credits"] as? Double {
                    extraCostUsed = used
                } else if let used = extraUsage["used_credits"] as? Int {
                    extraCostUsed = Double(used)
                }
                if let limit = extraUsage["monthly_limit"] as? Double {
                    extraCostLimit = limit
                } else if let limit = extraUsage["monthly_limit"] as? Int {
                    extraCostLimit = Double(limit)
                }
                if let currency = extraUsage["currency"] as? String {
                    extraCostCurrency = currency
                }
                if let utilization = extraUsage["utilization"] {
                    extraCostUtilization = parseUtilization(utilization)
                }
            }

            var usage = ClaudeUsage(
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
                costUsed: extraCostUsed,
                costLimit: extraCostLimit,
                costCurrency: extraCostCurrency,
                lastUpdated: Date(),
                userTimezone: .current
            )
            usage.costUtilization = extraCostUtilization
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
