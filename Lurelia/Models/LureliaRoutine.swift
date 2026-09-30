//
//  LureliaRoutine.swift
//  Lurelia
//

import Foundation
import SwiftData

// MARK: - Time of Day

enum LureliaRoutineTimeOfDay: String, Codable, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case anytime = "Anytime"
    
    var icon: String {
        switch self {
        case .morning:
            return "sun"
        case .afternoon:
            return "cloudie"
        case .evening:
            return "moonzs"
        case .anytime:
            return "sparkle"
        }
    }
}

// MARK: - Routine Task

@Model
final class LureliaRoutineTask {
    
    // MARK: - Identity
    
    var stableTaskID: String = UUID().uuidString
    
    // MARK: - Core
    
    var title: String = ""
    var icon: String = "sparkle"
    var notes: String = ""
    /// User-provided goal / context used to fill out the task's detail blueprint.
    var context: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // MARK: - State
    
    /// "pending" | "completed" | "skipped"
    var state: String = "pending"
    var completedAt: Date?
    var skippedAt: Date?
    
    // MARK: - Bank Link
    
    var isFromBank: Bool = false
    var bankTaskID: String?
    
    // MARK: - Relationship
    
    var routine: LureliaRoutine?
    var routinePersistentIDString: String = ""
    
    // MARK: - Phase Link

    var phaseID: String?

    // MARK: - Detail Blueprint (per-task)

    /// Why this task exists.
    var purpose: String = ""
    /// What emotionally / practically encourages follow-through.
    var motivation: String = ""
    /// The moment / event that signals the task should begin (formerly "Cue").
    /// This is the trigger *description*; `triggerType` and `triggerReason`
    /// mirror the habit Cue's type + "why this works" structure exactly.
    var trigger: String = ""
    /// Raw value of the selected trigger type (reuses LureliaCueType).
    var triggerTypeRaw: String?
    /// Why this trigger works.
    var triggerReason: String = ""
    /// Where the task is normally performed.
    var environment: String = ""
    /// What is currently making the task harder to begin or complete.
    var friction: String = ""
    /// The reward associated with completing the task.
    var reward: String = ""
    /// Whether the reward field is intentionally part of this task. `nil`
    /// means legacy data should infer this from the stored reward text.
    var rewardEnabled: Bool? = nil
    /// What happens if the task is not completed.
    var consequence: String = ""
    /// Whether the consequence field is intentionally part of this task. `nil`
    /// means legacy data should infer this from the stored consequence text.
    var consequenceEnabled: Bool? = nil
    /// What to do after missing / skipping the task.
    var recoveryPlan: String = ""

    // MARK: - Schedule (per-task)

    var hasDueTime: Bool = false
    var dueHour: Int = 8
    var dueMinute: Int = 0
    var estimatedDurationMinutes: Int = 0
    var repeatsOnDays: Bool = false
    /// 1 = Sunday ... 7 = Saturday
    var scheduledDays: [Int] = []

    // MARK: - Notifications & Alarm (per-task)

    var notificationsEnabled: Bool = false
    /// Lead-time offsets (minutes before the due time) for each notification.
    var notificationLeadMinutes: [Int] = []
    var notificationIDs: [String] = []
    var alarmEnabled: Bool = false
    var alarmSoundName: String?
    var alarmIDString: String?

