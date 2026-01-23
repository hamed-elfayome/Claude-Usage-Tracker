//
//  ClaudeUsageWidget.swift
//  Claude Usage Widget
//
//  Main widget configuration and timeline provider
//

import WidgetKit
import SwiftUI

struct ClaudeUsageWidget: Widget {
    let kind: String = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            ClaudeUsageWidgetEntryView(entry: entry)
                .containerBackground(.ultraThinMaterial, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Monitor your Claude AI usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}


struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), usage: nil, apiUsage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let provider = WidgetDataProvider.shared
        let entry = UsageEntry(
            date: Date(),
            usage: provider.loadUsage(),
            apiUsage: provider.loadAPIUsage(),
            smallMetric: provider.loadSmallWidgetMetric(),
            mediumLeftMetric: provider.loadMediumWidgetLeftMetric(),
            mediumRightMetric: provider.loadMediumWidgetRightMetric(),
            colorMode: provider.loadWidgetColorMode(),
            customColorHex: provider.loadWidgetSingleColorHex(),
            extraUsageFormat: provider.loadExtraUsageDisplayFormat()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let currentDate = Date()
        let provider = WidgetDataProvider.shared
        let entry = UsageEntry(
            date: currentDate,
            usage: provider.loadUsage(),
            apiUsage: provider.loadAPIUsage(),
            smallMetric: provider.loadSmallWidgetMetric(),
            mediumLeftMetric: provider.loadMediumWidgetLeftMetric(),
            mediumRightMetric: provider.loadMediumWidgetRightMetric(),
            colorMode: provider.loadWidgetColorMode(),
            customColorHex: provider.loadWidgetSingleColorHex(),
            extraUsageFormat: provider.loadExtraUsageDisplayFormat()
        )

        // Refresh every 15 minutes
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: WidgetUsageData?
    let apiUsage: WidgetAPIUsageData?
    let smallMetric: WidgetSmallMetric
    let mediumLeftMetric: WidgetSmallMetric
    let mediumRightMetric: WidgetSmallMetric
    let colorMode: WidgetColorDisplayMode
    let customColorHex: String
    let extraUsageFormat: ExtraUsageDisplayFormat

    init(
        date: Date,
        usage: WidgetUsageData?,
        apiUsage: WidgetAPIUsageData?,
        smallMetric: WidgetSmallMetric = .session,
        mediumLeftMetric: WidgetSmallMetric = .session,
        mediumRightMetric: WidgetSmallMetric = .weekly,
        colorMode: WidgetColorDisplayMode = .multiColor,
        customColorHex: String = "#00BFFF",
        extraUsageFormat: ExtraUsageDisplayFormat = .percentage
    ) {
        self.date = date
        self.usage = usage
        self.apiUsage = apiUsage
        self.smallMetric = smallMetric
        self.mediumLeftMetric = mediumLeftMetric
        self.mediumRightMetric = mediumRightMetric
        self.colorMode = colorMode
        self.customColorHex = customColorHex
        self.extraUsageFormat = extraUsageFormat
    }
}

struct ClaudeUsageWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: UsageEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            default:
                SmallWidgetView(entry: entry)
            }
        }
    }
}

#Preview(as: .systemSmall) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry(date: .now, usage: .preview, apiUsage: .preview)
}

#Preview(as: .systemMedium) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry(date: .now, usage: .preview, apiUsage: .preview)
}

#Preview(as: .systemLarge) {
    ClaudeUsageWidget()
} timeline: {
    UsageEntry(date: .now, usage: .preview, apiUsage: .preview)
}
