import Foundation

enum ProfileProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "OpenAI Codex"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "person.crop.circle.fill"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum CodexConnectionType: String, Codable, CaseIterable, Identifiable {
    case local
    case ssh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "This Mac"
        case .ssh: return "SSH"
        }
    }
}

/// Per-profile connection details for an OpenAI Codex profile.
///
/// SSH authentication deliberately remains in the user's standard macOS SSH
/// configuration and keychain/agent. No passwords or private keys are stored.
struct CodexProfileConfiguration: Codable, Equatable {
    var connectionType: CodexConnectionType
    var executablePath: String?
    var codexHome: String?
    var sshHost: String?
    var selectedRateLimitID: String?
    var showAccountEmail: Bool

    init(
        connectionType: CodexConnectionType = .local,
        executablePath: String? = nil,
        codexHome: String? = nil,
        sshHost: String? = nil,
        selectedRateLimitID: String? = nil,
        showAccountEmail: Bool = true
    ) {
        self.connectionType = connectionType
        self.executablePath = executablePath?.nilIfBlank
        self.codexHome = codexHome?.nilIfBlank
        self.sshHost = sshHost?.nilIfBlank
        self.selectedRateLimitID = selectedRateLimitID?.nilIfBlank
        self.showAccountEmail = showAccountEmail
    }

    var connectionSummary: String {
        switch connectionType {
        case .local:
            return codexHome.map { "This Mac · \($0)" } ?? "This Mac"
        case .ssh:
            return sshHost.map { "SSH · \($0)" } ?? "SSH host not configured"
        }
    }

    var validationError: String? {
        guard connectionType == .ssh else { return nil }
        guard let host = sshHost?.nilIfBlank else { return "Enter an SSH host alias." }
        if host.hasPrefix("-") || host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "The SSH host alias is invalid."
        }
        return nil
    }

    /// Settings that select the Codex installation/account producing a usage
    /// snapshot. Presentation-only choices must not invalidate cached usage.
    func targetsSameInstallation(as other: CodexProfileConfiguration) -> Bool {
        connectionType == other.connectionType
            && executablePath?.nilIfBlank == other.executablePath?.nilIfBlank
            && codexHome?.nilIfBlank == other.codexHome?.nilIfBlank
            && sshHost?.nilIfBlank == other.sshHost?.nilIfBlank
    }
}

/// Legacy machine-scoped settings retained only to migrate the first Codex
/// integration into a real profile. New runtime state belongs to `Profile`.
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

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
