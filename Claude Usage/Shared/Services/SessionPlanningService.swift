import Foundation
import Combine

@MainActor
final class SessionPlanningService: ObservableObject {
    static let shared = SessionPlanningService()

    private var checkTimer: Timer?
    private var lastPingTime: [UUID: Date] = [:]
    private var lastReminderTime: [UUID: Date] = [:]
    private var observationStore: SessionObservationStore
    private let profileManager = ProfileManager.shared
    private let notificationManager = NotificationManager.shared

    @Published var currentRecommendations: [SessionPlanRecommendation] = []

    private init() {
        self.observationStore = SessionObservationStore()
    }

    func start() {
        let timer = Timer.scheduledTimer(
            withTimeInterval: Constants.SessionPlanning.pingCheckIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.performChecks()
            }
        }
        timer.tolerance = 10
        checkTimer = timer
        LoggingService.shared.logInfo("SessionPlanningService started")
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        LoggingService.shared.logInfo("SessionPlanningService stopped")
    }

    func recordUsage(profile: Profile, usage: ClaudeUsage) {
        guard let settings = profile.sessionPlanningSettings,
              settings.isEnabled,
              settings.useAutoEstimate else { return }

        let threshold = Constants.SessionPlanning.observationThreshold
        guard usage.effectiveSessionPercentage >= threshold else { return }

        let key = profile.id.uuidString + usage.sessionResetTime.timeIntervalSince1970.description
        guard !observationStore.hasRecorded(forKey: key) else { return }

        let isPeak = PeakHoursService.shared.isPeakHours
        let observation = SessionLimitObservation(
            profileId: profile.id,
            sessionResetTime: usage.sessionResetTime,
            sessionPercentageAtObservation: usage.effectiveSessionPercentage,
            typicalTimeToLimitMinutes: estimateTypicalTimeToLimit(for: profile),
            peakHoursActive: isPeak
        )

        observationStore.add(observation, key: key)
        LoggingService.shared.logInfo("Recorded session limit observation for '\(profile.name)': \(Int(usage.effectiveSessionPercentage))%")
    }

    func estimateTypicalTimeToLimit(for profile: Profile) -> Int {
        let observations = observationStore.observations(for: profile.id)
        guard observations.count >= 3 else {
            return profile.sessionPlanningSettings?.manualTypicalTimeToLimitMinutes
                ?? Constants.SessionPlanning.defaultManualTimeToLimitMinutes
        }

        let sorted = observations.map(\.typicalTimeToLimitMinutes).sorted()
        let median = sorted[sorted.count / 2]
        return median
    }

    func calculateRecommendedPingTime(for profile: Profile) -> Date? {
        guard let settings = profile.sessionPlanningSettings,
              settings.isEnabled,
              let plannedWorkStart = settings.plannedWorkStart else { return nil }

        let typicalTTL = TimeInterval(estimateTypicalTimeToLimit(for: profile) * 60)
        let leadTime = max(0, Constants.sessionWindow - typicalTTL)
        let pingTime = plannedWorkStart.addingTimeInterval(-leadTime)
        return pingTime
    }

    func calculateSecondSessionAvailableTime(for profile: Profile) -> Date? {
        guard let pingTime = calculateRecommendedPingTime(for: profile) else { return nil }
        return pingTime.addingTimeInterval(Constants.sessionWindow)
    }

    func isSessionActive(for profile: Profile) -> Bool {
        guard let usage = profile.claudeUsage else { return false }
        return usage.effectiveSessionPercentage > 0
    }

    private func performChecks() async {
        let now = Date()

        for profile in profileManager.profiles {
            guard let settings = profile.sessionPlanningSettings,
                  settings.isEnabled else { continue }

            guard let plannedWorkStart = settings.plannedWorkStart else { continue }

            guard !isSessionActive(for: profile) else {
                LoggingService.shared.logDebug("SessionPlanningService: skipping '\(profile.name)' - session already active")
                continue
            }

            guard let pingTime = calculateRecommendedPingTime(for: profile) else { continue }

            // Pre-ping warning
            if settings.remindersEnabled,
               let lastReminder = lastReminderTime[profile.id],
               now.timeIntervalSince(lastReminder) > 3600,
               now >= pingTime.addingTimeInterval(-Double(Constants.SessionPlanning.prePingWarningMinutes * 60)),
               now < pingTime {
                notificationManager.sendSessionOverlapReminder(
                    profileName: profile.name,
                    pingTime: pingTime,
                    plannedWorkStart: plannedWorkStart
                )
                lastReminderTime[profile.id] = now
                continue
            }

            // Ping time
            if now >= pingTime,
               now < pingTime.addingTimeInterval(120),
               lastPingTime[profile.id] == nil || now.timeIntervalSince(lastPingTime[profile.id]!) > 300 {

                if settings.autoPingEnabled, profile.hasClaudeAI {
                    await AutoStartSessionService.shared.startSession(for: profile, source: .plannedOverlap)
                    notificationManager.sendPlannedPingSuccess(profileName: profile.name)
                } else if settings.remindersEnabled {
                    notificationManager.sendSessionOverlapReminder(
                        profileName: profile.name,
                        pingTime: pingTime,
                        plannedWorkStart: plannedWorkStart
                    )
                }

                lastPingTime[profile.id] = now

                // Clear one-off plans
                if settings.repeatBehavior == .none {
                    clearPlannedWorkStart(for: profile)
                }
            }
        }
    }

    private func clearPlannedWorkStart(for profile: Profile) {
        var updated = profile
        updated.sessionPlanningSettings?.plannedWorkStart = nil
        profileManager.updateProfile(updated)
        LoggingService.shared.logInfo("Cleared one-off planned work start for '\(profile.name)'")
    }
}

struct SessionPlanRecommendation: Identifiable {
    let id = UUID()
    let profileId: UUID
    let message: String
    let type: RecommendationType

    enum RecommendationType {
        case pingTime
        case wasteWarning
        case planMode
        case offPeak
    }
}

@MainActor
private final class SessionObservationStore {
    private var observations: [SessionLimitObservation] = []
    private var recordedKeys: Set<String> = []
    private var loaded = false

    func add(_ observation: SessionLimitObservation, key: String) {
        ensureLoaded()
        observations.append(observation)
        recordedKeys.insert(key)

        // Keep only recent observations (last 30)
        if observations.count > 30 {
            observations.removeFirst(observations.count - 30)
        }

        save()
    }

    func hasRecorded(forKey key: String) -> Bool {
        ensureLoaded()
        return recordedKeys.contains(key)
    }

    func observations(for profileId: UUID) -> [SessionLimitObservation] {
        ensureLoaded()
        return observations.filter { $0.profileId == profileId }
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        guard let data = UserDefaults.standard.data(forKey: "sessionLimitObservations"),
              let decoded = try? JSONDecoder().decode([SessionLimitObservation].self, from: data) else {
            return
        }
        observations = decoded
        recordedKeys = Set(observations.map { $0.profileId.uuidString + $0.sessionResetTime.timeIntervalSince1970.description })
    }

    private func save() {
        if let data = try? JSONEncoder().encode(observations) {
            UserDefaults.standard.set(data, forKey: "sessionLimitObservations")
        }
    }
}