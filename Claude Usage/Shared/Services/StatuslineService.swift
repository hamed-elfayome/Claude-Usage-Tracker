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
  show_dir=$SHOW_DIRECTORY
  show_branch=$SHOW_BRANCH
  show_context=$SHOW_CONTEXT
  context_as_tokens=$CONTEXT_AS_TOKENS
  show_usage=$SHOW_USAGE
  show_bar=$SHOW_PROGRESS_BAR
  show_pace_marker=$SHOW_PACE_MARKER
  show_reset=$SHOW_RESET_TIME
  use_24h=$USE_24_HOUR_TIME
  show_context_label=$SHOW_CONTEXT_LABEL
  show_usage_label=$SHOW_USAGE_LABEL
  show_reset_label=$SHOW_RESET_LABEL
  color_mode=$COLOR_MODE
  single_color=$SINGLE_COLOR
  show_profile=$SHOW_PROFILE
  profile_name="$PROFILE_NAME"
  pace_marker_step_colors=$PACE_MARKER_STEP_COLORS
else
  show_model=1
  show_dir=1
  show_branch=1
  show_context=1
  context_as_tokens=0
  show_usage=1
  show_bar=1
  show_pace_marker=1
  show_reset=1
  use_24h=0
  show_context_label=1
  show_usage_label=1
  show_reset_label=1
  color_mode="colored"
  single_color="#00BFFF"
  show_profile=0
  profile_name=""
  pace_marker_step_colors=1
fi

input=$(cat)
current_dir_path=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | sed 's/"current_dir":"//;s/"$//')
current_dir=$(basename "$current_dir_path")
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | sed 's/"display_name":"//;s/"$//')

# Function to convert hex color to ANSI escape code
hex_to_ansi() {
  local hex=$1
  hex=${hex#\\#}

  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))

  printf '\\033[38;2;%d;%d;%dm' "$r" "$g" "$b"
}

# Set colors based on mode
RESET=$'\\033[0m'

if [ "$color_mode" = "monochrome" ]; then
  # Monochrome mode - no colors
  BLUE=""
  GREEN=""
  GRAY=""
  YELLOW=""
  CYAN=""
  MAGENTA=""
  LEVEL_1=""
  LEVEL_2=""
  LEVEL_3=""
  LEVEL_4=""
  LEVEL_5=""
  LEVEL_6=""
  LEVEL_7=""
  LEVEL_8=""
  LEVEL_9=""
  LEVEL_10=""
  PACE_COMFORTABLE=""
  PACE_ON_TRACK=""
  PACE_WARMING=""
  PACE_PRESSING=""
  PACE_CRITICAL=""
  PACE_RUNAWAY=""
elif [ "$color_mode" = "singleColor" ]; then
  # Single color mode - use user's chosen color for everything
  single_ansi=$(hex_to_ansi "$single_color")
  BLUE=$single_ansi
  GREEN=$single_ansi
  GRAY=$single_ansi
  YELLOW=$single_ansi
  CYAN=$single_ansi
  MAGENTA=$single_ansi
  LEVEL_1=$single_ansi
  LEVEL_2=$single_ansi
  LEVEL_3=$single_ansi
  LEVEL_4=$single_ansi
  LEVEL_5=$single_ansi
  LEVEL_6=$single_ansi
  LEVEL_7=$single_ansi
  LEVEL_8=$single_ansi
  LEVEL_9=$single_ansi
  LEVEL_10=$single_ansi
  PACE_COMFORTABLE=$single_ansi
  PACE_ON_TRACK=$single_ansi
  PACE_WARMING=$single_ansi
  PACE_PRESSING=$single_ansi
  PACE_CRITICAL=$single_ansi
  PACE_RUNAWAY=$single_ansi
else
  # Colored mode (default) - use full color palette
  BLUE=$'\\033[0;34m'
  GREEN=$'\\033[0;32m'
  GRAY=$'\\033[0;90m'
  YELLOW=$'\\033[0;33m'
  CYAN=$'\\033[0;36m'
  MAGENTA=$'\\033[0;35m'

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

  # 6-tier pace marker colors
  PACE_COMFORTABLE=$'\\033[38;5;34m'  # green
  PACE_ON_TRACK=$'\\033[38;5;37m'     # teal
  PACE_WARMING=$'\\033[38;5;178m'     # yellow
  PACE_PRESSING=$'\\033[38;5;208m'    # orange
  PACE_CRITICAL=$'\\033[38;5;160m'    # red
  PACE_RUNAWAY=$'\\033[38;5;135m'     # purple
