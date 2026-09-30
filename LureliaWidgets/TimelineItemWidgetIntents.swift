//
//  TimelineItemWidgetIntents.swift
//  Lurelia
//
//  Dedicated Complete / Skip intents for the Kanban Timeline widget.
//  The Timeline widget needs occurrence-aware mutations: routine tasks are
//  addressed by their routine-scoped Kanban ID, and habits are addressed by
//  the exact fire time shown on the timeline.
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData

// String constants used as the intent's `itemKind` parameter.
enum TimelineItemKindString {
    static let habit = "habit"
    static let reminder = "reminder"
    static let routineTask = "routineTask"
}

private struct TimelineWidgetIntentPayload {
    let itemKind: String
    let itemID: String
    let fireDate: Date?

    init(token: String) {
        let parts = token.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        itemKind = parts.count > 0 ? String(parts[0]) : ""
        itemID = parts.count > 1 ? String(parts[1]) : ""

        if parts.count > 2, let interval = TimeInterval(String(parts[2])) {
            fireDate = Date(timeIntervalSince1970: interval)
        } else {
            fireDate = nil
        }
    }

    static func token(itemKind: String, itemID: String, fireDate: Date?) -> String {
        guard let fireDate else { return "\(itemKind)|\(itemID)" }
        return "\(itemKind)|\(itemID)|\(fireDate.timeIntervalSince1970)"
    }
}

// MARK: - Complete

struct CompleteTimelineItemWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Timeline Item"
    static var description = IntentDescription(
        "Completes the tapped item on the Kanban Timeline widget."
    )

    /// Single composite token: `"kind|id"`. Using one parameter (rather
    /// than two separate `@Parameter`s) side-steps an iOS discovery bug
    /// where widget-button intents with more than one parameter can be
    /// silently dropped by the AppIntent registration pipeline.
    @Parameter(title: "Token")
    var token: String

    init() {
        self.token = ""
    }

    init(itemKind: String, itemID: String, fireDate: Date? = nil) {
        self.token = TimelineWidgetIntentPayload.token(
            itemKind: itemKind,
            itemID: itemID,
            fireDate: fireDate
        )
    }

    func perform() async throws -> some IntentResult {
        let payload = TimelineWidgetIntentPayload(token: token)
        print("🟣 [TimelineIntent] Complete perform — kind=\(payload.itemKind) id=\(payload.itemID)")
        guard !payload.itemID.isEmpty else { return .result() }

        switch payload.itemKind {
        case TimelineItemKindString.habit:
            try completeHabit(habitID: payload.itemID, fireDate: payload.fireDate)
        case TimelineItemKindString.reminder:
            try await completeReminder(reminderID: payload.itemID)
        case TimelineItemKindString.routineTask:
            try await completeRoutineTask(itemID: payload.itemID, fireDate: payload.fireDate)
        default:
            print("🟣 [TimelineIntent] Complete — unknown kind, ignoring")
        }

        return .result()
    }

    // MARK: - Habit

    private func completeHabit(habitID: String, fireDate: Date?) throws {
        guard let id = UUID(uuidString: habitID) else { return }

        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<LureliaHabit>(
            predicate: #Predicate<LureliaHabit> { habit in
                habit.id == id
            }
        )

        guard let habit = try context.fetch(descriptor).first else { return }

        let calendar = Calendar.current
        let occurredAt = fireDate ?? Date()
        let dayStart = calendar.startOfDay(for: occurredAt)

        let log: LureliaHabitLog
        if let existingLog = (habit.logs ?? []).first(where: { log in
            calendar.isDate(log.dayStart, inSameDayAs: dayStart)
        }) {
            log = existingLog
        } else {
            log = LureliaHabitLog(habit: habit, dayStart: dayStart, count: 0)
            context.insert(log)
            habit.logs = (habit.logs ?? []) + [log]
        }

        guard !log.isCompleted(atFireDate: occurredAt, calendar: calendar) else { return }
        log.markCompleted(atFireDate: occurredAt, calendar: calendar)

        if let sameDaySkip = (habit.skips ?? []).first(where: { skip in
            calendar.isDate(skip.dayStart, inSameDayAs: dayStart)
        }) {
            context.delete(sameDaySkip)
            habit.skips = (habit.skips ?? []).filter {
                $0.persistentModelID != sameDaySkip.persistentModelID
            }
        }

        habit.updatedAt = Date()
        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaHabitsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaKanbanTimelineWidget")
    }

    // MARK: - Routine task

    private func completeRoutineTask(itemID: String, fireDate: Date?) async throws {
        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        guard let task = try routineTask(matching: itemID, in: context) else { return }

        let occurredAt = fireDate ?? Date()
        recordRoutineTaskHistory(
            task,
            wasCompleted: true,
            occurredAt: occurredAt,
            context: context
        )

        LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
            for: task,
            on: occurredAt
        )
        await LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrenceAndWait(
            for: task,
            on: occurredAt
        )

        if let routine = task.routine {
            routine.updatedAt = Date()
            if routine.allTasksDone {
                routine.lastCompletedAt = Date()
            }
        }

        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaDueRoutinesWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaHabitsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaKanbanTimelineWidget")
    }

    // MARK: - Reminder — delegates to CompleteReminderWidgetIntent (which owns 200+ lines of reminder scheduling logic)

    private func completeReminder(reminderID: String) async throws {
        // Reminder completion involves next-fire-date calculation across
        // every repeat unit; keep that source of truth, but await it so the
        // widget extension does not return before the mutation completes.
        let intent = CompleteReminderWidgetIntent(reminderID: reminderID)
        _ = try await intent.perform()
    }
}

