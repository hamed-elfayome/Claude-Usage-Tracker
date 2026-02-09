import Foundation

/// Service for managing Claude Code statusline configuration.
/// This service handles installation, configuration, and management of the statusline feature
/// for Claude Code terminal integration.
class StatuslineService {
    static let shared = StatuslineService()

    private init() {}

    // MARK: - Embedded Scripts

    /// Swift script that fetches Claude usage data from the API.
    /// Installed to ~/.claude/fetch-claude-usage.swift and executed by the bash statusline script.
    /// Reads CLI credentials from system keychain at runtime to detect the active CLI account.
    /// Falls back to cookie auth from the app's active profile when keychain is unavailable.
    private func generateSwiftScript(
        profileLookup: [String: String],
        appActiveProfileName: String?,
        fallbackSessionKey: String?,
        fallbackOrganizationId: String?
    ) -> String {
        // Build the profile lookup dictionary literal
        let lookupEntries = profileLookup.map { key, value in
            let escapedKey = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedValue = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "    \"\(escapedKey)\": \"\(escapedValue)\""
        }.joined(separator: ",\n")
        let lookupLiteral = profileLookup.isEmpty ? "[:]" : "[\n\(lookupEntries)\n]"

        let appProfileLine = if let name = appActiveProfileName {
            "let appActiveProfileName: String? = \"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        } else {
            "let appActiveProfileName: String? = nil"
        }

        let sessionKeyLine = if let key = fallbackSessionKey {
            "let fallbackSessionKey: String? = \"\(key)\""
        } else {
            "let fallbackSessionKey: String? = nil"
        }

        let orgIdLine = if let orgId = fallbackOrganizationId {
            "let fallbackOrgId: String? = \"\(orgId)\""
        } else {
            "let fallbackOrgId: String? = nil"
        }

        return """
#!/usr/bin/env swift

import Foundation

// Profile lookup: refresh token -> profile name
let profileLookup: [String: String] = \(lookupLiteral)
\(appProfileLine)
\(sessionKeyLine)
\(orgIdLine)

// MARK: - Keychain Reading

func readKeychainCredentials() -> (accessToken: String, refreshToken: String)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-a", NSUserName(), "-w"]
    let pipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = pipe
    process.standardError = errPipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch { return nil }
    guard process.terminationStatus == 0 else { return nil }
    guard let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          let data = raw.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let accessToken = oauth["accessToken"] as? String,
          let refreshToken = oauth["refreshToken"] as? String else { return nil }
    // Check expiry (expiresAt may be seconds or milliseconds)
    if let expiresAt = oauth["expiresAt"] as? TimeInterval {
        let expirySec = expiresAt > 1e12 ? expiresAt / 1000.0 : expiresAt
        if Date().timeIntervalSince1970 > expirySec { return nil }
    }
    return (accessToken, refreshToken)
}

// MARK: - API Calls

func fetchViaCookie(sessionKey: String, orgId: String) async throws -> (utilization: Int, resetsAt: String?) {
    guard !orgId.contains(".."), !orgId.contains("/") else {
        throw NSError(domain: "ClaudeAPI", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid organization ID"])
    }
    guard let url = URL(string: "https://claude.ai/api/organizations/\\(orgId)/usage") else {
        throw NSError(domain: "ClaudeAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }
    var request = URLRequest(url: url)
    request.setValue("sessionKey=\\(sessionKey)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpMethod = "GET"
    return try await performRequest(request)
}

func fetchViaOAuth(accessToken: String) async throws -> (utilization: Int, resetsAt: String?) {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
        throw NSError(domain: "ClaudeAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \\(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpMethod = "GET"
    return try await performRequest(request)
}

func performRequest(_ request: URLRequest) async throws -> (utilization: Int, resetsAt: String?) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw NSError(domain: "ClaudeAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch usage"])
    }
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let fiveHour = json["five_hour"] as? [String: Any],
       let utilization = fiveHour["utilization"] as? Int {
        let resetsAt = fiveHour["resets_at"] as? String
        return (utilization, resetsAt)
    }
    throw NSError(domain: "ClaudeAPI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
}

// MARK: - Main

Task {
    do {
        let result: (utilization: Int, resetsAt: String?)
        var resolvedProfileName: String? = nil
        var pendingRestart = false

        // Try keychain first (live CLI credentials)
        if let keychainCreds = readKeychainCredentials() {
            let cliProfileName = profileLookup[keychainCreds.refreshToken]

            do {
                result = try await fetchViaOAuth(accessToken: keychainCreds.accessToken)
            } catch {
                // OAuth failed (expired token, etc.) - try cookie fallback
                if let sk = fallbackSessionKey, let oid = fallbackOrgId {
                    result = try await fetchViaCookie(sessionKey: sk, orgId: oid)
                } else {
                    throw error
                }
            }

            if let appName = appActiveProfileName {
                if let cliName = cliProfileName, cliName != appName {
                    // CLI is on a known different profile
                    resolvedProfileName = appName
                    pendingRestart = true
                } else {
                    // CLI matches app, or token not in lookup (rotated/re-login)
                    resolvedProfileName = cliProfileName ?? appName
                }
            } else {
                resolvedProfileName = nil
            }
        } else if let sk = fallbackSessionKey, let oid = fallbackOrgId {
            // No keychain (CLI logged out) - fall back to cookie auth
            result = try await fetchViaCookie(sessionKey: sk, orgId: oid)
            resolvedProfileName = appActiveProfileName
        } else {
            print("ERROR:NO_CREDENTIALS")
            exit(1)
        }

        let prefix = resolvedProfileName ?? ""
        let hint = pendingRestart ? "pending restart" : ""
        print("\\(prefix)|\\(result.utilization)|\\(result.resetsAt ?? "")|\\(hint)")
        exit(0)
    } catch {
        print("ERROR:\\(error.localizedDescription)")
        exit(1)
    }
}

RunLoop.main.run()
"""
    }

