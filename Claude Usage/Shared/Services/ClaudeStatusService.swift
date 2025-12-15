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
        let (data, _) = try await URLSession.shared.data(from: statusURL)
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
