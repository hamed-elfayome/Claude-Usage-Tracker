import Foundation

/// Machine-scoped settings for the local OpenAI Codex CLI integration.
///
/// These settings deliberately live outside `Profile`: Codex owns one active
/// local login, while Claude Usage Tracker profiles model independent Claude
/// accounts.
struct CodexSettings: Codable, Equatable {
    var monitoringEnabled: Bool
    var executablePath: String?
    var menuBarMetric: MetricIconConfig
    var selectedRateLimitID: String?
    var showAccountEmail: Bool
    var notificationsEnabled: Bool
    var notificationThresholds: [Int]

    init(
        monitoringEnabled: Bool = true,
        executablePath: String? = nil,
        menuBarMetric: MetricIconConfig = .codexDefault,
        selectedRateLimitID: String? = nil,
        showAccountEmail: Bool = true,
        notificationsEnabled: Bool = false,
        notificationThresholds: [Int] = [75, 90, 95]
    ) {
        self.monitoringEnabled = monitoringEnabled
        self.executablePath = executablePath?.nilIfBlank
        self.menuBarMetric = menuBarMetric
        self.menuBarMetric.metricType = .codex
        self.selectedRateLimitID = selectedRateLimitID?.nilIfBlank
        self.showAccountEmail = showAccountEmail
        self.notificationsEnabled = notificationsEnabled
        self.notificationThresholds = Self.normalizedThresholds(notificationThresholds)
    }

    private enum CodingKeys: String, CodingKey {
        case monitoringEnabled
        case executablePath
        case menuBarMetric
        case selectedRateLimitID
        case showAccountEmail
        case notificationsEnabled
        case notificationThresholds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .monitoringEnabled) ?? true
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)?.nilIfBlank
        menuBarMetric = try container.decodeIfPresent(MetricIconConfig.self, forKey: .menuBarMetric) ?? .codexDefault
        menuBarMetric.metricType = .codex
        selectedRateLimitID = try container.decodeIfPresent(String.self, forKey: .selectedRateLimitID)?.nilIfBlank
        showAccountEmail = try container.decodeIfPresent(Bool.self, forKey: .showAccountEmail) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        notificationThresholds = Self.normalizedThresholds(
            try container.decodeIfPresent([Int].self, forKey: .notificationThresholds) ?? [75, 90, 95]
        )
    }

    static func migratingLegacyMetric(_ legacyMetric: MetricIconConfig?) -> CodexSettings {
        var settings = CodexSettings()
        if var legacyMetric {
            legacyMetric.metricType = .codex
            settings.menuBarMetric = legacyMetric
        }
        return settings
    }

    private static func normalizedThresholds(_ thresholds: [Int]) -> [Int] {
        Array(Set(thresholds.filter { (1...100).contains($0) })).sorted()
    }
}

struct CodexInstallationDiagnostics: Equatable, Sendable {
    var executablePath: String?
    var version: String?
    var isSignedIn: Bool
    var loginStatus: String?
    var error: String?

    var isInstalled: Bool { executablePath != nil }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