    /// Placeholder Swift script for when statusline is disabled
    /// This script returns an error indicating no session key is available
    private let placeholderSwiftScript = """
#!/usr/bin/env swift

import Foundation

// No session key available - statusline is disabled
print("ERROR:NO_SESSION_KEY")
exit(1)
"""

    /// Bash script that builds the statusline display.
    /// Installed to ~/.claude/statusline-command.sh and configured in Claude Code settings.json.
    /// Reads user preferences from ~/.claude/statusline-config.txt and displays selected components.
    private let bashScript = """
#!/bin/bash
config_file="$HOME/.claude/statusline-config.txt"
if [ -f "$config_file" ]; then
  source "$config_file"
  show_dir=$SHOW_DIRECTORY
  show_branch=$SHOW_BRANCH
  show_usage=$SHOW_USAGE
  show_bar=$SHOW_PROGRESS_BAR
  show_reset=$SHOW_RESET_TIME
  show_profile=${SHOW_PROFILE:-1}
else
  show_dir=1
  show_branch=1
  show_usage=1
  show_bar=1
  show_reset=1
  show_profile=1
fi

input=$(cat)
current_dir_path=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | sed 's/"current_dir":"//;s/"$//')
current_dir=$(basename "$current_dir_path")
BLUE=$'\\033[0;34m'
GREEN=$'\\033[0;32m'
GRAY=$'\\033[0;90m'
YELLOW=$'\\033[0;33m'
RESET=$'\\033[0m'

# 10-level gradient: dark green → deep red
LEVEL_1=$'\\033[38;5;22m'   # dark green
LEVEL_2=$'\\033[38;5;28m'   # soft green
LEVEL_3=$'\\033[38;5;34m'   # medium green
LEVEL_4=$'\\033[38;5;100m'  # green-yellowish dark
LEVEL_5=$'\\033[38;5;142m'  # olive/yellow-green dark
LEVEL_6=$'\\033[38;5;178m'  # muted yellow
LEVEL_7=$'\\033[38;5;172m'  # muted yellow-orange
LEVEL_8=$'\\033[38;5;166m'  # darker orange
LEVEL_9=$'\\033[38;5;160m'  # dark red
LEVEL_10=$'\\033[38;5;124m' # deep red

# Build components (without separators)
dir_text=""
if [ "$show_dir" = "1" ]; then
  dir_text="${BLUE}${current_dir}${RESET}"
fi

branch_text=""
if [ "$show_branch" = "1" ]; then
  if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -n "$branch" ] && branch_text="${GREEN}⎇ ${branch}${RESET}"
  fi
fi

usage_text=""
if [ "$show_usage" = "1" ]; then
  swift_result=$(swift "$HOME/.claude/fetch-claude-usage.swift" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$swift_result" ]; then
    profile_name=$(echo "$swift_result" | cut -d'|' -f1)
    utilization=$(echo "$swift_result" | cut -d'|' -f2)
    resets_at=$(echo "$swift_result" | cut -d'|' -f3)
    hint=$(echo "$swift_result" | cut -d'|' -f4)

    if [ -n "$utilization" ] && [ "$utilization" != "ERROR" ]; then
      if [ "$utilization" -le 10 ]; then
        usage_color="$LEVEL_1"
      elif [ "$utilization" -le 20 ]; then
        usage_color="$LEVEL_2"
      elif [ "$utilization" -le 30 ]; then
        usage_color="$LEVEL_3"
      elif [ "$utilization" -le 40 ]; then
        usage_color="$LEVEL_4"
      elif [ "$utilization" -le 50 ]; then
        usage_color="$LEVEL_5"
      elif [ "$utilization" -le 60 ]; then
        usage_color="$LEVEL_6"
      elif [ "$utilization" -le 70 ]; then
        usage_color="$LEVEL_7"
      elif [ "$utilization" -le 80 ]; then
        usage_color="$LEVEL_8"
      elif [ "$utilization" -le 90 ]; then
        usage_color="$LEVEL_9"
      else
        usage_color="$LEVEL_10"
      fi

      if [ "$show_bar" = "1" ]; then
        if [ "$utilization" -eq 0 ]; then
          filled_blocks=0
        elif [ "$utilization" -eq 100 ]; then
          filled_blocks=10
        else
          filled_blocks=$(( (utilization * 10 + 50) / 100 ))
        fi
        [ "$filled_blocks" -lt 0 ] && filled_blocks=0
        [ "$filled_blocks" -gt 10 ] && filled_blocks=10
        empty_blocks=$((10 - filled_blocks))

        # Build progress bar safely without seq
        progress_bar=" "
        i=0
        while [ $i -lt $filled_blocks ]; do
          progress_bar="${progress_bar}▓"
          i=$((i + 1))
        done
        i=0
        while [ $i -lt $empty_blocks ]; do
          progress_bar="${progress_bar}░"
          i=$((i + 1))
        done
      else
        progress_bar=""
      fi

      reset_time_display=""
      if [ "$show_reset" = "1" ] && [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
        iso_time=$(echo "$resets_at" | sed 's/\\.[0-9]*Z$//')
        epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$iso_time" "+%s" 2>/dev/null)

        if [ -n "$epoch" ]; then
          # Detect system time format (12h vs 24h) from macOS locale preferences
          time_format=$(defaults read -g AppleICUForce24HourTime 2>/dev/null)
          if [ "$time_format" = "1" ]; then
            # 24-hour format
            reset_time=$(date -r "$epoch" "+%H:%M" 2>/dev/null)
          else
            # 12-hour format (default)
            reset_time=$(date -r "$epoch" "+%I:%M %p" 2>/dev/null)
          fi
          [ -n "$reset_time" ] && reset_time_display=$(printf " → Reset: %s" "$reset_time")
        fi
      fi

      usage_text="${usage_color}Usage: ${utilization}%${progress_bar}${reset_time_display}${RESET}"
    else
      usage_text="${YELLOW}Usage: ~${RESET}"
    fi
  else
    usage_text="${YELLOW}Usage: ~${RESET}"
  fi
fi

profile_text=""
if [ "$show_profile" = "1" ] && [ -n "$profile_name" ]; then
  CYAN=$'\\033[0;36m'
  BLINK=$'\\033[5m'

  # Check for app-driven profile switch (sentinel file)
  sentinel="$HOME/.claude/.statusline-profile-switch"
  if [ -z "$hint" ] && [ -f "$sentinel" ]; then
    sentinel_mtime=$(stat -f %m "$sentinel" 2>/dev/null)
    # Walk up process tree to find the claude process ($PPID is an intermediary shell)
    cli_pid=""
    cur=$PPID
    for _ in 1 2 3 4 5; do
      cname=$(ps -o comm= -p "$cur" 2>/dev/null | xargs basename 2>/dev/null)
      if [ "$cname" = "claude" ]; then
        cli_pid=$cur
        break
      fi
      cur=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
      [ -z "$cur" ] || [ "$cur" = "1" ] && break
    done
    if [ -n "$cli_pid" ]; then
      cli_start=$(ps -o lstart= -p "$cli_pid" 2>/dev/null)
      cli_epoch=$(date -j -f "%a %b %d %T %Y" "$cli_start" "+%s" 2>/dev/null)
      if [ -n "$sentinel_mtime" ] && [ -n "$cli_epoch" ]; then
        if [ "$cli_epoch" -lt "$sentinel_mtime" ]; then
          hint="pending restart"
        else
          rm -f "$sentinel"
        fi
      fi
    fi
  fi

  if [ -n "$hint" ]; then
    profile_text="${CYAN}${profile_name} ${BLINK}${GRAY}(${hint})${RESET}"
  else
    profile_text="${CYAN}${profile_name}${RESET}"
  fi
fi

output=""
separator="${GRAY} │ ${RESET}"

[ -n "$dir_text" ] && output="${dir_text}"

if [ -n "$branch_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${branch_text}"
fi

if [ -n "$profile_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${profile_text}"
fi

if [ -n "$usage_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${usage_text}"
fi

printf "%s\\n" "$output"
"""

