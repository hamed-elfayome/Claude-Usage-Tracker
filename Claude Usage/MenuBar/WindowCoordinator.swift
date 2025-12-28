//
//  WindowCoordinator.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Cocoa
import SwiftUI

/// Coordinates window lifecycle (popover, settings, GitHub prompt, detached window)
final class WindowCoordinator: NSObject {
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var detachedWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var githubPromptWindow: NSWindow?

    weak var manager: AnyObject?

    // MARK: - Popover Management

    func setupPopover(contentViewController: NSViewController) {
        let popover = NSPopover()
        popover.contentSize = Constants.WindowSizes.popoverSize
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = contentViewController
        self.popover = popover
        LoggingService.shared.logWindowEvent("Popover created")
    }

    func togglePopover(relativeTo button: NSStatusBarButton, contentProvider: () -> NSViewController) {
        // If there's a detached window, close it
        if let window = detachedWindow {
            window.close()
            detachedWindow = nil
            LoggingService.shared.logWindowEvent("Detached window closed")
            return
        }

        // Otherwise toggle the popover
        guard let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            // Recreate content if it was moved to a detached window
            if popover.contentViewController == nil {
                popover.contentViewController = contentProvider()
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startMonitoringForOutsideClicks()
            LoggingService.shared.logWindowEvent("Popover shown")
        }
    }

    func closePopover() {
        popover?.performClose(nil)
        stopMonitoringForOutsideClicks()
        LoggingService.shared.logWindowEvent("Popover closed")
    }

    func closePopoverOrWindow() {
        if let window = detachedWindow {
            window.close()
            detachedWindow = nil
        } else {
            closePopover()
        }
    }

    // MARK: - Detached Window

    func detachPopover(contentProvider: () -> NSViewController) {
        guard let popover = popover, popover.isShown else { return }

        // Close the popover
        closePopover()

        // Get the content view controller
        let contentViewController = contentProvider()

        // Create a floating window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Constants.WindowSizes.popoverSize.width, height: Constants.WindowSizes.popoverSize.height),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "app.window.main".localized
        window.contentViewController = contentViewController
        window.level = .floating
        window.center()
        window.isRestorable = false
        window.makeKeyAndOrderFront(nil)

        // Clear popover's content so it can be recreated later
        popover.contentViewController = nil

        detachedWindow = window
        LoggingService.shared.logWindowEvent("Popover detached to window")
    }

    // MARK: - Settings Window

    func showSettings() {
        closePopoverOrWindow()

        // If settings window already exists, just bring it to front
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            LoggingService.shared.logWindowEvent("Settings window brought to front")
            return
        }

        // Create settings window
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.UITiming.popoverCloseDelay) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Constants.WindowSizes.settingsWindow),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "app.window.settings".localized
            window.contentViewController = hostingController
            window.center()
            window.isRestorable = false
            window.makeKeyAndOrderFront(nil)
            window.delegate = self

            self.settingsWindow = window
            LoggingService.shared.logWindowEvent("Settings window opened")
        }
    }

    // MARK: - GitHub Star Prompt

    func showGitHubPrompt(promptView: NSViewController) {
        // If prompt window already exists, just bring it to front
        if let existingWindow = githubPromptWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "app.window.github_prompt".localized
        window.contentViewController = promptView
        window.center()
        window.isRestorable = false
        window.makeKeyAndOrderFront(nil)
        window.delegate = self

        githubPromptWindow = window
        LoggingService.shared.logWindowEvent("GitHub prompt opened")
    }

    // MARK: - Event Monitoring

    private func startMonitoringForOutsideClicks() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                self?.closePopover()
            }
        }
    }

    private func stopMonitoringForOutsideClicks() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopMonitoringForOutsideClicks()
        detachedWindow?.close()
        detachedWindow = nil
        settingsWindow?.close()
        settingsWindow = nil
        githubPromptWindow?.close()
        githubPromptWindow = nil
        popover = nil
        LoggingService.shared.logWindowEvent("Window coordinator cleaned up")
    }
}

// MARK: - NSPopoverDelegate

extension WindowCoordinator: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        stopMonitoringForOutsideClicks()
    }
}

// MARK: - NSWindowDelegate

extension WindowCoordinator: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        } else if notification.object as? NSWindow === githubPromptWindow {
            githubPromptWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
