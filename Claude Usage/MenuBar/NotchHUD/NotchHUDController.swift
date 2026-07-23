//
//  NotchHUDController.swift
//  Claude Usage
//
//  Owns the DynamicNotchKit window for the Claude Code HUD and derives its
//  visibility from NotchSessionStore. Pure presentation — session state lives
//  in the store, events come from NotchHookServer.
//

import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchHUDController {
    static let shared = NotchHUDController()

    private var dynamicNotch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView>?
    private var cancellables: Set<AnyCancellable> = []
    private var idleHideTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    private var isVisible = false
    private var isExpanded = false
    private var screenHasNotch = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard dynamicNotch == nil else { return }

        refreshScreenHasNotch()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NotchHUDController.shared.refreshScreenHasNotch() }
        }

        dynamicNotch = DynamicNotch(
            hoverBehavior: [.keepVisible],
            style: .auto,
            expanded: { NotchExpandedView() },
            compactLeading: { NotchCompactLeadingView() },
            compactTrailing: { NotchCompactTrailingView() }
        )

        // Stale-sweep and store reset are owned by AppDelegate: the session
        // store outlives the HUD when Keep Awake's auto mode still needs it.
        NotchSessionStore.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateVisibility(for: sessions)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        idleHideTask?.cancel()
        idleHideTask = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        let notch = dynamicNotch
        dynamicNotch = nil
        isVisible = false
        isExpanded = false
        Task { await notch?.hide() }
    }

    // MARK: - Interaction

    /// Tap on the compact HUD toggles the expanded session list.
    func toggleExpanded() {
        guard let notch = dynamicNotch, isVisible else { return }
        let expand = !isExpanded
        isExpanded = expand
        Task {
            if expand {
                await notch.expand()
            } else {
                await self.showCompactState(notch)
            }
        }
    }

    // MARK: - Visibility policy

    private func updateVisibility(for sessions: [ClaudeCodeSession]) {
        guard let notch = dynamicNotch else { return }
        idleHideTask?.cancel()
        idleHideTask = nil

        guard !sessions.isEmpty else {
            hideNow(notch)
            return
        }

        let allIdle = sessions.allSatisfy { $0.status == .idle }
        if allIdle {
            if SharedDataStore.shared.loadNotchHUDAutoHide() {
                // Debounced hide: one rescheduled task, cancelled by any new event.
                idleHideTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Constants.NotchHUD.idleHideDelay * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.hideNow(notch)
                }
            }
            if !isVisible { showNow(notch) }
            return
        }

        // Active work or attention: ensure visible (never auto-expand — the
        // HUD stays quiet; expansion is a user gesture).
        if !isVisible { showNow(notch) }
    }

    private func showNow(_ notch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView>) {
        isVisible = true
        isExpanded = false
        Task { await self.showCompactState(notch) }
    }

    private func hideNow(_ notch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView>) {
        isVisible = false
        isExpanded = false
        Task { await notch.hide() }
    }

    /// Compact is only rendered over a physical notch; DynamicNotchKit
    /// auto-hides compact on plain displays, so the floating pill uses the
    /// expanded presentation as its resting state there.
    private func showCompactState(_ notch: DynamicNotch<NotchExpandedView, NotchCompactLeadingView, NotchCompactTrailingView>) async {
        if screenHasNotch {
            await notch.compact()
        } else {
            await notch.expand()
        }
    }

    private func refreshScreenHasNotch() {
        // IMPORTANT: detect on the SAME screen DynamicNotchKit presents on —
        // screens[0], the primary display. NSScreen.main is the KEY-WINDOW
        // screen and is volatile on multi-display setups: sampling it while
        // focus sat on an external monitor cached hasNotch=false and left the
        // HUD in its expanded fallback while rendering at the physical notch.
        guard let screen = NSScreen.screens.first else {
            screenHasNotch = false
            return
        }
        let hadNotch = screenHasNotch
        screenHasNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil

        // Displays changed (plug/unplug, rearrange): re-apply the correct
        // resting presentation unless the user explicitly expanded.
        if hadNotch != screenHasNotch, isVisible, !isExpanded, let notch = dynamicNotch {
            Task { await self.showCompactState(notch) }
        }
    }

    // MARK: - DEBUG preview support

    #if DEBUG
    /// Feeds fake sessions through the real store so the HUD can be iterated on
    /// without a live Claude Code session (`--mock-notch` launch argument).
    func injectMockSessions() {
        let store = NotchSessionStore.shared
        store.apply(.sessionStart(id: "mock-1", cwd: "/Users/dev/api-server"))
        store.apply(.preToolUse(id: "mock-1", cwd: nil, status: .runningCommand, task: "swift build"))
        store.apply(.sessionStart(id: "mock-2", cwd: "/Users/dev/webapp"))
        store.apply(.notification(id: "mock-2", message: "Claude needs your permission to use Bash"))
    }
    #endif
}
