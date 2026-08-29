//
//  SupportReminderService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-08-29.
//

import AppKit
import SwiftUI

/// Shows a gentle once-a-month "buy me a coffee" window.
///
/// Cadence rules:
/// - Never within the first 7 days of use (new installs shouldn't be greeted
///   with a donation ask; existing installs start the clock at update time).
/// - At most once every 30 days, counted from the last time the window was
///   SHOWN — dismissing and donating advance the clock identically, so there
///   is no way to be nagged more by declining.
final class SupportReminderService {
    static let shared = SupportReminderService()
    private init() {}

    static let coffeeURL = URL(string: "https://www.buymeacoffee.com/hamedelfayome")!

    private static let minimumDaysBeforeFirstShow = 7.0
    private static let daysBetweenShows = 30.0

    private var window: NSWindow?
    private var timer: Timer?

    /// Call once at app launch. Performs a delayed first check (so the popup
    /// never races the app's own startup UI) and then re-checks twice a day —
    /// enough resolution for a monthly cadence even if the Mac never relaunches
    /// the app.
    func start() {
        // Hidden preview hook: `open "Claude Usage.app" --args -showSupportReminder`
        // presents the window immediately, ignoring the cadence (and without
        // advancing the monthly clock).
        if ProcessInfo.processInfo.arguments.contains("-showSupportReminder") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.presentWindow()
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.showIfDue()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 12 * 60 * 60, repeats: true) { [weak self] _ in
            self?.showIfDue()
        }
    }

    func showIfDue(now: Date = Date()) {
        guard window == nil else { return }

        let store = SharedDataStore.shared
        let firstLaunch = store.supportReminderFirstLaunchAt()
        guard now.timeIntervalSince(firstLaunch) >= Self.minimumDaysBeforeFirstShow * 86_400 else {
            return
        }
        if let lastShown = store.loadSupportReminderLastShownAt(),
           now.timeIntervalSince(lastShown) < Self.daysBetweenShows * 86_400 {
            return
        }

        store.saveSupportReminderLastShownAt(now)
        presentWindow()
    }

    /// Whether the reminder would fire at `now` — split out for unit tests.
    func isDue(now: Date, firstLaunch: Date, lastShown: Date?) -> Bool {
        guard now.timeIntervalSince(firstLaunch) >= Self.minimumDaysBeforeFirstShow * 86_400 else {
            return false
        }
        guard let lastShown = lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= Self.daysBetweenShows * 86_400
    }

    private func presentWindow() {
        let view = SupportReminderView(
            onCoffee: { [weak self] in
                NSWorkspace.shared.open(Self.coffeeURL)
                self?.close()
            },
            onLater: { [weak self] in
                self?.close()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        LoggingService.shared.log("SupportReminder: shown monthly support window")
    }

    private func close() {
        window?.close()
        window = nil
    }
}

// MARK: - View

private struct SupportReminderView: View {
    let onCoffee: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 34))
                .foregroundColor(Color(red: 1.0, green: 0.87, blue: 0.0))
                .padding(.top, 8)

            Text("support.popup_title".localized)
                .font(.system(size: 16, weight: .semibold))

            Text("support.message".localized)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onCoffee) {
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 13))
                    Text("support.buy_coffee".localized)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(red: 1.0, green: 0.87, blue: 0.0))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button("support.popup_later".localized, action: onLater)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)
        }
        .padding(24)
        .frame(width: 320)
    }
}
