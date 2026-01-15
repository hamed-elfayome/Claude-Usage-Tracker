//
//  AutoStartSessionService.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-01-11.
//

import Foundation
import Cocoa

/// Background service that monitors all profiles and auto-starts sessions when they reset
@MainActor
final class AutoStartSessionService {
    static let shared = AutoStartSessionService()

    // Timer for 5-minute check cycle
    private var checkTimer: Timer?

    // Track last check time to prevent duplicate checks on wake
    private var lastCheckTime: Date = .distantPast

    // Observers for sleep/wake notifications
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    private let apiService: ClaudeAPIService
    private let profileManager: ProfileManager
    private let notificationManager: NotificationManager

    private init() {
        self.apiService = ClaudeAPIService()
        self.profileManager = ProfileManager.shared
        self.notificationManager = NotificationManager.shared
    }

    // MARK: - Lifecycle

    func start() {
        // Start 5-minute check timer with tolerance for energy efficiency
        let timer = Timer.scheduledTimer(
            withTimeInterval: 300, // 5 minutes
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.performCheckIfNeeded(source: "timer")
            }
        }
        timer.tolerance = 30 // Allow up to 30 seconds of drift for energy efficiency
        checkTimer = timer

        // Register for wake/sleep notifications
        let workspace = NSWorkspace.shared

        wakeObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                LoggingService.shared.logInfo("Mac woke from sleep - checking for session resets")
                await self.performCheckIfNeeded(source: "wake")
            }
        }

        sleepObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            LoggingService.shared.logDebug("Mac going to sleep")
        }

        LoggingService.shared.logInfo("AutoStartSessionService started (5-minute cycle + wake detection)")

        // Perform immediate initial check to populate state
        Task { @MainActor in
            await self.performCheckIfNeeded(source: "startup")
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil

        // Remove observers
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let sleepObserver = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }

        LoggingService.shared.logInfo("AutoStartSessionService stopped")
    }

    // MARK: - Profile Checking

    /// Performs check with debouncing to prevent duplicate checks
    private func performCheckIfNeeded(source: String) async {
        // Debounce: Don't check if we checked less than 10 seconds ago
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckTime)
        if timeSinceLastCheck < 10 {
            LoggingService.shared.logDebug("Skipping check from \(source) - checked \(Int(timeSinceLastCheck))s ago")
            return
        }

        lastCheckTime = Date()
        await checkAllProfiles(source: source)
    }

    private func checkAllProfiles(source: String) async {
        LoggingService.shared.logDebug("AutoStartSessionService: Checking all profiles for auto-start (source: \(source))")

        // Get all profiles with auto-start enabled
        let profilesWithAutoStart = profileManager.profiles.filter { $0.autoStartSessionEnabled }

        guard !profilesWithAutoStart.isEmpty else {
            LoggingService.shared.logDebug("No profiles with auto-start enabled")
            return
        }

        LoggingService.shared.logInfo("Checking \(profilesWithAutoStart.count) profile(s) with auto-start enabled")

        // Check each profile
        for profile in profilesWithAutoStart {
            await checkProfile(profile)
        }
    }

    private func checkProfile(_ profile: Profile) async {
        // Skip if profile doesn't have Claude.ai credentials
        guard profile.hasClaudeAI else {
            LoggingService.shared.logDebug("Skipping profile '\(profile.name)' - no Claude.ai credentials")
            return
        }

        do {
            // Fetch current usage for this profile
            let usage = try await fetchUsageForProfile(profile)

            let currentPercentage = usage.sessionPercentage

            // Simple logic (like v1.1.0): If session is at 0%, start it
            // The initialization message will bring usage above 0%, preventing repeated starts
            if currentPercentage == 0.0 {
                LoggingService.shared.logInfo("Session at 0% for profile '\(profile.name)' - triggering auto-start")

                // Auto-start the session
                await autoStartSession(for: profile)
            } else {
                LoggingService.shared.logDebug("Profile '\(profile.name)': session at \(currentPercentage)% (active)")
            }

        } catch {
            LoggingService.shared.logError("Failed to check profile '\(profile.name)': \(error.localizedDescription)")
        }
    }

    private func fetchUsageForProfile(_ profile: Profile) async throws -> ClaudeUsage {
        // Use ClaudeAPIService which now supports OAuth fallback
        let apiService = ClaudeAPIService()

        // Fetch usage - will automatically use fallback if needed
        let usage = try await apiService.fetchUsageData()

        // Save usage to profile
        await MainActor.run {
            profileManager.saveClaudeUsage(usage, for: profile.id)
        }

        return usage
    }

    private func fetchUsageData(sessionKey: String, orgId: String) async throws -> ClaudeUsage {
        // Build URL
        let url = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPath("/organizations/\(orgId)/usage")
            .build()

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError(code: .apiInvalidResponse, message: "Invalid response", isRecoverable: true)
        }

        guard httpResponse.statusCode == 200 else {
            throw AppError(
                code: .apiGenericError,
                message: "API returned status \(httpResponse.statusCode)",
                isRecoverable: true
            )
        }

        // Parse usage response (simplified version of ClaudeAPIService parsing)
        return try parseUsageResponse(data)
    }

    private func parseUsageResponse(_ data: Data) throws -> ClaudeUsage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError(code: .apiParsingFailed, message: "Failed to parse usage data", isRecoverable: false)
        }

        // Extract session usage (five_hour)
        var sessionPercentage = 0.0
        var sessionResetTime = Date().addingTimeInterval(5 * 3600)

        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let utilization = fiveHour["utilization"] {
                sessionPercentage = parseUtilization(utilization)
            }
            if let resetsAt = fiveHour["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                sessionResetTime = formatter.date(from: resetsAt) ?? sessionResetTime
            }
        }

        // Extract weekly usage (seven_day)
        var weeklyPercentage = 0.0
        var weeklyResetTime = Date().nextMonday1259pm()

        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let utilization = sevenDay["utilization"] {
                weeklyPercentage = parseUtilization(utilization)
            }
            if let resetsAt = sevenDay["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                weeklyResetTime = formatter.date(from: resetsAt) ?? weeklyResetTime
            }
        }

        // Extract Opus weekly usage (seven_day_opus)
        var opusPercentage = 0.0
        if let sevenDayOpus = json["seven_day_opus"] as? [String: Any] {
            if let utilization = sevenDayOpus["utilization"] {
                opusPercentage = parseUtilization(utilization)
            }
        }

        // Extract Sonnet weekly usage (seven_day_sonnet)
        var sonnetPercentage = 0.0
        var sonnetResetTime: Date? = nil
        if let sevenDaySonnet = json["seven_day_sonnet"] as? [String: Any] {
            if let utilization = sevenDaySonnet["utilization"] {
                sonnetPercentage = parseUtilization(utilization)
            }
            if let resetsAt = sevenDaySonnet["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                sonnetResetTime = formatter.date(from: resetsAt)
            }
        }

        let weeklyLimit = Constants.weeklyLimit
        let weeklyTokens = Int(Double(weeklyLimit) * (weeklyPercentage / 100.0))
        let opusTokens = Int(Double(weeklyLimit) * (opusPercentage / 100.0))
        let sonnetTokens = Int(Double(weeklyLimit) * (sonnetPercentage / 100.0))

        return ClaudeUsage(
            sessionTokensUsed: 0,
            sessionLimit: 0,
            sessionPercentage: sessionPercentage,
            sessionResetTime: sessionResetTime,
            weeklyTokensUsed: weeklyTokens,
            weeklyLimit: weeklyLimit,
            weeklyPercentage: weeklyPercentage,
            weeklyResetTime: weeklyResetTime,
            opusWeeklyTokensUsed: opusTokens,
            opusWeeklyPercentage: opusPercentage,
            sonnetWeeklyTokensUsed: sonnetTokens,
            sonnetWeeklyPercentage: sonnetPercentage,
            sonnetWeeklyResetTime: sonnetResetTime,
            costUsed: nil,
            costLimit: nil,
            costCurrency: nil,
            lastUpdated: Date(),
            userTimezone: .current
        )
    }

    private func parseUtilization(_ value: Any) -> Double {
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let stringValue = value as? String {
            let cleaned = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            if let parsed = Double(cleaned) {
                return parsed
            }
        }
        return 0.0
    }

    // MARK: - Auto-Start Session

    private func autoStartSession(for profile: Profile) async {
        do {
            // Call the initialization API for this profile
            try await sendInitializationMessage(for: profile)

            LoggingService.shared.logInfo("Successfully auto-started session for profile '\(profile.name)'")

            // Send success notification
            await MainActor.run {
                notificationManager.sendAutoStartNotification(
                    profileName: profile.name,
                    success: true,
                    error: nil
                )
            }

        } catch {
            LoggingService.shared.logError("Failed to auto-start session for profile '\(profile.name)': \(error.localizedDescription)")

            // Send failure notification
            await MainActor.run {
                notificationManager.sendAutoStartNotification(
                    profileName: profile.name,
                    success: false,
                    error: error.localizedDescription
                )
            }
        }
    }

    private func sendInitializationMessage(for profile: Profile) async throws {
        guard let sessionKey = profile.claudeSessionKey,
              let orgId = profile.organizationId else {
            throw AppError(
                code: .sessionKeyNotFound,
                message: "Missing credentials",
                isRecoverable: false
            )
        }

        // Create a new conversation
        let conversationURL = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations"])
            .build()

        var conversationRequest = URLRequest(url: conversationURL)
        conversationRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        conversationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        conversationRequest.httpMethod = "POST"

        let conversationBody: [String: Any] = [
            "uuid": UUID().uuidString.lowercased(),
            "name": ""
        ]
        conversationRequest.httpBody = try JSONSerialization.data(withJSONObject: conversationBody)

        let (conversationData, conversationResponse) = try await URLSession.shared.data(for: conversationRequest)

        guard let httpResponse = conversationResponse as? HTTPURLResponse,
              (httpResponse.statusCode == 200 || httpResponse.statusCode == 201) else {
            throw AppError(code: .apiGenericError, message: "Failed to create conversation", isRecoverable: true)
        }

        // Parse conversation UUID
        guard let json = try? JSONSerialization.jsonObject(with: conversationData) as? [String: Any],
              let conversationUUID = json["uuid"] as? String else {
            throw AppError(code: .apiParsingFailed, message: "Failed to parse conversation", isRecoverable: false)
        }

        // Send a minimal "Hi" message to initialize the session
        let messageURL = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations", conversationUUID, "/completion"])
            .build()

        var messageRequest = URLRequest(url: messageURL)
        messageRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        messageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        messageRequest.httpMethod = "POST"

        let messageBody: [String: Any] = [
            "prompt": "Hi",
            "model": "claude-3-5-haiku-20241022",  // Cheapest model
            "timezone": "UTC"
        ]
        messageRequest.httpBody = try JSONSerialization.data(withJSONObject: messageBody)

        let (_, messageResponse) = try await URLSession.shared.data(for: messageRequest)

        guard let messageHTTPResponse = messageResponse as? HTTPURLResponse,
              messageHTTPResponse.statusCode == 200 else {
            throw AppError(code: .apiGenericError, message: "Failed to send initialization message", isRecoverable: true)
        }

        // Delete the conversation to keep it out of chat history (incognito mode)
        let deleteURL = try URLBuilder(baseURL: Constants.APIEndpoints.claudeBase)
            .appendingPathComponents(["/organizations", orgId, "/chat_conversations", conversationUUID])
            .build()

        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        deleteRequest.httpMethod = "DELETE"

        // Attempt to delete, but don't fail if deletion fails
        do {
            _ = try await URLSession.shared.data(for: deleteRequest)
        } catch {
            // Silently ignore deletion errors - session is already initialized
        }
    }
}
