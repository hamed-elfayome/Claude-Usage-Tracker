import Foundation

enum ZAIAPIServiceError: LocalizedError, Equatable {
    /// HTTP 401/403, or body error codes 1000/1001/1309 — the key is unusable.
    case invalidKey(String)
    /// Valid key, but no active GLM Coding Plan subscription.
    case noCodingPlan(String)
    case server(code: Int, message: String)
    case network(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidKey(let message):
            return message.isEmpty ? "The z.ai API key was rejected." : message
        case .noCodingPlan(let message):
            return message
        case .server(let code, let message):
            return "z.ai error \(code): \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "z.ai returned an unrecognized response."
        }
    }
}

/// Fetches GLM Coding Plan quota windows from the z.ai monitor API.
///
/// The endpoint is undocumented but stable (the same one z.ai's own web
/// console uses): `GET /api/monitor/usage/quota/limit` with the coding-plan
/// API key as a Bearer token. The service answers 200 even for logical
/// failures — the real status lives in the response body.
final class ZAIAPIService: @unchecked Sendable {
    static let defaultBaseURL = URL(string: "https://api.z.ai")!

    private let baseURL: URL
    private let session: URLSession

    /// Injected transport so tests can stub HTTP responses. Production uses
    /// a shared URLSession.
    typealias DataProvider = (_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    private let dataProvider: DataProvider

    init(
        baseURL: URL = ZAIAPIService.defaultBaseURL,
        session: URLSession = ZAIAPIService.makeSession(),
        dataProvider: DataProvider? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.dataProvider = dataProvider ?? { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ZAIAPIServiceError.network("Non-HTTP response from z.ai")
            }
            return (data, http)
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    // MARK: - Fetch

    func fetchUsage(apiKey: String) async throws -> ZAIUsage {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ZAIAPIServiceError.invalidKey("No z.ai API key is configured.")
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/monitor/usage/quota/limit"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await dataProvider(request)
        } catch {
            throw ZAIAPIServiceError.network(error.localizedDescription)
        }

        if response.statusCode == 401 || response.statusCode == 403 {
            throw ZAIAPIServiceError.invalidKey("The z.ai API key was rejected (HTTP \(response.statusCode)).")
        }
        guard (200...299).contains(response.statusCode) else {
            throw ZAIAPIServiceError.network("HTTP \(response.statusCode)")
        }

        return try Self.parse(data: data, fetchedAt: Date())
    }

    // MARK: - Parsing (pure, unit-tested)

    /// Decodes a quota-limit response body into a `ZAIUsage` snapshot.
    static func parse(data: Data, fetchedAt: Date) throws -> ZAIUsage {
        let decoded: ZAIQuotaResponse
        do {
            decoded = try JSONDecoder().decode(ZAIQuotaResponse.self, from: data)
        } catch {
            throw ZAIAPIServiceError.invalidResponse
        }
        return try Self.parse(response: decoded, fetchedAt: fetchedAt)
    }

    static func parse(response: ZAIQuotaResponse, fetchedAt: Date) throws -> ZAIUsage {
        if response.success != true {
            let code = response.code ?? -1
            let message = response.msg ?? ""
            if code == 1000 || code == 1001 || code == 1309 {
                throw ZAIAPIServiceError.invalidKey(
                    message.isEmpty ? "Authentication failed. Check the z.ai API key." : message
                )
            }
            if message.lowercased().contains("coding plan") {
                throw ZAIAPIServiceError.noCodingPlan(
                    "This z.ai API key has no active GLM Coding Plan."
                )
            }
            throw ZAIAPIServiceError.server(code: code, message: message)
        }

        guard let quotaData = response.data, quotaData.limits != nil else {
            throw ZAIAPIServiceError.invalidResponse
        }

        let account = ZAIAccount(
            planType: quotaData.level?.nilIfBlank
        )
        let rateLimits = (quotaData.limits ?? []).compactMap { limit in
            Self.makeRateLimit(from: limit)
        }

        return ZAIUsage(
            account: account,
            rateLimits: rateLimits,
            lastUpdated: fetchedAt
        )
    }

    /// Normalizes one z.ai limit entry. z.ai has shipped two quota
    /// generations — token-based (`TOKENS_LIMIT`) and credit-based
    /// (`CREDIT_LIMIT`) — with the same `unit` window coding in both:
    /// 3 → 5-hour rolling window, 6 → weekly, 5 → monthly tool calls.
    /// Classification keys off `unit` (stable) rather than `type`.
    private static func makeRateLimit(from limit: ZAIQuotaLimit) -> ZAIRateLimit? {
        guard let type = limit.type else { return nil }
        let unit = limit.unit ?? 0
        let id = "\(type)-\(unit)"

        let kind: ZAIRateLimitKind?
        let windowDurationMinutes: Int?
        switch unit {
        case 3:
            kind = .tokens
            windowDurationMinutes = 5 * 60
        case 6:
            kind = .tokens
            windowDurationMinutes = 7 * 24 * 60
        case 5:
            kind = .toolCalls
            windowDurationMinutes = 30 * 24 * 60
        default:
            kind = ZAIRateLimitKind.kind(type: type, unit: unit)
            windowDurationMinutes = nil
        }

        let usedPercent = limit.percentage ?? Self.derivedPercentage(limit)
        let resetsAt = limit.nextResetTime.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
        }

        return ZAIRateLimit(
            id: id,
            name: Self.displayName(type: type, unit: unit),
            kind: kind,
            primary: ZAIRateLimitWindow(
                usedPercent: usedPercent,
                windowDurationMinutes: windowDurationMinutes,
                resetsAt: resetsAt,
                usedCredits: limit.currentValue,
                totalCredits: limit.usage
            )
        )
    }

    /// Falls back to computing a percentage from consumed/total credits when
    /// z.ai omits the `percentage` field.
    private static func derivedPercentage(_ limit: ZAIQuotaLimit) -> Double {
        guard let total = limit.usage, total > 0,
              let current = limit.currentValue else { return 0 }
        return min(max(current / total * 100.0, 0), 100)
    }

    /// Window-aware name; unit is the discriminator so both quota
    /// generations read correctly.
    private static func displayName(type: String, unit: Int) -> String {
        switch unit {
        case 3: return "Credits · 5-hour window"
        case 6: return "Credits · weekly"
        case 5: return "Web tools · monthly calls"
        default: return type.replacingOccurrences(of: "_LIMIT", with: "").lowercased()
        }
    }
}
