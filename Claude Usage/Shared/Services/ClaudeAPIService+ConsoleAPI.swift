import Foundation

// MARK: - Console API Methods

extension ClaudeAPIService {

    /// Performs a Console API GET request with network logging
    private func consoleRequest(url: URL, apiSessionKey: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(apiSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        guard let httpResponse = response as? HTTPURLResponse else {
            NetworkLoggerService.shared.logRequest(
                url: url.absoluteString, method: "GET", requestBody: nil,
                responseData: nil, statusCode: nil, duration: duration, error: APIError.invalidResponse
            )
            throw APIError.invalidResponse
        }

        NetworkLoggerService.shared.logRequest(
            url: url.absoluteString, method: "GET", requestBody: nil,
            responseData: data, statusCode: httpResponse.statusCode, duration: duration, error: nil
        )

        return (data, httpResponse)
    }

    /// Fetches organizations from Console API using the provided session key
    func fetchConsoleOrganizations(apiSessionKey: String) async throws -> [APIOrganization] {
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPath("/organizations")
            .build()

        let (data, httpResponse) = try await consoleRequest(url: url, apiSessionKey: apiSessionKey)

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
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/current_spend"])
            .build()

        let (data, httpResponse) = try await consoleRequest(url: url, apiSessionKey: apiSessionKey)

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
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/prepaid/credits"])
            .build()

        let (data, httpResponse) = try await consoleRequest(url: url, apiSessionKey: apiSessionKey)

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(PrepaidCreditsResponse.self, from: data)
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches usage cost data from Platform API for the current billing month
    func fetchUsageCost(organizationId: String, apiSessionKey: String) async throws -> UsageCostResponse {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/workspaces/default/usage_cost"])
            .addingQueryParameter(name: "starting_on", value: dateFormatter.string(from: startOfMonth))
            .addingQueryParameter(name: "ending_before", value: dateFormatter.string(from: startOfNextMonth))
            .addingQueryParameter(name: "group_by", value: "api_key_id")
            .build()

        let (data, httpResponse) = try await consoleRequest(url: url, apiSessionKey: apiSessionKey)

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(UsageCostResponse.self, from: data)
            } catch let decodingError as DecodingError {
                let detail: String
                switch decodingError {
                case .keyNotFound(let key, let ctx):
                    detail = "keyNotFound: \(key.stringValue) at \(ctx.codingPath.map(\.stringValue))"
                case .valueNotFound(let type, let ctx):
                    detail = "valueNotFound: \(type) at \(ctx.codingPath.map(\.stringValue))"
                case .typeMismatch(let type, let ctx):
                    detail = "typeMismatch: \(type) at \(ctx.codingPath.map(\.stringValue))"
                case .dataCorrupted(let ctx):
                    detail = "dataCorrupted at \(ctx.codingPath.map(\.stringValue))"
                @unknown default:
                    detail = "unknown: \(decodingError)"
                }
                let preview = String(data: data.prefix(2000), encoding: .utf8) ?? "non-utf8"
                LoggingService.shared.log("fetchUsageCost decode error: \(detail)")
                LoggingService.shared.log("fetchUsageCost raw response: \(preview)")
                throw decodingError
            }
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetches API key names for the given organization (non-fatal if it fails)
    func fetchAPIKeys(organizationId: String, apiSessionKey: String) async throws -> [String: String] {
        let url = try URLBuilder(baseURL: consoleBaseURL)
            .appendingPathComponents(["/organizations", organizationId, "/api_keys"])
            .addingQueryParameter(name: "status", value: "active")
            .build()

        let (data, httpResponse) = try await consoleRequest(url: url, apiSessionKey: apiSessionKey)

        switch httpResponse.statusCode {
        case 200:
            if let keysResponse = try? JSONDecoder().decode(APIKeysResponse.self, from: data) {
                return Dictionary(uniqueKeysWithValues: keysResponse.data.map { ($0.id, $0.name) })
            }
            if let keys = try? JSONDecoder().decode([APIKeyInfo].self, from: data) {
                return Dictionary(uniqueKeysWithValues: keys.map { ($0.id, $0.name) })
            }
            return [:]
        case 401, 403:
            throw APIError.unauthorized
        case 404:
            return [:]
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
        var costSources: [APICostSource]?
        var dailyTotals: [String: Double] = [:]
        do {
            let costResponse = try await fetchUsageCost(organizationId: organizationId, apiSessionKey: apiSessionKey)

            // Fetch API key names (non-fatal if it fails)
            var keyNames: [String: String] = [:]
            do {
                keyNames = try await fetchAPIKeys(organizationId: organizationId, apiSessionKey: apiSessionKey)
            } catch {
                LoggingService.shared.logAPIError("fetchAPIKeys", error: error)
            }

            var total = 0.0
            var modelCosts: [String: Double] = [:]
            var perKeyTotal: [String: Double] = [:]
            var perKeyModels: [String: [String: Double]] = [:]

            func processEntry(_ entry: UsageCostEntry, modelName: String, dateKey: String) {
                let cost = entry.safeTotal
                let key = entry.safeKeyId
                total += cost
                modelCosts[modelName, default: 0] += cost
                perKeyTotal[key, default: 0] += cost
                perKeyModels[key, default: [:]][modelName, default: 0] += cost
                dailyTotals[dateKey, default: 0] += cost
            }

            if let costs = costResponse.costs {
                for (dateKey, entries) in costs {
                    for entry in entries {
                        let cleanName = entry.safeModelName.replacingOccurrences(of: " Usage", with: "")
                        processEntry(entry, modelName: cleanName, dateKey: dateKey)
                    }
                }
            }
            if let webSearchCosts = costResponse.webSearchCosts {
                for (dateKey, entries) in webSearchCosts {
                    for entry in entries {
                        processEntry(entry, modelName: "Web Search", dateKey: dateKey)
                    }
                }
            }
            if let codeExecutionCosts = costResponse.codeExecutionCosts {
                for (dateKey, entries) in codeExecutionCosts {
                    for entry in entries {
                        processEntry(entry, modelName: "Code Execution", dateKey: dateKey)
                    }
                }
            }

            totalCostCents = total
            if !modelCosts.isEmpty {
                costByModel = modelCosts
            }

            if !perKeyTotal.isEmpty {
                costSources = perKeyTotal.map { keyId, keyCents in
                    let name = keyNames[keyId] ?? keyId
                    return APICostSource(
                        keyId: keyId,
                        keyName: name,
                        sourceType: APICostSourceType.detect(from: name),
                        totalCents: keyCents,
                        costByModel: perKeyModels[keyId] ?? [:]
                    )
                }
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
            apiCostByModel: costByModel,
            costBySource: costSources,
            dailyCostCents: dailyTotals.isEmpty ? nil : dailyTotals
        )
    }
}
