import Foundation

/// Service for fetching usage data directly from Claude's API
class ClaudeAPIService {
    
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
    private let baseURL = "https://claude.ai/api"
    
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
        
        // Fetch usage data
        let url = URL(string: "\(baseURL)/organizations/\(orgId)/usage")!
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
            // Parse usage data
            let usageData = try parseUsageResponse(data)
            return usageData
            
        case 401, 403:
            throw APIError.unauthorized
        default:
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Error response: \(errorString)")
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
                lastUpdated: Date(),
                userTimezone: .current
            )
            
            return usage
        }

        throw APIError.invalidResponse
    }
}

