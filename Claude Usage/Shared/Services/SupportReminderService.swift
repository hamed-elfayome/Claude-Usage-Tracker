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
        // Close is the only meaningful window action; hiding the other two
        // stops the traffic-light row from reserving visual weight.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        // Follow the user to their current Space — without this the window can
        // open on another desktop (or be invisible over a full-screen app) and
        // look like it never appeared.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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

    private static let coffeeYellow = Color(red: 1.0, green: 0.87, blue: 0.0)

    /// Whole days this install has been around; the stat line is hidden while
    /// the number is too small to feel meaningful.
    private var daysTogether: Int {
        let first = SharedDataStore.shared.supportReminderFirstLaunchAt()
        return Int(Date().timeIntervalSince(first) / 86_400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Maker's-note header: cup badge + hand-signed feel, left aligned —
            // a note from a person, not a marketing card.
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Self.coffeeYellow, Self.coffeeYellow.opacity(0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("support.popup_title".localized)
                        .font(.system(size: 14, weight: .bold))
                    Text("support.popup_signature".localized)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)

            Text("support.popup_body".localized)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            HStack(spacing: 8) {
                Button(action: onCoffee) {
                    HStack(spacing: 7) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 13))
                        Text("support.buy_coffee".localized)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Self.coffeeYellow)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 8)

            HStack {
                if daysTogether >= 14 {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Self.coffeeYellow)
                        Text(String(format: "support.popup_days".localized, daysTogether))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("support.popup_later".localized, action: onLater)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.top, 26)   // clears the (transparent) titlebar close button
        .padding([.horizontal, .bottom], 18)
        .frame(width: 320)
    }
}
