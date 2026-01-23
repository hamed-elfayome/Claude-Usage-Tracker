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

        // Load profiles into ProfileManager (synchronously)
        ProfileManager.shared.loadProfiles()

        // Initialize update manager to enable automatic update checks
        _ = UpdateManager.shared

        // Request notification permissions
        requestNotificationPermissions()

        // Listen for manual wizard trigger (for testing)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSetupWizard),
            name: .showSetupWizard,
            object: nil
        )

        // Check if setup has been completed
        if !shouldShowSetupWizard() {
            // Initialize menu bar with active profile
            menuBarManager = MenuBarManager()
            menuBarManager?.setup()
        } else {
            showSetupWizardManually()
            // Mark that wizard has been shown once
            SharedDataStore.shared.markWizardShown()
        }

        // Track first launch date for GitHub star prompt
        if SharedDataStore.shared.loadFirstLaunchDate() == nil {
            SharedDataStore.shared.saveFirstLaunchDate(Date())
        }

        // TESTING: Check for launch argument to force GitHub star prompt
        if CommandLine.arguments.contains("--show-github-prompt") {
            SharedDataStore.shared.resetGitHubStarPromptForTesting()
            SharedDataStore.shared.saveFirstLaunchDate(Date().addingTimeInterval(-2 * 24 * 60 * 60))
        }

        // Check if we should show GitHub star prompt (with a slight delay to not interrupt app startup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if SharedDataStore.shared.shouldShowGitHubStarPrompt() {
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


    private func shouldShowSetupWizard() -> Bool {
        // activeProfile will always exist after loadProfiles() is called
        // (ProfileManager creates a default profile if none exist)
        guard let activeProfile = ProfileManager.shared.activeProfile else {
            return true  // Safety fallback, should never happen
        }

        // If profile already has any credentials, skip wizard
        if activeProfile.hasAnyCredentials {
            return false
        }

        // Check if this is the very first launch (wizard never shown)
        if !SharedDataStore.shared.hasShownWizardOnce() {
            // First launch - check for CLI credentials to auto-import
            // This is the ONLY time we check system Keychain (to avoid repeated prompts)
            if hasValidSystemCLICredentials() {
                LoggingService.shared.log("AppDelegate: First launch - found valid CLI credentials, skipping wizard")
                return false
            }
            LoggingService.shared.log("AppDelegate: First launch - showing wizard")
            return true
        }

        // Wizard has been shown before, but user has no credentials
        // Don't show wizard again and don't check Keychain (avoids prompts)
        // User can manually configure credentials via Settings
        return false
    }

    /// Checks if valid Claude Code CLI credentials exist in system Keychain
    private func hasValidSystemCLICredentials() -> Bool {
        do {
            // Attempt to read credentials from system Keychain
            guard let jsonData = try ClaudeCodeSyncService.shared.readSystemCredentials() else {
                LoggingService.shared.log("AppDelegate: No CLI credentials found in system Keychain")
                return false
            }

            // Validate: not expired
            if ClaudeCodeSyncService.shared.isTokenExpired(jsonData) {
                LoggingService.shared.log("AppDelegate: CLI credentials found but expired")
                return false
            }

            // Validate: has valid access token
            guard ClaudeCodeSyncService.shared.extractAccessToken(from: jsonData) != nil else {
                LoggingService.shared.log("AppDelegate: CLI credentials found but missing access token")
                return false
            }

            LoggingService.shared.log("AppDelegate: Valid CLI credentials found in system Keychain")
            return true

        } catch {
            LoggingService.shared.logError("AppDelegate: Failed to check CLI credentials", error: error)
            return false
        }
    }

    /// Handles notification to show setup wizard
    @objc private func handleShowSetupWizard() {
        LoggingService.shared.log("AppDelegate: Received showSetupWizard notification")
        showSetupWizardManually()
    }

    /// Shows the setup wizard window (can be called manually for testing)
    func showSetupWizardManually() {
        LoggingService.shared.log("AppDelegate: showSetupWizardManually called")

        // Temporarily show dock icon for the setup window
        NSApp.setActivationPolicy(.regular)
        LoggingService.shared.log("AppDelegate: Set activation policy to regular")

        let setupView = SetupWizardView()
        let hostingController = NSHostingController(rootView: setupView)
        LoggingService.shared.log("AppDelegate: Created hosting controller")

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Claude Usage Tracker Setup"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        LoggingService.shared.log("AppDelegate: Window created and made key")

        // Hide dock icon again when setup window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.setupWindow = nil

            // Initialize menu bar after setup completes
            if self?.menuBarManager == nil {
                self?.menuBarManager = MenuBarManager()
                self?.menuBarManager?.setup()
            }
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
