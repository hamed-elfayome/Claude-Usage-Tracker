import Foundation

/// Service for fetching usage data directly from Claude's API
class ClaudeAPIService: APIServiceProtocol {
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

    /// Reads and validates the session key from Keychain
    private func readSessionKey() throws -> String {
        do {
            // Try to load from Keychain first
            if let key = try KeychainService.shared.load(for: .claudeSessionKey) {
                // Validate the session key using professional validator
                let validatedKey = try sessionKeyValidator.validate(key)
                return validatedKey
            }

            // Migration: Check if file exists and migrate to Keychain
            if FileManager.default.fileExists(atPath: sessionKeyPath.path) {
                LoggingService.shared.log("Found session key in file, migrating to Keychain")
                let fileKey = try String(contentsOf: sessionKeyPath, encoding: .utf8)
                let validatedKey = try sessionKeyValidator.validate(fileKey)

                // Save to Keychain
                try KeychainService.shared.save(validatedKey, for: .claudeSessionKey)

                // Delete the file (no longer needed as primary storage)
                // Note: File will be recreated by StatuslineService if statusline is enabled
                try? FileManager.default.removeItem(at: sessionKeyPath)
                LoggingService.shared.log("Migrated session key to Keychain and removed file")

                return validatedKey
            }

            // No key found anywhere
            throw AppError.sessionKeyNotFound()

        } catch let error as SessionKeyValidationError {
            // Convert validation errors to AppError
            throw AppError.wrap(error)
        } catch let error as AppError {
            // Re-throw AppError as-is
            throw error
        } catch {
            // Keychain or file errors
            let appError = AppError(
                code: .storageReadFailed,
                message: "Failed to read session key",
                technicalDetails: error.localizedDescription,
                underlyingError: error,
                isRecoverable: true,
                recoverySuggestion: "Please check your session key configuration and try again"
            )
            ErrorLogger.shared.log(appError)
            throw appError
        }
    }

    /// Saves a session key to Keychain with validation
    func saveSessionKey(_ key: String) throws {
        do {
            // Validate the key before saving
            let validatedKey = try sessionKeyValidator.validate(key)

            // Save to Keychain (primary storage)
            try KeychainService.shared.save(validatedKey, for: .claudeSessionKey)

            LoggingService.shared.log("Session key saved to Keychain")

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

    // MARK: - API Requests

    /// Fetches the organization UUID for the authenticated user
    func fetchOrganizationId(sessionKey: String? = nil) async throws -> String {
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
            request.httpMethod = "GET"
            request.timeoutInterval = 30

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                // Network errors
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

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError(
                    code: .apiInvalidResponse,
                    message: "Invalid response from server",
                    isRecoverable: true
                )
            }

            switch httpResponse.statusCode {
            case 200:
                // Parse organizations array
                do {
                    let organizations = try JSONDecoder().decode([AccountInfo].self, from: data)
                    guard let firstOrg = organizations.first else {
                        throw AppError(
                            code: .apiParsingFailed,
                            message: "No organizations found",
                            technicalDetails: "Organizations array is empty",
                            isRecoverable: false,
                            recoverySuggestion: "Please ensure your Claude account has access to organizations"
                        )
                    }
                    return firstOrg.uuid
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

    /// Fetches real usage data from Claude's API
    func fetchUsageData() async throws -> ClaudeUsage {
        let sessionKey = try readSessionKey()

        // First, get organization ID (pass session key to avoid re-reading from Keychain)
        let orgId = try await fetchOrganizationId(sessionKey: sessionKey)

        async let usageDataTask = performRequest(endpoint: "/organizations/\(orgId)/usage", sessionKey: sessionKey)

        let checkOverage = DataStore.shared.loadCheckOverageLimitEnabled()
        async let overageDataTask: Data? = checkOverage ? performRequest(endpoint: "/organizations/\(orgId)/overage_spend_limit", sessionKey: sessionKey) : nil

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

        return claudeUsage
    }

    private func performRequest(endpoint: String, sessionKey: String) async throws -> Data {
        // Build URL safely
        let url = try URLBuilder(baseURL: baseURL)
            .appendingPath(endpoint)
            .build()

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            throw APIError.unauthorized
        default:
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Error response for \(endpoint): \(errorString)")
            }
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Response Parsing

    private func parseUsageResponse(_ data: Data) throws -> ClaudeUsage {
        // Parse Claude's actual API response structure

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Extract session usage (five_hour)
            var sessionPercentage = 0.0
            var sessionResetTime = Date().addingTimeInterval(5 * 3600)
            if let fiveHour = json["five_hour"] as? [String: Any] {
                if let utilization = fiveHour["utilization"] as? Int {
                    sessionPercentage = Double(utilization)
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
            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let utilization = sevenDay["utilization"] as? Int {
                    weeklyPercentage = Double(utilization)
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
                if let utilization = sevenDayOpus["utilization"] as? Int {
                    opusPercentage = Double(utilization)
                }
            }

            // We don't know user's plan, so we use 0 for limits we can't determine
            let weeklyLimit = Constants.weeklyLimit

            // Calculate token counts from percentages (using weekly limit as reference)
            let sessionTokens = 0  // Can't calculate without knowing plan
            let sessionLimit = 0   // Unknown without plan
            let weeklyTokens = Int(Double(weeklyLimit) * (weeklyPercentage / 100.0))
            let opusTokens = Int(Double(weeklyLimit) * (opusPercentage / 100.0))

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
                costUsed: nil,
                costLimit: nil,
                costCurrency: nil,
                lastUpdated: Date(),
                userTimezone: .current
            )

            return usage
        }

        throw APIError.invalidResponse
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
        conversationRequest.httpMethod = "POST"

        let conversationBody: [String: Any] = [
            "uuid": UUID().uuidString.lowercased(),
            "name": ""
        ]
        conversationRequest.httpBody = try JSONSerialization.data(withJSONObject: conversationBody)

        let (conversationData, conversationResponse) = try await URLSession.shared.data(for: conversationRequest)

        guard let httpResponse = conversationResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

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
        messageRequest.httpMethod = "POST"

        let messageBody: [String: Any] = [
            "prompt": "Hi",
            "model": "claude-3-5-haiku-20241022",  // Cheapest model
            "timezone": "UTC"
        ]
        messageRequest.httpBody = try JSONSerialization.data(withJSONObject: messageBody)

        let (_, messageResponse) = try await URLSession.shared.data(for: messageRequest)

        guard let messageHTTPResponse = messageResponse as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard messageHTTPResponse.statusCode == 200 else {
            throw APIError.serverError(statusCode: messageHTTPResponse.statusCode)
        }

        // Delete the conversation to keep it out of chat history (incognito mode)
        let deleteURL = try URLBuilder(baseURL: baseURL)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations", conversationUUID])
            .build()

        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        deleteRequest.httpMethod = "DELETE"

        // Attempt to delete, but don't fail if deletion fails
        // The session is already initialized, which is the primary goal
        do {
            let (_, deleteResponse) = try await URLSession.shared.data(for: deleteRequest)
            if let deleteHTTPResponse = deleteResponse as? HTTPURLResponse {
                // Successfully deleted conversation - status code 200 or 204 expected
                _ = deleteHTTPResponse.statusCode
            }
        } catch {
            // Silently ignore deletion errors - session is already initialized
        }
    }

}
