import Foundation

struct ClaudeAPIBillingProvider: UsageProvider {
    let providerType: ProfileProviderType = .claudeAPI
    let profileId: UUID
    let displayName: String

    init(profile: Profile) {
        self.profileId = profile.id
        self.displayName = profile.name
    }

    func fetchUsage(for profile: Profile) async throws -> ProfileUsageUpdate {
        let apiService = ClaudeAPIService()
        guard let apiOrgId = profile.apiOrganizationId,
              let apiKey = profile.apiSessionKey else {
            throw ClaudeAPIService.APIError.noSessionKey
        }
        let apiUsage = try await apiService.fetchAPIUsageData(
            organizationId: apiOrgId,
            apiSessionKey: apiKey
        )
        return ProfileUsageUpdate(apiUsage: apiUsage)
    }

    func validateCredentials(for profile: Profile) async throws -> Bool {
        return profile.hasAPIConsole
    }
}
