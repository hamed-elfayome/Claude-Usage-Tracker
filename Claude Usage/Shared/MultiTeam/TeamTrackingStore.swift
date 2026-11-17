import Foundation

enum TeamTrackingSettings {
    static let enabledKey = "multiTeam.enabled"

    static func isEnabled(_ d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: enabledKey)
    }
}

/// Persists `TeamTrackingGlobalState` as JSON in UserDefaults; corrupt or missing data reads as `.empty`.
final class TeamTrackingGlobalStore {
    static let key = "multiTeam.globalState"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TeamTrackingGlobalState {
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(TeamTrackingGlobalState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(_ state: TeamTrackingGlobalState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
