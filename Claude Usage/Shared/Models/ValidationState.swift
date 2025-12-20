//
//  ValidationState.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation

/// Shared validation state used across multiple views
/// Represents the state of asynchronous validation operations
enum ValidationState: Equatable {
    case idle
    case validating
    case success(String)
    case error(String)

    var isValidating: Bool {
        if case .validating = self {
            return true
        }
        return false
    }

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case .success(let msg), .error(let msg):
            return msg
        default:
            return nil
        }
    }
}
