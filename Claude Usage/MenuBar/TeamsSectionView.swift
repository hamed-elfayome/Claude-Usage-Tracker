import SwiftUI

/// Popover "Teams" section (spec §11). Pure view over MT-3's `TeamRows`; the tracker callbacks are wired by the caller.
struct TeamsSectionView: View {
    let rows: [TeamRow]
    let events: [TeamEvent]
    let now: Date
    let onMakeCurrent: (PairRef) -> Void
    let onDelete: (PairRef) -> Void

    @AppStorage("popover.teamsExpanded") private var expanded = true
    @State private var pendingDelete: TeamRow?

    static func canMakeCurrent(_ row: TeamRow) -> Bool { row.state == .ok && !row.isCurrent }
    static func canDelete(_ row: TeamRow) -> Bool { row.state == .old || row.state == .unreachable }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { expanded.toggle() }) {
                HStack(spacing: 4) {
                    Text("multiteam.ui.teams".localized)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(rows) { row in rowView(row) }
                ForEach(Array(events.prefix(5))) { event in
                    HStack(spacing: 4) {
                        Text(event.title).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.relative(event.date, now: now)).lineLimit(1)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(width: 280, alignment: .leading)
        .confirmationDialog(
            pendingDelete.map {
                String(format: "multiteam.ui.delete_confirm".localized, $0.orgName, $0.profileName)
            } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("multiteam.ui.delete".localized, role: .destructive) {
                if let row = pendingDelete { onDelete(row.pair) }
                pendingDelete = nil
            }
            Button("multiteam.ui.cancel".localized, role: .cancel) { pendingDelete = nil }
        }
    }

    static func relative(_ date: Date, now: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: now)
    }

    /// Detail line pieces for a row, e.g. ["5h 40% left", "Week 70% left", "projected"]. Pure for tests.
    static func detail(_ row: TeamRow, now: Date) -> [String] {
        switch row.state {
        case .needsLogin: return ["multiteam.login_again".localized]
        case .notSignedIn: return ["multiteam.not_signed_in".localized]
        case .old:
            return [row.deleteAfterDays.map { String(format: "multiteam.ui.old_days".localized, $0) }
                    ?? "multiteam.ui.old".localized]
        case .unreachable: return ["multiteam.ui.old".localized]
        case .ok:
            var parts: [String] = []
            if let s = row.view.sessionLeft {
                parts.append(String(format: "multiteam.ui.five_hour_left".localized, Int(s.rounded())))
            }
            if let w = row.view.weeklyLeft {
                parts.append(String(format: "multiteam.ui.week_left".localized, Int(w.rounded())))
            }
            if row.view.sessionProjected || row.view.weeklyProjected {
                parts.append("multiteam.ui.projected".localized)
            }
            if let at = row.lastSampleAt, now.timeIntervalSince(at) > 15 * 60 {
                parts.append(String(format: "multiteam.ui.min_ago".localized, Int(now.timeIntervalSince(at) / 60)))
            }
            return parts
        }
    }

    @ViewBuilder
    private func rowView(_ row: TeamRow) -> some View {
        let dimmed = Self.canDelete(row)
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(row.profileName) · \(row.orgName)")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.isCurrent {
                        Text("multiteam.ui.now".localized)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                            .foregroundColor(.accentColor)
                    }
                }
                Text(Self.detail(row, now: now).joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if Self.canDelete(row) {
                Button("multiteam.ui.delete".localized) { pendingDelete = row }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            } else if Self.canMakeCurrent(row) {
                Menu {
                    Button("multiteam.ui.make_current".localized) { onMakeCurrent(row.pair) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .contextMenu {
            if Self.canMakeCurrent(row) {
                Button("multiteam.ui.make_current".localized) { onMakeCurrent(row.pair) }
            }
        }
    }

    // MARK: - History picker helpers

    static func historyChoices(for profile: Profile) -> [(key: String, label: String)] {
        guard let orgs = profile.orgTracking?.orgs, orgs.count > 1 else { return [] }
        return orgs.map {
            ($0.historyKey, $0.status == .old ? "\($0.name) \("multiteam.ui.history_old_suffix".localized)" : $0.name)
        }
    }

    static func defaultHistoryKey(for profile: Profile) -> String? {
        guard let orgs = profile.orgTracking?.orgs, orgs.count > 1 else { return nil }
        return (orgs.first { $0.orgId == profile.organizationId } ?? orgs[0]).historyKey
    }
}
