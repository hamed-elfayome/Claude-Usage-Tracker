import Foundation

final class GrokUsageProvider: UsageProviderService {
    static let shared = GrokUsageProvider()

    let provider: Provider = .grok
    private let client = GrokCLIClient()

    private init() {}

    func hasCredentials(for profile: Profile) -> Bool {
        profile.provider == .grok && GrokCLIClient.locateExecutable() != nil && GrokCLIClient.authFileExists()
    }

    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        let (activeProfileId, profiles) = await MainActor.run {
            (ProfileManager.shared.activeProfile?.id, ProfileManager.shared.profiles)
        }
        guard Self.mayUseSharedCLI(profile, activeProfileId: activeProfileId, profiles: profiles) else {
            throw AppError(
                code: .providerCredentialsNotFound,
                message: "grok.ambiguous".localized,
                technicalDetails: "The Grok CLI session belongs to one account and is reserved for the active Grok profile",
                isRecoverable: true,
                recoverySuggestion: "grok.login_needed".localized
            )
        }
        guard GrokCLIClient.locateExecutable() != nil else {
            throw AppError(
                code: .providerCredentialsNotFound,
                message: "grok.cli_missing".localized,
                technicalDetails: "grok executable was not found",
                isRecoverable: true,
                recoverySuggestion: "grok.login_needed".localized
            )
        }

        let payload: Data
        do {
            payload = try await client.fetchBillingPayload()
        } catch GrokCLIError.authenticationRequired {
            throw AppError(
                code: .providerAuthExpired,
                message: "grok.login_needed".localized,
                technicalDetails: "Grok CLI billing requires grok login",
                isRecoverable: true,
                recoverySuggestion: "grok.login_needed".localized
            )
        } catch {
            if let previous = profile.claudeUsage {
                return previous
            }
            throw AppError(
                code: .apiServerError,
                message: "grok.unavailable".localized,
                technicalDetails: "Grok CLI billing request failed",
                isRecoverable: true
            )
        }

        guard let quota = GrokBillingParser.quota(from: payload) else {
            if let previous = profile.claudeUsage {
                return previous
            }
            throw AppError(
                code: .apiParsingFailed,
                message: "grok.unavailable".localized,
                technicalDetails: "Billing payload had no weekly usage percent",
                isRecoverable: true
            )
        }
        return GrokBillingParser.usage(from: quota)
    }

    /// The CLI session is one personal account. The active Grok profile may
    /// use it. A non-active profile may use it only when it is the only Grok
    /// profile, so its reading cannot be written into another profile's history.
    static func mayUseSharedCLI(_ profile: Profile, activeProfileId: UUID?, profiles: [Profile]) -> Bool {
        guard profile.provider == .grok else { return false }
        if profile.id == activeProfileId { return true }
        let grokProfiles = profiles.filter { $0.provider == .grok }
        return grokProfiles.count == 1 && grokProfiles.first?.id == profile.id
    }
}
