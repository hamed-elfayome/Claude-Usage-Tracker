import Foundation

struct ClaudeCodeDiagnostics: Codable {
    let mcpServerCount: Int
    let mcpServersActive: Bool
    let hasClaudeMd: Bool
    let claudeMdSize: Int?
    let hasGlobalClaudeMd: Bool
    let globalClaudeMdSize: Int?
    let settingsEntriesCount: Int
    let hasAutoContext: Bool
    let hasAutoMCP: Bool

    var mcpWarning: Bool {
        mcpServerCount > 3 && mcpServersActive
    }

    var claudeMdWarning: Bool {
        if let size = claudeMdSize, size > 5000 { return true }
        if let size = globalClaudeMdSize, size > 10000 { return true }
        return false
    }
}

struct ClaudeCodeChecklistItem: Identifiable {
    let id = UUID()
    let command: String
    let description: String
    let whenToUse: String
}

final class ClaudeCodeOptimizationService {
    static let shared = ClaudeCodeOptimizationService()

    private init() {}

    func runDiagnostics() -> ClaudeCodeDiagnostics {
        let mcpCount = detectMCPServerCount()
        let mcpActive = detectMCPServersActive()
        let (hasLocalMd, localSize) = detectLocalClaudeMd()
        let (hasGlobalMd, globalSize) = detectGlobalClaudeMd()
        let settingsCount = detectSettingsEntries()
        let autoContext = detectAutoContextEnabled()
        let autoMCP = detectAutoMCP()

        return ClaudeCodeDiagnostics(
            mcpServerCount: mcpCount,
            mcpServersActive: mcpActive,
            hasClaudeMd: hasLocalMd,
            claudeMdSize: localSize,
            hasGlobalClaudeMd: hasGlobalMd,
            globalClaudeMdSize: globalSize,
            settingsEntriesCount: settingsCount,
            hasAutoContext: autoContext,
            hasAutoMCP: autoMCP
        )
    }

    func checklistItems() -> [ClaudeCodeChecklistItem] {
        [
            ClaudeCodeChecklistItem(
                command: "/context",
                description: "Show current context window usage",
                whenToUse: "Before starting a new task to assess available context"
            ),
            ClaudeCodeChecklistItem(
                command: "/clear",
                description: "Clear conversation history",
                whenToUse: "Between unrelated tasks to prevent stale context"
            ),
            ClaudeCodeChecklistItem(
                command: "/compact",
                description: "Compact conversation into a summary",
                whenToUse: "When context is filling up but you want to preserve task state"
            ),
            ClaudeCodeChecklistItem(
                command: "/rewind",
                description: "Rewind to a previous point in conversation",
                whenToUse: "When a recent change derailed the conversation"
            ),
        ]
    }

    func sessionHandoffTemplate() -> String {
        """
        # Session Handoff Summary

        ## Current Task
        [Brief description of what you're working on]

        ## Key Decisions
        - [Decision 1]
        - [Decision 2]

        ## Files Modified
        - `path/to/file.swift`
        - `path/to/config.json`

        ## Next Steps
        1. [Step 1]
        2. [Step 2]

        ## Context Notes
        [Any important context that should carry over]
        """
    }

    private func detectMCPServerCount() -> Int {
        // Check Claude Code settings.json for MCP server count
        let settingsPath = Constants.ClaudePaths.claudeDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 0
        }

        if let mcpServers = json["mcpServers"] as? [String: Any] {
            return mcpServers.count
        }

        return 0
    }

    private func detectMCPServersActive() -> Bool {
        let settingsPath = Constants.ClaudePaths.claudeDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let mcpServers = json["mcpServers"] as? [String: Any], !mcpServers.isEmpty {
            return true
        }

        return false
    }

    private func detectLocalClaudeMd() -> (Bool, Int?) {
        let currentDir = FileManager.default.currentDirectoryPath
        let localPath = URL(fileURLWithPath: currentDir).appendingPathComponent("CLAUDE.md")

        guard FileManager.default.fileExists(atPath: localPath.path) else {
            return (false, nil)
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: localPath.path)
            let size = attrs[.size] as? Int
            return (true, size)
        } catch {
            return (true, nil)
        }
    }

    private func detectGlobalClaudeMd() -> (Bool, Int?) {
        let globalPath = Constants.ClaudePaths.homeDirectory.appendingPathComponent("CLAUDE.md")

        guard FileManager.default.fileExists(atPath: globalPath.path) else {
            return (false, nil)
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: globalPath.path)
            let size = attrs[.size] as? Int
            return (true, size)
        } catch {
            return (true, nil)
        }
    }

    private func detectSettingsEntries() -> Int {
        let settingsPath = Constants.ClaudePaths.claudeDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 0
        }

        // Count top-level entries that might add context
        var count = 0
        for key in ["allowedTools", "mcpServers", "customInstructions", "systemPrompt"] {
            if json[key] != nil { count += 1 }
        }
        return count
    }

    private func detectAutoContextEnabled() -> Bool {
        let settingsPath = Constants.ClaudePaths.claudeDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let autoContext = json["autoContext"] as? Bool {
            return autoContext
        }
        return false
    }

    private func detectAutoMCP() -> Bool {
        let settingsPath = Constants.ClaudePaths.claudeDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let autoMCP = json["autoMCP"] as? Bool {
            return autoMCP
        }
        return false
    }
}