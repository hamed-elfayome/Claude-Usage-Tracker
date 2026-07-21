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

        NotchSessionStore.shared.startStaleSweep()
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
        NotchSessionStore.shared.reset()
        Task { await notch?.hide() }
    }

    // MARK: - Screen targeting

    /// The screen the HUD presents on: the built-in notched display when one is
    /// attached, else the primary display. DynamicNotchKit defaults every
    /// presentation to `NSScreen.screens[0]` — the *primary* display — so when
    /// an external monitor is set as main the HUD would float at its top edge
    /// instead of hugging the MacBook notch (#294).
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
            ?? NSScreen.screens.first
    }

    // MARK: - Interaction

    /// Tap on the compact HUD toggles the expanded session list.
    func toggleExpanded() {
        guard let notch = dynamicNotch, isVisible else { return }
        let expand = !isExpanded
        isExpanded = expand
        Task {
            if expand, let screen = self.targetScreen {
                await notch.expand(on: screen)
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
        guard let screen = targetScreen else { return }
        if screenHasNotch {
            await notch.compact(on: screen)
        } else {
            await notch.expand(on: screen)
        }
    }

    private func refreshScreenHasNotch() {
        // IMPORTANT: detect on the SAME screen the HUD presents on —
        // targetScreen. NSScreen.main is the KEY-WINDOW screen and is volatile
        // on multi-display setups: sampling it while focus sat on an external
        // monitor cached hasNotch=false and left the HUD in its expanded
        // fallback while rendering at the physical notch.
        guard let screen = targetScreen else {
            screenHasNotch = false
            return
        }
        screenHasNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil

        // Displays changed (plug/unplug, rearrange, main-display swap):
        // DynamicNotchKit re-initializes its window on the PRIMARY display on
        // every screen-parameter change, so always re-apply the presentation
        // on the target screen — not only when hasNotch flipped.
        if isVisible, let notch = dynamicNotch {
            Task {
                if self.isExpanded, let screen = self.targetScreen {
                    await notch.expand(on: screen)
                } else {
                    await self.showCompactState(notch)
                }
            }
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
        store.apply(.notification(id: "mock-2", cwd: nil, message: "Claude needs your permission to use Bash"))
    }
    #endif
}