fi

# When pace step colors enabled, always use real 6-tier colors regardless of color mode
if [ "$pace_marker_step_colors" != "0" ]; then
  PACE_COMFORTABLE=$'\\033[38;5;34m'
  PACE_ON_TRACK=$'\\033[38;5;37m'
  PACE_WARMING=$'\\033[38;5;178m'
  PACE_PRESSING=$'\\033[38;5;208m'
  PACE_CRITICAL=$'\\033[38;5;160m'
  PACE_RUNAWAY=$'\\033[38;5;135m'
fi

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

profile_text=""
if [ "$show_profile" = "1" ] && [ -n "$profile_name" ]; then
  profile_text="${MAGENTA}${profile_name}${RESET}"
fi

# Context percentage calculation from current_usage tokens
context_text=""
if [ "$show_context" = "1" ]; then
  input_tokens=$(echo "$input" | grep -o '"input_tokens":[0-9]*' | head -1 | sed 's/"input_tokens"://')
  cache_create=$(echo "$input" | grep -o '"cache_creation_input_tokens":[0-9]*' | sed 's/"cache_creation_input_tokens"://')
  cache_read=$(echo "$input" | grep -o '"cache_read_input_tokens":[0-9]*' | sed 's/"cache_read_input_tokens"://')
  context_size=$(echo "$input" | grep -o '"context_window_size":[0-9]*' | sed 's/"context_window_size"://')

  [ -z "$input_tokens" ] && input_tokens=0
  [ -z "$cache_create" ] && cache_create=0
  [ -z "$cache_read" ] && cache_read=0

  if [ -n "$context_size" ] && [ "$context_size" -gt 0 ]; then
    current_tokens=$((input_tokens + cache_create + cache_read))
    context_pct=$((current_tokens * 100 / context_size))

    # Determine color based on percentage
    if [ "$context_pct" -le 50 ]; then
      context_color="$CYAN"
    elif [ "$context_pct" -le 75 ]; then
      context_color="$YELLOW"
    else
      context_color="$LEVEL_9"
    fi

    # Integer percentage for display
    context_int=$context_pct

    # Display as tokens or percentage
    ctx_label=""
    [ "$show_context_label" = "1" ] && ctx_label="Ctx: "

    if [ "$context_as_tokens" = "1" ]; then
      if [ "$current_tokens" -ge 1000 ]; then
        tokens_k=$((current_tokens / 1000))
        context_text="${context_color}${ctx_label}${tokens_k}K${RESET}"
      else
        context_text="${context_color}${ctx_label}${current_tokens}${RESET}"
      fi
    else
      context_text="${context_color}${ctx_label}${context_int}%${RESET}"
    fi
  fi
fi

