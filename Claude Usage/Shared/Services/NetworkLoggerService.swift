//
//  NetworkLoggerService.swift
//  Claude Usage
//
//  Created by Claude on 2026-01-29.
//

import Foundation
import Combine

final class NetworkLoggerService: ObservableObject {
    static let shared = NetworkLoggerService()

    @Published private(set) var session: NetworkLoggingSession

    private var timer: Timer?
    private let maxLogs = 500
    private let maxFileSizeBytes = 10 * 1024 * 1024  // 10MB
    private let requestBodyMaxLength = 2000
    private let responsePreviewMaxLength = 1000

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDirectory = appSupport.appendingPathComponent("Claude Usage")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true
        )

        return appDirectory.appendingPathComponent("network_logs.json")
    }

    private init() {
        self.session = Self.loadSession() ?? NetworkLoggingSession()

        // Resume timer if session was active
        if session.isActive, let endTime = session.endTime, endTime > Date() {
            scheduleAutoStop(until: endTime)
        } else if session.isActive {
            // Session expired while app was closed
            stopLogging()
        }
    }

    // MARK: - Public API

    func startLogging(duration: TimeInterval) {
        let now = Date()
        session.isActive = true
        session.startTime = now
        session.endTime = now.addingTimeInterval(duration)
        session.duration = duration

        scheduleAutoStop(until: session.endTime!)
        saveSession()

        LoggingService.shared.logDebug("Network logging started for \(duration)s")
    }

    func stopLogging() {
        session.isActive = false
        timer?.invalidate()
        timer = nil
        saveSession()

        LoggingService.shared.logDebug("Network logging stopped")
    }

    func clearLogs() {
        session.logs.removeAll()
        saveSession()

        LoggingService.shared.logDebug("Network logs cleared")
    }

    func logRequest(url: String, method: String, requestBody: Data?,
                    responseData: Data?, statusCode: Int?,
                    duration: TimeInterval?, error: Error?) {
        guard session.isActive else { return }

        // Check if session has expired
        if let endTime = session.endTime, Date() > endTime {
            stopLogging()
            return
        }

        let requestBodyString = requestBody.flatMap { data in
            String(data: data, encoding: .utf8)?
                .prefix(requestBodyMaxLength)
                .description
        }

        let responsePreview = responseData.flatMap { data in
            String(data: data, encoding: .utf8)?
                .prefix(responsePreviewMaxLength)
                .description
        }

        let log = NetworkRequestLog(
            timestamp: Date(),
            url: url,
            method: method,
            statusCode: statusCode,
            duration: duration,
            requestBody: requestBodyString,
            responsePreview: responsePreview,
            fullResponseSize: responseData?.count,
            errorMessage: error?.localizedDescription
        )

        session.logs.append(log)

        // Enforce max logs limit (FIFO)
        if session.logs.count > maxLogs {
            session.logs.removeFirst(session.logs.count - maxLogs)
        }

        saveSession()
    }

    var remainingTime: TimeInterval? {
        guard session.isActive, let endTime = session.endTime else { return nil }
        let remaining = endTime.timeIntervalSinceNow
        return remaining > 0 ? remaining : 0
    }

    // MARK: - Private Helpers

    private func scheduleAutoStop(until endTime: Date) {
        timer?.invalidate()
        timer = Timer(fire: endTime, interval: 0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopLogging()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func saveSession() {
        do {
            let data = try JSONEncoder().encode(session)

            // Check file size limit
            if data.count > maxFileSizeBytes {
                LoggingService.shared.logWarning("Network logs exceed max size, truncating...")
                // Remove oldest logs until under limit
                while session.logs.count > 0 {
                    session.logs.removeFirst()
                    let newData = try JSONEncoder().encode(session)
                    if newData.count <= maxFileSizeBytes {
                        try newData.write(to: storageURL)
                        return
                    }
                }
            } else {
                try data.write(to: storageURL)
            }
        } catch {
            LoggingService.shared.logStorageError("saveNetworkLogs", error: error)
        }
    }

    private static func loadSession() -> NetworkLoggingSession? {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDirectory = appSupport.appendingPathComponent("Claude Usage")
        let url = appDirectory.appendingPathComponent("network_logs.json")

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(NetworkLoggingSession.self, from: data) else {
            return nil
        }
        return session
    }
}
