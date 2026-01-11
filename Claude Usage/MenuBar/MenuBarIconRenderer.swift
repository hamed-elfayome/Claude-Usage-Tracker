//
//  MenuBarIconRenderer.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Cocoa

/// Handles rendering of individual metric icons for the menu bar
final class MenuBarIconRenderer {

    // MARK: - Public Methods

    /// Creates an image for a specific metric
    func createImage(
        for metricType: MenuBarMetricType,
        config: MetricIconConfig,
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool,
        showNextSessionTime: Bool
    ) -> NSImage {
        // Get the metric value and percentage
        let metricData = getMetricData(
            metricType: metricType,
            config: config,
            usage: usage,
            apiUsage: apiUsage
        )

        // API is ALWAYS text-based (no icon styles)
        if metricType == .api {
            return createAPITextStyle(
                metricData: metricData,
                isDarkMode: isDarkMode,
                showIconName: showIconName
            )
        }

        // Render based on icon style for Session and Week
        switch config.iconStyle {
        case .battery:
            return createBatteryStyle(
                metricType: metricType,
                metricData: metricData,
                isDarkMode: isDarkMode,
                monochromeMode: monochromeMode,
                showIconName: showIconName,
                showNextSessionTime: showNextSessionTime,
                usage: usage
            )
        case .progressBar:
            return createProgressBarStyle(
                metricType: metricType,
                metricData: metricData,
                isDarkMode: isDarkMode,
                monochromeMode: monochromeMode,
                showIconName: showIconName,
                showNextSessionTime: showNextSessionTime,
                usage: usage
            )
        case .percentageOnly:
            return createPercentageOnlyStyle(
                metricType: metricType,
                metricData: metricData,
                isDarkMode: isDarkMode,
                monochromeMode: monochromeMode,
                showIconName: showIconName
            )
        case .icon:
            return createIconWithBarStyle(
                metricType: metricType,
                metricData: metricData,
                isDarkMode: isDarkMode,
                monochromeMode: monochromeMode,
                showIconName: showIconName
            )
        case .compact:
            return createCompactStyle(
                metricType: metricType,
                metricData: metricData,
                isDarkMode: isDarkMode,
                monochromeMode: monochromeMode,
                showIconName: showIconName
            )
        }
    }

    // MARK: - Metric Data Extraction

    private struct MetricData {
        let percentage: Double
        let displayText: String
        let statusLevel: UsageStatusLevel
        let sessionResetTime: Date?  // Only populated for session metric
    }

    private func getMetricData(
        metricType: MenuBarMetricType,
        config: MetricIconConfig,
        usage: ClaudeUsage,
        apiUsage: APIUsage?
    ) -> MetricData {
        switch metricType {
        case .session:
            return MetricData(
                percentage: usage.sessionPercentage,
                displayText: "\(Int(usage.sessionPercentage))%",
                statusLevel: usage.statusLevel,
                sessionResetTime: usage.sessionResetTime
            )

        case .week:
            let percentage = usage.weeklyPercentage
            let displayText: String
            if config.weekDisplayMode == .percentage {
                displayText = "\(Int(percentage))%"
            } else {
                // Token display mode - smart formatting
                displayText = formatTokenCount(usage.weeklyTokensUsed, usage.weeklyLimit)
            }

            let statusLevel: UsageStatusLevel
            switch percentage {
            case 0..<50:
                statusLevel = .safe
            case 50..<80:
                statusLevel = .moderate
            default:
                statusLevel = .critical
            }

            return MetricData(
                percentage: percentage,
                displayText: displayText,
                statusLevel: statusLevel,
                sessionResetTime: nil
            )

        case .api:
            guard let apiUsage = apiUsage else {
                return MetricData(
                    percentage: 0,
                    displayText: "N/A",
                    statusLevel: .safe,
                    sessionResetTime: nil
                )
            }

            let percentage = apiUsage.usagePercentage
            let displayText: String
            switch config.apiDisplayMode {
            case .remaining:
                displayText = apiUsage.formattedRemaining
            case .used:
                displayText = apiUsage.formattedUsed
            case .both:
                displayText = "\(apiUsage.formattedUsed)/\(apiUsage.formattedTotal)"
            }

            let statusLevel: UsageStatusLevel
            switch percentage {
            case 0..<50:
                statusLevel = .safe
            case 50..<80:
                statusLevel = .moderate
            default:
                statusLevel = .critical
            }

            return MetricData(
                percentage: percentage,
                displayText: displayText,
                statusLevel: statusLevel,
                sessionResetTime: nil
            )
        }
    }

