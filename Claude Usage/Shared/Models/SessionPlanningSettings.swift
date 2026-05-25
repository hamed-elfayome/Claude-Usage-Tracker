import Foundation

struct SessionPlanningSettings: Codable, Equatable {
    var isEnabled: Bool
    var plannedWorkStart: Date?
    var repeatBehavior: RepeatBehavior
    var useAutoEstimate: Bool
    var manualTypicalTimeToLimitMinutes: Int
    var remindersEnabled: Bool
    var autoPingEnabled: Bool
    var wasteWarningEnabled: Bool
    var planModeTipsEnabled: Bool

    var tipPreferences: TipPreferences

    enum RepeatBehavior: String, Codable, CaseIterable {
        case none
        case daily
        case weekdays
        case weekly
    }

    struct TipPreferences: Codable, Equatable {
        var showClaudeAITips: Bool
        var showClaudeCodeTips: Bool
        var showCoworkTips: Bool
        var peakHoursReminders: Bool

        init(
            showClaudeAITips: Bool = true,
            showClaudeCodeTips: Bool = true,
            showCoworkTips: Bool = true,
            peakHoursReminders: Bool = true
        ) {
            self.showClaudeAITips = showClaudeAITips
            self.showClaudeCodeTips = showClaudeCodeTips
            self.showCoworkTips = showCoworkTips
            self.peakHoursReminders = peakHoursReminders
        }
    }

    static var `default`: SessionPlanningSettings {
        SessionPlanningSettings(
            isEnabled: false,
            plannedWorkStart: nil,
            repeatBehavior: .weekdays,
            useAutoEstimate: true,
            manualTypicalTimeToLimitMinutes: Constants.SessionPlanning.defaultManualTimeToLimitMinutes,
            remindersEnabled: true,
            autoPingEnabled: false,
            wasteWarningEnabled: true,
            planModeTipsEnabled: true,
            tipPreferences: TipPreferences(
                showClaudeAITips: true,
                showClaudeCodeTips: true,
                showCoworkTips: true,
                peakHoursReminders: true
            )
        )
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case plannedWorkStart
        case repeatBehavior
        case useAutoEstimate
        case manualTypicalTimeToLimitMinutes
        case remindersEnabled
        case autoPingEnabled
        case wasteWarningEnabled
        case planModeTipsEnabled
        case tipPreferences
    }

    init(
        isEnabled: Bool = false,
        plannedWorkStart: Date? = nil,
        repeatBehavior: RepeatBehavior = .weekdays,
        useAutoEstimate: Bool = true,
        manualTypicalTimeToLimitMinutes: Int = Constants.SessionPlanning.defaultManualTimeToLimitMinutes,
        remindersEnabled: Bool = true,
        autoPingEnabled: Bool = false,
        wasteWarningEnabled: Bool = true,
        planModeTipsEnabled: Bool = true,
        tipPreferences: TipPreferences = TipPreferences()
    ) {
        self.isEnabled = isEnabled
        self.plannedWorkStart = plannedWorkStart
        self.repeatBehavior = repeatBehavior
        self.useAutoEstimate = useAutoEstimate
        self.manualTypicalTimeToLimitMinutes = Self.clampTimeToLimit(manualTypicalTimeToLimitMinutes)
        self.remindersEnabled = remindersEnabled
        self.autoPingEnabled = autoPingEnabled
        self.wasteWarningEnabled = wasteWarningEnabled
        self.planModeTipsEnabled = planModeTipsEnabled
        self.tipPreferences = tipPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        plannedWorkStart = try container.decodeIfPresent(Date.self, forKey: .plannedWorkStart)
        repeatBehavior = try container.decodeIfPresent(RepeatBehavior.self, forKey: .repeatBehavior) ?? .weekdays
        useAutoEstimate = try container.decodeIfPresent(Bool.self, forKey: .useAutoEstimate) ?? true

        let minutes = try container.decodeIfPresent(Int.self, forKey: .manualTypicalTimeToLimitMinutes)
        manualTypicalTimeToLimitMinutes = Self.clampTimeToLimit(minutes ?? Constants.SessionPlanning.defaultManualTimeToLimitMinutes)

        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        autoPingEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPingEnabled) ?? false
        wasteWarningEnabled = try container.decodeIfPresent(Bool.self, forKey: .wasteWarningEnabled) ?? true
        planModeTipsEnabled = try container.decodeIfPresent(Bool.self, forKey: .planModeTipsEnabled) ?? true
        tipPreferences = try container.decodeIfPresent(TipPreferences.self, forKey: .tipPreferences) ?? TipPreferences()
    }

    private static func clampTimeToLimit(_ minutes: Int) -> Int {
        min(max(minutes, Constants.SessionPlanning.minTimeToLimitMinutes), Constants.SessionPlanning.maxTimeToLimitMinutes)
    }

    var typicalTimeToLimitSeconds: TimeInterval {
        TimeInterval(manualTypicalTimeToLimitMinutes * 60)
    }
}

struct SessionLimitObservation: Codable, Identifiable {
    let id: UUID
    let profileId: UUID
    let sessionResetTime: Date
    let observedAt: Date
    let sessionPercentageAtObservation: Double
    let typicalTimeToLimitMinutes: Int
    let peakHoursActive: Bool

    init(
        profileId: UUID,
        sessionResetTime: Date,
        sessionPercentageAtObservation: Double,
        typicalTimeToLimitMinutes: Int,
        peakHoursActive: Bool
    ) {
        self.id = UUID()
        self.profileId = profileId
        self.sessionResetTime = sessionResetTime
        self.observedAt = Date()
        self.sessionPercentageAtObservation = sessionPercentageAtObservation
        self.typicalTimeToLimitMinutes = typicalTimeToLimitMinutes
        self.peakHoursActive = peakHoursActive
    }
}