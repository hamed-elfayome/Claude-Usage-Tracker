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
    /// The session key and organization ID are injected into this script when statusline is enabled.
    private func generateSwiftScript(sessionKey: String, organizationId: String) -> String {
        return """
#!/usr/bin/env swift

import Foundation
func readSessionKey() -> String? {
    // Session key injected from Keychain by Claude Usage app
    let injectedKey = "\(sessionKey)"
    let trimmedKey = injectedKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedKey.isEmpty ? nil : trimmedKey
}
func readOrganizationId() -> String? {
    // Organization ID injected from settings by Claude Usage app
    let injectedOrgId = "\(organizationId)"
    let trimmedOrgId = injectedOrgId.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedOrgId.isEmpty ? nil : trimmedOrgId
}
func fetchUsageData(sessionKey: String, orgId: String) async throws -> (utilization: Int, resetsAt: String?) {
    // Build URL safely - validate orgId doesn't contain path traversal
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

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
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

// Main execution
// Use Task to run async code, RunLoop keeps script alive until exit() is called
Task {
    guard let sessionKey = readSessionKey() else {
        print("ERROR:NO_SESSION_KEY")
        exit(1)
    }

    guard let orgId = readOrganizationId() else {
        print("ERROR:NO_ORG_CONFIGURED")
        exit(1)
    }

    do {
        let (utilization, resetsAt) = try await fetchUsageData(sessionKey: sessionKey, orgId: orgId)

        // Output format: UTILIZATION|RESETS_AT
        if let resets = resetsAt {
            print("\\(utilization)|\\(resets)")
        } else {
            print("\\(utilization)|")
        }
        exit(0)
    } catch {
        print("ERROR:\\(error.localizedDescription)")
        exit(1)
    }
}

// Keep script alive while async Task executes
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
  show_model=$SHOW_MODEL
  show_context=$SHOW_CONTEXT
  show_dir=$SHOW_DIRECTORY
  show_branch=$SHOW_BRANCH
  show_usage=$SHOW_USAGE
  show_bar=$SHOW_PROGRESS_BAR
  show_reset=$SHOW_RESET_TIME
else
  show_model=1
  show_context=0
  show_dir=1
  show_branch=1
  show_usage=1
  show_bar=1
  show_reset=1
fi

input=$(cat)
current_dir_path=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | sed 's/"current_dir":"//;s/"$//')
current_dir=$(basename "$current_dir_path")
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | sed 's/"display_name":"//;s/"$//')
context_pct=$(echo "$input" | grep -o '"used_percentage":[0-9.]*' | head -1 | sed 's/"used_percentage"://')
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

model_text=""
if [ "$show_model" = "1" ] && [ -n "$model" ]; then
  model_text="${YELLOW}${model}${RESET}"
fi

context_text=""
if [ "$show_context" = "1" ] && [ -n "$context_pct" ]; then
  # Convert to integer for comparison (remove decimal)
  context_int=${context_pct%.*}
  [ -z "$context_int" ] && context_int=0

  # Use same 10-level color gradient as usage
  if [ "$context_int" -le 10 ]; then
    context_color="$LEVEL_1"
  elif [ "$context_int" -le 20 ]; then
    context_color="$LEVEL_2"
  elif [ "$context_int" -le 30 ]; then
    context_color="$LEVEL_3"
  elif [ "$context_int" -le 40 ]; then
    context_color="$LEVEL_4"
  elif [ "$context_int" -le 50 ]; then
    context_color="$LEVEL_5"
  elif [ "$context_int" -le 60 ]; then
    context_color="$LEVEL_6"
  elif [ "$context_int" -le 70 ]; then
    context_color="$LEVEL_7"
  elif [ "$context_int" -le 80 ]; then
    context_color="$LEVEL_8"
  elif [ "$context_int" -le 90 ]; then
    context_color="$LEVEL_9"
  else
    context_color="$LEVEL_10"
  fi

  context_text="${context_color}Ctx: ${context_int}%${RESET}"
fi

usage_text=""
if [ "$show_usage" = "1" ]; then
  swift_result=$(swift "$HOME/.claude/fetch-claude-usage.swift" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$swift_result" ]; then
    utilization=$(echo "$swift_result" | cut -d'|' -f1)
    resets_at=$(echo "$swift_result" | cut -d'|' -f2)

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

output=""
separator="${GRAY} │ ${RESET}"

# Model comes first
[ -n "$model_text" ] && output="${model_text}"

# Then directory
if [ -n "$dir_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${dir_text}"
fi

# Then branch
if [ -n "$branch_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${branch_text}"
fi

# Then context (before usage)
if [ -n "$context_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${context_text}"
fi

# Finally usage
if [ -n "$usage_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${usage_text}"
fi

printf "%s\\n" "$output"
"""

    // MARK: - Installation

    /// Installs statusline scripts with session key injection from active profile
    /// - Parameter injectSessionKey: If true, injects the session key from active profile into the Swift script
    func installScripts(injectSessionKey: Bool = false) throws {
        let claudeDir = Constants.ClaudePaths.claudeDirectory

        if !FileManager.default.fileExists(atPath: claudeDir.path) {
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        // Install Swift script (with or without session key)
        let swiftDestination = claudeDir.appendingPathComponent("fetch-claude-usage.swift")
        let swiftScriptContent: String

        if injectSessionKey {
            // Load session key and org ID from active profile
            guard let activeProfile = ProfileManager.shared.activeProfile else {
                throw StatuslineError.noActiveProfile
            }

            guard let sessionKey = activeProfile.claudeSessionKey else {
                throw StatuslineError.sessionKeyNotFound
            }

            guard let organizationId = activeProfile.organizationId else {
                throw StatuslineError.organizationNotConfigured
            }

            swiftScriptContent = generateSwiftScript(sessionKey: sessionKey, organizationId: organizationId)
            LoggingService.shared.log("Injected session key and org ID from profile '\(activeProfile.name)' into statusline")
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
        showModel: Bool,
        showContext: Bool,
        showDirectory: Bool,
        showBranch: Bool,
        showUsage: Bool,
        showProgressBar: Bool,
        showResetTime: Bool
    ) throws {
        let configPath = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("statusline-config.txt")

        let config = """
SHOW_MODEL=\(showModel ? "1" : "0")
SHOW_CONTEXT=\(showContext ? "1" : "0")
SHOW_DIRECTORY=\(showDirectory ? "1" : "0")
SHOW_BRANCH=\(showBranch ? "1" : "0")
SHOW_USAGE=\(showUsage ? "1" : "0")
SHOW_PROGRESS_BAR=\(showProgressBar ? "1" : "0")
SHOW_RESET_TIME=\(showResetTime ? "1" : "0")
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

    /// Checks if active profile has a valid session key
    func hasValidSessionKey() -> Bool {
        guard let activeProfile = ProfileManager.shared.activeProfile,
              let key = activeProfile.claudeSessionKey else {
            return false
        }

        // Use professional validator for comprehensive validation
        let validator = SessionKeyValidator()
        return validator.isValid(key)
    }
}

// MARK: - StatuslineError

enum StatuslineError: Error, LocalizedError {
    case noActiveProfile
    case sessionKeyNotFound
    case organizationNotConfigured

    var errorDescription: String? {
        switch self {
        case .noActiveProfile:
            return "No active profile found. Please create or select a profile first."
        case .sessionKeyNotFound:
            return "Session key not found in active profile. Please configure your session key first."
        case .organizationNotConfigured:
            return "Organization not configured in active profile. Please select an organization in the app settings."
        }
    }
}
