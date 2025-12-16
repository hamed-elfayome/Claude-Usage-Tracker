import Foundation

/// Model for GitHub contributor
struct Contributor: Codable, Identifiable {
    let login: String
    let id: Int
    let avatarUrl: String
    let htmlUrl: String
    let contributions: Int

    enum CodingKeys: String, CodingKey {
        case login
        case id
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
        case contributions
    }
}

/// Service for fetching GitHub repository contributors
class GitHubService {
    static let shared = GitHubService()

    private let repoOwner = "hamed-elfayome"
    private let repoName = "Claude-Usage-Tracker"

    private init() {}

    /// Fetches contributors from the GitHub repository
    func fetchContributors() async throws -> [Contributor] {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/contributors"

        guard let url = URL(string: urlString) else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let contributors = try decoder.decode([Contributor].self, from: data)

        return contributors
    }
}

enum GitHubError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid GitHub URL"
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
