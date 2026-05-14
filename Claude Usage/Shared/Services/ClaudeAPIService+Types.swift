import Foundation

// MARK: - API Response Types

extension ClaudeAPIService {
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
        // Existing fields
        let monthlyCreditLimit: Double?
        let currency: String?
        let usedCredits: Double?
        let isEnabled: Bool?

        // Extended fields (present when ?account_uuid=<uuid> query param is supplied)
        let limitType: String?
        let accountEmail: String?
        let accountName: String?
        let groupUuid: String?
        let groupName: String?
        let period: String?
        let disabledReason: String?
        let disabledUntil: String?
        let outOfCredits: Bool?
        let discountPercent: Double?
        let resolvedGroupLimit: Double?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case monthlyCreditLimit   = "monthly_credit_limit"
            case currency
            case usedCredits          = "used_credits"
            case isEnabled            = "is_enabled"
            case limitType            = "limit_type"
            case accountEmail         = "account_email"
            case accountName          = "account_name"
            case groupUuid            = "group_uuid"
            case groupName            = "group_name"
            case period
            case disabledReason       = "disabled_reason"
            case disabledUntil        = "disabled_until"
            case outOfCredits         = "out_of_credits"
            case discountPercent      = "discount_percent"
            case resolvedGroupLimit   = "resolved_group_limit"
            case createdAt            = "created_at"
            case updatedAt            = "updated_at"
        }
    }

    struct OverageCreditGrantResponse: Codable {
        let remainingBalance: Double?
        let currency: String?
        let totalGranted: Double?

        enum CodingKeys: String, CodingKey {
            case remainingBalance = "remaining_balance"
            case currency
            case totalGranted = "total_granted"
        }
    }

    /// Response from GET /v1/code/routines/run-budget
    struct RunBudgetResponse: Codable {
        /// Monthly routine run allowance as a string (e.g. "25")
        let limit: String
        /// Routine runs consumed this month as a string (e.g. "0")
        let used: String
        /// When true, the user's billing is unified and this budget applies
        let unifiedBillingEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case limit
            case used
            case unifiedBillingEnabled = "unified_billing_enabled"
        }

        /// Number of routine runs consumed this month.
        var usedRuns: Int  { Int(used)  ?? 0 }
        /// Monthly routine run allowance.
        var limitRuns: Int { Int(limit) ?? 0 }
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

    struct UsageCostResponse: Codable {
        let costs: [String: [UsageCostEntry]]?
        let webSearchCosts: [String: [UsageCostEntry]]?
        let codeExecutionCosts: [String: [UsageCostEntry]]?

        enum CodingKeys: String, CodingKey {
            case costs
            case webSearchCosts = "web_search_costs"
            case codeExecutionCosts = "code_execution_costs"
        }
    }

    struct UsageCostEntry: Codable {
        let workspaceId: String?
        let keyId: String?
        let modelName: String?
        let total: Double?
        let tokenType: String?
        let usageType: String?

        enum CodingKeys: String, CodingKey {
            case workspaceId = "workspace_id"
            case keyId = "key_id"
            case modelName = "model_name"
            case total
            case tokenType = "token_type"
            case usageType = "usage_type"
        }

        var safeKeyId: String { keyId ?? "unknown" }
        var safeModelName: String { modelName ?? "Unknown" }
        var safeTotal: Double { total ?? 0 }
    }

    struct APIKeyInfo: Codable {
        let id: String
        let name: String
    }

    struct APIKeysResponse: Codable {
        let data: [APIKeyInfo]
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
}