    // MARK: - Installation

    /// Installs statusline scripts with credential injection from active profile
    /// - Parameter injectSessionKey: If true, injects credentials and profile lookup into the Swift script
    func installScripts(injectSessionKey: Bool = false) throws {
        let claudeDir = Constants.ClaudePaths.claudeDirectory

        if !FileManager.default.fileExists(atPath: claudeDir.path) {
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        // Install Swift script (with or without credentials)
        let swiftDestination = claudeDir.appendingPathComponent("fetch-claude-usage.swift")
        let swiftScriptContent: String

        if injectSessionKey {
            guard let activeProfile = ProfileManager.shared.activeProfile else {
                throw StatuslineError.noActiveProfile
            }

            let allProfiles = ProfileManager.shared.profiles
            let hasMultipleProfiles = allProfiles.count > 1

            // Build refresh token -> profile name lookup from all profiles
            var profileLookup: [String: String] = [:]
            if hasMultipleProfiles {
                for profile in allProfiles {
                    if let cliJSON = profile.cliCredentialsJSON,
                       let refreshToken = ClaudeCodeSyncService.shared.extractRefreshToken(from: cliJSON) {
                        profileLookup[refreshToken] = profile.name
                    }
                }
            }

            let appActiveProfileName = hasMultipleProfiles ? activeProfile.name : nil

            // Cookie credentials from active profile as fallback
            let fallbackSessionKey = activeProfile.claudeSessionKey
            let fallbackOrganizationId = activeProfile.organizationId

            // The script reads the keychain at runtime for live credentials,
            // so we always install even if stored profile tokens are expired.
            swiftScriptContent = generateSwiftScript(
                profileLookup: profileLookup,
                appActiveProfileName: appActiveProfileName,
                fallbackSessionKey: fallbackSessionKey,
                fallbackOrganizationId: fallbackOrganizationId
            )
            LoggingService.shared.log("Injected credentials from profile '\(activeProfile.name)' into statusline with \(profileLookup.count) profile lookup entries")
        } else {
            // Install placeholder script
            swiftScriptContent = placeholderSwiftScript
            LoggingService.shared.log("Installed placeholder statusline Swift script")
        }

        try swiftScriptContent.write(to: swiftDestination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: swiftDestination.path
        )

        // Install bash script
        let bashDestination = claudeDir.appendingPathComponent("statusline-command.sh")
        try bashScript.write(to: bashDestination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bashDestination.path
        )
    }

    /// Removes the session key from the statusline Swift script
    func removeSessionKeyFromScript() throws {
        let swiftDestination = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("fetch-claude-usage.swift")

        // Replace with placeholder script that returns error
        try placeholderSwiftScript.write(to: swiftDestination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: swiftDestination.path
        )

        LoggingService.shared.log("Removed session key from statusline Swift script")
    }

    // MARK: - Configuration

    func updateConfiguration(
        showDirectory: Bool,
        showBranch: Bool,
        showUsage: Bool,
        showProgressBar: Bool,
        showResetTime: Bool,
        showProfile: Bool
    ) throws {
        let configPath = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("statusline-config.txt")

        let config = """
SHOW_DIRECTORY=\(showDirectory ? "1" : "0")
SHOW_BRANCH=\(showBranch ? "1" : "0")
SHOW_USAGE=\(showUsage ? "1" : "0")
SHOW_PROGRESS_BAR=\(showProgressBar ? "1" : "0")
SHOW_RESET_TIME=\(showResetTime ? "1" : "0")
SHOW_PROFILE=\(showProfile ? "1" : "0")
"""

        try config.write(to: configPath, atomically: true, encoding: .utf8)
    }

    /// Enables or disables statusline in Claude Code settings.json
    /// When enabling, also injects the session key into the Swift script
    /// When disabling, removes the session key from the Swift script
    func updateClaudeCodeSettings(enabled: Bool) throws {
        let settingsPath = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("settings.json")

        let homeDir = Constants.ClaudePaths.homeDirectory.path
        let commandPath = "\(homeDir)/.claude/statusline-command.sh"

        if enabled {
            // Install scripts with session key injection
            try installScripts(injectSessionKey: true)

            // Update settings.json
            var settings: [String: Any] = [:]

            if FileManager.default.fileExists(atPath: settingsPath.path) {
                let existingData = try Data(contentsOf: settingsPath)
                if let existing = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                    settings = existing
                }
            }

            settings["statusLine"] = [
                "type": "command",
                "command": "bash \(commandPath)"
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
            try jsonData.write(to: settingsPath)
        } else {
            // Remove session key from Swift script
            try removeSessionKeyFromScript()

            // Update settings.json
            if FileManager.default.fileExists(atPath: settingsPath.path) {
                let existingData = try Data(contentsOf: settingsPath)
                if var settings = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                    settings.removeValue(forKey: "statusLine")

                    let jsonData = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
                    try jsonData.write(to: settingsPath)
                }
            }
        }
    }