    // MARK: - Structured Content (owned child models, CloudKit-safe)

    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineTaskStep.task)
    var stepItems: [LureliaRoutineTaskStep]?

    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineTaskSupply.task)
    var supplyItems: [LureliaRoutineTaskSupply]?

    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineTaskObstacle.task)
    var obstacleItems: [LureliaRoutineTaskObstacle]?

    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineTaskHistoryEntry.task)
    var historyItems: [LureliaRoutineTaskHistoryEntry]?

    // MARK: - Init

    init(
        title: String,
        icon: String = "sparkle",
        notes: String = "",
        sortOrder: Int = 0,
        isFromBank: Bool = false,
        bankTaskID: String? = nil
    ) {
        self.title = title
        self.icon = icon
        self.notes = notes
        self.sortOrder = sortOrder
        self.state = "pending"
        self.createdAt = Date()
        self.updatedAt = Date()
        self.stableTaskID = bankTaskID ?? "routine-task::\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())::\(sortOrder)"
        self.isFromBank = isFromBank
        self.bankTaskID = bankTaskID
    }
    
    // MARK: - Helpers
    
    var isPending: Bool { state == "pending" }
    var isCompleted: Bool { state == "completed" }
    var isSkipped: Bool { state == "skipped" }

    var routineScopedTaskID: String {
        let routineID = routinePersistentIDString.isEmpty ? routine?.persistentID : routinePersistentIDString
        return "\(routineID ?? "unlinked")::\(stableTaskID)"
    }

    func attach(to routine: LureliaRoutine) {
        self.routine = routine
        self.routinePersistentIDString = routine.persistentID
    }

    func matchesRoutineScopedTaskID(_ itemID: String) -> Bool {
        itemID == routineScopedTaskID || itemID == stableTaskID
    }
    
    func markCompleted() {
        state = "completed"
        completedAt = Date()
        skippedAt = nil
        updatedAt = Date()
    }
    
    func markSkipped() {
        state = "skipped"
        skippedAt = Date()
        completedAt = nil
        updatedAt = Date()
    }
    
    func resetState() {
        state = "pending"
        completedAt = nil
        skippedAt = nil
        for step in stepItems ?? [] {
            step.resetCompletion()
        }
        updatedAt = Date()
    }
}

// MARK: - Routine Run Task

@Model
final class LureliaRoutineRunTask {
    
    // MARK: - Identity
    
    var sourceStableTaskID: String = ""
    
    // MARK: - Core
    
    var taskName: String = ""
    var taskNotes: String = ""
    var sortOrder: Int = 0
    
    /// "pending" | "completed" | "skipped"
    var state: String = "pending"
    
    // MARK: - Relationship
    
    var run: LureliaRoutineRun?
    
    // MARK: - Init
    
    init(
        name: String,
        notes: String = "",
        sortOrder: Int
    ) {
        self.taskName = name
        self.taskNotes = notes
        self.sortOrder = sortOrder
        self.sourceStableTaskID = ""
        self.state = "pending"
    }
    
    // MARK: - Helpers
    
    var isPending: Bool {
        state == "pending"
    }
    
    var isCompleted: Bool {
        state == "completed"
    }
    
    var isSkipped: Bool {
        state == "skipped"
    }
}

// MARK: - Routine Run

@Model
final class LureliaRoutineRun {
    
    // MARK: - Run State
    
    var startedAt: Date = Date()
    var endedAt: Date?
    var wasCompleted: Bool = false
    
    // MARK: - Pause State
    
    var isPaused: Bool = false
    var pausedAt: Date?
    var totalPausedSeconds: Double = 0
    
    // MARK: - Routine Snapshot
    
    var routineName: String = "Routine"
    var routineIcon: String = "sparkle"
    var routineColorHex: String = "#7d19f7"
    var routineTimeOfDayRaw: String = "Routine"
    
    // MARK: - Relationships
    