    // MARK: - Icon Style Renderers

    private func createBatteryStyle(
        metricType: MenuBarMetricType,
        metricData: MetricData,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool,
        showNextSessionTime: Bool,
        usage: ClaudeUsage
    ) -> NSImage {
        let percentage = CGFloat(metricData.percentage) / 100.0

        // Battery style: NO prefix before the bar, label goes below
        let batteryWidth: CGFloat = 42  // Match original exactly
        let totalWidth = batteryWidth
        let totalHeight: CGFloat = 28  // Taller to fit bar on top, text below
        let barHeight: CGFloat = 10  // Match original

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        let outlineColor: NSColor = isDarkMode ? .white : .black
        let textColor: NSColor = isDarkMode ? .white : .black
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForStatusLevel(metricData.statusLevel)

        let xOffset: CGFloat = 0

        // Battery bar at TOP (like original)
        let barY = totalHeight - barHeight - 4
        let barWidth = batteryWidth - 2
        let padding: CGFloat = 2.0

        // Outer container
        let containerPath = NSBezierPath(
            roundedRect: NSRect(x: xOffset + 1, y: barY, width: barWidth, height: barHeight),
            xRadius: 2.5,
            yRadius: 2.5
        )
        outlineColor.withAlphaComponent(0.5).setStroke()
        containerPath.lineWidth = 1.2
        containerPath.stroke()

        // Fill level
        let fillWidth = (barWidth - padding * 2) * percentage
        if fillWidth > 1 {
            let fillPath = NSBezierPath(
                roundedRect: NSRect(
                    x: xOffset + 1 + padding,
                    y: barY + padding,
                    width: fillWidth,
                    height: barHeight - padding * 2
                ),
                xRadius: 1.5,
                yRadius: 1.5
            )
            fillColor.setFill()
            fillPath.fill()
        }

        // Label BELOW the battery (replaces percentage text)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: textColor.withAlphaComponent(0.85)
        ]

        // Show metric label if enabled, otherwise show percentage
        let text: NSString
        if showNextSessionTime && metricType == .session, let resetTime = metricData.sessionResetTime {
            if showIconName {
                // Show "S (→2H)" when labels enabled
                text = "S (\(resetTime.timeRemainingHoursString()))" as NSString
            } else {
                // Show just "→2H" when labels disabled
                text = resetTime.timeRemainingHoursString() as NSString
            }
        } else if showIconName {
            // Show full word: "Session" or "Week"
            text = (metricType == .session ? "Session" : "Week") as NSString
        } else {
            // No label mode - show percentage instead
            text = "\(Int(metricData.percentage))%" as NSString
        }

