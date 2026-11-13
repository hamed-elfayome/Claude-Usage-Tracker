import SwiftUI
import WidgetKit

// The widgets are built around one idea from the app itself: usage is only
// meaningful next to the clock. Every meter is a track cut into the window's
// own units (5 hours for a session, 7 days for a week), filled by usage, with
// a needle marking how far through the window "now" is. Fill behind the
// needle means there is room; fill past it means the limit will arrive before
// the reset does.

// MARK: - Meter model

/// One usage window of a profile, as the widget draws it.
struct WidgetMeter: Identifiable {
    enum Kind {
        case session, week

        var window: TimeInterval {
            switch self {
            case .session: return 5 * 3600
            case .week: return 7 * 86400
            }
        }

        /// The track is cut into the window's natural units: hours, or days.
        var segments: Int {
            switch self {
            case .session: return 5
            case .week: return 7
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .session: return "widget.session"
            case .week: return "widget.weekly"
            }
        }
    }

    let kind: Kind
    let percentage: Double
    let resetTime: Date

    var id: Int { kind == .session ? 0 : 1 }

    var fraction: Double { min(max(percentage, 0), 100) / 100 }

    /// How far through the window `now` is, or nil when the reset time is
    /// past or further away than the window is long (not a running window).
    func elapsedFraction(at now: Date) -> Double? {
        let remaining = resetTime.timeIntervalSince(now)
        guard remaining > 0, remaining <= kind.window else { return nil }
        return 1 - remaining / kind.window
    }
}

extension WidgetSnapshot.ProfileEntry {
    /// Session first, then week. Plans without a 5-hour window have the week only.
    var meters: [WidgetMeter] {
        let week = WidgetMeter(kind: .week, percentage: weeklyPercentage, resetTime: weeklyResetTime)
        guard hasSessionLimit else { return [week] }
        return [WidgetMeter(kind: .session, percentage: sessionPercentage, resetTime: sessionResetTime), week]
    }
}

// MARK: - Shared pieces

private func levelColor(_ percentage: Double) -> Color {
    switch percentage {
    case ..<75: return .green
    case ..<90: return .orange
    default: return .red
    }
}

enum WidgetTimeText {
    /// "2d 7h", "2h 10m", "25m": short, localized by the system, and coarse
    /// enough to stay true between timeline entries.
    static func countdown(to date: Date, from now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        if seconds >= 86400 {
            formatter.allowedUnits = [.day, .hour]
        } else if seconds >= 3600 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.minute]
        }
        return formatter.string(from: max(seconds, 60))
    }

    /// "3 hr. ago": how old a reading is, for profiles that stopped updating.
    static func age(of date: Date, at now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// The segmented track with its usage fill and the "now" needle.
struct MeterTrack: View {
    let meter: WidgetMeter
    let now: Date
    var isStale = false
    var height: CGFloat = 8

    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Tinted and vibrant desktop modes drop color, so hierarchy has to come
    /// from opacity there; in full color the fill carries the usage level.
    private var fillStyle: AnyShapeStyle {
        if isStale { return AnyShapeStyle(.secondary) }
        if renderingMode == .fullColor { return AnyShapeStyle(levelColor(meter.percentage)) }
        return AnyShapeStyle(.primary)
    }

    private var needleOverhang: CGFloat { height >= 7 ? 3 : 2 }

    private var segments: some View {
        HStack(spacing: 2) {
            ForEach(0..<meter.kind.segments, id: \.self) { _ in
                RoundedRectangle(cornerRadius: height * 0.38, style: .continuous)
            }
        }
        .frame(height: height)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                segments
                    .foregroundStyle(.primary.opacity(0.13))
                segments
                    .foregroundStyle(fillStyle)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * meter.fraction)
                    }
                    .widgetAccentable()
                if !isStale, let elapsed = meter.elapsedFraction(at: now) {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: height + needleOverhang * 2)
                        .offset(x: min(max(width * elapsed - 1, 0), width - 2))
                }
            }
            .frame(width: width, height: height + needleOverhang * 2)
        }
        .frame(height: height + needleOverhang * 2)
        .accessibilityHidden(true)
    }
}

private struct PercentText: View {
    let percentage: Double
    var size: CGFloat = 13
    var isStale = false

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text("\(Int(percentage))%")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(
                isStale || renderingMode != .fullColor
                    ? AnyShapeStyle(.primary)
                    : AnyShapeStyle(levelColor(percentage))
            )
            .opacity(isStale ? 0.55 : 1)
    }
}