    var routine: LureliaRoutine?
    
    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineRunTask.run)
    var tasks: [LureliaRoutineRunTask]?
    
    // MARK: - Init
    
    init(routine: LureliaRoutine) {
        self.startedAt = Date()
        self.endedAt = nil
        self.wasCompleted = false
        
        self.isPaused = false
        self.pausedAt = nil
        self.totalPausedSeconds = 0
        
        self.routineName = routine.name
        self.routineIcon = routine.icon
        self.routineColorHex = routine.colorHex
        self.routineTimeOfDayRaw = routine.timeOfDay.rawValue
        self.routine = routine
    }
    
    // MARK: - Helpers
    
    var isActive: Bool {
        endedAt == nil
    }
    
    var isRunning: Bool {
        isActive && !isPaused
    }
    
    var completedCount: Int {
        (tasks ?? []).filter { $0.isCompleted }.count
    }
    
    var skippedCount: Int {
        (tasks ?? []).filter { $0.isSkipped }.count
    }
    
    var pendingCount: Int {
        (tasks ?? []).filter { $0.isPending }.count
    }
    
    var totalCount: Int {
        (tasks ?? []).count
    }
    
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount + skippedCount) / Double(totalCount)
    }
    
    var allDone: Bool {
        pendingCount == 0
    }
    
    func pause() {
        guard isActive, !isPaused else { return }
        
        isPaused = true
        pausedAt = Date()
    }
    
    func resume() {
        guard isActive, isPaused else { return }
        
        if let pausedAt {
            totalPausedSeconds += Date().timeIntervalSince(pausedAt)
        }
        
        isPaused = false
        pausedAt = nil
    }

    func pausedDuration(at date: Date) -> TimeInterval {
        let activePauseDuration: TimeInterval

        if isPaused, let pausedAt {
            activePauseDuration = max(0, date.timeIntervalSince(pausedAt))
        } else {
            activePauseDuration = 0
        }

        return max(0, totalPausedSeconds) + activePauseDuration
    }
}

// MARK: - Routine

enum LureliaRoutineOffDayValidationResult: Equatable {
    case valid
    case duplicate
    case backToBack
    case limitReached
}

@Model
final class LureliaRoutine {
    
    // MARK: - Identity
    
    var persistentID: String = UUID().uuidString
    var starterRoutineID: String?
    
    // MARK: - Core
    
    var name: String = ""
    var icon: String = "sparkle"
    var timeOfDay: LureliaRoutineTimeOfDay = LureliaRoutineTimeOfDay.morning
    var colorHex: String = "#7d19f7"
    
    // MARK: - Enhanced Fields
    
    var purpose: String = ""
    var descriptionText: String = ""
    var principlesStorage: String = "[]"
    var phasesEnabled: Bool = false
    
    // MARK: - Schedule
    
    /// 1 = Sunday, 2 = Monday, 3 = Tuesday, 4 = Wednesday, 5 = Thursday, 6 = Friday, 7 = Saturday
    var scheduledDays: [Int] = []
    
    var startHour: Int = 8
    var startMinute: Int = 0
    var endHour: Int = 8
    var endMinute: Int = 30
    var scheduleEnabled: Bool = false
    var remindersEnabled: Bool = false
    var durationMode: Bool = false
    var durationMinutesOverride: Int = 30
    var offDayKeysStorage: String = "[]"
    
    // MARK: - Notification IDs

    var startReminderNotificationIDs: [String] = []
    var halfwayReminderNotificationIDs: [String] = []
    var endReminderNotificationIDs: [String] = []
    
    // MARK: - Journey Links

    var journeyID: UUID?
    var journeyMilestoneID: UUID?
    var journeyStepID: UUID?
    var journeyTimelineItemID: UUID?
    
    // MARK: - Practice Link
    
    var practiceID: String?

    // MARK: - Metadata
    
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // MARK: - Direct Completion (no run required)
    
    var lastCompletedAt: Date?
    var lastSkippedAt: Date?
    
