//
//  UsageHistoryService.swift
//  Claude Usage
//
//  Created by Claude Code on 2025-01-26.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

/// Service for managing usage history data
@MainActor
class UsageHistoryService {
    static let shared = UsageHistoryService()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Key prefix for profile-specific history storage
    private let historyKeyPrefix = "usageHistory_"

    /// Maximum snapshots to keep per type (to prevent excessive data)
    private let maxSessionSnapshots = 1000   // ~7 days at 10-min intervals
    private let maxWeeklySnapshots = 500     // ~6 weeks at 2-hour intervals

    /// Recording intervals for periodic snapshots
    private let sessionRecordingInterval: TimeInterval = 10 * 60  // 10 minutes
    private let weeklyRecordingInterval: TimeInterval = 2 * 60 * 60  // 2 hours

    /// Track last recording time per profile
    private var lastSessionRecordTime: [UUID: Date] = [:]
    private var lastWeeklyRecordTime: [UUID: Date] = [:]

    private init() {
        self.defaults = UserDefaults.standard
    }

    // MARK: - Storage Key

    /// Generates the storage key for a specific profile's history
    private func storageKey(for profileId: UUID) -> String {
        return "\(historyKeyPrefix)\(profileId.uuidString)"
    }

    // MARK: - Save/Load History

    /// Saves usage history for a profile
    func saveHistory(_ history: UsageHistoryData, for profileId: UUID) {
        do {
            let data = try encoder.encode(history)
            defaults.set(data, forKey: storageKey(for: profileId))
            LoggingService.shared.logStorageSave("usageHistory for profile \(profileId.uuidString.prefix(8))")
        } catch {
            LoggingService.shared.logStorageError("saveHistory", error: error)
        }
    }

    /// Loads usage history for a profile
    func loadHistory(for profileId: UUID) -> UsageHistoryData {
        guard let data = defaults.data(forKey: storageKey(for: profileId)) else {
            return UsageHistoryData()
        }

        do {
            let history = try decoder.decode(UsageHistoryData.self, from: data)
            return history
        } catch {
            LoggingService.shared.logStorageError("loadHistory", error: error)
            return UsageHistoryData()
        }
    }

    // MARK: - Record Resets

    /// Records a session reset snapshot
    func recordSessionReset(for profileId: UUID, previousUsage: ClaudeUsage?, resetTime: Date) {
        guard let usage = previousUsage else {
            LoggingService.shared.logInfo("recordSessionReset: No previous usage data to record")
            return
        }

        // Only record if there was actual usage
        guard usage.sessionTokensUsed > 0 || usage.sessionPercentage > 0 else {
            LoggingService.shared.logInfo("recordSessionReset: Skipping snapshot - no usage to record")
            return
        }

        let snapshot = UsageSnapshot.fromSessionReset(usage, resetTime: resetTime)

        var history = loadHistory(for: profileId)
        history.addSnapshot(snapshot)

        // Prune old session snapshots if exceeding limit
        let sessionCount = history.sessionSnapshots.count
        if sessionCount > maxSessionSnapshots {
            let toRemove = sessionCount - maxSessionSnapshots
            let oldestSessions = history.sessionSnapshots.suffix(toRemove)
            let idsToRemove = Set(oldestSessions.map { $0.id })
            history.snapshots.removeAll { idsToRemove.contains($0.id) }
        }

        saveHistory(history, for: profileId)
        LoggingService.shared.logInfo("Recorded session reset snapshot for profile \(profileId.uuidString.prefix(8)): \(usage.sessionPercentage)% usage")
    }

    /// Records a weekly reset snapshot
    func recordWeeklyReset(for profileId: UUID, previousUsage: ClaudeUsage?, resetTime: Date) {
        guard let usage = previousUsage else {
            LoggingService.shared.logInfo("recordWeeklyReset: No previous usage data to record")
            return
        }

        // Only record if there was actual usage
        guard usage.weeklyTokensUsed > 0 || usage.weeklyPercentage > 0 else {
            LoggingService.shared.logInfo("recordWeeklyReset: Skipping snapshot - no usage to record")
            return
        }

        let snapshot = UsageSnapshot.fromWeeklyReset(usage, resetTime: resetTime)

        var history = loadHistory(for: profileId)
        history.addSnapshot(snapshot)
        saveHistory(history, for: profileId)

        LoggingService.shared.logInfo("Recorded weekly reset snapshot for profile \(profileId.uuidString.prefix(8)): \(usage.weeklyPercentage)% usage")
    }

    /// Records a billing cycle reset snapshot
    func recordBillingCycleReset(for profileId: UUID, previousUsage: APIUsage?, resetTime: Date) {
        guard let usage = previousUsage else {
            LoggingService.shared.logInfo("recordBillingCycleReset: No previous usage data to record")
            return
        }

        // Only record if there was actual spend
        guard usage.currentSpendCents > 0 else {
            LoggingService.shared.logInfo("recordBillingCycleReset: Skipping snapshot - no spend to record")
            return
        }

        let snapshot = UsageSnapshot.fromBillingCycleReset(usage, resetTime: resetTime)

        var history = loadHistory(for: profileId)
        history.addSnapshot(snapshot)
        saveHistory(history, for: profileId)

        LoggingService.shared.logInfo("Recorded billing cycle snapshot for profile \(profileId.uuidString.prefix(8)): \(usage.formattedUsed) spent")
    }

    // MARK: - Periodic Recording

