import Foundation

enum ProfileProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case zai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "OpenAI Codex"
        case .zai: return "Z.ai GLM"
        }
    }

    var icon: String {
        switch self {
        case .claude: return "person.crop.circle.fill"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .zai: return "z.square.fill"
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

    private enum CodingKeys: String, CodingKey {
        case connectionType
        case executablePath
        case codexHome
        case sshHost
        case selectedRateLimitID
        case showAccountEmail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath)?.nilIfBlank
        codexHome = try container.decodeIfPresent(String.self, forKey: .codexHome)?.nilIfBlank
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost)?.nilIfBlank
        selectedRateLimitID = try container.decodeIfPresent(
            String.self,
            forKey: .selectedRateLimitID
        )?.nilIfBlank
        showAccountEmail = try container.decodeIfPresent(
            Bool.self,
            forKey: .showAccountEmail
        ) ?? true

        // Early experimental builds predated connectionType. Preserve an SSH
        // target if they already stored a host; otherwise retain the original
        // local behavior.
        connectionType = try container.decodeIfPresent(
            CodexConnectionType.self,
            forKey: .connectionType
        ) ?? (sshHost == nil ? .local : .ssh)
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

    /// Shell commands users can copy to authenticate the exact Codex
    /// installation selected by this profile. In particular, a custom
    /// `CODEX_HOME` must exist and must also be present during `codex login`;
    /// logging into the default home would configure a different account.
    var setupCommands: String {
        let executable = executablePath?.nilIfBlank ?? "codex"
        var commands: [String] = []

        switch connectionType {
        case .local:
            if let codexHome = codexHome?.nilIfBlank {
                commands.append("mkdir -p \(Self.shellQuote(codexHome))")
            }
            let prefix = codexHome?.nilIfBlank.map {
                "env CODEX_HOME=\(Self.shellQuote($0)) "
            } ?? ""
            commands.append("\(prefix)\(Self.shellQuote(executable)) login")
            commands.append("\(prefix)\(Self.shellQuote(executable)) login status")

        case .ssh:
            let host = sshHost?.nilIfBlank ?? "codex-vm"
            let quotedHost = Self.shellQuote(host)
            let prefix = codexHome?.nilIfBlank.map {
                "env CODEX_HOME=\(Self.shellQuote($0)) "
            } ?? ""
            if let codexHome = codexHome?.nilIfBlank {
                let createHome = "mkdir -p \(Self.shellQuote(codexHome))"
                commands.append("ssh \(quotedHost) \(Self.shellQuote(createHome))")
            }
            let login = "\(prefix)\(Self.shellQuote(executable)) login --device-auth"
            let status = "\(prefix)\(Self.shellQuote(executable)) login status"
            commands.append("ssh -t \(quotedHost) \(Self.shellQuote(login))")
            commands.append("ssh \(quotedHost) \(Self.shellQuote(status))")
        }

        return commands.joined(separator: "\n")
    }

    /// Settings that select the Codex installation/account producing a usage
    /// snapshot. Presentation-only choices must not invalidate cached usage.
    func targetsSameInstallation(as other: CodexProfileConfiguration) -> Bool {
        connectionType == other.connectionType
            && executablePath?.nilIfBlank == other.executablePath?.nilIfBlank
            && codexHome?.nilIfBlank == other.codexHome?.nilIfBlank
            && sshHost?.nilIfBlank == other.sshHost?.nilIfBlank
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
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
