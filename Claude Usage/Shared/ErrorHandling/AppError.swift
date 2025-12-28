//
//  AppError.swift
//  Claude Usage - Unified Error Handling System
//
//  Created on 2025-12-27.
//

import Foundation

/// Unified error system with error codes for debugging and user support
struct AppError: Error, LocalizedError, CustomStringConvertible {

    // MARK: - Properties

    /// Unique error code for identification and support
    let code: ErrorCode

    /// Human-readable error message
    let message: String

    /// Technical details for debugging
    let technicalDetails: String?

    /// Underlying error if this wraps another error
    let underlyingError: Error?

    /// Timestamp when error occurred
    let timestamp: Date

    /// Whether this error is recoverable
    let isRecoverable: Bool

    /// Suggested recovery action for the user
    let recoverySuggestion: String?

    /// Context information (file, line, function)
    let context: ErrorContext?

    // MARK: - Initialization

    init(
        code: ErrorCode,
        message: String,
        technicalDetails: String? = nil,
        underlyingError: Error? = nil,
        isRecoverable: Bool = true,
        recoverySuggestion: String? = nil,
        file: String = #file,
        line: Int = #line,
        function: String = #function
    ) {
        self.code = code
        self.message = message
        self.technicalDetails = technicalDetails
        self.underlyingError = underlyingError
        self.timestamp = Date()
        self.isRecoverable = isRecoverable
        self.recoverySuggestion = recoverySuggestion
        self.context = ErrorContext(file: file, line: line, function: function)
    }

    // MARK: - LocalizedError

    var errorDescription: String? {
        return message
    }

    var failureReason: String? {
        return technicalDetails
    }

    var recoverySuggestionValue: String? {
        return recoverySuggestion
    }

    // MARK: - CustomStringConvertible

    var description: String {
        var desc = "[\(code.rawValue)] \(message)"
        if let details = technicalDetails {
            desc += "\nDetails: \(details)"
        }
        if let underlying = underlyingError {
            desc += "\nUnderlying: \(underlying.localizedDescription)"
        }
        return desc
    }

    // MARK: - Support Information

    /// User-friendly error report for support tickets
    var supportReport: String {
        var report = """
        Error Code: \(code.rawValue)
        Message: \(message)
        Time: \(timestamp.formatted())
        Recoverable: \(isRecoverable ? "Yes" : "No")
        """

        if let details = technicalDetails {
            report += "\nTechnical Details: \(details)"
        }

        if let suggestion = recoverySuggestion {
            report += "\nSuggested Action: \(suggestion)"
        }

        if let context = context {
            report += "\nLocation: \(context.file):\(context.line) in \(context.function)"
        }

        return report
    }

    /// Copy-friendly error code for users to report
    var copyableErrorCode: String {
        return "Error-\(code.rawValue)-\(Int(timestamp.timeIntervalSince1970))"
    }
}

// MARK: - Error Context

struct ErrorContext {
    let file: String
    let line: Int
    let function: String

    var fileName: String {
        return (file as NSString).lastPathComponent
    }
}

// MARK: - Error Codes

enum ErrorCode: String, CaseIterable {

    // MARK: - Session Key Errors (1000-1099)

    case sessionKeyNotFound = "E1000"
    case sessionKeyInvalid = "E1001"
    case sessionKeyExpired = "E1002"
    case sessionKeyTooShort = "E1003"
    case sessionKeyTooLong = "E1004"
    case sessionKeyInvalidPrefix = "E1005"
    case sessionKeyInvalidCharacters = "E1006"
    case sessionKeyInvalidFormat = "E1007"
    case sessionKeyMalicious = "E1008"
    case sessionKeyWhitespace = "E1009"
    case sessionKeyStorageFailed = "E1010"

    // MARK: - Network Errors (2000-2099)

    case networkUnavailable = "E2000"
    case networkTimeout = "E2001"
    case networkConnectionLost = "E2002"
    case networkDNSFailed = "E2003"
    case networkSSLFailed = "E2004"
    case networkGenericError = "E2099"

    // MARK: - API Errors (3000-3099)

    case apiUnauthorized = "E3000"
    case apiInvalidResponse = "E3001"
    case apiServerError = "E3002"
    case apiRateLimited = "E3003"
    case apiNotFound = "E3004"
    case apiBadRequest = "E3005"
    case apiServiceUnavailable = "E3006"
    case apiParsingFailed = "E3007"
    case apiGenericError = "E3099"

    // MARK: - URL Construction Errors (4000-4099)

    case urlInvalidBase = "E4000"
    case urlInvalidPath = "E4001"
    case urlInvalidQuery = "E4002"
    case urlMalformed = "E4003"
    case urlPathTraversal = "E4004"

    // MARK: - Data Storage Errors (5000-5099)

    case storageReadFailed = "E5000"
    case storageWriteFailed = "E5001"
    case storageEncodingFailed = "E5002"
    case storageDecodingFailed = "E5003"
    case storagePermissionDenied = "E5004"
    case storageFileNotFound = "E5005"

    // MARK: - GitHub API Errors (6000-6099)

    case githubRateLimited = "E6000"
    case githubNotFound = "E6001"
    case githubServerError = "E6002"
    case githubGenericError = "E6099"

    // MARK: - Unknown Errors (9000-9999)

    case unknown = "E9999"

    // MARK: - Helpers

    var category: ErrorCategory {
        let prefix = String(rawValue.prefix(2))
        switch prefix {
        case "E1": return .sessionKey
        case "E2": return .network
        case "E3": return .api
        case "E4": return .urlConstruction
        case "E5": return .dataStorage
        case "E6": return .github
        default: return .unknown
        }
    }
}