usage_text=""
if [ "$show_usage" = "1" ]; then
  # Try reading from cache first (written by Claude Usage app on each refresh)
  cache_file="$HOME/.claude/.statusline-usage-cache"
  swift_result=""
  if [ -f "$cache_file" ]; then
    cache_ts=$(grep "^TIMESTAMP=" "$cache_file" 2>/dev/null | cut -d= -f2)
    now_ts=$(date +%s)
    if [ -n "$cache_ts" ]; then
      cache_age=$((now_ts - cache_ts))
      if [ "$cache_age" -lt 300 ]; then
        cache_util=$(grep "^UTILIZATION=" "$cache_file" | cut -d= -f2)
        cache_reset=$(grep "^RESETS_AT=" "$cache_file" | cut -d= -f2)
        if [ -n "$cache_util" ]; then
          swift_result="${cache_util}|${cache_reset}"
        fi
      fi
    fi
  fi

  # Fall back to swift script if cache is stale or missing
  if [ -z "$swift_result" ]; then
    swift_result=$(swift "$HOME/.claude/fetch-claude-usage.swift" 2>/dev/null)
  fi

  if [ $? -eq 0 ] && [ -n "$swift_result" ]; then
    utilization=$(echo "$swift_result" | cut -d'|' -f1)
    resets_at=$(echo "$swift_result" | cut -d'|' -f2)

    # Parse reset epoch once for shared use by pace marker and reset time display
      reset_epoch=""
      if [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
        iso_time=$(echo "$resets_at" | sed 's/\\.[0-9]*Z$//')
        reset_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$iso_time" "+%s" 2>/dev/null)
      fi

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

      # Pace marker: insert colored │ at elapsed time position
      if [ "$show_pace_marker" = "1" ] && [ "$show_bar" = "1" ] && [ -n "$reset_epoch" ]; then
        now_epoch=$(date +%s)
        remaining=$((reset_epoch - now_epoch))
        if [ $remaining -gt 0 ] && [ $remaining -lt 18000 ]; then
          elapsed_secs=$((18000 - remaining))
          marker_pos=$(( (elapsed_secs * 10 + 9000) / 18000 ))
          [ $marker_pos -gt 9 ] && marker_pos=9
          [ $marker_pos -lt 0 ] && marker_pos=0

          # Compute 6-tier pace color (integer math, >= 3% elapsed = 540s)
          pace_color=""
          if [ $elapsed_secs -ge 540 ]; then
            projected_pct=$((utilization * 18000 / elapsed_secs))
            if [ $projected_pct -lt 50 ]; then
              pace_color="$PACE_COMFORTABLE"
            elif [ $projected_pct -lt 75 ]; then
              pace_color="$PACE_ON_TRACK"
            elif [ $projected_pct -lt 90 ]; then
              pace_color="$PACE_WARMING"
            elif [ $projected_pct -lt 100 ]; then
              pace_color="$PACE_PRESSING"
            elif [ $projected_pct -lt 120 ]; then
              pace_color="$PACE_CRITICAL"
            else
              pace_color="$PACE_RUNAWAY"
            fi
          fi

          # Override: use usage bar color if step colors disabled
          if [ "$pace_marker_step_colors" = "0" ]; then
            pace_color="$usage_color"
          fi

          if [ -n "$pace_color" ]; then
            # Replace bar character at marker_pos with bold ┃
            # progress_bar = " " + 10 block chars; marker_pos+1 is the target index
            left="${progress_bar:0:$((marker_pos + 1))}"
            right="${progress_bar:$((marker_pos + 2))}"
            progress_bar="${left}${pace_color}┃${RESET}${usage_color}${right}"
          fi
        fi
      fi

      reset_time_display=""
      if [ "$show_reset" = "1" ] && [ -n "$reset_epoch" ]; then
        epoch=$reset_epoch

        if [ -n "$epoch" ]; then
          # Round to nearest minute to prevent pinballing (e.g., 6:59:45 -> 7:00)
          seconds_part=$((epoch % 60))
          if [ "$seconds_part" -ge 30 ]; then
            epoch=$((epoch + (60 - seconds_part)))
          else
            epoch=$((epoch - seconds_part))
          fi

          # Use user's time format preference from config
          if [ "$use_24h" = "1" ]; then
            # 24-hour format
            reset_time=$(date -r "$epoch" "+%H:%M" 2>/dev/null)
          else
            # 12-hour format (default)
            reset_time=$(date -r "$epoch" "+%I:%M %p" 2>/dev/null)
          fi
          if [ "$show_reset_label" = "1" ]; then
            [ -n "$reset_time" ] && reset_time_display=$(printf " → Reset: %s" "$reset_time")
          else
            [ -n "$reset_time" ] && reset_time_display=$(printf " → %s" "$reset_time")
          fi
        fi
      fi

      if [ "$show_usage_label" = "1" ]; then
        usage_text="${usage_color}Usage: ${utilization}%${progress_bar}${reset_time_display}${RESET}"
      else
        usage_text="${usage_color}${utilization}%${progress_bar}${reset_time_display}${RESET}"
      fi
    else
      if [ "$show_usage_label" = "1" ]; then
        usage_text="${YELLOW}Usage: ~${RESET}"
      else
        usage_text="${YELLOW}~${RESET}"
      fi
    fi
  else
    if [ "$show_usage_label" = "1" ]; then
      usage_text="${YELLOW}Usage: ~${RESET}"
    else
      usage_text="${YELLOW}~${RESET}"
    fi
  fi
fi

output=""
separator="${GRAY} │ ${RESET}"

# New order: Directory → Branch → Model → Context → Usage
# Directory comes first
[ -n "$dir_text" ] && output="${dir_text}"

# Then branch
if [ -n "$branch_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${branch_text}"
fi

# Then model
if [ -n "$model_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${model_text}"
fi

# Then profile
if [ -n "$profile_text" ]; then
  [ -n "$output" ] && output="${output}${separator}"
  output="${output}${profile_text}"
fi

# Then context
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

        print("[StatuslineService] Bash script installed to: \(bashDestination.path)")
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
        showDirectory: Bool,
        showBranch: Bool,
        showContext: Bool,
        contextAsTokens: Bool,
        showUsage: Bool,
        showProgressBar: Bool,
        showPaceMarker: Bool = true,
        paceMarkerStepColors: Bool = true,
        showResetTime: Bool,
        use24HourTime: Bool = false,
        showContextLabel: Bool = true,
        showUsageLabel: Bool = true,
        showResetLabel: Bool = true,
        colorMode: StatuslineColorMode = .colored,
        singleColorHex: String = "#00BFFF",
        showProfile: Bool,
        profileName: String
    ) throws {
        let configPath = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("statusline-config.txt")

        let colorModeString: String
        switch colorMode {
        case .colored:
            colorModeString = "colored"
        case .monochrome:
            colorModeString = "monochrome"
        case .singleColor:
            colorModeString = "singleColor"
        }

        let config = """
SHOW_MODEL=\(showModel ? "1" : "0")
SHOW_DIRECTORY=\(showDirectory ? "1" : "0")
SHOW_BRANCH=\(showBranch ? "1" : "0")
SHOW_CONTEXT=\(showContext ? "1" : "0")
CONTEXT_AS_TOKENS=\(contextAsTokens ? "1" : "0")
SHOW_USAGE=\(showUsage ? "1" : "0")
SHOW_PROGRESS_BAR=\(showProgressBar ? "1" : "0")
SHOW_PACE_MARKER=\(showPaceMarker ? "1" : "0")
PACE_MARKER_STEP_COLORS=\(paceMarkerStepColors ? "1" : "0")
SHOW_RESET_TIME=\(showResetTime ? "1" : "0")
USE_24_HOUR_TIME=\(use24HourTime ? "1" : "0")
SHOW_CONTEXT_LABEL=\(showContextLabel ? "1" : "0")
SHOW_USAGE_LABEL=\(showUsageLabel ? "1" : "0")
SHOW_RESET_LABEL=\(showResetLabel ? "1" : "0")
COLOR_MODE=\(colorModeString)
SINGLE_COLOR=\(singleColorHex)
SHOW_PROFILE=\(showProfile ? "1" : "0")
PROFILE_NAME="\(profileName)"
"""

        try config.write(to: configPath, atomically: true, encoding: .utf8)

        // Debug: Log what was written
        print("[StatuslineService] Config written to: \(configPath.path)")
        print("[StatuslineService] Config content:\n\(config)")
    }

    /// Updates only the profile name in the statusline config file.
    /// Called during profile switches to keep the config in sync.
    func updateProfileNameInConfig(_ profileName: String) throws {
        let configPath = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent("statusline-config.txt")

        guard FileManager.default.fileExists(atPath: configPath.path) else { return }

        var content = try String(contentsOf: configPath, encoding: .utf8)

        if let range = content.range(of: #"PROFILE_NAME="[^"]*""#, options: .regularExpression) {
            content.replaceSubrange(range, with: "PROFILE_NAME=\"\(profileName)\"")
        } else {
            content += "\nPROFILE_NAME=\"\(profileName)\"\n"
        }

        try content.write(to: configPath, atomically: true, encoding: .utf8)
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

    /// Writes usage data to cache file for fast bash script access
    func writeUsageCache(usage: ClaudeUsage, profileName: String? = nil) {
        let cachePath = Constants.ClaudePaths.claudeDirectory
            .appendingPathComponent(".statusline-usage-cache")

        let formatter = ISO8601DateFormatter()
        var cacheContent = """
        UTILIZATION=\(Int(usage.effectiveSessionPercentage))
        RESETS_AT=\(formatter.string(from: usage.sessionResetTime))
        TIMESTAMP=\(Int(Date().timeIntervalSince1970))
        """

        if let name = profileName {
            cacheContent += "\nPROFILE_NAME=\(name)"
        }

        try? cacheContent.write(to: cachePath, atomically: true, encoding: .utf8)
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
