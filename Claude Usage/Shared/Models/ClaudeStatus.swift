import Foundation

/// Model representing Claude system status
struct ClaudeStatus: Codable, Equatable {
    let indicator: StatusIndicator
    let description: String

    enum StatusIndicator: String, Codable {
        case none       // All systems operational
        case minor      // Minor issues
        case major      // Major outage
        case critical   // Critical outage
        case unknown    // Unable to fetch status

        var color: StatusColor {
            switch self {
            case .none:
                return .green
            case .minor:
                return .yellow
            case .major:
                return .orange
            case .critical:
                return .red
            case .unknown:
                return .gray
            }
        }
    }

    enum StatusColor {
        case green, yellow, orange, red, gray
    }

    /// Default unknown status
    static var unknown: ClaudeStatus {
        ClaudeStatus(indicator: .unknown, description: "Status Unknown")
    }

    /// Operational status
    static var operational: ClaudeStatus {
        ClaudeStatus(indicator: .none, description: "All Systems Operational")
    }
}
