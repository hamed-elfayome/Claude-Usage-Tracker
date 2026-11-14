import Foundation

/// Gives every existing Anthropic profile an `orgTracking` state (spec §9). Pure and idempotent.
enum TeamTrackingMigration {
    static func migrate(_ profile: Profile, now: Date = Date()) -> Profile {
        guard profile.provider == .anthropic, profile.orgTracking == nil else { return profile }

        let account = parseOAuthAccount(profile.oauthAccountJSON)
        let orgId = profile.organizationId ?? account.orgId ?? TrackedOrg.unknownOrgId
        let name = (account.name != nil && account.orgId == orgId) ? account.name! : "Team"

        let org = TrackedOrg(
            orgId: orgId,
            name: name,
            status: .member,
            historyKey: profile.id.uuidString,
            seat: nil,
            lastUsage: profile.claudeUsage,
            lastSampleAt: profile.claudeUsage?.lastUpdated,
            firstSeenAt: now,
            lastSeenInListAt: nil,
            missingFromListCount: 0,
            lastMembershipFailureAt: nil,
            pending: nil,
            baselineStartedAt: now,
            roundReading: nil)

        var migrated = profile
        var state = OrgTrackingState.empty
        state.orgs = [org]
        state.legacyHistoryKeyAssigned = true
        migrated.orgTracking = state
        return migrated
    }

    static func pairHistoryKey(profileId: UUID, orgId: String) -> String {
        "\(profileId.uuidString)_\(orgId)"
    }

    /// Reads `organizationUuid` / `organizationName` from the top level or a nested `oauthAccount`.
    private static func parseOAuthAccount(_ json: String?) -> (orgId: String?, name: String?) {
        guard let data = json?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let dict = (root["oauthAccount"] as? [String: Any]) ?? root
        func nonEmpty(_ k: String) -> String? {
            guard let s = dict[k] as? String, !s.isEmpty else { return nil }
            return s
        }
        return (nonEmpty("organizationUuid"), nonEmpty("organizationName"))
    }
}
