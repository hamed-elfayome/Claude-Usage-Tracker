import AppIntents
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

extension UsageEntry {
    /// The profile the single-profile widgets show: the active one, else the
    /// first displayed one.
    var focusProfile: WidgetSnapshot.ProfileEntry? {
        let profiles = snapshot?.profiles ?? []
        // A picked profile that has since been deleted falls back to the active one.
        if let profileID, let picked = profiles.first(where: { $0.id == profileID }) {
            return picked
        }
        return profiles.first(where: \.isActive)
            ?? profiles.first(where: \.isDisplayed)
            ?? profiles.first
    }
}

// MARK: - Profile picker

/// A profile as it appears in a widget's "Edit Widget" settings.
struct WidgetProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "widget.config.profile"
    static var defaultQuery = WidgetProfileQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Lists the profiles the app last published. The widget has no other view of them.
struct WidgetProfileQuery: EntityQuery {
    private func allProfiles() -> [WidgetProfileEntity] {
        (WidgetSnapshot.load()?.profiles ?? []).map {
            WidgetProfileEntity(id: $0.id.uuidString, name: $0.name)
        }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetProfileEntity] {
        allProfiles().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetProfileEntity] {
        allProfiles()
    }
}

/// Settings for the single-profile widgets. With no profile picked, the
/// widget follows whichever profile is active in the app.
struct SelectProfileIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.config.title"
    static var description = IntentDescription("widget.config.desc")

    @Parameter(title: "widget.config.profile")
    var profile: WidgetProfileEntity?
}

struct ProfileTimelineProvider: AppIntentTimelineProvider {
    private func profileID(_ configuration: SelectProfileIntent) -> UUID? {
        configuration.profile.flatMap { UUID(uuidString: $0.id) }
    }

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: UsageEntry.placeholderSnapshot())
    }

    func snapshot(for configuration: SelectProfileIntent, in context: Context) async -> UsageEntry {
        let snapshot = context.isPreview ? UsageEntry.placeholderSnapshot() : WidgetSnapshot.load()
        return UsageEntry(date: Date(), snapshot: snapshot, profileID: profileID(configuration))
    }

    func timeline(for configuration: SelectProfileIntent, in context: Context) async -> Timeline<UsageEntry> {
        UsageTimelineProvider.makeTimeline(profileID: profileID(configuration))
    }
}

// MARK: - Shared pieces

