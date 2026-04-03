import Foundation

struct ClaudeMaxProvider: UsageProvider {
    let providerType: ProfileProviderType = .claudeMax
    let profileId: UUID
    let displayName: String

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        let apiService = ClaudeAPIService()
        let usage = try await apiService.fetchUsageData()
        return ProfileUsageUpdate(claudeUsage: usage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        return profile.hasUsageCredentials
    }
}
