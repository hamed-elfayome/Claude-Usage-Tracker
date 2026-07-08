//
//  NotchHookEvent.swift
//  Claude Usage
//
//  Typed events decoded from Claude Code hook payloads, plus the mapping from
//  tool invocations to a display status/task. The notch HUD is a passive
//  observer: events only ever update local display state.
//

import Foundation

/// A passive observation event from a Claude Code hook.
enum NotchHookEvent: Equatable {
    case sessionStart(id: String, cwd: String?)
    case sessionEnd(id: String)
    case userPromptSubmit(id: String, prompt: String?)
    case preToolUse(id: String, cwd: String?, status: SessionStatus, task: String)
    case postToolUse(id: String)
    case toolFailure(id: String)
    case stop(id: String)
    case notification(id: String, message: String?)

    /// The hook URL path suffix each event is received on (after the token segment).
    static let pathSuffixes: [String] = [
        "session-start", "session-end", "user-prompt-submit", "pre-tool-use",
        "post-tool-use", "post-tool-use-failure", "stop", "notification",
    ]

    /// Builds an event from a hook path suffix + parsed JSON payload.
    /// Returns nil for unknown paths or payloads without a session id.
    static func from(pathSuffix: String, payload: [String: Any]) -> NotchHookEvent? {
        guard let sessionId = payload["session_id"] as? String, !sessionId.isEmpty else {
            return nil
        }
        let cwd = payload["cwd"] as? String

        switch pathSuffix {
        case "session-start":
            return .sessionStart(id: sessionId, cwd: cwd)
        case "session-end":
            return .sessionEnd(id: sessionId)
        case "user-prompt-submit":
            return .userPromptSubmit(id: sessionId, prompt: payload["prompt"] as? String)
        case "pre-tool-use":
            let activity = ToolActivityMapper.map(
                toolName: payload["tool_name"] as? String ?? "",
                toolInput: payload["tool_input"] as? [String: Any]
            )
            return .preToolUse(id: sessionId, cwd: cwd, status: activity.status, task: activity.task)
        case "post-tool-use":
            return .postToolUse(id: sessionId)
        case "post-tool-use-failure":
            return .toolFailure(id: sessionId)
        case "stop":
            return .stop(id: sessionId)
        case "notification":
            return .notification(id: sessionId, message: payload["message"] as? String)
        default:
            return nil
        }
    }
}

/// Maps a Claude Code tool invocation to a HUD status + short task description.
enum ToolActivityMapper {
    static func map(toolName: String, toolInput: [String: Any]?) -> (status: SessionStatus, task: String) {
        func fileName() -> String {
            let path = toolInput?["file_path"] as? String ?? ""
            return (path as NSString).lastPathComponent
        }

        switch toolName {
        case "Bash":
            let command = toolInput?["command"] as? String ?? ""
            return (.runningCommand, command.isEmpty
                ? "notch.task.running_command".localized
                : String(command.prefix(60)))
        case "Write":
            return (.writingCode, "notch.task.writing".localized(with: fileName()))
        case "Edit", "MultiEdit", "NotebookEdit":
            return (.writingCode, "notch.task.editing".localized(with: fileName()))
        case "Read":
            return (.readingFiles, "notch.task.reading".localized(with: fileName()))
        case "Glob", "Grep":
            return (.readingFiles, "notch.task.searching".localized)
        case "Task", "Agent":
            return (.thinking, "notch.task.subagent".localized)
        case "WebFetch", "WebSearch":
            return (.readingFiles, "notch.task.web".localized)
        default:
            return (.thinking, toolName)
        }
    }
}
