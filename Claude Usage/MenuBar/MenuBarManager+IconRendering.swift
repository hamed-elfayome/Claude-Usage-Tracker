import Cocoa

// MARK: - Icon Rendering Methods

extension MenuBarManager {
    // MARK: - Icon Style: Battery
    func createBatteryStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let percentage = CGFloat(usage.sessionPercentage) / 100.0

        // Create a taller image to fit battery + text
        let width: CGFloat = 42
        let totalHeight: CGFloat = 28
        let barHeight: CGFloat = 10
        let image = NSImage(size: NSSize(width: width, height: totalHeight))

        image.lockFocus()
        defer { image.unlockFocus() }

        // Choose outline and text color based on menu bar appearance
        let outlineColor: NSColor = isDarkMode ? .white : .black
        let textColor: NSColor = isDarkMode ? .white : .black

        // Get color based on usage level or monochrome
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForUsageLevel(usage.statusLevel)

        // Position and size calculations for the bar
        let barY = totalHeight - barHeight - 4
        let barWidth = width - 2
        let padding: CGFloat = 2.0

        // Draw outer capsule/container (at top) - clean rounded rectangle
        let containerPath = NSBezierPath(
            roundedRect: NSRect(x: 1, y: barY, width: barWidth, height: barHeight),
            xRadius: 2.5,
            yRadius: 2.5
        )
        outlineColor.withAlphaComponent(0.5).setStroke()
        containerPath.lineWidth = 1.2
        containerPath.stroke()

        // Draw fill level inside - perfectly aligned with container
        let fillWidth = (barWidth - padding * 2) * percentage
        if fillWidth > 1 {
            let fillPath = NSBezierPath(
                roundedRect: NSRect(
                    x: 1 + padding,
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

        // Draw "Claude" text below the battery
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: textColor.withAlphaComponent(0.85)
        ]
        let text = "Claude" as NSString
        let textSize = text.size(withAttributes: textAttributes)
        let textX = (width - textSize.width) / 2
        let textY: CGFloat = 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: textAttributes)

        return image
    }

    // MARK: - Icon Style: Progress Bar
    func createProgressBarStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let width: CGFloat = 40
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForUsageLevel(usage.statusLevel)
        let backgroundColor: NSColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.2)
            : NSColor.black.withAlphaComponent(0.15)

        // Progress bar
        let barWidth: CGFloat = width - 2
        let barHeight: CGFloat = 8
        let barX: CGFloat = 1
        let barY = (height - barHeight) / 2

        // Background
        let bgPath = NSBezierPath(
            roundedRect: NSRect(x: barX, y: barY, width: barWidth, height: barHeight),
            xRadius: 4,
            yRadius: 4
        )
        backgroundColor.setFill()
        bgPath.fill()

        // Fill
        let fillWidth = barWidth * CGFloat(usage.sessionPercentage / 100.0)
        if fillWidth > 1 {
            let fillPath = NSBezierPath(
                roundedRect: NSRect(x: barX, y: barY, width: fillWidth, height: barHeight),
                xRadius: 4,
                yRadius: 4
            )
            fillColor.setFill()
            fillPath.fill()
        }

        return image
    }

    // MARK: - Icon Style: Percentage Only
    func createPercentageOnlyStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let percentageText = "\(Int(usage.sessionPercentage))%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForUsageLevel(usage.statusLevel)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fillColor
        ]

        let textSize = percentageText.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: textSize.width + 2, height: 18))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textY = (18 - textSize.height) / 2
        percentageText.draw(at: NSPoint(x: 1, y: textY), withAttributes: attributes)

        return image
    }

    // MARK: - Icon Style: Icon with Bar
    func createIconWithBarStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let textColor: NSColor = isDarkMode ? .white : .black
        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForUsageLevel(usage.statusLevel)

        // Progress arc (outer ring)
        let percentage = usage.sessionPercentage / 100.0
        let center = NSPoint(x: size / 2, y: size / 2)
        let radius = (size - 3.5) / 2
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
        bgArcPath.lineWidth = 3.5
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
            arcPath.lineWidth = 3.5
            arcPath.lineCapStyle = .round
            arcPath.stroke()
        }

        return image
    }

    // MARK: - Icon Style: Compact
    func createCompactStyle(usage: ClaudeUsage, isDarkMode: Bool, monochromeMode: Bool) -> NSImage {
        let width: CGFloat = 8
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        let fillColor = monochromeMode
            ? (isDarkMode ? NSColor.white : NSColor.black)
            : getColorForUsageLevel(usage.statusLevel)
        let dotSize: CGFloat = 6

        // Draw dot
        let dotY = (height - dotSize) / 2
        let dotRect = NSRect(x: (width - dotSize) / 2, y: dotY, width: dotSize, height: dotSize)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        fillColor.setFill()
        dotPath.fill()

        return image
    }

    // Helper method to get color based on usage level
    func getColorForUsageLevel(_ level: UsageStatusLevel) -> NSColor {
        switch level {
        case .safe:
            return NSColor.systemGreen
        case .moderate:
            return NSColor.systemOrange
        case .critical:
            return NSColor.systemRed
        }
    }

    // MARK: - New Multi-Metric Rendering

    /// Creates an image for a specific metric using the new renderer
    func createImageForMetric(
        _ metricType: MenuBarMetricType,
        config: MetricIconConfig,
        usage: ClaudeUsage,
        apiUsage: APIUsage?,
        isDarkMode: Bool,
        monochromeMode: Bool,
        showIconName: Bool,
        showNextSessionTime: Bool
    ) -> NSImage {
        let renderer = MenuBarIconRenderer()
        return renderer.createImage(
            for: metricType,
            config: config,
            usage: usage,
            apiUsage: apiUsage,
            isDarkMode: isDarkMode,
            monochromeMode: monochromeMode,
            showIconName: showIconName,
            showNextSessionTime: showNextSessionTime
        )
    }
}
