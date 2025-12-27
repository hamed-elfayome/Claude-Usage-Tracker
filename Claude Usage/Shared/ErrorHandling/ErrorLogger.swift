//
//  ErrorLogger.swift
//  Claude Usage - Error Logging and Tracking
//
//  Created on 2025-12-27.
//

import Foundation

/// Centralized error logging system
class ErrorLogger {

    static let shared = ErrorLogger()

    private var errorLog: [LoggedError] = []
    private let maxLogSize = 100
    private let logQueue = DispatchQueue(label: "com.claude-usage.errorlogger", qos: .utility)

    private init() {}

    // MARK: - Logging

    /// Log an error
    func log(_ error: AppError, severity: ErrorSeverity = .error) {
        logQueue.async { [weak self] in
            guard let self = self else { return }

            let logged = LoggedError(
                error: error,
                severity: severity,
                timestamp: Date()
            )

            self.errorLog.append(logged)

            // Keep log size manageable
            if self.errorLog.count > self.maxLogSize {
                self.errorLog.removeFirst(self.errorLog.count - self.maxLogSize)
            }

            // Print to console in debug
            #if DEBUG
            self.printError(logged)
            #endif
        }
    }

    /// Log any error (will wrap it in AppError)
    func log(_ error: Error, severity: ErrorSeverity = .error) {
        let appError = AppError.wrap(error)
        log(appError, severity: severity)
    }

    // MARK: - Retrieval

    /// Get recent errors
    func getRecentErrors(count: Int = 10) -> [LoggedError] {
        return logQueue.sync {
            return Array(errorLog.suffix(count))
        }
    }

    /// Get errors by category
    func getErrors(category: ErrorCategory) -> [LoggedError] {
        return logQueue.sync {
            return errorLog.filter { $0.error.code.category == category }
        }
    }

    /// Get errors by severity
    func getErrors(severity: ErrorSeverity) -> [LoggedError] {
        return logQueue.sync {
            return errorLog.filter { $0.severity == severity }
        }
    }

    /// Clear all logs
    func clearLog() {
        logQueue.async { [weak self] in
            self?.errorLog.removeAll()
        }
    }

    // MARK: - Export

    /// Export error log for support
    func exportLog() -> String {
        return logQueue.sync {
            var export = "=== Claude Usage Error Log ===\n"
            export += "Generated: \(Date().formatted())\n"
            export += "Total Errors: \(errorLog.count)\n\n"

            for (index, logged) in errorLog.enumerated() {
                export += "[\(index + 1)] \(logged.timestamp.formatted())\n"
                export += logged.error.supportReport
                export += "\nSeverity: \(logged.severity.rawValue)\n"
                export += String(repeating: "-", count: 60) + "\n"
            }

            return export
        }
    }

    // MARK: - Statistics

    /// Get error statistics
    func getStatistics() -> ErrorStatistics {
        return logQueue.sync {
            var stats = ErrorStatistics()

            for logged in errorLog {
                stats.totalErrors += 1

                switch logged.severity {
                case .debug:
                    stats.debugCount += 1
                case .info:
                    stats.infoCount += 1
                case .warning:
                    stats.warningCount += 1
                case .error:
                    stats.errorCount += 1
                case .critical:
                    stats.criticalCount += 1
                }

                stats.errorsByCategory[logged.error.code.category, default: 0] += 1
                stats.errorsByCode[logged.error.code, default: 0] += 1
            }

            return stats
        }
    }

    // MARK: - Private Helpers

    private func printError(_ logged: LoggedError) {
        let icon = logged.severity.icon
        let timestamp = logged.timestamp.formatted(date: .omitted, time: .standard)

        print("\(icon) [\(timestamp)] [\(logged.severity.rawValue.uppercased())] \(logged.error.description)")

        if let context = logged.error.context {
            print("   📍 \(context.fileName):\(context.line) in \(context.function)")
        }

        if logged.error.isRecoverable {
            print("   ✅ Recoverable")
        } else {
            print("   ❌ Not Recoverable")
        }

        if let suggestion = logged.error.recoverySuggestion {
            print("   💡 \(suggestion)")
        }
    }
}

// MARK: - Supporting Types

struct LoggedError {
    let error: AppError
    let severity: ErrorSeverity
    let timestamp: Date
}

enum ErrorSeverity: String {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"

    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
}

struct ErrorStatistics {
    var totalErrors: Int = 0
    var debugCount: Int = 0
    var infoCount: Int = 0
    var warningCount: Int = 0
    var errorCount: Int = 0
    var criticalCount: Int = 0
    var errorsByCategory: [ErrorCategory: Int] = [:]
    var errorsByCode: [ErrorCode: Int] = [:]

    var mostCommonCategory: ErrorCategory? {
        return errorsByCategory.max(by: { $0.value < $1.value })?.key
    }

    var mostCommonError: ErrorCode? {
        return errorsByCode.max(by: { $0.value < $1.value })?.key
    }
}
