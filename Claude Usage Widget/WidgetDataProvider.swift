//
//  WidgetDataProvider.swift
//  Claude Usage Widget
//
//  Provides data access to the widget from App Groups shared storage
//

import Foundation
import SwiftUI

/// Lightweight usage data structure for widget display
struct WidgetUsageData: Codable {
    let sessionPercentage: Double
    let sessionResetTime: Date
    let weeklyPercentage: Double
    let weeklyResetTime: Date
    let opusPercentage: Double
    let sonnetPercentage: Double
    let extraPercentage: Double?
    let extraUsed: Double?
    let extraLimit: Double?
    let extraCurrency: String?
    let lastUpdated: Date

    var statusLevel: WidgetStatusLevel {
        switch sessionPercentage {
        case 0..<50:
            return .safe
        case 50..<80:
            return .moderate
        default:
            return .critical
        }
    }

    var weeklyStatusLevel: WidgetStatusLevel {
        switch weeklyPercentage {
        case 0..<50:
            return .safe
        case 50..<80:
            return .moderate
        default:
            return .critical
        }
    }

    var extraStatusLevel: WidgetStatusLevel {
        guard let percentage = extraPercentage else { return .safe }
        switch percentage {
        case 0..<50:
            return .safe
        case 50..<80:
            return .moderate
        default:
            return .critical
        }
    }

    var formattedExtraUsed: String? {
        guard let used = extraUsed, let currency = extraCurrency else { return nil }
        return formatCurrency(used, currency: currency)
    }

    var formattedExtraLimit: String? {
        guard let limit = extraLimit, let currency = extraCurrency else { return nil }
        return formatCurrency(limit, currency: currency)
    }

    /// Formats extra usage for display based on format preference
    func formattedExtraDisplay(format: ExtraUsageDisplayFormat) -> String? {
        guard let percentage = extraPercentage else { return nil }

        switch format {
        case .percentage:
            return "\(Int(percentage.rounded()))%"
        case .currency:
            return formattedExtraUsed ?? "$0.00"
        case .both:
            let percentStr = "\(Int(percentage.rounded()))%"
            let currencyStr = formattedExtraUsed ?? "$0.00"
            return "\(percentStr) • \(currencyStr)"
        }
    }

    private func formatCurrency(_ amount: Double, currency: String) -> String {
        // Convert from cents to dollars
        let dollars = amount / 100.0

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: dollars)) ?? "\(currency) \(String(format: "%.2f", dollars))"
    }

    static var preview: WidgetUsageData {
        WidgetUsageData(
            sessionPercentage: 45.0,
            sessionResetTime: Date().addingTimeInterval(3600),
            weeklyPercentage: 32.0,
            weeklyResetTime: Date().addingTimeInterval(86400 * 3),
            opusPercentage: 28.0,
            sonnetPercentage: 35.0,
            extraPercentage: 22.5,
            extraUsed: 2.25,
            extraLimit: 10.0,
            extraCurrency: "USD",
            lastUpdated: Date()
        )
    }
}

/// Lightweight API usage data for widget display
struct WidgetAPIUsageData: Codable {
    let usedAmount: Double
    let totalCredits: Double
    let usagePercentage: Double
    let currency: String
    let resetsAt: Date

    var formattedUsed: String {
        formatCurrency(usedAmount)
    }

    var formattedTotal: String {
        formatCurrency(totalCredits)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.2f", amount))"
    }

    static var preview: WidgetAPIUsageData {
        WidgetAPIUsageData(
            usedAmount: 12.50,
            totalCredits: 100.00,
            usagePercentage: 12.5,
            currency: "USD",
            resetsAt: Date().addingTimeInterval(86400 * 14)
        )
    }
}

enum WidgetStatusLevel {
    case safe
    case moderate
    case critical
}

/// Widget small metric selection (mirrors main app's SmallWidgetMetric)
enum WidgetSmallMetric: String {
    case session = "session"
    case weekly = "weekly"
    case opus = "opus"
    case sonnet = "sonnet"
    case extra = "extra"

