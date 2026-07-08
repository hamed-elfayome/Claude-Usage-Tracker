//
//  NotchExpandedView.swift
//  Claude Usage
//
//  Expanded presentation of the Claude Code HUD: all live sessions with
//  status, current task / last prompt, and elapsed time. One TimelineView
//  drives every duration label (no per-row timers).
//

import SwiftUI

struct NotchExpandedView: View {
    @ObservedObject private var store = NotchSessionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if store.sessions.isEmpty {
                Text("notch.no_sessions".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        ForEach(store.sessions.sorted { $0.startTime < $1.startTime }) { session in
                            NotchSessionRow(session: session, now: context.date)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
        .contentShape(Rectangle())
        .onTapGesture { NotchHUDController.shared.toggleExpanded() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("notch.hud.expanded_title".localized)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if store.sessions.count > 1 {
                Text("\(store.sessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

private struct NotchSessionRow: View {
    let session: ClaudeCodeSession
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: session.status.sfSymbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(session.status.tintColor)
                .symbolEffect(.pulse, isActive: session.status == .needsAttention)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(session.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if session.hasRecentError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
                Text(secondaryLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Text(elapsedText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 3)
    }

    private var secondaryLine: String {
        if let task = session.currentTask, !task.isEmpty {
            return task
        }
        if session.status == .idle, let prompt = session.lastUserPrompt {
            return prompt
        }
        return session.status.displayText
    }

    private var elapsedText: String {
        let seconds = max(0, Int(now.timeIntervalSince(session.startTime)))
        let minutes = seconds / 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d", minutes, seconds % 60)
    }
}
