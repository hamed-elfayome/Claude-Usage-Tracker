import Foundation
@testable import Claude_Usage

/// Shared fixtures for multi-team tracking tests (spec §13). They follow the parser, not production recordings.
enum TeamFixtures {
    // MARK: Org lists

    private static func org(_ uuid: String, _ name: String, caps: [String] = ["chat"], tier: String = "default_team_standard") -> String {
        let capsJSON = caps.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"uuid":"\#(uuid)","name":"\#(name)","capabilities":[\#(capsJSON)],"rate_limit_tier":"\#(tier)"}"#
    }

    static let orgsAB = "[\(org("org-a", "Team A")),\(org("org-b", "Team B"))]"
    static let orgsB = "[\(org("org-b", "Team B"))]"
    static let orgsABC = "[\(org("org-a", "Team A")),\(org("org-b", "Team B")),\(org("org-c", "Team C"))]"
    static let orgsAStandard = "[\(org("org-a", "Team A", tier: "default_team_standard"))]"
    static let orgsAPremium = "[\(org("org-a", "Team A", tier: "default_team_premium"))]"
    static let orgsAPIOnly = "[\(org("org-a", "Team A", caps: ["api"]))]"

    // MARK: Usage

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let defaultSessionReset = Date(timeIntervalSince1970: 1_800_000_000)
    static let defaultWeeklyReset = Date(timeIntervalSince1970: 1_800_400_000)

    static func usageJSON(session: Double, weekly: Double,
                          sessionReset: Date = defaultSessionReset,
                          weeklyReset: Date = defaultWeeklyReset,
                          opus: Double? = nil) -> String {
        func window(_ u: Double, _ d: Date) -> String {
            #"{"utilization":\#(u),"resets_at":"\#(isoFormatter.string(from: d))"}"#
        }
        let opusJSON = opus.map { window($0, weeklyReset) } ?? "null"
        return #"{"five_hour":\#(window(session, sessionReset)),"seven_day":\#(window(weekly, weeklyReset)),"seven_day_opus":\#(opusJSON)}"#
    }

    static let usageNoFiveHour = #"{"five_hour":null,"seven_day":{"utilization":47.0,"resets_at":"2026-11-03T17:00:00.036205+00:00"},"seven_day_opus":null}"#

    static func usage(session: Double, weekly: Double,
                      sessionReset: Date = defaultSessionReset,
                      weeklyReset: Date = defaultWeeklyReset,
                      opus: Double? = nil) throws -> ClaudeUsage {
        let json = usageJSON(session: session, weekly: weekly, sessionReset: sessionReset, weeklyReset: weeklyReset, opus: opus)
        return try ClaudeAPIService().parseUsageResponse(Data(json.utf8))
    }

    // MARK: Credentials

    private static func credentials(orgId: String?) -> String {
        let orgPart = orgId.map { #""organizationUuid":"\#($0)","# } ?? ""
        return #"{\#(orgPart)"claudeAiOauth":{"accessToken":"sk-ant-oat-test","refreshToken":"sk-ant-ort-test","expiresAt":1900000000000,"subscriptionType":"team"}}"#
    }

    static let credentialsOrgA = credentials(orgId: "org-a")
    static let credentialsOrgB = credentials(orgId: "org-b")
    static let credentialsNoOrg = credentials(orgId: nil)

    static let oauthAccountOrgA = #"{"accountUuid":"acc-1","emailAddress":"a@example.com","organizationUuid":"org-a","organizationName":"Team A"}"#

    // MARK: Legacy profile

    /// A profile as written before `orgTracking` existed: encode in code, then strip the key.
    static func legacyProfileJSON(_ profile: Profile = Profile(name: "Legacy", organizationId: "org-a")) throws -> Data {
        var copy = profile
        copy.orgTracking = nil
        let data = try JSONEncoder().encode(copy)
        var object = try XCTUnwrapObject(data)
        object.removeValue(forKey: "orgTracking")
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func XCTUnwrapObject(_ data: Data) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "TeamFixtures", code: 1)
        }
        return o
    }
}
