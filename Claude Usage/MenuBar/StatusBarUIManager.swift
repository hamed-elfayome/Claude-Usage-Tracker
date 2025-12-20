//
//  StatusBarUIManager.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Cocoa
import Combine

/// Manages the menu bar status item UI and appearance
final class StatusBarUIManager {
    private var statusItem: NSStatusItem?
    private var appearanceObserver: NSKeyValueObservation?

    weak var delegate: StatusBarUIManagerDelegate?

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    func setup(target: AnyObject, action: Selector) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = action
            button.target = target
        }

        observeAppearanceChanges()
        LoggingService.shared.logUIEvent("Status bar initialized")
    }

    func cleanup() {
        appearanceObserver?.invalidate()
        appearanceObserver = nil
        statusItem = nil
        LoggingService.shared.logUIEvent("Status bar cleaned up")
    }

    // MARK: - UI Updates

    func updateButton(usage: ClaudeUsage) {
        guard let button = statusItem?.button else { return }
        updateStatusButton(button, usage: usage)
    }

    var button: NSStatusBarButton? {
        return statusItem?.button
    }

    // MARK: - Appearance Observation

    private func observeAppearanceChanges() {
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.delegate?.statusBarAppearanceDidChange()
        }
    }

    // MARK: - Button Rendering

    private func updateStatusButton(_ button: NSStatusBarButton, usage: ClaudeUsage) {
        let percentage = usage.sessionPercentage
        let isDarkMode = NSApp.effectiveAppearance.name == .darkAqua

        // Create the image with battery-style progress
        let image = createBatteryImage(percentage: percentage, isDarkMode: isDarkMode)
        button.image = image
        button.image?.isTemplate = false
    }

    private func createBatteryImage(percentage: Double, isDarkMode: Bool) -> NSImage {
        let width: CGFloat = 60
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Colors
        let textColor: NSColor = isDarkMode ? .white : .black
        let backgroundColor: NSColor = isDarkMode ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.1)

        let fillColor: NSColor
        switch percentage {
        case 0..<50:
            fillColor = NSColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 1.0)
        case 50..<80:
            fillColor = NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        default:
            fillColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        }

        // Draw "Claude" text
        let text = "Claude"
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(x: 2, y: (height - textSize.height) / 2, width: textSize.width, height: textSize.height)
        text.draw(in: textRect, withAttributes: attributes)

        // Battery background
        let batteryX = textSize.width + 6
        let batteryWidth: CGFloat = 20
        let batteryHeight: CGFloat = 10
        let batteryY = (height - batteryHeight) / 2
        let batteryRect = NSRect(x: batteryX, y: batteryY, width: batteryWidth, height: batteryHeight)

        let path = NSBezierPath(roundedRect: batteryRect, xRadius: 2, yRadius: 2)
        backgroundColor.setFill()
        path.fill()

        // Battery fill
        let fillWidth = (batteryWidth - 4) * CGFloat(percentage / 100.0)
        let fillRect = NSRect(x: batteryX + 2, y: batteryY + 2, width: fillWidth, height: batteryHeight - 4)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1)
        fillColor.setFill()
        fillPath.fill()

        // Battery tip
        let tipWidth: CGFloat = 2
        let tipHeight: CGFloat = 4
        let tipX = batteryX + batteryWidth
        let tipY = batteryY + (batteryHeight - tipHeight) / 2
        let tipRect = NSRect(x: tipX, y: tipY, width: tipWidth, height: tipHeight)
        let tipPath = NSBezierPath(rect: tipRect)
        backgroundColor.setFill()
        tipPath.fill()

        return image
    }
}

// MARK: - Delegate Protocol

protocol StatusBarUIManagerDelegate: AnyObject {
    func statusBarAppearanceDidChange()
}
