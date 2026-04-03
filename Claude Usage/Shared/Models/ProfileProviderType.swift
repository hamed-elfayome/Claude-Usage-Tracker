import Foundation

enum ProfileProviderType: String, Codable, CaseIterable {
    case claudeMax
    case claudeAPI
    case openaiAPI
    case codex

    var displayName: String {
        switch self {
        case .claudeMax: return "Claude Max"
        case .claudeAPI: return "Claude API"
        case .openaiAPI: return "OpenAI API"
        case .codex: return "Codex"
        }
    }

    var iconSystemName: String {
        switch self {
        case .claudeMax: return "brain.head.profile"
        case .claudeAPI: return "server.rack"
        case .openaiAPI: return "cloud"
        case .codex: return "terminal"
        }
    }

    var defaultRefreshInterval: TimeInterval {
        switch self {
        case .claudeMax: return 30
        case .claudeAPI: return 300
        case .openaiAPI: return 300
        case .codex: return 60
        }
    }

    var isPercentageBased: Bool {
        switch self {
        case .claudeMax, .codex: return true
        case .claudeAPI, .openaiAPI: return false
        }
    }
}
