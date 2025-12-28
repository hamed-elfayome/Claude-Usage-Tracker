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
}
