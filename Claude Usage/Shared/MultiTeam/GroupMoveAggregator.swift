import Foundation

// Builds the one grouped event for a team move seen by several accounts (spec §6 "Grouped move").

enum PeerOutcome: Equatable { case moved(to: String?), notMoved, unchecked }

enum GroupMoveAggregator {
    static func event(from orgId: String, trigger: UUID, triggerTarget: String?,
                      peers: [UUID: PeerOutcome], names: [String: String], now: Date) -> TeamEvent {
        var moves: [UUID: String?] = [trigger: triggerTarget]
        var notMoved: [UUID] = []
        var unchecked: [UUID] = []
        for (id, outcome) in peers where id != trigger {
            switch outcome {
            case let .moved(to): moves[id] = .some(to)
            case .notMoved: notMoved.append(id)
            case .unchecked: unchecked.append(id)
            }
        }
        let to = mostCommonTarget(moves, trigger: trigger)
        return TeamEvent(kind: .groupMove(from: orgId, to: to, moves: moves,
                                          notMoved: notMoved.sorted { $0.uuidString < $1.uuidString },
                                          unchecked: unchecked.sorted { $0.uuidString < $1.uuidString }),
                         names: names, date: now)
    }

    /// Most common non-nil target; ties go to the trigger's target.
    static func mostCommonTarget(_ moves: [UUID: String?], trigger: UUID) -> String? {
        var counts: [String: Int] = [:]
        for case let target?? in moves.values { counts[target, default: 0] += 1 }
        guard let best = counts.values.max() else { return nil }
        if let t = moves[trigger] ?? nil, counts[t] == best { return t }
        return counts.filter { $0.value == best }.keys.sorted().first
    }
}