    var displayName: String {
        switch self {
        case .session: return "Session"
        case .weekly: return "Weekly"
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .extra: return "Extra"
        }
    }

    var icon: String {
        switch self {
        case .session: return "clock.fill"
        case .weekly: return "calendar"
        case .opus: return "star.fill"
        case .sonnet: return "bolt.fill"
        case .extra: return "dollarsign.circle.fill"
        }
    }
}

/// Widget medium layout selection (mirrors main app's MediumWidgetLayout)
/// Widget color display mode (mirrors main app's WidgetColorMode)
enum WidgetColorDisplayMode: String {
    case multiColor = "multiColor"
    case monochrome = "monochrome"
    case singleColor = "singleColor"
}

/// Extra usage display format (mirrors main app's ExtraUsageDisplayFormat)
enum ExtraUsageDisplayFormat: String {
    case percentage = "percentage"
    case currency = "currency"
    case both = "both"
}

// MARK: - Widget Date Formatter

/// Helper for formatting dates in widgets (matches menu bar format)
enum WidgetDateFormatter {
    /// Formats reset time (e.g., "Today, 3:59AM")
    static func resetTimeString(from date: Date) -> String {
        return exactTime(from: date)
    }

    /// Formats time as short string for tiles (no prefix)
    static func shortTimeString(from date: Date) -> String {
        return exactTime(from: date)
    }

    private static func exactTime(from date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        // Round to nearest minute to prevent pinballing (e.g., 6:59:45 -> 7:00, 6:59:20 -> 6:59)
        let roundedDate = roundToNearestMinute(date, using: calendar)

        if calendar.isDateInToday(roundedDate) {
            formatter.dateFormat = "'Today,' h:mma"
        } else if calendar.isDateInTomorrow(roundedDate) {
            formatter.dateFormat = "'Tomorrow,' h:mma"
        } else {
            // Show day name (e.g., "Wednesday, 7:00PM")
            formatter.dateFormat = "EEEE',' h:mma"
        }

        // Convert am/pm to uppercase AM/PM
        return formatter.string(from: roundedDate)
            .replacingOccurrences(of: "am", with: "AM")
            .replacingOccurrences(of: "pm", with: "PM")
    }

    /// Rounds the date to the nearest minute
    private static func roundToNearestMinute(_ date: Date, using calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let seconds = components.second ?? 0

        // Round: >= 30 seconds rounds up, < 30 seconds rounds down
        if seconds >= 30 {
            return calendar.date(byAdding: .minute, value: 1, to: calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: components.hour,
                minute: components.minute
            ))!) ?? date
        } else {
            return calendar.date(from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: components.hour,
                minute: components.minute
            )) ?? date
        }
    }
}

// MARK: - Widget Design Tokens

/// Centralized design tokens for consistent widget styling per Apple HIG
enum WidgetDesign {
    enum Typography {
        static let percentageLarge: CGFloat = 28    // Primary percentage display
        static let percentageMedium: CGFloat = 26   // Card percentages
        static let headerTitle: CGFloat = 14        // Widget header
        static let cardTitle: CGFloat = 13          // Section/card titles
        static let subtitle: CGFloat = 11           // Secondary text
        static let timestamp: CGFloat = 10          // Last updated text
        static let iconSmall: CGFloat = 11          // Card icons
        static let iconMedium: CGFloat = 12         // Header icons
    }

    enum Spacing {
        static let outerPadding: CGFloat = 8        // All widget outer padding
        static let cardPadding: CGFloat = 10        // Internal card padding
        static let cardCornerRadius: CGFloat = 10   // Card corners
        static let progressHeight: CGFloat = 8     // Progress bar height
        static let sectionSpacing: CGFloat = 10     // Between sections
        static let cardSpacing: CGFloat = 10        // Between cards
    }

    enum Ring {
        static let lineWidth: CGFloat = 8           // Circular progress ring
        static let size: CGFloat = 100              // Ring diameter (small widget)
    }

