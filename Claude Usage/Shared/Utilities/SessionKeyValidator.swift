//
//  SessionKeyValidator.swift
//  Claude Usage
//
//  Created on 2025-12-27.
//

import Foundation

/// Error types for session key validation failures
enum SessionKeyValidationError: LocalizedError {
    case empty
    case tooShort(minLength: Int, actualLength: Int)
    case tooLong(maxLength: Int, actualLength: Int)
    case invalidPrefix(expected: String)
    case invalidCharacters(String)
    case invalidFormat(String)
    case containsWhitespace
    case potentiallyMalicious(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Session key cannot be empty"
        case .tooShort(let min, let actual):
            return "Session key too short (minimum: \(min), actual: \(actual))"
        case .tooLong(let max, let actual):
            return "Session key too long (maximum: \(max), actual: \(actual))"
        case .invalidPrefix(let expected):
            return "Session key must start with '\(expected)'"
        case .invalidCharacters(let description):
            return "Session key contains invalid characters: \(description)"
        case .invalidFormat(let description):
            return "Invalid session key format: \(description)"
        case .containsWhitespace:
            return "Session key cannot contain whitespace"
        case .potentiallyMalicious(let reason):
            return "Session key rejected for security: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .empty, .tooShort, .tooLong:
            return "Please copy the complete sessionKey cookie value from your browser's DevTools"
        case .invalidPrefix:
            return "Ensure you're copying the sessionKey cookie value, which should start with 'sk-ant-'"
        case .invalidCharacters, .invalidFormat:
            return "The session key may be corrupted. Please copy it again from your browser"
        case .containsWhitespace:
            return "Remove any spaces or newlines from the session key"
        case .potentiallyMalicious:
            return "Please verify the session key is from a legitimate source"
        }
    }
}

/// Professional session key validator with comprehensive security checks
struct SessionKeyValidator {

    // MARK: - Configuration

    /// Validation configuration
    struct Configuration {
        let requiredPrefix: String
        let minLength: Int
        let maxLength: Int
        let allowedCharacterSet: CharacterSet
        let strictMode: Bool

        static let `default` = Configuration(
            requiredPrefix: "sk-ant-",
            minLength: 20,
            maxLength: 500,
            allowedCharacterSet: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"),
            strictMode: true
        )

        static let relaxed = Configuration(
            requiredPrefix: "sk-ant-",
            minLength: 10,
            maxLength: 1000,
            allowedCharacterSet: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."),
            strictMode: false
        )
    }

    private let configuration: Configuration

    // MARK: - Initialization

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Validation

    /// Validate a session key
    /// - Parameter sessionKey: The session key to validate
    /// - Throws: SessionKeyValidationError if validation fails
    /// - Returns: The sanitized session key
    @discardableResult
    func validate(_ sessionKey: String) throws -> String {
        // Step 1: Trim whitespace
        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 2: Check if empty
        guard !trimmed.isEmpty else {
            throw SessionKeyValidationError.empty
        }

        // Step 3: Check for internal whitespace
        if configuration.strictMode && trimmed.contains(where: { $0.isWhitespace }) {
            throw SessionKeyValidationError.containsWhitespace
        }

        // Step 4: Check length constraints
        guard trimmed.count >= configuration.minLength else {
            throw SessionKeyValidationError.tooShort(
                minLength: configuration.minLength,
                actualLength: trimmed.count
            )
        }

        guard trimmed.count <= configuration.maxLength else {
            throw SessionKeyValidationError.tooLong(
                maxLength: configuration.maxLength,
                actualLength: trimmed.count
            )
        }

        // Step 5: Check prefix
        guard trimmed.hasPrefix(configuration.requiredPrefix) else {
            throw SessionKeyValidationError.invalidPrefix(expected: configuration.requiredPrefix)
        }

        // Step 6: Security checks (strict mode) - CHECK BEFORE character validation
        // This ensures malicious patterns are caught with specific error messages
        if configuration.strictMode {
            try performSecurityChecks(trimmed)
        }

        // Step 7: Validate character set
        let invalidCharacters = trimmed.unicodeScalars.filter { scalar in
            !configuration.allowedCharacterSet.contains(scalar)
        }

        if !invalidCharacters.isEmpty {
            let invalidCharsString = String(String.UnicodeScalarView(invalidCharacters))
            throw SessionKeyValidationError.invalidCharacters(
                "Found disallowed characters: '\(invalidCharsString)'"
            )
        }

        // Step 8: Format validation
        try validateFormat(trimmed)

        return trimmed
    }

