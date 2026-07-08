//
//  ClaudeCodeSession.swift
//  Claude Usage
//
//  Data models for live Claude Code session tracking shown in the notch HUD.
//

import Foundation
import SwiftUI

/// A live Claude Code CLI session observed via hook events.
struct ClaudeCodeSession: Identifiable {
    /// Claude Code's own `session_id` from hook payloads.
    let id: String
    var status: SessionStatus
    var currentTask: String?
    var projectPath: String?
    var startTime: Date
    var lastUpdate: Date
    var lastUserPrompt: String?
    /// Set when the most recent tool use failed; cleared on the next successful tool use.
    var hasRecentError: Bool = false

    /// Display name derived from projectPath (last path component) or session ID.
    var displayName: String {
        if let path = projectPath, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return "Session \(id.prefix(5))"
    }
}

/// The current state of a Claude Code session (passive observation only).
enum SessionStatus: String, Codable {
    case thinking
    case writingCode
    case readingFiles
    case runningCommand
    /// Claude Code is waiting for the user in the terminal (permission prompt,
    /// idle notice, …). The HUD only signals this — it never answers on the
    /// user's behalf.
    case needsAttention
    case idle

    var displayText: String {
        switch self {
        case .thinking: return "notch.status.thinking".localized
        case .writingCode: return "notch.status.writing_code".localized
        case .readingFiles: return "notch.status.reading_files".localized
        case .runningCommand: return "notch.status.running_command".localized
        case .needsAttention: return "notch.status.needs_attention".localized
        case .idle: return "notch.status.idle".localized
        }
    }

    var sfSymbolName: String {
        switch self {
        case .thinking: return "brain.head.profile"
        case .writingCode: return "doc.text"
        case .readingFiles: return "doc.text.magnifyingglass"
        case .runningCommand: return "terminal"
        case .needsAttention: return "bell.badge.fill"
        case .idle: return "checkmark.circle"
        }
    }

    /// Single source of truth for the status accent color across all HUD views.
    var tintColor: Color {
        switch self {
        case .thinking: return .purple
        case .writingCode, .readingFiles: return .cyan
        case .runningCommand: return .green
        case .needsAttention: return .orange
        case .idle: return Color(nsColor: .secondaryLabelColor)
        }
    }

    /// Priority for choosing the session shown in the compact notch view
    /// (higher = more urgent).
    var priority: Int {
        switch self {
        case .needsAttention: return 100
        case .runningCommand: return 80
        case .writingCode: return 70
        case .readingFiles: return 60
        case .thinking: return 50
        case .idle: return 10
        }
    }
}