    // MARK: - Status

    var isInstalled: Bool {
        let swiftScript = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("fetch-claude-usage.swift")

        let bashScript = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("statusline-command.sh")

        return FileManager.default.fileExists(atPath: swiftScript.path) &&
               FileManager.default.fileExists(atPath: bashScript.path)
    }

    /// Updates scripts only if already installed (installation is optional)
    func updateScriptsIfInstalled() throws {
        guard isInstalled else { return }
        try installScripts(injectSessionKey: true)
    }

    // MARK: - Profile Switch Sentinel

    private var sentinelPath: URL {
        Constants.ClaudePaths.claudeDirectory.appendingPathComponent(".statusline-profile-switch")
    }

    /// Writes a sentinel file to signal that a profile switch occurred.
    /// The bash statusline script uses this + CLI process start time to detect pending restarts.
    func writePendingRestartSentinel() {
        let path = sentinelPath
        let fm = FileManager.default

        // Ensure directory exists
        let dir = path.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Write (or overwrite) sentinel with current timestamp
        fm.createFile(atPath: path.path, contents: nil)
        LoggingService.shared.log("Wrote statusline profile-switch sentinel")
    }

    /// Removes the sentinel file (e.g. when statusline is disabled).
    func clearPendingRestartSentinel() {
        try? FileManager.default.removeItem(at: sentinelPath)
    }

