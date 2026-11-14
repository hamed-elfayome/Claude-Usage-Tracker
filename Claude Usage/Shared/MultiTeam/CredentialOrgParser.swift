import Foundation

/// Pure parsing of org and seat info in stored Claude Code credentials / oauthAccount JSON. Never throws.
enum CredentialOrgParser {
    private static func object(_ json: String?) -> [String: Any]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func nonEmpty(_ dict: [String: Any]?, _ key: String) -> String? {
        guard let s = dict?[key] as? String, !s.isEmpty else { return nil }
        return s
    }

    static func orgId(fromCredentialsJSON json: String?) -> String? {
        guard let root = object(json) else { return nil }
        return nonEmpty(root, "organizationUuid")
            ?? nonEmpty(root["claudeAiOauth"] as? [String: Any], "organizationUuid")
    }

    private static func account(_ json: String?) -> [String: Any]? {
        guard let root = object(json) else { return nil }
        return (root["oauthAccount"] as? [String: Any]) ?? root
    }

    static func orgId(fromOAuthAccountJSON json: String?) -> String? {
        nonEmpty(account(json), "organizationUuid")
    }

    static func orgName(fromOAuthAccountJSON json: String?) -> String? {
        nonEmpty(account(json), "organizationName")
    }

    static func seat(fromCredentialsJSON json: String?) -> SeatFingerprint? {
        let oauth = object(json)?["claudeAiOauth"] as? [String: Any]
        return join([nonEmpty(oauth, "rateLimitTier"), nonEmpty(oauth, "subscriptionType")], .credentials)
    }

    static func seat(rateLimitTier: String?, ravenType: String?, billingType: String?) -> SeatFingerprint? {
        join([rateLimitTier, ravenType, billingType], .orgList)
    }

    private static func join(_ parts: [String?], _ source: SeatFingerprint.Source) -> SeatFingerprint? {
        let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : SeatFingerprint(source: source, value: present.joined(separator: "|"))
    }
}
