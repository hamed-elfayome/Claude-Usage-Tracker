import Foundation

/// Service for fetching Claude system status
class ClaudeStatusService {
    private let statusURL = URL(string: "https://status.claude.com/api/v2/status.json")!
    
    // TESTING ONLY: Set to test different status states
    // Set to nil to use real API
    var debugStatus: ClaudeStatus.StatusIndicator? = nil
    
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
        // TESTING: Return debug status if set
        if let debug = debugStatus {
            let description: String
            switch debug {
            case .none:
                description = "All Systems Operational"
            case .minor:
                description = "Minor Service Outage"
            case .major:
                description = "Major Service Outage"
            case .critical:
                description = "Critical Service Outage"
            case .unknown:
                description = "Status Unknown"
            }
            return ClaudeStatus(indicator: debug, description: description)
        }
        
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