    /// Validate and return a Result type
    /// - Parameter sessionKey: The session key to validate
    /// - Returns: Result containing sanitized key or error
    func validateResult(_ sessionKey: String) -> Result<String, Error> {
        do {
            return .success(try validate(sessionKey))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Private Validation Helpers

    private func performSecurityChecks(_ sessionKey: String) throws {
        // Check for null bytes
        if sessionKey.contains("\0") {
            throw SessionKeyValidationError.potentiallyMalicious("Contains null bytes")
        }

        // Check for control characters
        if sessionKey.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            throw SessionKeyValidationError.potentiallyMalicious("Contains control characters")
        }

        // Check for path traversal attempts
        if sessionKey.contains("..") || sessionKey.contains("//") {
            throw SessionKeyValidationError.potentiallyMalicious("Contains suspicious patterns")
        }

        // Check for script injection patterns
        let suspiciousPatterns = ["<script", "javascript:", "data:", "vbscript:", "file:"]
        for pattern in suspiciousPatterns {
            if sessionKey.lowercased().contains(pattern) {
                throw SessionKeyValidationError.potentiallyMalicious("Contains script injection pattern")
            }
        }
    }

    private func validateFormat(_ sessionKey: String) throws {
        // After the prefix, we should have a reasonable structure
        let afterPrefix = String(sessionKey.dropFirst(configuration.requiredPrefix.count))

        // Should not be empty after prefix
        guard !afterPrefix.isEmpty else {
            throw SessionKeyValidationError.invalidFormat("No content after prefix")
        }

        // Should contain at least one section separator (typically a hyphen or underscore)
        // This is typical of session key formats like: sk-ant-sid01-xxxxx-yyyyy
        guard afterPrefix.contains("-") || afterPrefix.contains("_") else {
            throw SessionKeyValidationError.invalidFormat("Missing expected separators")
        }
    }

    // MARK: - Sanitization

    /// Sanitize a session key for storage (additional layer of security)
    /// - Parameter sessionKey: The validated session key
    /// - Returns: Sanitized session key safe for storage
    func sanitizeForStorage(_ sessionKey: String) -> String {
        // Remove any potential padding or encoding issues
        return sessionKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    // MARK: - Quick Validation

    /// Quick validation check (less strict, for UI feedback)
    /// - Parameter sessionKey: The session key to check
    /// - Returns: true if key looks valid
    func isValid(_ sessionKey: String) -> Bool {
        do {
            try validate(sessionKey)
            return true
        } catch {
            return false
        }
    }

    /// Get validation status with detailed feedback
    /// - Parameter sessionKey: The session key to check
    /// - Returns: Tuple with validation status and optional error message
    func validationStatus(_ sessionKey: String) -> (isValid: Bool, errorMessage: String?) {
        do {
            try validate(sessionKey)
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Validate this string as a session key
    /// - Parameter configuration: Optional validator configuration
    /// - Throws: SessionKeyValidationError if invalid
    /// - Returns: Sanitized session key
    func validateAsSessionKey(
        configuration: SessionKeyValidator.Configuration = .default
    ) throws -> String {
        let validator = SessionKeyValidator(configuration: configuration)
        return try validator.validate(self)
    }

    /// Check if this string is a valid session key
    var isValidSessionKey: Bool {
        let validator = SessionKeyValidator()
        return validator.isValid(self)
    }
}