private struct ProfileName: View {
    let profile: WidgetSnapshot.ProfileEntry
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 5) {
            Text(profile.name)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
            // The profile Claude Code is using right now.
            if profile.isActive {
                Circle()
                    .fill(.orange)
                    .frame(width: 5, height: 5)
                    .widgetAccentable()
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

// MARK: - Small widget: the active profile

/// One number you can read from across the room, the track that explains it,
/// and the second window underneath.
struct SessionUsageContent: View {
    let entry: UsageEntry

    private var profile: WidgetSnapshot.ProfileEntry? {
        let profiles = entry.snapshot?.profiles ?? []
        return profiles.first(where: \.isActive)
            ?? profiles.first(where: \.isDisplayed)
            ?? profiles.first
    }

    var body: some View {
        if let profile, let primary = profile.meters.first {
            let isStale = entry.isProfileStale(profile)
            VStack(alignment: .leading, spacing: 0) {
                ProfileName(profile: profile)

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(primary.percentage))")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .opacity(isStale ? 0.55 : 1)

                HStack(spacing: 4) {
                    Text(primary.kind.label)
                    Spacer(minLength: 0)
                    if isStale {
                        Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                    } else if let countdown = WidgetTimeText.countdown(to: primary.resetTime, from: entry.date) {
                        Text(countdown).monospacedDigit()
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 3)

                MeterTrack(meter: primary, now: entry.date, isStale: isStale, height: 9)

                if let secondary = profile.meters.dropFirst().first {
                    HStack(spacing: 6) {
                        Text(secondary.kind.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                        MeterTrack(meter: secondary, now: entry.date, isStale: isStale, height: 4)
                        PercentText(percentage: secondary.percentage, size: 10, isStale: isStale)
                    }
                    .padding(.top, 5)
                }
            }
        } else {
            NoDataView()
        }
    }
}

struct SessionUsageWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        SessionUsageContent(entry: entry)
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

// MARK: - Medium / large widget: every displayed profile

/// One meter on one line: label, track, percentage, time until it resets.
/// The fixed side columns keep tracks aligned across profiles.
private struct MeterRow: View {
    let meter: WidgetMeter
    let now: Date
    let isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(meter.kind.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 50, alignment: .leading)
            MeterTrack(meter: meter, now: now, isStale: isStale)
            PercentText(percentage: meter.percentage, isStale: isStale)
                .frame(width: 38, alignment: .trailing)
            Text(isStale ? "" : (WidgetTimeText.countdown(to: meter.resetTime, from: now) ?? ""))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// Roomy block used while there is space: the name, then a row per meter.
private struct ProfileBlock: View {
    let profile: WidgetSnapshot.ProfileEntry
    let entry: UsageEntry

    var body: some View {
        let isStale = entry.isProfileStale(profile)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                ProfileName(profile: profile)
                Spacer(minLength: 4)
                if isStale {
                    Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ForEach(profile.meters) { meter in
                MeterRow(meter: meter, now: entry.date, isStale: isStale)
            }
        }
    }
}

/// Tight line used once profiles outnumber the space: name on the left, the
/// profile's meters stacked as a pair on the right.
private struct ProfileLine: View {
    let profile: WidgetSnapshot.ProfileEntry
    let entry: UsageEntry

    var body: some View {
        let isStale = entry.isProfileStale(profile)
        HStack(spacing: 10) {
            ProfileName(profile: profile, size: 12)
                .frame(width: 76, alignment: .leading)
            VStack(spacing: 1) {
                ForEach(profile.meters) { meter in
                    HStack(spacing: 6) {
                        MeterTrack(meter: meter, now: entry.date, isStale: isStale, height: 5)
                        PercentText(percentage: meter.percentage, size: 10, isStale: isStale)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct UsageOverviewContent: View {
    let entry: UsageEntry
    let isLarge: Bool

    private var profiles: [WidgetSnapshot.ProfileEntry] {
        let selected = (entry.snapshot?.profiles ?? []).filter(\.isDisplayed)
        return Array(selected.prefix(isLarge ? 6 : 4))
    }

    /// Blocks while they fit, lines once they would not.
    private var usesBlocks: Bool {
        profiles.count <= (isLarge ? 4 : 2)
    }

    var body: some View {
        if profiles.isEmpty {
            NoDataView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 {
                        Spacer(minLength: usesBlocks ? 6 : 3)
                    }
                    if usesBlocks {
                        ProfileBlock(profile: profile, entry: entry)
                    } else {
                        ProfileLine(profile: profile, entry: entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct UsageOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageOverviewContent(entry: entry, isLarge: family == .systemLarge)
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
