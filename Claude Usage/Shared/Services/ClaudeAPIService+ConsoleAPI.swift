import Foundation

// MARK: - Console API Methods

extension ClaudeAPIService {
    /// Fetches organizations from Console API using the provided session key
    func fetchConsoleOrganizations(apiSessionKey: String) async throws -> [APIOrganization] {
        // Build URL safely
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPath("/organizations")
            .build()

        var request = URLRequest(url: url)
        let safeKey = Self.sanitizeForHeader(apiSessionKey)
        request.setValue("sessionKey=\(safeKey)", forHTTPHeaderField: "Cookie")
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
        let safeKey = Self.sanitizeForHeader(apiSessionKey)
        request.setValue("sessionKey=\(safeKey)", forHTTPHeaderField: "Cookie")
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
        let safeKey = Self.sanitizeForHeader(apiSessionKey)
        request.setValue("sessionKey=\(safeKey)", forHTTPHeaderField: "Cookie")
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

    /// Fetches usage cost for the current billing period from Platform API
    func fetchUsageCost(organizationId: String, apiSessionKey: String) async throws -> UsageCostResponse {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/workspaces/default/usage_cost"])
            .addingQueryParameter(name: "starting_on", value: dateFormatter.string(from: startOfMonth))
            .addingQueryParameter(name: "ending_before", value: dateFormatter.string(from: tomorrow))
            .addingQueryParameter(name: "group_by", value: "api_key_id")
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
            return try JSONDecoder().decode(UsageCostResponse.self, from: data)
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

        // Fetch cost data (non-fatal if it fails)
        var totalCostCents: Double?
        var costByModel: [String: Double]?
        do {
            let costResponse = try await fetchUsageCost(organizationId: organizationId, apiSessionKey: apiSessionKey)
            var total = 0.0
            var modelCosts: [String: Double] = [:]
            for (_, entries) in costResponse.costs {
                for entry in entries {
                    total += entry.total
                    let cleanName = entry.modelName.replacingOccurrences(of: " Usage", with: "")
                    modelCosts[cleanName, default: 0] += entry.total
                }
            }
            // Also include web search and code execution costs in total
            for (_, entries) in costResponse.webSearchCosts {
                for entry in entries {
                    total += entry.total
                    modelCosts["Web Search", default: 0] += entry.total
                }
            }
            for (_, entries) in costResponse.codeExecutionCosts {
                for entry in entries {
                    total += entry.total
                    modelCosts["Code Execution", default: 0] += entry.total
                }
            }
            totalCostCents = total
            if !modelCosts.isEmpty {
                costByModel = modelCosts
            }
        } catch {
            LoggingService.shared.logAPIError("fetchUsageCost", error: error)
        }

        return APIUsage(
            currentSpendCents: spend.amount,
            resetsAt: resetsAt,
            prepaidCreditsCents: credits.amount,
            currency: credits.currency,
            apiTokenCostCents: totalCostCents,
            apiCostByModel: costByModel
        )
    }
}
