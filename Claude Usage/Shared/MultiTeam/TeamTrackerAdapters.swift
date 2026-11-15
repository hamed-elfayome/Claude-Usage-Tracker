import Foundation
import CryptoKit

// Real implementations of the TeamTracker protocols (spec §10). No Keychain reads here.

final class ClaudeAPITeamFetcher: TeamUsageFetching, @unchecked Sendable {
    private let api = ClaudeAPIService()

    func fetchOrganizations(sessionKey: String) async throws -> [ClaudeAPIService.AccountInfo] {
        try await api.fetchAllOrganizations(sessionKey: sessionKey)
    }

    func fetchUsageOnly(sessionKey: String, organizationId: String) async throws -> ClaudeUsage {
        try await api.fetchUsageOnly(sessionKey: sessionKey, organizationId: organizationId)
    }

    func fetchUsageViaProvider(_ profile: Profile) async throws -> ClaudeUsage {
        try await ProviderRegistry.service(for: .anthropic).fetchUsage(for: profile)
    }
}

struct StoredCredentialReader: TeamCredentialReading {
    func sessionKey(for p: Profile) -> String? {
        guard let key = p.claudeSessionKey, !key.isEmpty else { return nil }
        return key
    }

    func hasCredential(_ p: Profile) -> Bool {
        sessionKey(for: p) != nil || p.cliCredentialsJSON != nil || p.customKeychainServiceName != nil
    }

    func credentialOrg(for p: Profile) -> (orgId: String?, seat: SeatFingerprint?) {
        let orgId = CredentialOrgParser.orgId(fromCredentialsJSON: p.cliCredentialsJSON)
            ?? CredentialOrgParser.orgId(fromOAuthAccountJSON: p.oauthAccountJSON)
        return (orgId, CredentialOrgParser.seat(fromCredentialsJSON: p.cliCredentialsJSON))
    }

    /// First 16 hex chars of SHA256(session key + refresh token). Never logged.
    func fingerprint(for p: Profile) -> String? {
        var refresh: String?
        if let data = p.cliCredentialsJSON?.data(using: .utf8),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let oauth = root["claudeAiOauth"] as? [String: Any] {
            refresh = oauth["refreshToken"] as? String
        }
        let material = (sessionKey(for: p) ?? "") + (refresh ?? "")
        guard !material.isEmpty else { return nil }
        let hex = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}

extension ProfileManager: TeamProfileStore {
    var trackedProfiles: [Profile] { profiles.filter { $0.provider == .anthropic } }
    var activeProfileId: UUID? { activeProfile?.id }
}

extension UsageHistoryService: PairHistoryRecording {}

@MainActor
final class NoopTeamEventNotifier: TeamEventNotifying {
    func post(_ event: TeamEvent, profiles: [Profile]) {}
}
