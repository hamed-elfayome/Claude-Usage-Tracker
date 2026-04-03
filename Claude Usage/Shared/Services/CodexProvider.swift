import Foundation

struct CodexProvider: UsageProvider {
    let providerType: ProfileProviderType = .codex
    let profileId: UUID
    let displayName: String

    private static let completionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        guard let apiKey = profile.openaiApiKey else {
            throw CodexError.noApiKey
        }
        let request = buildProbeRequest(apiKey: apiKey)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexError.invalidResponse
        }
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 429 else {
            if httpResponse.statusCode == 401 { throw CodexError.unauthorized }
            throw CodexError.serverError(statusCode: httpResponse.statusCode)
        }
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }
        guard let usage = CodexUsage.fromHeaders(headers) else {
            throw CodexError.missingRateLimitHeaders
        }
        return ProfileUsageUpdate(codexUsage: usage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        guard let apiKey = profile.openaiApiKey else { return false }
        let request = buildProbeRequest(apiKey: apiKey)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    func buildProbeRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: Self.completionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ])
        return request
    }

    enum CodexError: Error, LocalizedError {
        case noApiKey, invalidResponse, unauthorized, missingRateLimitHeaders
        case serverError(statusCode: Int)
        var errorDescription: String? {
            switch self {
            case .noApiKey: return "No OpenAI API key configured for Codex probe"
            case .invalidResponse: return "Invalid response from OpenAI API"
            case .unauthorized: return "OpenAI API key is invalid or expired"
            case .missingRateLimitHeaders: return "Rate-limit headers missing from response"
            case .serverError(let code): return "OpenAI API returned status \(code)"
            }
        }
    }
}
