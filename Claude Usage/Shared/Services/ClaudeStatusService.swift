import Foundation

/// Service for fetching Claude system status
class ClaudeStatusService {
    private let statusURL = URL(string: "https://status.claude.com/api/v2/status.json")!

    /// Response structure from Statuspage API
    private struct StatusResponse: Codable {
        let status: StatusDetail

        struct StatusDetail: Codable {
            let indicator: String
            let description: String
        }
    }

    /// Fetch current Claude status
    func fetchStatus() async throws -> ClaudeStatus {
        // TESTING: Uncomment to test different status states
        // return ClaudeStatus(indicator: .none, description: "All Systems Operational")      // Green
        // return ClaudeStatus(indicator: .minor, description: "Minor Service Outage")        // Yellow
        // return ClaudeStatus(indicator: .major, description: "Major Service Outage")        // Orange
        // return ClaudeStatus(indicator: .critical, description: "Critical Service Outage")  // Red
        // return ClaudeStatus(indicator: .unknown, description: "Status Unknown")            // Gray

        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 10  // 10 second timeout

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(StatusResponse.self, from: data)

        // Map indicator string to enum
        let indicator: ClaudeStatus.StatusIndicator
        switch response.status.indicator {
        case "none":
            indicator = .none
        case "minor":
            indicator = .minor
        case "major":
            indicator = .major
        case "critical":
            indicator = .critical
        default:
            indicator = .unknown
        }

        return ClaudeStatus(indicator: indicator, description: response.status.description)
    }
}
