import Foundation

/// Service for fetching usage data directly from Claude's API
class ClaudeAPIService: APIServiceProtocol {
    
    // MARK: - Types
    
    struct UsageResponse: Codable {
        let usage: [UsagePeriod]
        
        struct UsagePeriod: Codable {
            let period: String
            let usageType: String
            let inputTokens: Int
            let outputTokens: Int
            let cacheCreationTokens: Int?
            let cacheReadTokens: Int?
            
            enum CodingKeys: String, CodingKey {
                case period
                case usageType = "usage_type"
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationTokens = "cache_creation_tokens"
                case cacheReadTokens = "cache_read_tokens"
            }
        }
    }
    
    struct AccountInfo: Codable {
        let uuid: String
        let name: String
        let capabilities: [String]
    }
    
    struct OverageSpendLimitResponse: Codable {
        let monthlyCreditLimit: Double?
        let currency: String?
        let usedCredits: Double?
        let isEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case monthlyCreditLimit = "monthly_credit_limit"
            case currency
            case usedCredits = "used_credits"
            case isEnabled = "is_enabled"
        }
    }

    struct CurrentSpendResponse: Codable {
        let amount: Int
        let resetsAt: String

        enum CodingKeys: String, CodingKey {
            case amount
            case resetsAt = "resets_at"
        }
    }

    struct PrepaidCreditsResponse: Codable {
        let amount: Int
        let currency: String
        let autoReloadSettings: AutoReloadSettings?

        enum CodingKeys: String, CodingKey {
            case amount
            case currency
            case autoReloadSettings = "auto_reload_settings"
        }

        struct AutoReloadSettings: Codable {
            let enabled: Bool?
            let threshold: Int?
            let reloadAmount: Int?
        }
    }

    struct ConsoleOrganization: Codable {
        let id: Int
        let uuid: String
        let name: String
    }
    
    enum APIError: Error, LocalizedError {
        case noSessionKey
        case invalidSessionKey
        case networkError(Error)
        case invalidResponse
        case unauthorized
        case serverError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .noSessionKey:
                return "No session key found. Please configure your Claude session key."
            case .invalidSessionKey:
                return "Invalid session key format."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from Claude API."
            case .unauthorized:
                return "Unauthorized. Your session key may have expired."
            case .serverError(let code):
                return "Server error: HTTP \(code)"
            }
        }
    }
    
    // MARK: - Properties

    private let sessionKeyPath: URL
    private let baseURL = Constants.APIEndpoints.claudeBase
    private let consoleBaseURL = Constants.APIEndpoints.consoleBase
    
    // MARK: - Initialization
    
    init(sessionKeyPath: URL? = nil) {
        // Default path: ~/.claude-session-key
        self.sessionKeyPath = sessionKeyPath ?? Constants.ClaudePaths.homeDirectory
            .appendingPathComponent(".claude-session-key")
    }
    
    // MARK: - Session Key Management
    
    /// Reads the session key from manual file only
    private func readSessionKey() throws -> String {
        // Read from manual file: ~/.claude-session-key
        guard FileManager.default.fileExists(atPath: sessionKeyPath.path) else {
            throw APIError.noSessionKey
        }

        let key = try String(contentsOf: sessionKeyPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty && key.hasPrefix("sk-ant-") else {
            throw APIError.noSessionKey
        }

        return key
    }
    
    /// Saves a session key to the configured file path
    func saveSessionKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try trimmedKey.write(to: sessionKeyPath, atomically: true, encoding: .utf8)
        
        // Set restrictive permissions (read/write for owner only)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: sessionKeyPath.path
        )
    }
    
    // MARK: - API Requests
    
    /// Fetches the organization UUID for the authenticated user
    func fetchOrganizationId() async throws -> String {
        let sessionKey = try readSessionKey()
        
        let url = URL(string: "\(baseURL)/organizations")!
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
            // Parse organizations array
            let organizations = try JSONDecoder().decode([AccountInfo].self, from: data)
            guard let firstOrg = organizations.first else {
                throw APIError.invalidResponse
            }
            return firstOrg.uuid
            
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    /// Fetches real usage data from Claude's API
    func fetchUsageData() async throws -> ClaudeUsage {
        let sessionKey = try readSessionKey()
        
        // First, get organization ID
        let orgId = try await fetchOrganizationId()
        
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
        let url = URL(string: "\(baseURL)\(endpoint)")!
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
        let orgId = try await fetchOrganizationId()

        // Create a new conversation
        let conversationURL = URL(string: "\(baseURL)/organizations/\(orgId)/chat_conversations")!
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
        let messageURL = URL(string: "\(baseURL)/organizations/\(orgId)/chat_conversations/\(conversationUUID)/completion")!
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
        let deleteURL = URL(string: "\(baseURL)/organizations/\(orgId)/chat_conversations/\(conversationUUID)")!
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

    // MARK: - Console API Methods

    /// Fetches organizations from Console API using the provided session key
    func fetchConsoleOrganizations(apiSessionKey: String) async throws -> [APIOrganization] {
        let url = URL(string: "\(consoleBaseURL)/organizations")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(apiSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let organizations = try JSONDecoder().decode([ConsoleOrganization].self, from: data)
            return organizations.map { APIOrganization(id: $0.uuid, name: $0.name) }
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches current spend for the given organization from Console API
    private func fetchCurrentSpend(organizationId: String, apiSessionKey: String) async throws -> CurrentSpendResponse {
        let url = URL(string: "\(consoleBaseURL)/organizations/\(organizationId)/current_spend")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(apiSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(CurrentSpendResponse.self, from: data)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches prepaid credits for the given organization from Console API
    private func fetchPrepaidCredits(organizationId: String, apiSessionKey: String) async throws -> PrepaidCreditsResponse {
        let url = URL(string: "\(consoleBaseURL)/organizations/\(organizationId)/prepaid/credits")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(apiSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(PrepaidCreditsResponse.self, from: data)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches complete API usage data for the given organization
    func fetchAPIUsageData(organizationId: String, apiSessionKey: String) async throws -> APIUsage {
        async let spendTask = fetchCurrentSpend(organizationId: organizationId, apiSessionKey: apiSessionKey)
        async let creditsTask = fetchPrepaidCredits(organizationId: organizationId, apiSessionKey: apiSessionKey)

        let spend = try await spendTask
        let credits = try await creditsTask

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetsAt = formatter.date(from: spend.resetsAt) ?? Date()

        return APIUsage(
            currentSpendCents: spend.amount,
            resetsAt: resetsAt,
            prepaidCreditsCents: credits.amount,
            currency: credits.currency
        )
    }
}