    enum Colors {
        // Glass style opacities
        static let glassCardBg: Double = 0.06
        static let glassProgressBg: Double = 0.12
        static let glassSecondaryText: Double = 0.6
        static let glassDivider: Double = 0.15

        // Standard style opacities
        static let standardCardBg: Double = 0.08
        static let standardProgressBg: Double = 0.2
        static let standardDivider: Double = 0.3
    }

    enum NoData {
        // Icon sizes per widget size
        static let iconSmall: CGFloat = 32
        static let iconMedium: CGFloat = 36
        static let iconLarge: CGFloat = 48

        // Title font sizes
        static let titleSmall: CGFloat = 13
        static let titleMedium: CGFloat = 14
        static let titleLarge: CGFloat = 18

        // Subtitle font sizes
        static let subtitleSmall: CGFloat = 10
        static let subtitleMedium: CGFloat = 11
        static let subtitleLarge: CGFloat = 13
    }
}

/// Data provider that reads from App Groups shared storage
class WidgetDataProvider {
    static let shared = WidgetDataProvider()

    private let appGroupIdentifier = "group.claude-usage"
    private let defaults: UserDefaults?
    private let decoder = JSONDecoder()

    /// Cached widget settings from file
    private var cachedSettings: WidgetSettingsFile?
    private var settingsLastLoaded: Date?

