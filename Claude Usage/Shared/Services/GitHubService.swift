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

// Legacy GitHubError - kept for compatibility, converted to AppError
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

    // Convert to AppError
    func toAppError() -> AppError {
        switch self {
        case .invalidURL:
            return AppError(
                code: .urlInvalidBase,
                message: "Invalid GitHub URL",
                isRecoverable: false
            )
        case .invalidResponse:
            return AppError(
                code: .githubGenericError,
                message: "Invalid response from GitHub",
                isRecoverable: true
            )
        case .httpError(let code):
            if code == 404 {
                return AppError(
                    code: .githubNotFound,
                    message: "GitHub resource not found",
                    technicalDetails: "HTTP \(code)",
                    isRecoverable: false
                )
            } else if code == 429 {
                return AppError.apiRateLimited()
            } else if code >= 500 {
                return AppError(
                    code: .githubServerError,
                    message: "GitHub server error",
                    technicalDetails: "HTTP \(code)",
                    isRecoverable: true
                )
            } else {
                return AppError(
                    code: .githubGenericError,
                    message: "GitHub API error",
                    technicalDetails: "HTTP \(code)",
                    isRecoverable: true
                )
            }
        }
    }
}