        let textSize = text.size(withAttributes: textAttributes)
        let textX = xOffset + (batteryWidth - textSize.width) / 2
        let textY: CGFloat = 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttributes)

        return image
    }

    private func createProgressBarStyle(
        metricType: MenuBarMetricType,
        metricData: MetricData,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool,
        showNextSessionTime: Bool,
        usage: ClaudeUsage
    ) -> NSImage {
        // For progress bar: show "S" or "W" before the bar (not full prefix)
        let labelWidth: CGFloat = showIconName ? 10 : 0
        let barWidth: CGFloat = 40
        let spacing: CGFloat = showIconName ? 2 : 0
        let totalWidth = labelWidth + spacing + barWidth + 2
        let height: CGFloat = 18

        let image = NSImage(size: NSSize(width: totalWidth, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textColor: NSColor = isDarkMode ? .white : .black
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForStatusLevel(metricData.statusLevel)
        let backgroundColor: NSColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.15)

        var xOffset: CGFloat = 1

        // Draw label before bar (just "S" or "W")
        if showIconName {
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: textColor.withAlphaComponent(0.9)
            ]
            let label = (metricType == .session ? "S" : "W") as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            label.draw(
                at: NSPoint(x: xOffset, y: (height - labelSize.height) / 2),
                withAttributes: labelAttributes
            )
            xOffset += labelWidth + spacing
        }

        // Progress bar
        let barHeight: CGFloat = 9  // Slightly taller
        let barY = (height - barHeight) / 2

        // Background
        let bgPath = NSBezierPath(
            roundedRect: NSRect(x: xOffset, y: barY, width: barWidth, height: barHeight),
            xRadius: 4,
            yRadius: 4
        )
        backgroundColor.setFill()
        bgPath.fill()

        // Fill
        let fillWidth = barWidth * CGFloat(metricData.percentage / 100.0)
        if fillWidth > 1 {
            let fillPath = NSBezierPath(
                roundedRect: NSRect(x: xOffset, y: barY, width: fillWidth, height: barHeight),
                xRadius: 4,
                yRadius: 4
            )
            fillColor.setFill()
            fillPath.fill()

            // Draw session reset time inside the fill area if enabled and this is a session metric
            if showNextSessionTime && metricType == .session, let resetTime = metricData.sessionResetTime {
                let timeString = resetTime.timeRemainingHoursString() as NSString
                let timeFont = NSFont.systemFont(ofSize: 5.5, weight: .medium)
                let timeAttributes: [NSAttributedString.Key: Any] = [
                    .font: timeFont,
                    .foregroundColor: NSColor.white
                ]

                let timeSize = timeString.size(withAttributes: timeAttributes)
                // Only draw if there's enough space in the fill area
                if fillWidth > timeSize.width + 2 {
                    // Right-align the text in the fill area
                    let timeX = xOffset + fillWidth - timeSize.width - 4
                    let timeY = barY + (barHeight - timeSize.height) / 2
                    timeString.draw(at: NSPoint(x: timeX, y: timeY), withAttributes: timeAttributes)
                }
            }
        }

        return image
    }

    private func createPercentageOnlyStyle(
        metricType: MenuBarMetricType,
        metricData: MetricData,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)  // Larger font
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForStatusLevel(metricData.statusLevel)

        var fullText = ""

        if showIconName {
            fullText = "\(metricType.prefixText) \(metricData.displayText)"
        } else {
            fullText = metricData.displayText
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fillColor
        ]

        let textSize = fullText.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: textSize.width + 2, height: 18))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textY = (18 - textSize.height) / 2
        fullText.draw(at: NSPoint(x: 2, y: textY), withAttributes: attributes)

        return image
    }

    private func createIconWithBarStyle(
        metricType: MenuBarMetricType,
        metricData: MetricData,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool
    ) -> NSImage {
        // For circle: make it bigger to fit S/W in center
        let circleSize: CGFloat = showIconName ? 22 : 18  // Bigger when showing label
        let size: CGFloat = showIconName ? 22 : 18
        let totalWidth = circleSize + 1

        let image = NSImage(size: NSSize(width: totalWidth, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textColor: NSColor = isDarkMode ? .white : .black
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForStatusLevel(metricData.statusLevel)

        let xOffset: CGFloat = 1

        // Progress arc
        let percentage = metricData.percentage / 100.0
        let centerX = xOffset + circleSize / 2
        let center = NSPoint(x: centerX, y: size / 2)
        let radius = (circleSize - 4.0) / 2
        let startAngle: CGFloat = 90
        let endAngle = startAngle + (360 * CGFloat(percentage))

        // Background ring
        let bgArcPath = NSBezierPath()
        bgArcPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        textColor.withAlphaComponent(0.15).setStroke()
        bgArcPath.lineWidth = 3.0
        bgArcPath.lineCapStyle = .round
        bgArcPath.stroke()

        // Progress ring
        if percentage > 0 {
            let arcPath = NSBezierPath()
            arcPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            fillColor.setStroke()
            arcPath.lineWidth = 3.0
            arcPath.lineCapStyle = .round
            arcPath.stroke()
        }

        // Draw S/W in the CENTER of the circle
        if showIconName {
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: textColor
            ]
            let label = (metricType == .session ? "S" : "W") as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            let labelX = center.x - labelSize.width / 2
            let labelY = center.y - labelSize.height / 2
            label.draw(at: NSPoint(x: labelX, y: labelY), withAttributes: labelAttributes)
        }

        return image
    }

    private func createCompactStyle(
        metricType: MenuBarMetricType,
        metricData: MetricData,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool
    ) -> NSImage {
        let prefixWidth: CGFloat = showIconName ? 16 : 0
        let dotSize: CGFloat = 8
        let spacing: CGFloat = showIconName ? 1 : 0
        let totalWidth = prefixWidth + spacing + dotSize + 1
        let height: CGFloat = 18

        let image = NSImage(size: NSSize(width: totalWidth, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textColor: NSColor = isDarkMode ? .white : .black
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForStatusLevel(metricData.statusLevel)

        var xOffset: CGFloat = 1

        // Draw prefix if enabled
        if showIconName {
            let prefixAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: textColor.withAlphaComponent(0.85)
            ]
            let prefixText = metricType.prefixText as NSString
            let prefixSize = prefixText.size(withAttributes: prefixAttributes)
            prefixText.draw(
                at: NSPoint(x: xOffset, y: (height - prefixSize.height) / 2),
                withAttributes: prefixAttributes
            )
            xOffset += prefixWidth + spacing
        }

        // Draw dot
        let dotY = (height - dotSize) / 2
        let dotRect = NSRect(x: xOffset, y: dotY, width: dotSize, height: dotSize)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        fillColor.setFill()
        dotPath.fill()

        return image
    }

    // MARK: - API Text Style (Always Text-Based)

    private func createAPITextStyle(
        metricData: MetricData,
        isDarkMode: Bool,
        showIconName: Bool
    ) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textColor: NSColor = isDarkMode ? .white : .black

        var fullText = ""

        if showIconName {
            fullText = "API: \(metricData.displayText)"
        } else {
            fullText = metricData.displayText
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let textSize = fullText.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: textSize.width + 4, height: 18))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textY = (18 - textSize.height) / 2
        fullText.draw(at: NSPoint(x: 2, y: textY), withAttributes: attributes)

        return image
    }

    // MARK: - Default App Logo (for profiles without credentials)

    /// Creates a default app logo icon for the menu bar when no credentials are configured
    func createDefaultAppLogo(isDarkMode: Bool) -> NSImage {
        // Try to load the app logo from assets
        if let logo = NSImage(named: "HeaderLogo") {
            // Create a copy to avoid modifying the original
            let resizedLogo = NSImage(size: NSSize(width: 20, height: 20))
            resizedLogo.lockFocus()
            defer { resizedLogo.unlockFocus() }

            // Draw the logo centered
            logo.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20),
                     from: NSRect.zero,
                     operation: .sourceOver,
                     fraction: 1.0)

            return resizedLogo
        }

        // Fallback: Create a simple circle icon if logo not found
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let color: NSColor = isDarkMode ? .white : .black

        // Draw a simple circle
        let circlePath = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: size - 4, height: size - 4))
        color.withAlphaComponent(0.7).setStroke()
        circlePath.lineWidth = 2.0
        circlePath.stroke()

        // Draw a small dot in the center
        let dotPath = NSBezierPath(ovalIn: NSRect(x: size/2 - 2, y: size/2 - 2, width: 4, height: 4))
        color.setFill()
        dotPath.fill()

        return image
    }

    // MARK: - Helper Methods

    private func getColorForStatusLevel(_ level: UsageStatusLevel) -> NSColor {
        switch level {
        case .safe:
            return NSColor.systemGreen
        case .moderate:
            return NSColor.systemOrange
        case .critical:
            return NSColor.systemRed
        }
    }

    /// Formats token count intelligently (e.g., 1M instead of 1000K)
    private func formatTokenCount(_ used: Int, _ limit: Int) -> String {
        func formatSingleValue(_ value: Int) -> String {
            if value >= 1_000_000 {
                let millions = Double(value) / 1_000_000.0
                if millions.truncatingRemainder(dividingBy: 1.0) == 0 {
                    return "\(Int(millions))M"
                } else {
                    return String(format: "%.1fM", millions)
                }
            } else if value >= 1_000 {
                let thousands = Double(value) / 1_000.0
                if thousands.truncatingRemainder(dividingBy: 1.0) == 0 {
                    return "\(Int(thousands))K"
                } else {
                    return String(format: "%.1fK", thousands)
                }
            } else {
                return "\(value)"
            }
        }

        return "\(formatSingleValue(used))/\(formatSingleValue(limit))"
    }
}