    private init() {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    /// Gets the Group Container URL
    private var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    // MARK: - Widget Settings File

    /// Structure for widget settings file (must match main app's SharedDataStore)
    private struct WidgetSettingsFile: Codable {
        let colorMode: String
        let singleColorHex: String
        let extraUsageFormat: String
        let smallMetric: String
        let mediumLeftMetric: String
        let mediumRightMetric: String
    }

    /// Loads widget settings from file (refreshes cache if stale)
    private func loadSettingsFromFile() -> WidgetSettingsFile? {
        // Return cached if loaded recently (within 1 second)
        if let cached = cachedSettings,
           let lastLoaded = settingsLastLoaded,
           Date().timeIntervalSince(lastLoaded) < 1.0 {
            return cached
        }

        guard let data = loadFromFile(filename: "widgetSettings.json") else {
            #if DEBUG
            print("Widget: No settings file found")
            #endif
            return nil
        }

        do {
            let settings = try decoder.decode(WidgetSettingsFile.self, from: data)
            cachedSettings = settings
            settingsLastLoaded = Date()
            #if DEBUG
            print("Widget: Loaded settings from file - colorMode: \(settings.colorMode)")
            #endif
            return settings
        } catch {
            #if DEBUG
            print("Widget: Failed to decode settings file: \(error)")
            #endif
            return nil
        }
    }

    /// Loads usage data from shared storage
    func loadUsage() -> WidgetUsageData? {
        // Try file-based storage first
        if let data = loadFromFile(filename: "claudeUsageData.json") {
            #if DEBUG
            print("Widget: Found file data (\(data.count) bytes)")
            #endif
            if let usage = decodeUsage(from: data) {
                #if DEBUG
                print("Widget: Successfully decoded usage from file")
                #endif
                return usage
            } else {
                #if DEBUG
                print("Widget: Failed to decode usage from file")
                #endif
            }
        } else {
            #if DEBUG
            print("Widget: No file data found at container path: \(groupContainerURL?.path ?? "nil")")
            #endif
        }

        // Fall back to UserDefaults
        if let defaults = defaults,
           let data = defaults.data(forKey: "claudeUsageData") {
            #if DEBUG
            print("Widget: Found UserDefaults data (\(data.count) bytes)")
            #endif
            if let usage = decodeUsage(from: data) {
                #if DEBUG
                print("Widget: Successfully decoded usage from UserDefaults")
                #endif
                return usage
            } else {
                #if DEBUG
                print("Widget: Failed to decode usage from UserDefaults")
                #endif
            }
        } else {
            #if DEBUG
            print("Widget: No UserDefaults data found (defaults nil: \(defaults == nil))")
            #endif
        }

        #if DEBUG
        print("Widget: Returning nil - no data available")
        #endif
        return nil
    }

    /// Loads data from a file in the group container
    private func loadFromFile(filename: String) -> Data? {
        guard let containerURL = groupContainerURL else { return nil }
        let fileURL = containerURL.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Decodes ClaudeUsage data
    private func decodeUsage(from data: Data) -> WidgetUsageData? {
        do {
            let fullUsage = try decoder.decode(ClaudeUsageCompat.self, from: data)

            // Calculate extra usage percentage if available
            var extraPercentage: Double? = nil
            if let used = fullUsage.costUsed, let limit = fullUsage.costLimit, limit > 0 {
                extraPercentage = (used / limit) * 100.0
            }

            return WidgetUsageData(
                sessionPercentage: fullUsage.sessionPercentage,
                sessionResetTime: fullUsage.sessionResetTime,
                weeklyPercentage: fullUsage.weeklyPercentage,
                weeklyResetTime: fullUsage.weeklyResetTime,
                opusPercentage: fullUsage.opusWeeklyPercentage,
                sonnetPercentage: fullUsage.sonnetWeeklyPercentage,
                extraPercentage: extraPercentage,
                extraUsed: fullUsage.costUsed,
                extraLimit: fullUsage.costLimit,
                extraCurrency: fullUsage.costCurrency,
                lastUpdated: fullUsage.lastUpdated
            )
        } catch {
            #if DEBUG
            print("Widget: Decode error: \(error)")
            #endif
            return nil
        }
    }

    /// Loads API usage data from shared storage
    func loadAPIUsage() -> WidgetAPIUsageData? {
        guard let defaults = defaults,
              let data = defaults.data(forKey: "apiUsageData") else {
            return nil
        }

        do {
            let apiUsage = try decoder.decode(APIUsageCompat.self, from: data)
            let usedAmount = Double(apiUsage.currentSpendCents) / 100.0
            let remainingAmount = Double(apiUsage.prepaidCreditsCents) / 100.0
            let totalCredits = usedAmount + remainingAmount
            let usagePercentage = totalCredits > 0 ? (usedAmount / totalCredits) * 100.0 : 0

            return WidgetAPIUsageData(
                usedAmount: usedAmount,
                totalCredits: totalCredits,
                usagePercentage: usagePercentage,
                currency: apiUsage.currency,
                resetsAt: apiUsage.resetsAt
            )
        } catch {
            return nil
        }
    }

    /// Loads small widget metric preference from shared storage
    func loadSmallWidgetMetric() -> WidgetSmallMetric {
        // Try file first
        if let settings = loadSettingsFromFile(),
           let metric = WidgetSmallMetric(rawValue: settings.smallMetric) {
            return metric
        }

        // Fall back to UserDefaults
        guard let defaults = defaults,
              let rawValue = defaults.string(forKey: "smallWidgetMetric"),
              let metric = WidgetSmallMetric(rawValue: rawValue) else {
            return .session  // Default to session
        }
        return metric
    }

    /// Loads medium widget left metric preference from shared storage
    func loadMediumWidgetLeftMetric() -> WidgetSmallMetric {
        // Try file first
        if let settings = loadSettingsFromFile(),
           let metric = WidgetSmallMetric(rawValue: settings.mediumLeftMetric) {
            return metric
        }

        // Fall back to UserDefaults
        guard let defaults = defaults,
              let rawValue = defaults.string(forKey: "mediumWidgetLeftMetric"),
              let metric = WidgetSmallMetric(rawValue: rawValue) else {
            return .session  // Default left metric
        }
        return metric
    }

    /// Loads medium widget right metric preference from shared storage
    func loadMediumWidgetRightMetric() -> WidgetSmallMetric {
        // Try file first
        if let settings = loadSettingsFromFile(),
           let metric = WidgetSmallMetric(rawValue: settings.mediumRightMetric) {
            return metric
        }

        // Fall back to UserDefaults
        guard let defaults = defaults,
              let rawValue = defaults.string(forKey: "mediumWidgetRightMetric"),
              let metric = WidgetSmallMetric(rawValue: rawValue) else {
            return .weekly  // Default right metric
        }
        return metric
    }

    /// Loads widget color mode preference from shared storage
    func loadWidgetColorMode() -> WidgetColorDisplayMode {
        // Try file first
        if let settings = loadSettingsFromFile(),
           let mode = WidgetColorDisplayMode(rawValue: settings.colorMode) {
            #if DEBUG
            print("Widget: Using color mode from file: \(mode.rawValue)")
            #endif
            return mode
        }

        // Fall back to UserDefaults
        guard let defaults = defaults,
              let rawValue = defaults.string(forKey: "widgetColorMode"),
              let mode = WidgetColorDisplayMode(rawValue: rawValue) else {
            #if DEBUG
            print("Widget: Using default color mode (multiColor)")
            #endif
            return .multiColor  // Default to threshold-based colors
        }
        #if DEBUG
        print("Widget: Using color mode from UserDefaults: \(mode.rawValue)")
        #endif
        return mode
    }

    /// Loads widget single color hex from shared storage
    func loadWidgetSingleColorHex() -> String {
        // Try file first
        if let settings = loadSettingsFromFile() {
            return settings.singleColorHex
        }

        // Fall back to UserDefaults
        return defaults?.string(forKey: "widgetSingleColorHex") ?? "#00BFFF"  // Default cyan
    }

    /// Loads extra usage display format from shared storage
    func loadExtraUsageDisplayFormat() -> ExtraUsageDisplayFormat {
        // Try file first
        if let settings = loadSettingsFromFile(),
           let format = ExtraUsageDisplayFormat(rawValue: settings.extraUsageFormat) {
            return format
        }

        // Fall back to UserDefaults
        guard let defaults = defaults,
              let rawValue = defaults.string(forKey: "extraUsageDisplayFormat"),
              let format = ExtraUsageDisplayFormat(rawValue: rawValue) else {
            return .percentage  // Default to showing percentage
        }
        return format
    }

    /// Returns color for usage percentage based on color mode
    func colorForUsage(_ percentage: Double, mode: WidgetColorDisplayMode, customColorHex: String) -> Color {
        switch mode {
        case .multiColor:
            // Threshold-based colors (matching menu bar)
            switch percentage {
            case 0..<50:
                return .green    // Safe
            case 50..<80:
                return .orange   // Moderate
            default: // 80%+
                return .red      // Critical
            }
        case .monochrome:
            return .primary
        case .singleColor:
            return hexToColor(customColorHex) ?? .cyan
        }
    }

    /// Convert hex string to Color
    private func hexToColor(_ hex: String) -> Color? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count

        switch length {
        case 6: // RGB (24-bit)
            return Color(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8: // RGBA (32-bit)
            return Color(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }
}

// MARK: - Compatibility Models (for decoding main app data)

/// Compatibility struct for decoding ClaudeUsage from main app
/// Must match ALL fields from ClaudeUsage.swift for proper decoding
private struct ClaudeUsageCompat: Codable {
    // Session data
    let sessionTokensUsed: Int
    let sessionLimit: Int
    let sessionPercentage: Double
    let sessionResetTime: Date

    // Weekly data (all models)
    let weeklyTokensUsed: Int
    let weeklyLimit: Int
    let weeklyPercentage: Double
    let weeklyResetTime: Date

    // Weekly data (Opus only)
    let opusWeeklyTokensUsed: Int
    let opusWeeklyPercentage: Double

    // Weekly data (Sonnet only)
    let sonnetWeeklyTokensUsed: Int
    let sonnetWeeklyPercentage: Double
    let sonnetWeeklyResetTime: Date?

    // Extra usage data
    let costUsed: Double?
    let costLimit: Double?
    let costCurrency: String?

    // Metadata
    let lastUpdated: Date
    let userTimezone: TimeZone
}

/// Compatibility struct for decoding APIUsage from main app
private struct APIUsageCompat: Codable {
    let currentSpendCents: Int
    let resetsAt: Date
    let prepaidCreditsCents: Int
    let currency: String
}
