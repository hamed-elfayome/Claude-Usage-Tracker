import Foundation

enum SmartStatusBarRenderer {

    enum AlertLevel: Equatable {
        case none
        case warning
        case critical
    }

    static func profilesForStatusBar(
        _ profiles: [Profile],
        threshold: Double = 60,
        maxItems: Int = 4
    ) -> [Profile] {
        profiles
            .compactMap { profile -> (Profile, Double)? in
                guard let pct = profile.effectivePercentageForThreshold,
                      pct >= threshold else { return nil }
                return (profile, pct)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxItems)
            .map(\.0)
    }

    static func alertLevel(for percentage: Double) -> AlertLevel {
        if percentage >= 90 { return .critical }
        if percentage >= 60 { return .warning }
        return .none
    }

    static func statusBarLabel(for profile: Profile) -> String {
        let pct = profile.effectivePercentageForThreshold ?? 0
        let pctStr = String(format: "%.0f%%", pct)

        switch profile.providerType {
        case .claudeMax:
            let model = profile.primaryModel ?? "opus"
            return "\(profile.name) \(model) \(pctStr)"
        case .codex:
            return "Codex \(pctStr)"
        case .claudeAPI, .openaiAPI:
            if profile.providerType == .claudeAPI, let usage = profile.apiUsage {
                return "\(profile.name) $\(String(format: "%.0f", usage.usedAmount))"
            } else if profile.providerType == .openaiAPI, let usage = profile.openaiUsage {
                return "\(profile.name) $\(String(format: "%.0f", usage.usedAmount))"
            }
            return "\(profile.name) \(pctStr)"
        }
    }
}