/// Tinted and vibrant desktop modes drop color, so hierarchy has to come from
/// opacity there; in full color the fill carries the usage level.
private func meterFill(_ percentage: Double, isStale: Bool, mode: WidgetRenderingMode) -> AnyShapeStyle {
    if isStale { return AnyShapeStyle(.secondary) }
    if mode == .fullColor { return AnyShapeStyle(levelColor(percentage)) }
    return AnyShapeStyle(.primary)
}

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

    private var fillStyle: AnyShapeStyle {
        meterFill(meter.percentage, isStale: isStale, mode: renderingMode)
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

    private var profile: WidgetSnapshot.ProfileEntry? { entry.focusProfile }

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
        AppIntentConfiguration(kind: "SessionUsageWidget", intent: SelectProfileIntent.self, provider: ProfileTimelineProvider()) { entry in
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
    /// Larger type and a taller track, for when few profiles share the widget.
    var isEmphasized = false

    var body: some View {
        HStack(spacing: isEmphasized ? 10 : 8) {
            Text(meter.kind.label)
                .font(.system(size: isEmphasized ? 13 : 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: isEmphasized ? 58 : 50, alignment: .leading)
            MeterTrack(meter: meter, now: now, isStale: isStale, height: isEmphasized ? 12 : 8)
            PercentText(percentage: meter.percentage, size: isEmphasized ? 16 : 13, isStale: isStale)
                .frame(width: isEmphasized ? 46 : 38, alignment: .trailing)
            Text(isStale ? "" : (WidgetTimeText.countdown(to: meter.resetTime, from: now) ?? ""))
                .font(.system(size: isEmphasized ? 11 : 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: isEmphasized ? 50 : 44, alignment: .trailing)
        }
    }
}

/// Roomy block used while there is space: the name, then a row per meter.
private struct ProfileBlock: View {
    let profile: WidgetSnapshot.ProfileEntry
    let entry: UsageEntry
    var isEmphasized = false

    var body: some View {
        let isStale = entry.isProfileStale(profile)
        VStack(alignment: .leading, spacing: isEmphasized ? 8 : 3) {
            HStack(alignment: .firstTextBaseline) {
                ProfileName(profile: profile, size: isEmphasized ? 16 : 13)
                Spacer(minLength: 4)
                if isStale {
                    Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            ForEach(profile.meters) { meter in
                MeterRow(meter: meter, now: entry.date, isStale: isStale, isEmphasized: isEmphasized)
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
    enum Size {
        case medium, large, extraLarge

        var maxProfiles: Int {
            switch self {
            case .medium: return 4
            case .large: return 6
            case .extraLarge: return 8
            }
        }

        /// How many roomy blocks fit in one column before switching to lines.
        var blocksPerColumn: Int {
            switch self {
            case .medium: return 2
            case .large, .extraLarge: return 4
            }
        }

        /// Up to this many profiles in a column get the larger block, so a
        /// widget showing one or two profiles is filled, not mostly empty.
        var emphasizedPerColumn: Int {
            switch self {
            case .medium: return 1
            case .large, .extraLarge: return 2
            }
        }
    }

    let entry: UsageEntry
    var size: Size = .medium

    private var profiles: [WidgetSnapshot.ProfileEntry] {
        let selected = (entry.snapshot?.profiles ?? []).filter(\.isDisplayed)
        return Array(selected.prefix(size.maxProfiles))
    }

    /// The extra-large widget is twice as wide, so it reads as two columns.
    private var columns: [[WidgetSnapshot.ProfileEntry]] {
        guard size == .extraLarge, profiles.count > 1 else { return [profiles] }
        let half = (profiles.count + 1) / 2
        return [Array(profiles.prefix(half)), Array(profiles.dropFirst(half))]
    }

    private func column(_ profiles: [WidgetSnapshot.ProfileEntry]) -> some View {
        // Blocks while they fit, lines once they would not.
        let usesBlocks = profiles.count <= size.blocksPerColumn
        let isEmphasized = profiles.count <= size.emphasizedPerColumn
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 {
                    Spacer(minLength: usesBlocks ? 6 : 3)
                }
                if usesBlocks {
                    ProfileBlock(profile: profile, entry: entry, isEmphasized: isEmphasized)
                } else {
                    ProfileLine(profile: profile, entry: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: profiles.count > 1 ? .infinity : nil, alignment: .topLeading)
    }

    /// A single profile in the large widget has the whole square to itself:
    /// its rings at full size, then each window's number and time to reset.
    private func hero(_ profile: WidgetSnapshot.ProfileEntry) -> some View {
        let isStale = entry.isProfileStale(profile)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                ProfileName(profile: profile, size: 17)
                Spacer(minLength: 4)
                if isStale {
                    Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            ProfileRings(profile: profile, entry: entry, diameter: 176, showsPercentage: false)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            HStack(alignment: .top, spacing: 16) {
                ForEach(profile.meters) { meter in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(meter.kind.label)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            PercentText(percentage: meter.percentage, size: 26, isStale: isStale)
                            if !isStale, let countdown = WidgetTimeText.countdown(to: meter.resetTime, from: entry.date) {
                                Text(countdown)
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Two profiles in the large widget: each gets its rings with the numbers beside them.
    private func ringRows(_ profiles: [WidgetSnapshot.ProfileEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 {
                    Divider().padding(.vertical, 10)
                }
                HStack(spacing: 20) {
                    ProfileRings(profile: profile, entry: entry, diameter: 112, showsPercentage: false)
                    VStack(alignment: .leading, spacing: 6) {
                        ProfileName(profile: profile, size: 15)
                        MeterLegend(profile: profile, entry: entry)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    var body: some View {
        if profiles.isEmpty {
            NoDataView()
        } else if size == .large, profiles.count == 1, let profile = profiles.first {
            hero(profile)
        } else if size == .large, profiles.count == 2 {
            ringRows(profiles)
        } else {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, profiles in
                    column(profiles)
                }
            }
        }
    }
}

struct UsageOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    private var size: UsageOverviewContent.Size {
        switch family {
        case .systemExtraLarge: return .extraLarge
        case .systemLarge: return .large
        default: return .medium
        }
    }

    var body: some View {
        UsageOverviewContent(entry: entry, size: size)
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
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Rings

/// One ring: the window as a circle, usage as the arc, and a notch where
/// "now" falls. The same reading as the track, bent round.
private struct MeterRing: View {
    let meter: WidgetMeter
    let now: Date
    let isStale: Bool
    let lineWidth: CGFloat
    /// The dial leaves a gap at the bottom; a ring is the whole circle.
    var sweep: Double = 1
    var startDegrees: Double = -90

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2 - lineWidth / 2
            ZStack {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(.primary.opacity(0.13), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(startDegrees))
                if meter.fraction > 0 {
                    Circle()
                        .trim(from: 0, to: sweep * meter.fraction)
                        .stroke(meterFill(meter.percentage, isStale: isStale, mode: renderingMode),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(startDegrees))
                        .widgetAccentable()
                }
                if !isStale, let elapsed = meter.elapsedFraction(at: now) {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: lineWidth + 4)
                        .offset(y: -radius)
                        // The notch is drawn at 12 o'clock (-90°); turn it to its place on the arc.
                        .rotationEffect(.degrees(startDegrees + 90 + 360 * sweep * elapsed))
                }
            }
            .padding(lineWidth / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A profile as concentric rings, the way the menu bar draws it: session
/// outside, week inside. The first meter's percentage sits in the middle.
private struct ProfileRings: View {
    let profile: WidgetSnapshot.ProfileEntry
    let entry: UsageEntry
    let diameter: CGFloat
    /// Off when the numbers are spelled out next to the rings.
    var showsPercentage = true

    var body: some View {
        let isStale = entry.isProfileStale(profile)
        let meters = profile.meters
        let lineWidth = diameter * (meters.count > 1 ? 0.105 : 0.13)
        ZStack {
            ForEach(Array(meters.enumerated()), id: \.element.id) { index, meter in
                MeterRing(meter: meter, now: entry.date, isStale: isStale, lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + diameter * 0.03))
            }
            if showsPercentage, let primary = meters.first {
                PercentText(percentage: primary.percentage, size: max(10, diameter * 0.17), isStale: isStale)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Label, percentage and time to reset for each meter, beside a ring.
private struct MeterLegend: View {
    let profile: WidgetSnapshot.ProfileEntry
    let entry: UsageEntry

    var body: some View {
        let isStale = entry.isProfileStale(profile)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(profile.meters) { meter in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(meter.kind.label)
                        Spacer(minLength: 0)
                        if !isStale, let countdown = WidgetTimeText.countdown(to: meter.resetTime, from: entry.date) {
                            Text(countdown).monospacedDigit()
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    PercentText(percentage: meter.percentage, size: 20, isStale: isStale)
                }
            }
            if isStale {
                Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UsageRingsContent: View {
    let entry: UsageEntry
    let isMedium: Bool

    private var profiles: [WidgetSnapshot.ProfileEntry] {
        // A picked profile is shown alone at either size; with none picked the
        // medium size shows every displayed profile.
        guard isMedium, entry.profileID == nil else { return entry.focusProfile.map { [$0] } ?? [] }
        return Array((entry.snapshot?.profiles ?? []).filter(\.isDisplayed).prefix(4))
    }

    var body: some View {
        if profiles.isEmpty {
            NoDataView()
        } else if !isMedium, let profile = profiles.first {
            VStack(alignment: .leading, spacing: 6) {
                ProfileName(profile: profile)
                ProfileRings(profile: profile, entry: entry, diameter: 98)
                    .frame(maxWidth: .infinity)
            }
        } else if profiles.count == 1, let profile = profiles.first {
            // One profile has the width to spell its numbers out.
            HStack(spacing: 20) {
                ProfileRings(profile: profile, entry: entry, diameter: 118, showsPercentage: false)
                VStack(alignment: .leading, spacing: 8) {
                    ProfileName(profile: profile, size: 15)
                    MeterLegend(profile: profile, entry: entry)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            let diameter: CGFloat = profiles.count == 2 ? 96 : (profiles.count == 3 ? 86 : 64)
            HStack(alignment: .top, spacing: 0) {
                ForEach(profiles) { profile in
                    VStack(spacing: 7) {
                        ProfileRings(profile: profile, entry: entry, diameter: diameter)
                        ProfileName(profile: profile, size: 11)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct UsageRingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageRingsContent(entry: entry, isMedium: family == .systemMedium)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct UsageRingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UsageRingsWidget", intent: SelectProfileIntent.self, provider: ProfileTimelineProvider()) { entry in
            UsageRingsWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.rings.name"))
        .description(String(localized: "widget.rings.desc"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Dial

/// A single meter as an instrument dial: three quarters of a circle, the
/// reading in the middle, the time to reset in the gap underneath.
struct UsageDialContent: View {
    let entry: UsageEntry

    var body: some View {
        if let profile = entry.focusProfile, let primary = profile.meters.first {
            let isStale = entry.isProfileStale(profile)
            VStack(alignment: .leading, spacing: 2) {
                ProfileName(profile: profile)
                ZStack {
                    MeterRing(meter: primary, now: entry.date, isStale: isStale, lineWidth: 11,
                              sweep: 0.75, startDegrees: 135)
                    VStack(spacing: -2) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(Int(primary.percentage))")
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("%")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .opacity(isStale ? 0.55 : 1)
                        Text(primary.kind.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Group {
                        if isStale {
                            Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                        } else if let countdown = WidgetTimeText.countdown(to: primary.resetTime, from: entry.date) {
                            Text(countdown).monospacedDigit()
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(width: 104, height: 104)
                .frame(maxWidth: .infinity)
            }
        } else {
            NoDataView()
        }
    }
}

struct UsageDialWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UsageDialWidget", intent: SelectProfileIntent.self, provider: ProfileTimelineProvider()) { entry in
            UsageDialContent(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.dial.name"))
        .description(String(localized: "widget.dial.desc"))
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Next reset

/// The same data read the other way round: not how much is used, but how
/// long until it comes back.
struct NextResetContent: View {
    let entry: UsageEntry

    var body: some View {
        if let profile = entry.focusProfile, let primary = profile.meters.first {
            let isStale = entry.isProfileStale(profile)
            VStack(alignment: .leading, spacing: 0) {
                ProfileName(profile: profile)

                Spacer(minLength: 0)

                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(isStale
                     ? WidgetTimeText.age(of: profile.lastUpdated, at: entry.date)
                     : (WidgetTimeText.countdown(to: primary.resetTime, from: entry.date) ?? "–"))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .opacity(isStale ? 0.55 : 1)

                HStack(spacing: 4) {
                    Text(primary.kind.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    PercentText(percentage: primary.percentage, size: 11, isStale: isStale)
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .padding(.bottom, 3)

                MeterTrack(meter: primary, now: entry.date, isStale: isStale, height: 9)

                if let secondary = profile.meters.dropFirst().first {
                    HStack(spacing: 4) {
                        Text(secondary.kind.label)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if !isStale, let countdown = WidgetTimeText.countdown(to: secondary.resetTime, from: entry.date) {
                            Text(countdown)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.top, 5)
                }
            }
        } else {
            NoDataView()
        }
    }
}

struct NextResetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextResetWidget", intent: SelectProfileIntent.self, provider: ProfileTimelineProvider()) { entry in
            NextResetContent(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.reset.name"))
        .description(String(localized: "widget.reset.desc"))
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Active profile, wide

/// The active profile with room to breathe: its headline number on the left,
/// each window as a full-width track on the right.
struct ActiveProfileContent: View {
    let entry: UsageEntry

    var body: some View {
        if let profile = entry.focusProfile, let primary = profile.meters.first {
            let isStale = entry.isProfileStale(profile)
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) {
                    ProfileName(profile: profile, size: 14)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(primary.percentage))")
                            .font(.system(size: 50, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(isStale ? 0.55 : 1)
                    (isStale
                         ? Text(WidgetTimeText.age(of: profile.lastUpdated, at: entry.date))
                         : Text(primary.kind.label))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 100, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(profile.meters) { meter in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(meter.kind.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                if !isStale, let countdown = WidgetTimeText.countdown(to: meter.resetTime, from: entry.date) {
                                    Text(countdown)
                                        .font(.system(size: 10))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                PercentText(percentage: meter.percentage, isStale: isStale)
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .lineLimit(1)
                            MeterTrack(meter: meter, now: entry.date, isStale: isStale, height: 10)
                        }
                    }
                }
            }
        } else {
            NoDataView()
        }
    }
}

struct ActiveProfileWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ActiveProfileWidget", intent: SelectProfileIntent.self, provider: ProfileTimelineProvider()) { entry in
            ActiveProfileContent(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "widget.active.name"))
        .description(String(localized: "widget.active.desc"))
        .supportedFamilies([.systemMedium])
    }
}
