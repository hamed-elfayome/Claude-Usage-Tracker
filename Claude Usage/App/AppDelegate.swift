import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
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
    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
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
}