    // MARK: - Relationships
    
    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineTask.routine)
    var tasks: [LureliaRoutineTask]?
    
    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutineRun.routine)
    var runs: [LureliaRoutineRun]?
    
    @Relationship(deleteRule: .cascade, inverse: \LureliaRoutinePhase.routine)
    var phases: [LureliaRoutinePhase]?

    @Relationship(deleteRule: .nullify, inverse: \LureliaRoutineContract.routine)
    var contracts: [LureliaRoutineContract]?
    
    // MARK: - Init
    
    init(
        name: String,
        icon: String = "sparkle",
        timeOfDay: LureliaRoutineTimeOfDay = .morning,
        colorHex: String = "#7d19f7",
        scheduledDays: [Int] = [],
        startHour: Int = 8,
        startMinute: Int = 0,
        endHour: Int = 8,
        endMinute: Int = 30,
        scheduleEnabled: Bool = false,
        sortOrder: Int = 0,
        durationMode: Bool = false,
        durationMinutesOverride: Int = 30
    ) {
        self.persistentID = UUID().uuidString
        self.starterRoutineID = nil
        self.name = name
        self.icon = icon
        self.timeOfDay = timeOfDay
        self.colorHex = colorHex
        
        self.scheduledDays = scheduledDays
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.scheduleEnabled = scheduleEnabled
        self.durationMode = durationMode
        self.durationMinutesOverride = durationMinutesOverride
        
        self.startReminderNotificationIDs = []
        self.halfwayReminderNotificationIDs = []
        self.endReminderNotificationIDs = []
        
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Helpers
    
    var activeRun: LureliaRoutineRun? {
        (runs ?? []).first { $0.isActive }
    }
    
    var durationMinutes: Int {
        if durationMode {
            return max(1, durationMinutesOverride)
        }

        let startMins = startHour * 60 + startMinute
        let endMins = endHour * 60 + endMinute
        let difference = endMins - startMins

        return max(1, difference > 0 ? difference : difference + 1440)
    }

    var formattedDuration: String {
        let minutes = durationMinutes
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(remainingMinutes)m"
    }
    
    var sortedTasks: [LureliaRoutineTask] {
        (tasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var sortedPhases: [LureliaRoutinePhase] {
        (phases ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var principles: [String] {
        get {
            guard let data = principlesStorage.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                principlesStorage = string
            }
        }
    }

    var offDayKeys: Set<String> {
        get {
            guard let data = offDayKeysStorage.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(decoded)
        }
        set {
            let sorted = Array(newValue).sorted()
            if let data = try? JSONEncoder().encode(sorted),
               let string = String(data: data, encoding: .utf8) {
                offDayKeysStorage = string
            } else {
                offDayKeysStorage = "[]"
            }
            updatedAt = Date()
        }
    }

    func offDayKey(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    func offDayDate(
        from key: String,
        calendar: Calendar = .current
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    func sortedOffDayDates(calendar: Calendar = .current) -> [Date] {
        offDayKeys
            .compactMap { offDayDate(from: $0, calendar: calendar) }
            .sorted()
    }

    func isOffDay(
        _ date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        offDayKeys.contains(offDayKey(for: date, calendar: calendar))
    }

    func offDayValidationResult(
        for date: Date,
        calendar: Calendar = .current
    ) -> LureliaRoutineOffDayValidationResult {
        let day = calendar.startOfDay(for: date)
        let key = offDayKey(for: day, calendar: calendar)
        let existingDates = sortedOffDayDates(calendar: calendar)

        if offDayKeys.contains(key) {
            return .duplicate
        }

        let isBackToBack = existingDates.contains { existing in
            abs(calendar.dateComponents([.day], from: existing, to: day).day ?? 0) == 1
        }

        if isBackToBack {
            return .backToBack
        }

        let datesInRollingWindow = existingDates.filter { existing in
            abs(calendar.dateComponents([.day], from: existing, to: day).day ?? 0) < 30
        }

        if datesInRollingWindow.count >= 2 {
            return .limitReached
        }

        return .valid
    }

    @discardableResult
    func addOffDay(
        _ date: Date,
        calendar: Calendar = .current
    ) -> LureliaRoutineOffDayValidationResult {
        let result = offDayValidationResult(for: date, calendar: calendar)
        guard result == .valid else { return result }

        var keys = offDayKeys
        keys.insert(offDayKey(for: date, calendar: calendar))
        offDayKeys = keys
        return .valid
    }

    func removeOffDay(
        _ date: Date,
        calendar: Calendar = .current
    ) {
        var keys = offDayKeys
        keys.remove(offDayKey(for: date, calendar: calendar))
        offDayKeys = keys
    }
    
    func tasksForPhase(_ phase: LureliaRoutinePhase) -> [LureliaRoutineTask] {
        let phaseIDString = phase.id.uuidString
        return sortedTasks.filter { $0.phaseID == phaseIDString }
    }
    
    // MARK: - Direct Complete / Skip
    
    /// Completes the routine: all pending (non-skipped) tasks get marked completed.
    func completeRoutine() {
        for task in (tasks ?? []) where task.isPending {
            task.markCompleted()
        }
        lastCompletedAt = Date()
        updatedAt = Date()
    }
    
    /// Skips the routine: all pending (non-completed) tasks get marked skipped.
    func skipRoutine() {
        for task in (tasks ?? []) where task.isPending {
            task.markSkipped()
        }
        lastSkippedAt = Date()
        updatedAt = Date()
    }
    
    /// Resets all tasks to pending.
    func resetTaskStates() {
        for task in (tasks ?? []) {
            task.resetState()
        }
        updatedAt = Date()
    }
    
    var allTasksDone: Bool {
        let allTasks = tasks ?? []
        guard !allTasks.isEmpty else { return false }
        return allTasks.allSatisfy { !$0.isPending }
    }
    
    var completedTaskCount: Int {
        (tasks ?? []).filter { $0.isCompleted }.count
    }
    
    var skippedTaskCount: Int {
        (tasks ?? []).filter { $0.isSkipped }.count
    }
    
    var pendingTaskCount: Int {
        (tasks ?? []).filter { $0.isPending }.count
    }
    
    var startDateComponents: DateComponents {
        DateComponents(
            hour: startHour,
            minute: startMinute
        )
    }
    
    var endDateComponents: DateComponents {
        DateComponents(
            hour: endHour,
            minute: endMinute
        )
    }
    
    var formattedStartTime: String {
        formattedTime(hour: startHour, minute: startMinute)
    }
    
    var formattedEndTime: String {
        formattedTime(hour: endHour, minute: endMinute)
    }
    
    var formattedTimeRange: String {
        "\(formattedStartTime) - \(formattedEndTime)"
    }
    
    var enabledReminderTimes: [LureliaRoutineReminderTime] {
        [
            LureliaRoutineReminderTime(
                title: "Start Reminder",
                hour: startHour,
                minute: startMinute,
                notificationIDs: startReminderNotificationIDs
            ),
            LureliaRoutineReminderTime(
                title: "Halfway Reminder",
                hour: halfwayReminderHour,
                minute: halfwayReminderMinute,
                notificationIDs: halfwayReminderNotificationIDs
            ),
            LureliaRoutineReminderTime(
                title: "End Reminder",
                hour: endHour,
                minute: endMinute,
                notificationIDs: endReminderNotificationIDs
            )
        ]
    }
    
    private var halfwayReminderTotalMinutes: Int {
        let startTotal = startHour * 60 + startMinute
        let halfwayTotal = startTotal + (durationMinutes / 2)
        return halfwayTotal % 1440
    }

    var halfwayReminderHour: Int {
        halfwayReminderTotalMinutes / 60
    }

    var halfwayReminderMinute: Int {
        halfwayReminderTotalMinutes % 60
    }
    
    private func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        guard let date = Calendar.current.date(from: components) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }
        
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct LureliaRoutineReminderTime: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var hour: Int
    var minute: Int
    var notificationIDs: [String]

    var formattedTime: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        guard let date = Calendar.current.date(from: components) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }

        return date.formatted(date: .omitted, time: .shortened)
    }
}
