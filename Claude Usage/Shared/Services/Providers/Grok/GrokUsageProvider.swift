import Foundation

final class GrokUsageProvider: UsageProviderService {
    static let shared = GrokUsageProvider()

    let provider: Provider = .grok
    private let profileContext: @MainActor () -> (activeID: UUID?, profiles: [Profile])
    private let billingPayload: (URL) async throws -> Data

    init(
        profileContext: @escaping @MainActor () -> (activeID: UUID?, profiles: [Profile]) = {
            (ProfileManager.shared.activeProfile?.id, ProfileManager.shared.profiles)
        },
        billingPayload: @escaping (URL) async throws -> Data = { try await GrokCLIClient(home: $0).fetchBillingPayload() }
    ) {
        self.profileContext = profileContext
        self.billingPayload = billingPayload
    }

    func hasCredentials(for profile: Profile) -> Bool {
        profile.provider == .grok && profile.hasUsageCredentials
    }

    func fetchUsage(for profile: Profile) async throws -> ClaudeUsage {
        let profiles = profileContext().profiles
        guard let stored = profiles.first(where: { $0.id == profile.id && $0.provider == .grok }),
              profile.provider == .grok, stored.grokHomePath == profile.grokHomePath,
              let home = GrokHome.available(for: profile.id, path: profile.grokHomePath, in: profiles) else { throw Self.ownershipError }
        return try await fetchLiveUsage(in: home)
    }

    func fetchSetupUsage(for profileID: UUID, homePath: String?) async throws -> ClaudeUsage {
        let context = profileContext()
        guard let candidate = Self.setupProfile(for: profileID, activeID: context.activeID, profiles: context.profiles, homePath: homePath),
              let home = GrokHome.resolve(candidate.grokHomePath) else { throw Self.ownershipError }
        return try await fetchLiveUsage(in: home)
    }

    private func fetchLiveUsage(in home: URL) async throws -> ClaudeUsage {
        let payload: Data
        do {
            payload = try await billingPayload(home)
        } catch is CancellationError {
            throw CancellationError()
        } catch GrokCLIError.executableMissing {
            throw AppError(
                code: .providerCredentialsNotFound,
                message: "grok.cli_missing".localized,
                technicalDetails: "grok executable was not found",
                recoverySuggestion: "grok.login_needed".localized
            )
        } catch GrokCLIError.authenticationRequired {
            throw AppError(
                code: .providerAuthExpired,
                message: "grok.login_needed".localized,
                technicalDetails: "Grok CLI billing requires grok login",
                isRecoverable: true,
                recoverySuggestion: "grok.login_needed".localized
            )
        } catch GrokCLIError.timedOut {
            throw AppError.networkTimeout()
        } catch {
            throw AppError(
                code: .apiServerError,
                message: "grok.unavailable".localized,
                technicalDetails: "Grok CLI billing request failed",
                isRecoverable: true
            )
        }

        guard let quota = GrokBillingParser.quota(from: payload) else {
            throw AppError(
                code: .apiParsingFailed,
                message: "grok.unavailable".localized,
                technicalDetails: "Billing payload had no weekly usage percent",
                isRecoverable: true
            )
        }
        return GrokBillingParser.usage(from: quota)
    }

    static func canConfigure(profileID: UUID?, homePath: String?, profiles: [Profile]) -> Bool {
        GrokHome.available(for: profileID, path: homePath, in: profiles) != nil
    }

    /// Read the latest saved profile both before testing and before committing.
    /// A failed or abandoned test must leave the original profile untouched.
    static func setupProfile(for id: UUID, activeID: UUID?, profiles: [Profile], homePath: String?) -> Profile? {
        guard id == activeID, var profile = profiles.first(where: { $0.id == id }),
              let home = GrokHome.available(for: id, path: homePath, in: profiles) else { return nil }
        if profile.provider == .grok {
            guard let current = GrokHome.resolve(profile.grokHomePath), GrokHome.sameDirectory(current, home) else { return nil }
        } else {
            profile.grokHomePath = home.path
            profile.provider = .grok
            profile.claudeUsage = nil
            profile.apiUsage = nil
        }
        return profile
    }

    private static var ownershipError: AppError {
        AppError(code: .providerCredentialsNotFound, message: "grok.ambiguous".localized)
    }
}
