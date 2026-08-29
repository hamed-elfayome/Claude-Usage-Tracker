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
        // Remove the titlebar safe-area at the source: the glow owns the full
        // window and the fitting size stops including a phantom titlebar band.
        hosting.safeAreaRegions = []
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
        // The window was sized before fullSizeContentView/ignoresSafeArea took
        // effect, leaving a titlebar-height dead band at the bottom. Re-fit to
        // the SwiftUI content's real size.
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // No control needs initial keyboard focus; without this the CTA gets a
        // focus ring the moment the window becomes key.
        window.makeFirstResponder(nil)
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

    @State private var hoveringCTA = false

    var body: some View {
        VStack(spacing: 0) {
            // Warm "coffee break" header: amber glow washing down from the very
            // top of the window (safe area ignored), steam drifting off the cup.
            // endRadius stays INSIDE the frame so the gradient reaches clear
            // before the clip — no hard cropped edge.
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [Self.coffeeYellow.opacity(0.28), .clear],
                    center: .init(x: 0.5, y: 0.0),
                    startRadius: 4, endRadius: 92
                )
                .frame(height: 96)

                VStack(spacing: 2) {
                    SteamView(color: Self.coffeeYellow)
                        .padding(.top, 20)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(LinearGradient(
                            colors: [Self.coffeeYellow, Self.coffeeYellow.opacity(0.72)],
                            startPoint: .top, endPoint: .bottom))
                        .shadow(color: Self.coffeeYellow.opacity(0.4), radius: 10)
                }
            }
            .frame(height: 92)

            VStack(spacing: 4) {
                Text("support.popup_title".localized)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("support.popup_signature".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 10)

            Text("support.popup_body".localized)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.78))
                .lineSpacing(2.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            if daysTogether >= 14 {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Self.coffeeYellow)
                    Text(String(format: "support.popup_days".localized, daysTogether))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(Self.coffeeYellow.opacity(0.10)))
                .overlay(Capsule().strokeBorder(Self.coffeeYellow.opacity(0.25), lineWidth: 1))
                .padding(.bottom, 14)
            }

            Button(action: onCoffee) {
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("support.buy_coffee".localized)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.black.opacity(0.88))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.91, blue: 0.30), Color(red: 1.0, green: 0.80, blue: 0.0)],
                        startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(10)
                .shadow(color: Self.coffeeYellow.opacity(hoveringCTA ? 0.55 : 0.30),
                        radius: hoveringCTA ? 14 : 8, y: 3)
                .scaleEffect(hoveringCTA ? 1.02 : 1.0)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .focusEffectDisabled()
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { hoveringCTA = hovering }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Button("support.popup_later".localized, action: onLater)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.85))
                .keyboardShortcut(.cancelAction)
                .padding(.bottom, 14)
        }
        .frame(width: 316)
    }
}

/// Three steam wisps drifting up off the cup — one gentle looping animation,
/// staggered per wisp.
private struct SteamView: View {
    let color: Color
    @State private var rising = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(color.opacity(0.6))
                    .frame(width: 2.5, height: i == 1 ? 13 : 9)
                    .offset(y: rising ? -7 : 3)
                    .opacity(rising ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.7)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.4),
                        value: rising
                    )
            }
        }
        .frame(height: 14)
        .onAppear { rising = true }
    }
}
