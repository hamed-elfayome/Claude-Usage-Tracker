//
//  UsageRefreshCoordinator.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-12-20.
//

import Foundation
import Combine

/// Coordinates usage data refresh from API services
@MainActor
final class UsageRefreshCoordinator {
    private var refreshTimer: Timer?
    private var refreshIntervalObserver: NSKeyValueObservation?

    private let apiService: APIServiceProtocol
    private let statusService: ClaudeStatusService
    private let dataStore: StorageProvider
    private let notificationService: NotificationServiceProtocol

    weak var delegate: UsageRefreshCoordinatorDelegate?

    // MARK: - Initialization

    init(
        apiService: APIServiceProtocol? = nil,
        statusService: ClaudeStatusService? = nil,
        dataStore: StorageProvider? = nil,
        notificationService: NotificationServiceProtocol? = nil
    ) {
        self.apiService = apiService ?? ClaudeAPIService()
        self.statusService = statusService ?? ClaudeStatusService()
        self.dataStore = dataStore ?? DataStore.shared
        self.notificationService = notificationService ?? NotificationManager.shared
    }

    // MARK: - Lifecycle

    func start() {
        startAutoRefresh()
        observeRefreshIntervalChanges()
        LoggingService.shared.logInfo("Usage refresh coordinator started")
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshIntervalObserver?.invalidate()
        refreshIntervalObserver = nil
        LoggingService.shared.logInfo("Usage refresh coordinator stopped")
    }

    // MARK: - Refresh Logic

    func refreshUsage() {
        Task {
            // Fetch usage and status in parallel
            async let usageResult = apiService.fetchUsageData()
            async let statusResult = statusService.fetchStatus()

            do {
                let newUsage = try await usageResult

                await MainActor.run {
                    dataStore.saveUsage(newUsage)
                    delegate?.usageRefreshDidComplete(usage: newUsage)
                    notificationService.checkAndNotify(usage: newUsage)
                }
            } catch {
                LoggingService.shared.logAPIError("fetchUsageData", error: error)
            }

            // Fetch status separately (don't fail if usage fetch works)
            do {
                let newStatus = try await statusResult
                await MainActor.run {
                    delegate?.statusRefreshDidComplete(status: newStatus)
                }
            } catch {
                LoggingService.shared.logAPIError("fetchStatus", error: error)
            }

            // Fetch API usage if enabled
            if dataStore.loadAPITrackingEnabled(),
               let apiSessionKey = dataStore.loadAPISessionKey(),
               let orgId = dataStore.loadAPIOrganizationId() {
                do {
                    let newAPIUsage = try await apiService.fetchAPIUsageData(organizationId: orgId, apiSessionKey: apiSessionKey)
                    await MainActor.run {
                        dataStore.saveAPIUsage(newAPIUsage)
                        delegate?.apiUsageRefreshDidComplete(apiUsage: newAPIUsage)
                    }
                } catch {
                    LoggingService.shared.logAPIError("fetchAPIUsageData", error: error)
                }
            }
        }
    }

    // MARK: - Timer Management

    private func startAutoRefresh() {
        let interval = dataStore.loadRefreshInterval()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
        LoggingService.shared.logInfo("Auto-refresh started with interval: \(interval)s")
    }

    private func observeRefreshIntervalChanges() {
        // Observe using DataStore.shared directly for KVO
        refreshIntervalObserver = DataStore.shared.userDefaults.observe(\.refreshIntervalValue, options: [.new]) { [weak self] _, change in
            if let newInterval = change.newValue, newInterval > 0 {
                self?.startAutoRefresh()
                LoggingService.shared.logInfo("Refresh interval changed to: \(newInterval)s")
            }
        }
    }
}

// MARK: - UserDefaults Extension for KVO

private extension UserDefaults {
    @objc var refreshIntervalValue: Double {
        return double(forKey: Constants.UserDefaultsKeys.refreshInterval)
    }
}

// MARK: - Delegate Protocol

protocol UsageRefreshCoordinatorDelegate: AnyObject {
    func usageRefreshDidComplete(usage: ClaudeUsage)
    func statusRefreshDidComplete(status: ClaudeStatus)
    func apiUsageRefreshDidComplete(apiUsage: APIUsage)
}
