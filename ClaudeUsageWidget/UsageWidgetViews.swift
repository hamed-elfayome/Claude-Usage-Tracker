import SwiftUI
import WidgetKit

// MARK: - Shared helpers

private func usageColor(_ percentage: Double) -> Color {
    switch percentage {
    case ..<75: return .green
    case ..<90: return .orange
    default: return .red
    }
}

private struct UsageBar: View {
    let label: LocalizedStringKey
    let percentage: Double
    let resetTime: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(usageColor(percentage))
            }
            ProgressView(value: min(max(percentage, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(usageColor(percentage))
            if resetTime > Date() {
                Text(resetTime, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct NoDataView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("widget.no_data")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Small widget: active profile session usage

struct SessionUsageWidgetView: View {
    let entry: UsageEntry

    private var profile: WidgetSnapshot.ProfileEntry? {
        entry.snapshot?.profiles.first(where: \.isActive) ?? entry.snapshot?.profiles.first
    }

    var body: some View {
        Group {
            if let profile {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                        Text(profile.name)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                    Gauge(value: min(max(profile.sessionPercentage, 0), 100), in: 0...100) {
                        Text("widget.session")
                    } currentValueLabel: {
                        Text("\(Int(profile.sessionPercentage))%")
                            .font(.callout.monospacedDigit().bold())
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(usageColor(profile.sessionPercentage))
                    .frame(maxWidth: .infinity)
                    if profile.sessionResetTime > entry.date {
                        Text(profile.sessionResetTime, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .opacity(entry.isStale ? 0.4 : 1)
            } else {
                NoDataView()
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SessionUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SessionUsageWidget", provider: UsageTimelineProvider()) { entry in
            SessionUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.session.name"))
        .description(String(localized: "widget.session.desc"))
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Medium widget: all display-selected profiles

struct UsageOverviewWidgetView: View {
    let entry: UsageEntry

    private var profiles: [WidgetSnapshot.ProfileEntry] {
        Array((entry.snapshot?.profiles ?? []).prefix(4))
    }

    var body: some View {
        Group {
            if profiles.isEmpty {
                NoDataView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profiles) { profile in
                        HStack(alignment: .top, spacing: 10) {
                            Text(profile.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .frame(width: 78, alignment: .leading)
                            UsageBar(
                                label: "widget.session",
                                percentage: profile.sessionPercentage,
                                resetTime: profile.sessionResetTime
                            )
                            UsageBar(
                                label: "widget.weekly",
                                percentage: profile.weeklyPercentage,
                                resetTime: profile.weeklyResetTime
                            )
                        }
                    }
                }
                .opacity(entry.isStale ? 0.4 : 1)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct UsageOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageOverviewWidget", provider: UsageTimelineProvider()) { entry in
            UsageOverviewWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.overview.name"))
        .description(String(localized: "widget.overview.desc"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
