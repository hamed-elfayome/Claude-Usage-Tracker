//
//  URLBuilder.swift
//  Claude Usage
//
//  Created on 2025-12-27.
//

import Foundation

/// Error types for URL construction failures
enum URLBuilderError: LocalizedError {
    case invalidBaseURL(String)
    case invalidPath(String)
    case invalidQueryParameter(key: String, value: String)
    case malformedURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let urlString):
            return "Invalid base URL: \(urlString)"
        case .invalidPath(let path):
            return "Invalid URL path: \(path)"
        case .invalidQueryParameter(let key, let value):
            return "Invalid query parameter: \(key)=\(value)"
        case .malformedURL(let description):
            return "Malformed URL: \(description)"
        }
    }
}

/// Professional URL builder with safe construction and validation
struct URLBuilder {
    private var components: URLComponents

    // MARK: - Initialization

    /// Initialize with a base URL string
    /// - Parameter baseURL: The base URL string (e.g., "https://api.example.com")
    /// - Throws: URLBuilderError.invalidBaseURL if the URL is malformed
    init(baseURL: String) throws {
        guard let components = URLComponents(string: baseURL) else {
            throw URLBuilderError.invalidBaseURL(baseURL)
        }

        guard components.scheme != nil, components.host != nil else {
            throw URLBuilderError.invalidBaseURL("Missing scheme or host")
        }

        self.components = components
    }

    /// Initialize with existing URLComponents
    /// - Parameter components: Pre-configured URLComponents
    init(components: URLComponents) {
        // Don't validate here - we trust components from internal methods
        // Validation happens in build()
        self.components = components
    }

    // MARK: - Path Building

    /// Append a path component safely
    /// - Parameter path: The path to append (e.g., "/api/v1/users")
    /// - Returns: A new URLBuilder with the path appended
    func appendingPath(_ path: String) throws -> URLBuilder {
        var newComponents = components

        // Clean the path
        let cleanPath = path.trimmingCharacters(in: .whitespaces)

        // Validate path doesn't contain invalid characters
        guard !cleanPath.contains("..") else {
            throw URLBuilderError.invalidPath("Path contains '..'")
        }

        // Build the new path
        let currentPath = newComponents.path

        // Remove leading/trailing slashes from the path to append
        let trimmedPath = cleanPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Build the new path with proper slash handling
        if currentPath.isEmpty {
            // If current path is empty, start with a slash
            newComponents.path = "/" + trimmedPath
        } else {
            // Add slash separator if current path doesn't end with one
            let needsSlash = !currentPath.hasSuffix("/")
            newComponents.path = currentPath + (needsSlash ? "/" : "") + trimmedPath
        }

        return URLBuilder(components: newComponents)
    }

    /// Append multiple path components
    /// - Parameter paths: Array of path components
    /// - Returns: A new URLBuilder with all paths appended
    func appendingPathComponents(_ paths: [String]) throws -> URLBuilder {
        var builder = self
        for path in paths {
            builder = try builder.appendingPath(path)
        }
        return builder
    }

    // MARK: - Query Parameters

    /// Add a query parameter
    /// - Parameters:
    ///   - name: Query parameter name
    ///   - value: Query parameter value
    /// - Returns: A new URLBuilder with the query parameter added
    func addingQueryParameter(name: String, value: String) throws -> URLBuilder {
        var newComponents = components

        // Validate parameter name and value
        guard !name.isEmpty else {
            throw URLBuilderError.invalidQueryParameter(key: name, value: "Empty parameter name")
        }

        var queryItems = newComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: name, value: value))
        newComponents.queryItems = queryItems

        return URLBuilder(components: newComponents)
    }

    /// Add multiple query parameters
    /// - Parameter parameters: Dictionary of query parameters
    /// - Returns: A new URLBuilder with all parameters added
    func addingQueryParameters(_ parameters: [String: String]) throws -> URLBuilder {
        var builder = self
        for (key, value) in parameters {
            builder = try builder.addingQueryParameter(name: key, value: value)
        }
        return builder
    }

    // MARK: - Build

    /// Build the final URL
    /// - Returns: A validated URL
    /// - Throws: URLBuilderError.malformedURL if the final URL is invalid
    func build() throws -> URL {
        guard let url = components.url else {
            throw URLBuilderError.malformedURL("Failed to construct URL from components")
        }

        // Final validation
        guard let scheme = components.scheme, ["http", "https"].contains(scheme) else {
            throw URLBuilderError.malformedURL("Invalid or missing URL scheme")
        }

        return url
    }
}

// MARK: - Convenience Extensions

extension URLBuilder {
    /// Create a builder for Claude API endpoints
    /// - Parameter endpoint: The API endpoint path
    /// - Returns: A configured URLBuilder
    static func claudeAPI(endpoint: String = "") throws -> URLBuilder {
        let builder = try URLBuilder(baseURL: "https://claude.ai/api")
        return endpoint.isEmpty ? builder : try builder.appendingPath(endpoint)
    }

    /// Create a builder for Console API endpoints
    /// - Parameter endpoint: The API endpoint path
    /// - Returns: A configured URLBuilder
    static func consoleAPI(endpoint: String = "") throws -> URLBuilder {
        let builder = try URLBuilder(baseURL: "https://console.anthropic.com/api")
        return endpoint.isEmpty ? builder : try builder.appendingPath(endpoint)
    }

    /// Create a builder for Claude Status endpoints
    /// - Parameter endpoint: The API endpoint path
    /// - Returns: A configured URLBuilder
    static func claudeStatus(endpoint: String = "") throws -> URLBuilder {
        let builder = try URLBuilder(baseURL: "https://status.claude.com/api/v2")
        return endpoint.isEmpty ? builder : try builder.appendingPath(endpoint)
    }
}

// MARK: - Result-based API

extension URLBuilder {
    /// Build the URL and return a Result type
    /// - Returns: Result containing URL or Error
    func buildResult() -> Result<URL, Error> {
        do {
            return .success(try build())
        } catch {
            return .failure(error)
        }
    }
}
