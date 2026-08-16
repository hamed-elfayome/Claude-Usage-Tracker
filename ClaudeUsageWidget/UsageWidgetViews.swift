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

private func providerIcon(_ provider: WidgetSnapshot.ProfileEntry.Provider) -> String {
    switch provider {
    case .claude: return "sparkle"
    case .codex: return "chevron.left.forwardslash.chevron.right"
    case .zai: return "z.square.fill"
    }
}

private struct UsageBar: View {
    let label: LocalizedStringKey
    let percentage: Double
    let resetTime: Date?
    /// The timeline entry's date — comparisons must use it (not `Date()`)
    /// so pre-rendered future entries evaluate correctly.
    let now: Date
    /// Compact sizing for the medium family's tight rows; the large family
    /// has room for more legible type.
    var compact = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 3) {
            HStack {
                Text(label)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage))%")
                    .font((compact ? Font.caption2 : .caption).monospacedDigit().bold())
                    .foregroundStyle(usageColor(percentage))
            }
            ProgressView(value: min(max(percentage, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(usageColor(percentage))
            if let resetTime, resetTime > now {
                Text(resetTime, style: .relative)
                    .font(compact ? .system(size: 9) : .caption2)
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
        let profiles = entry.snapshot?.profiles ?? []
        return profiles.first(where: \.isActive)
            ?? profiles.first(where: \.isDisplayed)
            ?? profiles.first
    }

    var body: some View {
        Group {
            if let profile {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: providerIcon(profile.provider))
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
                    if let sessionResetTime = profile.sessionResetTime,
                       sessionResetTime > entry.date {
                        Text(sessionResetTime, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .opacity(entry.isProfileStale(profile) ? 0.4 : 1)
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

// MARK: - Medium/large widget: all display-selected profiles

struct UsageOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var profiles: [WidgetSnapshot.ProfileEntry] {
        let selected = (entry.snapshot?.profiles ?? []).filter(\.isDisplayed)
        return Array(selected.prefix(family == .systemLarge ? 6 : 4))
    }

    var body: some View {
        Group {
            if profiles.isEmpty {
                NoDataView()
            } else if family == .systemLarge {
                largeLayout
            } else {
                mediumLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Large: one card per profile — name as a header line, both bars at
    /// full width beneath it. Rows share the vertical space equally so the
    /// content fills the widget instead of clustering in the center.
    private var largeLayout: some View {
        VStack(spacing: 6) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(profile.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if profile.isActive {
                            Image(systemName: providerIcon(profile.provider))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        UsageBar(
                            label: "widget.session",
                            percentage: profile.sessionPercentage,
                            resetTime: profile.sessionResetTime,
                            now: entry.date,
                            compact: false
                        )
                        if let weeklyPercentage = profile.weeklyPercentage {
                            UsageBar(
                                label: "widget.weekly",
                                percentage: weeklyPercentage,
                                resetTime: profile.weeklyResetTime,
                                now: entry.date,
                                compact: false
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Per-row: a profile can go stale on its own — the
                // single-profile refresh path only updates the
                // active profile.
                .opacity(entry.isProfileStale(profile) ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Medium: one compact line per profile, name in a fixed column so the
    /// bars align across rows. Rows share the vertical space equally.
    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(profiles) { profile in
                HStack(alignment: .top, spacing: 10) {
                    Text(profile.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .frame(width: 78, alignment: .leading)
                    UsageBar(
                        label: "widget.session",
                        percentage: profile.sessionPercentage,
                        resetTime: profile.sessionResetTime,
                        now: entry.date
                    )
                    if let weeklyPercentage = profile.weeklyPercentage {
                        UsageBar(
                            label: "widget.weekly",
                            percentage: weeklyPercentage,
                            resetTime: profile.weeklyResetTime,
                            now: entry.date
                        )
                    }
                }
                .frame(maxHeight: .infinity)
                .opacity(entry.isProfileStale(profile) ? 0.4 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