// MARK: - Error Category

enum ErrorCategory: String {
    case sessionKey = "Session Key"
    case network = "Network"
    case api = "API"
    case urlConstruction = "URL Construction"
    case dataStorage = "Data Storage"
    case github = "GitHub"
    case unknown = "Unknown"
}

// MARK: - Convenience Constructors

extension AppError {

    // MARK: - Session Key Errors

    static func sessionKeyNotFound(file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .sessionKeyNotFound,
            message: "error.session_key_not_found".localized,
            technicalDetails: "Session key file does not exist at expected path",
            isRecoverable: true,
            recoverySuggestion: "error.session_key_not_found.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    static func sessionKeyInvalid(reason: String, file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .sessionKeyInvalid,
            message: "error.session_key_invalid".localized,
            technicalDetails: reason,
            isRecoverable: true,
            recoverySuggestion: "error.session_key_invalid.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    // MARK: - Network Errors

    static func networkUnavailable(file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .networkUnavailable,
            message: "error.network_unavailable".localized,
            technicalDetails: "Network is unreachable",
            isRecoverable: true,
            recoverySuggestion: "error.network_unavailable.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    static func networkTimeout(file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .networkTimeout,
            message: "error.network_timeout".localized,
            technicalDetails: "The server did not respond in time",
            isRecoverable: true,
            recoverySuggestion: "error.network_timeout.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    // MARK: - API Errors

    static func apiUnauthorized(file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .apiUnauthorized,
            message: "error.api_unauthorized".localized,
            technicalDetails: "API returned 401/403 - session key may be expired or invalid",
            isRecoverable: true,
            recoverySuggestion: "error.api_unauthorized.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    static func apiServerError(statusCode: Int, file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .apiServerError,
            message: "error.api_server_error".localized,
            technicalDetails: "HTTP \(statusCode)",
            isRecoverable: true,
            recoverySuggestion: "error.api_server_error.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    static func apiRateLimited(file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        return AppError(
            code: .apiRateLimited,
            message: "error.api_rate_limited".localized,
            technicalDetails: "Too many requests to the API",
            isRecoverable: true,
            recoverySuggestion: "error.api_rate_limited.suggestion".localized,
            file: file,
            line: line,
            function: function
        )
    }

    // MARK: - Wrapping Errors

    static func wrap(_ error: Error, file: String = #file, line: Int = #line, function: String = #function) -> AppError {
        // If already an AppError, return as-is
        if let appError = error as? AppError {
            return appError
        }

        // If it's a SessionKeyValidationError, convert it
        if let validationError = error as? SessionKeyValidationError {
            return fromSessionKeyValidationError(validationError, file: file, line: line, function: function)
        }

        // If it's a URLBuilderError, convert it
        if let urlError = error as? URLBuilderError {
            return fromURLBuilderError(urlError, file: file, line: line, function: function)
        }

        // Generic wrap
        return AppError(
            code: .unknown,
            message: error.localizedDescription,
            technicalDetails: "\(type(of: error)): \(error)",
            underlyingError: error,
            isRecoverable: true,
            file: file,
            line: line,
            function: function
        )
    }

    // MARK: - Conversion from Other Errors

    private static func fromSessionKeyValidationError(_ error: SessionKeyValidationError, file: String, line: Int, function: String) -> AppError {
        switch error {
        case .empty:
            return sessionKeyNotFound(file: file, line: line, function: function)
        case .tooShort(let min, let actual):
            return AppError(code: .sessionKeyTooShort, message: "Session key too short", technicalDetails: "Min: \(min), Actual: \(actual)", file: file, line: line, function: function)
        case .tooLong(let max, let actual):
            return AppError(code: .sessionKeyTooLong, message: "Session key too long", technicalDetails: "Max: \(max), Actual: \(actual)", file: file, line: line, function: function)
        case .invalidPrefix:
            return AppError(code: .sessionKeyInvalidPrefix, message: "Invalid session key prefix", file: file, line: line, function: function)
        case .invalidCharacters:
            return AppError(code: .sessionKeyInvalidCharacters, message: "Invalid characters in session key", file: file, line: line, function: function)
        case .invalidFormat:
            return AppError(code: .sessionKeyInvalidFormat, message: "Invalid session key format", file: file, line: line, function: function)
        case .potentiallyMalicious:
            return AppError(code: .sessionKeyMalicious, message: "Potentially malicious session key", file: file, line: line, function: function)
        case .containsWhitespace:
            return AppError(code: .sessionKeyWhitespace, message: "Session key contains whitespace", file: file, line: line, function: function)
        }
    }

    private static func fromURLBuilderError(_ error: URLBuilderError, file: String, line: Int, function: String) -> AppError {
        switch error {
        case .invalidBaseURL(let url):
            return AppError(code: .urlInvalidBase, message: "Invalid base URL", technicalDetails: url, file: file, line: line, function: function)
        case .invalidPath(let path):
            return AppError(code: .urlInvalidPath, message: "Invalid URL path", technicalDetails: path, file: file, line: line, function: function)
        case .invalidQueryParameter(let key, let value):
            return AppError(code: .urlInvalidQuery, message: "Invalid query parameter", technicalDetails: "\(key)=\(value)", file: file, line: line, function: function)
        case .malformedURL(let details):
            return AppError(code: .urlMalformed, message: "Malformed URL", technicalDetails: details, file: file, line: line, function: function)
        }
    }
}
