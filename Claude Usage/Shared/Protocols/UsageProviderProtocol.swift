import Foundation

struct ProfileUsageUpdate {
    var claudeUsage: ClaudeUsage?
    var apiUsage: APIUsage?
    var openaiUsage: OpenAIUsage?
    var codexUsage: CodexUsage?
}

protocol UsageProvider {
    var providerType: ProfileProviderType { get }
    var profileId: UUID { get }
    var displayName: String { get }
    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate
    func validateCredentials(for profile: Profile) async throws -> Bool
}
