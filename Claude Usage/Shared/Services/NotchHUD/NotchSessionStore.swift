//
//  NotchSessionStore.swift
//  Claude Usage
//
//  Main-actor state store for Claude Code sessions observed via hooks.
//  Pure reducer over NotchHookEvent so transitions are unit-testable.
//

import Foundation
import Combine

@MainActor
final class NotchSessionStore: ObservableObject {
    static let shared = NotchSessionStore()

    enum ServerStatus: Equatable {
        case stopped
        case running
        case portBusy
    }

    /// Ordered by startTime (stable row order in the expanded view).
    @Published private(set) var sessions: [ClaudeCodeSession] = []
    /// Surfaced in the settings UI (listening / port busy).
    @Published var serverStatus: ServerStatus = .stopped

    private var staleTimer: Timer?

    /// Injectable clock for tests.
    var now: () -> Date = { Date() }

    var primarySession: ClaudeCodeSession? {
        sessions.max { a, b in
            (a.status.priority, a.lastUpdate.timeIntervalSinceReferenceDate)
                < (b.status.priority, b.lastUpdate.timeIntervalSinceReferenceDate)
        }
    }

    // MARK: - Reducer

    func apply(_ event: NotchHookEvent) {
        switch event {
        case let .sessionStart(id, cwd):
            upsert(id: id, cwd: cwd) { session in
                session.status = .thinking
                session.currentTask = nil
            }

        case let .sessionEnd(id):
            sessions.removeAll { $0.id == id }

        case let .userPromptSubmit(id, cwd, prompt):
            upsert(id: id, cwd: cwd) { session in
                session.status = .thinking
                session.currentTask = nil
                if let prompt = prompt, !prompt.isEmpty {
                    session.lastUserPrompt = String(prompt.prefix(80))
                }
            }

        case let .preToolUse(id, cwd, status, task):
            upsert(id: id, cwd: cwd) { session in
                session.status = status
                session.currentTask = task
            }

        case let .postToolUse(id, cwd):
            upsert(id: id, cwd: cwd) { session in
                session.status = .thinking
                session.hasRecentError = false
            }

        case let .toolFailure(id, cwd):
            upsert(id: id, cwd: cwd) { session in
                session.hasRecentError = true
            }

        case let .stop(id, cwd):
            upsert(id: id, cwd: cwd) { session in
                session.status = .idle
                session.currentTask = nil
            }

        case let .notification(id, cwd, message):
            upsert(id: id, cwd: cwd) { session in
                session.status = .needsAttention
                if let message = message, !message.isEmpty {
                    session.currentTask = String(message.prefix(80))
                }
            }
        }
    }

    /// Updates a session, auto-creating it for out-of-order events (app launched
    /// mid-session, or SessionStart lost). `.needsAttention` is implicitly
    /// cleared by any status-setting transition above.
    private func upsert(id: String, cwd: String? = nil, _ mutate: (inout ClaudeCodeSession) -> Void) {
        let timestamp = now()
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            mutate(&sessions[index])
            sessions[index].lastUpdate = timestamp
            if let cwd = cwd, !cwd.isEmpty { sessions[index].projectPath = cwd }
        } else {
            var session = ClaudeCodeSession(
                id: id,
                status: .thinking,
                currentTask: nil,
                projectPath: cwd,
                startTime: timestamp,
                lastUpdate: timestamp,
                lastUserPrompt: nil
            )
            mutate(&session)
            session.lastUpdate = timestamp
            sessions.append(session)
        }
    }

    // MARK: - Stale sweep

    func startStaleSweep() {
        stopStaleSweep()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sweepStaleSessions() }
        }
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }

    func stopStaleSweep() {
        staleTimer?.invalidate()
        staleTimer = nil
    }

    func sweepStaleSessions() {
        let reference = now()
        sessions.removeAll { session in
            // "Claude is waiting for you" gets a longer grace than normal
            // activity, so the cue isn't swept while the user is away.
            let timeout = session.status == .needsAttention
                ? Constants.NotchHUD.attentionStaleTimeout
                : Constants.NotchHUD.staleSessionTimeout
            return reference.timeIntervalSince(session.lastUpdate) > timeout
        }
    }

    /// Removes everything (feature disabled).
    func reset() {
        sessions.removeAll()
        stopStaleSweep()
    }
}
