//
//  NetworkMonitor.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-27.
//

import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor
/// Provides notifications when network becomes available or unavailable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.claudeusage.networkmonitor")

    /// Current network path status
    private(set) var isConnected: Bool = false

    /// Callback triggered when network becomes available
    var onNetworkAvailable: (() -> Void)?

    /// Callback triggered when network becomes unavailable
    var onNetworkUnavailable: (() -> Void)?

    private init() {
        monitor = NWPathMonitor()
    }

    // MARK: - Public API

    /// Starts monitoring network connectivity
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let wasConnected = self.isConnected
            let nowConnected = path.status == .satisfied

            self.isConnected = nowConnected

            DispatchQueue.main.async {
                if nowConnected && !wasConnected {
                    // Network just became available
                    LoggingService.shared.logInfo("Network became available")
                    self.onNetworkAvailable?()
                } else if !nowConnected && wasConnected {
                    // Network just became unavailable
                    LoggingService.shared.logInfo("Network became unavailable")
                    self.onNetworkUnavailable?()
                }
            }
        }

        monitor.start(queue: queue)
        LoggingService.shared.logInfo("Network monitoring started")
    }

    /// Stops monitoring network connectivity
    func stopMonitoring() {
        monitor.cancel()
        LoggingService.shared.logInfo("Network monitoring stopped")
    }

    /// Waits for network to become available, then executes the callback
    /// If already connected, executes immediately
    /// - Parameter timeout: Maximum time to wait (default: 60 seconds)
    /// - Parameter callback: Called when network is available or timeout occurs
    func waitForConnection(timeout: TimeInterval = 60, callback: @escaping (Bool) -> Void) {
        if isConnected {
            callback(true)
            return
        }

        var timeoutWorkItem: DispatchWorkItem?
        var hasCompleted = false

        // Set up timeout
        timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard !hasCompleted else { return }
            hasCompleted = true
            self?.onNetworkAvailable = nil
            LoggingService.shared.logWarning("Network wait timed out after \(timeout)s")
            callback(false)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem!)

        // Set up success handler
        let previousHandler = onNetworkAvailable
        onNetworkAvailable = { [weak self] in
            guard !hasCompleted else { return }
            hasCompleted = true
            timeoutWorkItem?.cancel()
            self?.onNetworkAvailable = previousHandler
            previousHandler?()
            callback(true)
        }
    }
}
