import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarManager: MenuBarManager?
    private var setupWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window restoration for menu bar app
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Set app icon early for Stage Manager and windows
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Request notification permissions
        requestNotificationPermissions()

        // Check if setup has been completed
        if !DataStore.shared.hasCompletedSetup() {
            showSetupWizard()
        }

        // Initialize menu bar
        menuBarManager = MenuBarManager()
        menuBarManager?.setup()

        // Track first launch date for GitHub star prompt
        if DataStore.shared.loadFirstLaunchDate() == nil {
            DataStore.shared.saveFirstLaunchDate(Date())
        }

        // TESTING: Check for launch argument to force GitHub star prompt
        if CommandLine.arguments.contains("--show-github-prompt") {
            DataStore.shared.resetGitHubStarPromptForTesting()
            DataStore.shared.saveFirstLaunchDate(Date().addingTimeInterval(-2 * 24 * 60 * 60))
        }

        // Check if we should show GitHub star prompt (with a slight delay to not interrupt app startup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if DataStore.shared.shouldShowGitHubStarPrompt() {
                self?.menuBarManager?.showGitHubStarPrompt()
            }
        }
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Silently request permissions
        }
    }

    private func showSetupWizard() {
        // Temporarily show dock icon for the setup window
        NSApp.setActivationPolicy(.regular)

        let setupView = SetupWizardView()
        let hostingController = NSHostingController(rootView: setupView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Claude Usage Tracker Setup"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        // Hide dock icon again when setup window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.setupWindow = nil
        }

        setupWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        menuBarManager?.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running even if all windows are closed
        return false
    }

    func application(_ application: NSApplication, willEncodeRestorableState coder: NSCoder) {
        // Prevent window restoration state from being saved
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Disable state restoration for menu bar app
        return false
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground (menu bar apps are always foreground)
        completionHandler([.banner, .sound])
    }
}
