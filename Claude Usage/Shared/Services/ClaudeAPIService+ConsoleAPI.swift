import Foundation

// MARK: - Console API Methods

extension ClaudeAPIService {
    /// Platform API base URL for Claude Code metrics
    var platformBaseURL: String {
        Constants.APIEndpoints.platformBase
    }
    /// Fetches organizations from Console/Platform API using the provided session key
    /// Tries platform.claude.com first, falls back to console.anthropic.com
    func fetchConsoleOrganizations(apiSessionKey: String) async throws -> [APIOrganization] {
        // Try platform.claude.com first (newer endpoint)
        do {
            return try await fetchPlatformOrganizations(apiSessionKey: apiSessionKey)
        } catch {
            LoggingService.shared.log("Platform API orgs failed, trying console API: \(error.localizedDescription)")
        }

        // Fallback to console.anthropic.com
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPath("/organizations")
            .build()

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
    func fetchCurrentSpend(organizationId: String, apiSessionKey: String) async throws -> CurrentSpendResponse {
        // Build URL safely
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/current_spend"])
            .build()

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
    func fetchPrepaidCredits(organizationId: String, apiSessionKey: String) async throws -> PrepaidCreditsResponse {
        // Build URL safely
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/prepaid/credits"])
            .build()

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

    // MARK: - Claude Code Team Metrics (platform.claude.com)

    /// Fetches Claude Code user metrics from platform.claude.com
    /// - Parameters:
    ///   - organizationId: The organization UUID
    ///   - apiSessionKey: The session key for authentication
    ///   - userEmail: Optional email to filter for specific user. If nil, returns first user's metrics
    ///   - startDate: Start of the metrics period (defaults to 1 month ago)
    ///   - endDate: End of the metrics period (defaults to today)
    /// - Returns: ClaudeCodeMetrics for the user
    func fetchClaudeCodeUserMetrics(
        organizationId: String,
        apiSessionKey: String,
        userEmail: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> ClaudeCodeMetrics {
        // Calculate date range (default: current month - from 1st of month to today)
        let calendar = Calendar.current
        let end = endDate ?? Date()
        let start: Date
        if let providedStart = startDate {
            start = providedStart
        } else {
            // Default to first day of current month
            let components = calendar.dateComponents([.year, .month], from: end)
            start = calendar.date(from: components) ?? end
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateStr = dateFormatter.string(from: start)
        let endDateStr = dateFormatter.string(from: end)

        // Build URL with query parameters
        // Note: The API uses "organization_uuid" as the parameter name
        let url = try URLBuilder(baseURL: platformBaseURL)
            .appendingPath("/claude_code/metrics_aggs/users")
            .addingQueryParameter(name: "organization_uuid", value: organizationId)
            .addingQueryParameter(name: "start_date", value: startDateStr)
            .addingQueryParameter(name: "end_date", value: endDateStr)
            .addingQueryParameter(name: "limit", value: "10")
            .addingQueryParameter(name: "offset", value: "0")
            .addingQueryParameter(name: "sort_by", value: "total_lines_accepted")
            .addingQueryParameter(name: "sort_order", value: "desc")
            .build()

        LoggingService.shared.log("Platform API request URL: \(url.absoluteString)")
        LoggingService.shared.log("Platform API organization ID: \(organizationId)")

        var request = URLRequest(url: url)
        // Platform API requires specific headers matching web_console client
        request.setValue("sessionKey=\(apiSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("web_console", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("unknown", forHTTPHeaderField: "anthropic-client-version")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Log response for debugging
        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
            LoggingService.shared.logError("Platform API error: HTTP \(httpResponse.statusCode) - \(responseBody.prefix(500))")
        }

        switch httpResponse.statusCode {
        case 200:
            let metricsResponse: ClaudeCodeMetricsResponse
            do {
                metricsResponse = try JSONDecoder().decode(ClaudeCodeMetricsResponse.self, from: data)
            } catch let decodingError as DecodingError {
                let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
                // Log detailed decoding error
                switch decodingError {
                case .keyNotFound(let key, let context):
                    LoggingService.shared.logError("Platform API JSON: Missing key '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    LoggingService.shared.logError("Platform API JSON: Type mismatch for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    LoggingService.shared.logError("Platform API JSON: Value not found for \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    LoggingService.shared.logError("Platform API JSON: Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    LoggingService.shared.logError("Platform API JSON decode error: \(decodingError.localizedDescription)")
                }
                LoggingService.shared.logError("Platform API response body: \(responseBody.prefix(1000))")
                throw decodingError
            } catch {
                let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
                LoggingService.shared.logError("Platform API JSON decode error: \(error.localizedDescription)")
                LoggingService.shared.logError("Platform API response body: \(responseBody.prefix(1000))")
                throw error
            }

            // Find the user's metrics (by email if provided, otherwise use first with valid email)
            let userMetrics: ClaudeCodeUserMetrics?
            if let email = userEmail, !email.isEmpty {
                userMetrics = metricsResponse.users.first { $0.email?.lowercased() == email.lowercased() }
            } else {
                // Get first user with a valid email
                userMetrics = metricsResponse.users.first { $0.email != nil && !$0.email!.isEmpty }
            }

            guard let metrics = userMetrics else {
                throw APIError.serverError(statusCode: 404)
            }

            // Parse dates
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]

            var lastActiveDate: Date? = nil
            if let lastActiveStr = metrics.lastActive {
                lastActiveDate = isoFormatter.date(from: lastActiveStr)
            }

            // Parse cost strings to Double (handle optional fields)
            let totalCost = Double(metrics.totalCost ?? "0") ?? 0.0
            let avgCost = Double(metrics.avgCostPerDay ?? "0") ?? 0.0

            // Calculate team statistics
            let allUsers = metricsResponse.users.filter { $0.email != nil && !$0.email!.isEmpty }
            let teamTotalUsers = allUsers.count

            // Calculate team average cost per day
            var teamAvgCostPerDay: Double? = nil
            if !allUsers.isEmpty {
                let totalTeamAvgCost = allUsers.compactMap { Double($0.avgCostPerDay ?? "0") }.reduce(0, +)
                teamAvgCostPerDay = totalTeamAvgCost / Double(allUsers.count)
            }

            // Calculate user rank by cost (sort descending by total cost)
            let sortedUsers = allUsers.sorted { user1, user2 in
                let cost1 = Double(user1.totalCost ?? "0") ?? 0
                let cost2 = Double(user2.totalCost ?? "0") ?? 0
                return cost1 > cost2
            }

            var userRankByCost: Int? = nil
            if let userEmail = metrics.email {
                userRankByCost = sortedUsers.firstIndex { $0.email?.lowercased() == userEmail.lowercased() }.map { $0 + 1 }
            }

            return ClaudeCodeMetrics(
                totalCost: totalCost,
                avgCostPerDay: avgCost,
                totalSessions: metrics.totalSessions ?? 0,
                totalLinesAccepted: metrics.totalLinesAccepted ?? 0,
                lastActive: lastActiveDate,
                periodStart: start,
                periodEnd: end,
                userEmail: metrics.email,
                prsWithCc: metrics.prsWithCc,
                totalPrs: metrics.totalPrs,
                prsWithCcPercentage: metrics.prsWithCcPercentage.map { $0 * 100 },  // Convert to percentage
                teamAvgCostPerDay: teamAvgCostPerDay,
                teamTotalUsers: teamTotalUsers,
                userRankByCost: userRankByCost
            )

        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches organizations from Platform API (platform.claude.com)
    func fetchPlatformOrganizations(apiSessionKey: String) async throws -> [APIOrganization] {
        // Build URL safely
        let url = try URLBuilder(baseURL: platformBaseURL)
            .appendingPath("/organizations")
            .build()

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(apiSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("web_console", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("unknown", forHTTPHeaderField: "anthropic-client-version")
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode"
            LoggingService.shared.logError("Platform orgs API error: HTTP \(httpResponse.statusCode) - \(responseBody.prefix(300))")
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

    // MARK: - Usage Cost API (for sparkline and model breakdown)

    /// Fetches daily usage costs from console.anthropic.com
    /// - Parameters:
    ///   - organizationId: The organization UUID
    ///   - workspaceId: The workspace UUID
    ///   - apiKeyId: Optional API key ID to filter results
    ///   - apiSessionKey: The session key for authentication
    ///   - startDate: Start of the period
    ///   - endDate: End of the period
    /// - Returns: Array of DailyCost objects
    func fetchUsageCost(
        organizationId: String,
        workspaceId: String,
        apiKeyId: String?,
        apiSessionKey: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [DailyCost] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDateStr = dateFormatter.string(from: startDate)
        let endDateStr = dateFormatter.string(from: endDate)

        // Build URL: /workspaces/{workspace_id}/usage_cost
        var urlBuilder = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/workspaces", workspaceId, "/usage_cost"])
            .addingQueryParameter(name: "starting_on", value: startDateStr)
            .addingQueryParameter(name: "ending_before", value: endDateStr)
            .addingQueryParameter(name: "group_by", value: "api_key_id")

        let url = try urlBuilder.build()

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
            let costResponse = try JSONDecoder().decode(UsageCostResponse.self, from: data)
            return costResponse.toDailyCosts(filterByApiKeyId: apiKeyId)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches API keys for a workspace
    /// - Parameters:
    ///   - organizationId: The organization UUID
    ///   - workspaceId: The workspace UUID
    ///   - apiSessionKey: The session key for authentication
    /// - Returns: Array of APIKeyInfo objects
    func fetchWorkspaceApiKeys(
        organizationId: String,
        workspaceId: String,
        apiSessionKey: String
    ) async throws -> [APIKeyInfo] {
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/workspaces", workspaceId, "/api_keys"])
            .build()

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
            return try JSONDecoder().decode([APIKeyInfo].self, from: data)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches workspaces for an organization
    /// - Parameters:
    ///   - organizationId: The organization UUID
    ///   - apiSessionKey: The session key for authentication
    /// - Returns: Array of WorkspaceInfo objects
    func fetchOrganizationWorkspaces(
        organizationId: String,
        apiSessionKey: String
    ) async throws -> [WorkspaceInfo] {
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/workspaces"])
            .build()

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
            return try JSONDecoder().decode([WorkspaceInfo].self, from: data)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Workspace Info

/// Information about a workspace
struct WorkspaceInfo: Codable, Identifiable {
    let id: String
    let name: String
    let organizationId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case organizationId = "organization_id"
    }
}
