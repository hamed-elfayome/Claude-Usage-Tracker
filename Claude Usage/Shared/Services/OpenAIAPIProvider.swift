import Foundation

struct OpenAIAPIProvider: UsageProvider {
    let providerType: ProfileProviderType = .openaiAPI
    let profileId: UUID
    let displayName: String

    private static let baseURL = "https://api.openai.com/v1/organization"

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        guard let adminKey = profile.openaiAdminKey else {
            throw OpenAIError.noAdminKey
        }

        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        let startTime = Int(startOfMonth.timeIntervalSince1970)
        let endTime = Int(now.timeIntervalSince1970)

        let costs = try await fetchAllCosts(adminKey: adminKey, startTime: startTime, endTime: endTime)
        let completions = try await fetchAllCompletions(adminKey: adminKey, startTime: startTime, endTime: endTime)

        var dailyCosts: [String: Double] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var totalCents: Int = 0
        var currency = "usd"

        for bucket in costs {
            let dateStr = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(bucket.startTime)))
            let bucketTotal = bucket.results.reduce(0) { $0 + $1.amount.value }
            dailyCosts[dateStr, default: 0] += Double(bucketTotal)
            totalCents += bucketTotal
            if let c = bucket.results.first?.amount.currency {
                currency = c
            }
        }

        var tokensByModel: [String: OpenAIModelTokens] = [:]
        for bucket in completions {
            for result in bucket.results {
                let model = result.model ?? "unknown"
                let existing = tokensByModel[model] ?? OpenAIModelTokens(inputTokens: 0, outputTokens: 0, cachedTokens: 0)
                tokensByModel[model] = OpenAIModelTokens(
                    inputTokens: existing.inputTokens + result.inputTokens,
                    outputTokens: existing.outputTokens + result.outputTokens,
                    cachedTokens: existing.cachedTokens + result.inputCachedTokens
                )
            }
        }

        let usage = OpenAIUsage(
            currentSpendCents: totalCents,
            currency: currency,
            resetsAt: startOfNextMonth,
            dailyCostCents: dailyCosts,
            tokensByModel: tokensByModel.isEmpty ? nil : tokensByModel,
            lastUpdated: now
        )
        return ProfileUsageUpdate(openaiUsage: usage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        guard let adminKey = profile.openaiAdminKey else { return false }
        let now = Int(Date().timeIntervalSince1970)
        let oneDayAgo = now - 86400
        let url = URL(string: "\(Self.baseURL)/costs?start_time=\(oneDayAgo)&end_time=\(now)&bucket_width=1d&limit=1")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    // MARK: - Pagination

    private func fetchAllCosts(adminKey: String, startTime: Int, endTime: Int) async throws -> [CostBucket] {
        var allBuckets: [CostBucket] = []
        var nextPage: String? = nil
        repeat {
            var urlString = "\(Self.baseURL)/costs?start_time=\(startTime)&end_time=\(endTime)&bucket_width=1d&limit=7"
            if let page = nextPage { urlString += "&page=\(page)" }
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try JSONDecoder().decode(CostsPageResponse.self, from: data)
            allBuckets.append(contentsOf: page.data)
            nextPage = page.hasMore ? page.nextPage : nil
        } while nextPage != nil
        return allBuckets
    }

    private func fetchAllCompletions(adminKey: String, startTime: Int, endTime: Int) async throws -> [CompletionsBucket] {
        var allBuckets: [CompletionsBucket] = []
        var nextPage: String? = nil
        repeat {
            var urlString = "\(Self.baseURL)/usage/completions?start_time=\(startTime)&end_time=\(endTime)&bucket_width=1d&group_by[]=model&limit=7"
            if let page = nextPage { urlString += "&page=\(page)" }
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try JSONDecoder().decode(CompletionsPageResponse.self, from: data)
            allBuckets.append(contentsOf: page.data)
            nextPage = page.hasMore ? page.nextPage : nil
        } while nextPage != nil
        return allBuckets
    }

    // MARK: - Response Types

    struct CostsPageResponse: Codable {
        let data: [CostBucket]
        let hasMore: Bool
        let nextPage: String?
        enum CodingKeys: String, CodingKey {
            case data; case hasMore = "has_more"; case nextPage = "next_page"
        }
    }

    struct CostBucket: Codable {
        let startTime: Int
        let endTime: Int
        let results: [CostResult]
        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"; case endTime = "end_time"; case results
        }
    }

    struct CostResult: Codable {
        let amount: CostAmount
        let lineItem: String?
        enum CodingKeys: String, CodingKey {
            case amount; case lineItem = "line_item"
        }
    }

    struct CostAmount: Codable {
        let value: Int
        let currency: String
    }

    struct CompletionsPageResponse: Codable {
        let data: [CompletionsBucket]
        let hasMore: Bool
        let nextPage: String?
        enum CodingKeys: String, CodingKey {
            case data; case hasMore = "has_more"; case nextPage = "next_page"
        }
    }

    struct CompletionsBucket: Codable {
        let startTime: Int
        let endTime: Int
        let results: [CompletionsResult]
        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"; case endTime = "end_time"; case results
        }
    }

    struct CompletionsResult: Codable {
        let inputTokens: Int
        let outputTokens: Int
        let inputCachedTokens: Int
        let model: String?
        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"; case outputTokens = "output_tokens"
            case inputCachedTokens = "input_cached_tokens"; case model
        }
    }

    enum OpenAIError: Error, LocalizedError {
        case noAdminKey
        case invalidResponse
        case unauthorized
        var errorDescription: String? {
            switch self {
            case .noAdminKey: return "No OpenAI Admin API key configured"
            case .invalidResponse: return "Invalid response from OpenAI API"
            case .unauthorized: return "OpenAI Admin API key is invalid or expired"
            }
        }
    }
}