    /// Checks if active profile has valid credentials (session key or CLI OAuth)
    func hasValidCredentials() -> Bool {
        guard let activeProfile = ProfileManager.shared.activeProfile else {
            return false
        }

        // Cookie-based session
        if let key = activeProfile.claudeSessionKey {
            let validator = SessionKeyValidator()
            if validator.isValid(key) && activeProfile.organizationId != nil {
                return true
            }
        }

        // CLI OAuth token
        if let cliJSON = activeProfile.cliCredentialsJSON,
           !ClaudeCodeSyncService.shared.isTokenExpired(cliJSON),
           ClaudeCodeSyncService.shared.extractAccessToken(from: cliJSON) != nil {
            return true
        }

        return false
    }
}

// MARK: - StatuslineError

enum StatuslineError: Error, LocalizedError {
    case noActiveProfile
    case sessionKeyNotFound
    case organizationNotConfigured
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .noActiveProfile:
            return "No active profile found. Please create or select a profile first."
        case .sessionKeyNotFound:
            return "Session key not found in active profile. Please configure your session key first."
        case .organizationNotConfigured:
            return "Organization not configured in active profile. Please select an organization in the app settings."
        case .noCredentials:
            return "No credentials available. Please configure a Claude.ai session key or sync a CLI account."
        }
    }
}
