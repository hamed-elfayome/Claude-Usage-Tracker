//
//  ErrorRecovery.swift
//  Claude Usage - Intelligent Error Recovery and Retry System
//
//  Created on 2025-12-27.
//

import Foundation

/// Intelligent retry system for network and API operations
class ErrorRecovery {

    static let shared = ErrorRecovery()

    private init() {}

    // MARK: - Retry Decision

    /// Determine if an error should be retried
    func shouldRetry(_ error: AppError, attemptNumber: Int = 1) -> RetryDecision {
        // Never retry after max attempts
        guard attemptNumber < 5 else {
            return .doNotRetry(reason: "Maximum retry attempts reached")
        }

        // Check if error is recoverable
        guard error.isRecoverable else {
            return .doNotRetry(reason: "Error is not recoverable")
        }

        // Determine retry strategy based on error code
        switch error.code {

        // Network errors - retry with exponential backoff
        case .networkUnavailable, .networkConnectionLost:
            return .retryAfter(delay: exponentialBackoff(attempt: attemptNumber), strategy: .exponential)

        case .networkTimeout:
            return .retryAfter(delay: exponentialBackoff(attempt: attemptNumber, base: 2.0), strategy: .exponential)

        // API errors
        case .apiRateLimited:
            // Rate limiting - wait longer
            return .retryAfter(delay: exponentialBackoff(attempt: attemptNumber, base: 5.0), strategy: .exponential)

        case .apiServerError:
            // Server errors might be temporary
            return .retryAfter(delay: exponentialBackoff(attempt: attemptNumber), strategy: .exponential)

        case .apiUnauthorized:
            // Don't retry auth errors - user needs to fix session key
            return .doNotRetry(reason: "Authentication required - please update session key")

        case .apiServiceUnavailable:
            // Service unavailable - retry with backoff
            return .retryAfter(delay: exponentialBackoff(attempt: attemptNumber, base: 3.0), strategy: .exponential)

        // Session key errors - no retry, user action needed
        case .sessionKeyNotFound, .sessionKeyInvalid, .sessionKeyExpired:
            return .doNotRetry(reason: "Session key configuration required")

        // Storage errors - retry once
        case .storageReadFailed, .storageWriteFailed:
            if attemptNumber == 1 {
                return .retryAfter(delay: 0.5, strategy: .immediate)
            } else {
                return .doNotRetry(reason: "Storage operation failed multiple times")
            }

        // GitHub errors
        case .githubRateLimited:
            return .retryAfter(delay: 60.0, strategy: .fixed)

        // URL errors - no retry, programming error
        case .urlInvalidBase, .urlInvalidPath, .urlMalformed:
            return .doNotRetry(reason: "Invalid URL configuration")

        default:
            // Generic errors - one retry with short delay
            if attemptNumber == 1 {
                return .retryAfter(delay: 1.0, strategy: .fixed)
            } else {
                return .doNotRetry(reason: "Unknown error type")
            }
        }
    }

    // MARK: - Retry Execution

    /// Execute an async operation with intelligent retry
    func executeWithRetry<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var attemptNumber = 1
        var lastError: AppError?

        while attemptNumber <= maxAttempts {
            do {
                // Try the operation
                let result = try await operation()
                return result

            } catch let error as AppError {
                lastError = error
                ErrorLogger.shared.log(error, severity: .warning)

                // Determine if we should retry
                let decision = shouldRetry(error, attemptNumber: attemptNumber)

                switch decision {
                case .retryAfter(let delay, _):
                    LoggingService.shared.log("ErrorRecovery: Attempt \(attemptNumber) failed. Retrying after \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    attemptNumber += 1

                case .doNotRetry(let reason):
                    LoggingService.shared.logError("ErrorRecovery: Not retrying - \(reason)")
                    throw error
                }

            } catch {
                // Wrap unknown errors
                let appError = AppError.wrap(error)
                lastError = appError
                ErrorLogger.shared.log(appError, severity: .error)
                throw appError
            }
        }

        // All attempts failed
        if let error = lastError {
            throw error
        } else {
            throw AppError(
                code: .unknown,
                message: "Operation failed after \(maxAttempts) attempts",
                isRecoverable: false
            )
        }
    }

    // MARK: - Backoff Strategies

    private func exponentialBackoff(attempt: Int, base: Double = 1.0, max: Double = 30.0) -> TimeInterval {
        let delay = base * pow(2.0, Double(attempt - 1))
        return min(delay, max)
    }

    private func linearBackoff(attempt: Int, increment: Double = 1.0) -> TimeInterval {
        return Double(attempt) * increment
    }

    // MARK: - Circuit Breaker

    private var circuitBreakerState: [ErrorCategory: CircuitState] = [:]

    /// Check if circuit breaker is open for a category
    func isCircuitOpen(for category: ErrorCategory) -> Bool {
        guard let state = circuitBreakerState[category] else {
            return false
        }

        switch state {
        case .open(let openedAt):
            // Circuit opens for 60 seconds
            let timeSinceOpen = Date().timeIntervalSince(openedAt)
            if timeSinceOpen > 60 {
                // Try half-open
                circuitBreakerState[category] = .halfOpen
                return false
            }
            return true

        case .halfOpen, .closed:
            return false
        }
    }

    /// Record a failure for circuit breaker
    func recordFailure(for category: ErrorCategory) {
        circuitBreakerState[category] = .open(openedAt: Date())
    }

    /// Record a success for circuit breaker
    func recordSuccess(for category: ErrorCategory) {
        circuitBreakerState[category] = .closed
    }
}

// MARK: - Supporting Types

enum RetryDecision {
    case retryAfter(delay: TimeInterval, strategy: RetryStrategy)
    case doNotRetry(reason: String)
}

enum RetryStrategy {
    case immediate
    case fixed
    case exponential
    case linear
}

enum CircuitState {
    case closed
    case open(openedAt: Date)
    case halfOpen
}