    /// Records session usage periodically (every 10 minutes)
    func recordSessionPeriodic(for profileId: UUID, usage: ClaudeUsage) {
        let now = Date()

        // Check if enough time has passed since last recording
        if let lastRecord = lastSessionRecordTime[profileId] {
            let elapsed = now.timeIntervalSince(lastRecord)
            if elapsed < sessionRecordingInterval {
                return  // Not enough time passed
            }
        }

        // Create periodic snapshot
        let snapshot = UsageSnapshot(
            resetType: .sessionReset,
            sessionTokensUsed: usage.sessionTokensUsed,
            sessionPercentage: usage.sessionPercentage,
            triggeringResetTime: now
        )

        var history = loadHistory(for: profileId)
        history.addSnapshot(snapshot)

        // Prune old session snapshots if exceeding limit
        let sessionCount = history.sessionSnapshots.count
        if sessionCount > maxSessionSnapshots {
            let toRemove = sessionCount - maxSessionSnapshots
            let oldestSessions = history.sessionSnapshots.suffix(toRemove)
            let idsToRemove = Set(oldestSessions.map { $0.id })
            history.snapshots.removeAll { idsToRemove.contains($0.id) }
        }

        saveHistory(history, for: profileId)
        lastSessionRecordTime[profileId] = now
        LoggingService.shared.logInfo("Recorded periodic session snapshot: \(usage.sessionPercentage)%")
    }

    /// Records weekly usage periodically (every 2 hours)
    func recordWeeklyPeriodic(for profileId: UUID, usage: ClaudeUsage) {
        let now = Date()

        // Check if enough time has passed since last recording
        if let lastRecord = lastWeeklyRecordTime[profileId] {
            let elapsed = now.timeIntervalSince(lastRecord)
            if elapsed < weeklyRecordingInterval {
                return  // Not enough time passed
            }
        }

        // Create periodic snapshot
        let snapshot = UsageSnapshot(
            resetType: .weeklyReset,
            weeklyTokensUsed: usage.weeklyTokensUsed,
            weeklyPercentage: usage.weeklyPercentage,
            opusWeeklyTokensUsed: usage.opusWeeklyTokensUsed,
            opusWeeklyPercentage: usage.opusWeeklyPercentage,
            sonnetWeeklyTokensUsed: usage.sonnetWeeklyTokensUsed,
            sonnetWeeklyPercentage: usage.sonnetWeeklyPercentage,
            triggeringResetTime: now
        )

        var history = loadHistory(for: profileId)
        history.addSnapshot(snapshot)

        // Prune old weekly snapshots if exceeding limit
        let weeklyCount = history.weeklySnapshots.count
        if weeklyCount > maxWeeklySnapshots {
            let toRemove = weeklyCount - maxWeeklySnapshots
            let oldestWeekly = history.weeklySnapshots.suffix(toRemove)
            let idsToRemove = Set(oldestWeekly.map { $0.id })
            history.snapshots.removeAll { idsToRemove.contains($0.id) }
        }

        saveHistory(history, for: profileId)
        lastWeeklyRecordTime[profileId] = now
        LoggingService.shared.logInfo("Recorded periodic weekly snapshot: \(usage.weeklyPercentage)%")
    }

    // MARK: - Query Methods

    /// Gets session snapshots for a profile (sorted newest first)
    func getSessionSnapshots(for profileId: UUID) -> [UsageSnapshot] {
        return loadHistory(for: profileId).sessionSnapshots
    }

    /// Gets weekly snapshots for a profile (sorted newest first)
    func getWeeklySnapshots(for profileId: UUID) -> [UsageSnapshot] {
        return loadHistory(for: profileId).weeklySnapshots
    }

    /// Gets billing cycle snapshots for a profile (sorted newest first)
    func getBillingCycleSnapshots(for profileId: UUID) -> [UsageSnapshot] {
        return loadHistory(for: profileId).billingCycleSnapshots
    }

    /// Gets all snapshots for a profile (sorted newest first)
    func getAllSnapshots(for profileId: UUID) -> [UsageSnapshot] {
        return loadHistory(for: profileId).snapshots.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Export

    /// Exports history to JSON and saves to file
    func exportToFile(for profileId: UUID, resetType: ResetType? = nil) {
        let history = loadHistory(for: profileId)
        let jsonString: String?

        if let type = resetType {
            jsonString = history.exportToJSON(for: type)
        } else {
            jsonString = history.exportToJSON()
        }

        guard let json = jsonString else {
            LoggingService.shared.logError("Failed to export history to JSON")
            return
        }

        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        let typeSuffix = resetType?.rawValue ?? "all"
        savePanel.nameFieldStringValue = "claude-usage-history-\(typeSuffix)-\(dateStr).json"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try json.write(to: url, atomically: true, encoding: .utf8)
                    LoggingService.shared.logInfo("Exported history to \(url.path)")
                } catch {
                    LoggingService.shared.logError("Failed to save export file: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Deletes all history for a profile
    func deleteHistory(for profileId: UUID) {
        defaults.removeObject(forKey: storageKey(for: profileId))
        LoggingService.shared.logInfo("Deleted usage history for profile \(profileId.uuidString.prefix(8))")
    }

    /// Clears all snapshots for a profile but keeps the history structure
    func clearHistory(for profileId: UUID) {
        saveHistory(UsageHistoryData(), for: profileId)
        LoggingService.shared.logInfo("Cleared usage history for profile \(profileId.uuidString.prefix(8))")
    }

    /// Clears snapshots of a specific type for a profile
    func clearHistory(for profileId: UUID, resetType: ResetType) {
        var history = loadHistory(for: profileId)
        history.snapshots.removeAll { $0.resetType == resetType }
        saveHistory(history, for: profileId)
        LoggingService.shared.logInfo("Cleared \(resetType.rawValue) history for profile \(profileId.uuidString.prefix(8))")
    }
}