// MARK: - Skip

struct SkipTimelineItemWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Timeline Item"
    static var description = IntentDescription(
        "Skips the tapped item on the Kanban Timeline widget."
    )

    /// Single composite token: `"kind|id"` — see the Complete intent
    /// above for the reason a single-parameter shape is used here.
    @Parameter(title: "Token")
    var token: String

    init() {
        self.token = ""
    }

    init(itemKind: String, itemID: String, fireDate: Date? = nil) {
        self.token = TimelineWidgetIntentPayload.token(
            itemKind: itemKind,
            itemID: itemID,
            fireDate: fireDate
        )
    }

    func perform() async throws -> some IntentResult {
        let payload = TimelineWidgetIntentPayload(token: token)
        print("🟣 [TimelineIntent] Skip perform — kind=\(payload.itemKind) id=\(payload.itemID)")
        guard !payload.itemID.isEmpty else { return .result() }

        switch payload.itemKind {
        case TimelineItemKindString.habit:
            try skipHabit(habitID: payload.itemID, fireDate: payload.fireDate)
        case TimelineItemKindString.reminder:
            try await skipReminder(reminderID: payload.itemID)
        case TimelineItemKindString.routineTask:
            try await skipRoutineTask(itemID: payload.itemID, fireDate: payload.fireDate)
        default:
            print("🟣 [TimelineIntent] Skip — unknown kind, ignoring")
        }

        return .result()
    }

    // MARK: - Habit

    private func skipHabit(habitID: String, fireDate: Date?) throws {
        guard let id = UUID(uuidString: habitID) else { return }

        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<LureliaHabit>(
            predicate: #Predicate<LureliaHabit> { habit in
                habit.id == id
            }
        )

        guard let habit = try context.fetch(descriptor).first else { return }

        let calendar = Calendar.current
        let occurredAt = fireDate ?? Date()
        let dayStart = calendar.startOfDay(for: occurredAt)

        let hasLog = (habit.logs ?? []).contains { log in
            calendar.isDate(log.dayStart, inSameDayAs: dayStart)
        }
        guard !hasLog else { return }

        let hasSkip = (habit.skips ?? []).contains { skip in
            calendar.isDate(skip.dayStart, inSameDayAs: dayStart)
        }
        guard !hasSkip else { return }

        let skip = LureliaHabitSkip(habit: habit, dayStart: dayStart)
        context.insert(skip)
        habit.updatedAt = Date()
        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaHabitsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaKanbanTimelineWidget")
    }

    // MARK: - Routine task

    private func skipRoutineTask(itemID: String, fireDate: Date?) async throws {
        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        guard let task = try routineTask(matching: itemID, in: context) else { return }

        let occurredAt = fireDate ?? Date()
        recordRoutineTaskHistory(
            task,
            wasCompleted: false,
            occurredAt: occurredAt,
            context: context
        )

        LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
            for: task,
            on: occurredAt
        )
        await LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrenceAndWait(
            for: task,
            on: occurredAt
        )

        if let routine = task.routine {
            routine.updatedAt = Date()
            if routine.allTasksDone {
                routine.lastCompletedAt = Date()
            }
        }

        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaDueRoutinesWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaHabitsWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaKanbanTimelineWidget")
    }

    // MARK: - Reminder — delegates to SkipReminderWidgetIntent

    private func skipReminder(reminderID: String) async throws {
        let intent = SkipReminderWidgetIntent(reminderID: reminderID)
        _ = try await intent.perform()
    }
}

private func routineTask(
    matching itemID: String,
    in context: ModelContext
) throws -> LureliaRoutineTask? {
    let descriptor = FetchDescriptor<LureliaRoutineTask>()
    let tasks = try context.fetch(descriptor)

    if let exact = tasks.first(where: { $0.kanbanItemID == itemID }) {
        return exact
    }

    let legacyMatches = tasks.filter { $0.matchesKanbanItemID(itemID) }
    return legacyMatches.count == 1 ? legacyMatches.first : nil
}

private func recordRoutineTaskHistory(
    _ task: LureliaRoutineTask,
    wasCompleted: Bool,
    occurredAt: Date,
    context: ModelContext
) {
    let calendar = Calendar.current
    let existingHistory = task.historyItems ?? []

    if let existing = existingHistory.first(where: { calendar.isDate($0.date, inSameDayAs: occurredAt) }) {
        existing.date = occurredAt
        existing.wasCompleted = wasCompleted
        existing.durationSeconds = 0
        existing.skipReason = wasCompleted ? "" : "Skipped from Kanban Timeline widget"
        existing.note = ""
    } else {
        let entry = LureliaRoutineTaskHistoryEntry(
            date: occurredAt,
            durationSeconds: 0,
            wasCompleted: wasCompleted,
            skipReason: wasCompleted ? "" : "Skipped from Kanban Timeline widget",
            note: ""
        )
        context.insert(entry)
        entry.task = task
        task.historyItems = existingHistory + [entry]
    }

    if calendar.isDateInToday(occurredAt) {
        if wasCompleted {
            task.markCompleted()
        } else {
            task.markSkipped()
        }
    } else {
        task.updatedAt = Date()
    }

    task.routine?.refreshCurrentContractStatusIfNeeded()
}
