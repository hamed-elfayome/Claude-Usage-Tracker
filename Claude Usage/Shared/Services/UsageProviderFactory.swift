import Foundation

enum UsageProviderFactory {
    static func makeProvider(for profile: Profile) -> UsageProvider {
        switch profile.providerType {
        case .claudeMax:
            return ClaudeMaxProvider(profile: profile)
        case .claudeAPI:
            return ClaudeAPIBillingProvider(profile: profile)
        case .openaiAPI:
            return OpenAIAPIProvider(profile: profile)
        case .codex:
            return CodexProvider(profile: profile)
        }
    }
}
