//
//  NetworkRequestLog.swift
//  Claude Usage
//
//  Created by Claude on 2026-01-29.
//

import Foundation

struct NetworkRequestLog: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let url: String
    let method: String
    let statusCode: Int?
    let duration: TimeInterval?
    let requestBody: String?
    let responsePreview: String?
    let fullResponseSize: Int?
    let errorMessage: String?

    init(id: UUID = UUID(), timestamp: Date, url: String, method: String,
         statusCode: Int? = nil, duration: TimeInterval? = nil,
         requestBody: String? = nil, responsePreview: String? = nil,
         fullResponseSize: Int? = nil, errorMessage: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.url = url
        self.method = method
        self.statusCode = statusCode
        self.duration = duration
        self.requestBody = requestBody
        self.responsePreview = responsePreview
        self.fullResponseSize = fullResponseSize
        self.errorMessage = errorMessage
    }
}

struct NetworkLoggingSession: Codable {
    var isActive: Bool
    var startTime: Date?
    var endTime: Date?
    var duration: TimeInterval
    var logs: [NetworkRequestLog]

    init(isActive: Bool = false, startTime: Date? = nil,
         endTime: Date? = nil, duration: TimeInterval = 900,
         logs: [NetworkRequestLog] = []) {
        self.isActive = isActive
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.logs = logs
    }
}

enum LoggingDuration: TimeInterval, CaseIterable, Identifiable {
    case fifteenMinutes = 900      // 15 * 60
    case thirtyMinutes = 1800      // 30 * 60
    case oneHour = 3600            // 60 * 60
    case threeHours = 10800        // 3 * 60 * 60
    case twelveHours = 43200       // 12 * 60 * 60

    var id: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .threeHours: return "3 hours"
        case .twelveHours: return "12 hours"
        }
    }
}
