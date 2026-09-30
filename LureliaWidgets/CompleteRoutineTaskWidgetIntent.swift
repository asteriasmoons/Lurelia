//
//  CompleteRoutineTaskWidgetIntent.swift
//  Lurelia
//
//  Task-level completion intent used by LureliaDueRoutinesWidget's task
//  tiles. Marks one `LureliaRoutineTask` completed by its routine-scoped
//  action ID and, if that finished off the parent routine, marks the routine
//  itself.
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData

struct CompleteRoutineTaskWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Routine Task"
    static var description = IntentDescription(
        "Completes a single routine task from the widget."
    )

    /// The task's routine-scoped widget action ID. Bare `stableTaskID` is not
    /// unique across routines, so new widget rows pass `task.routineScopedTaskID`.
    /// The resolver still accepts bare IDs for already-rendered old timelines.
    @Parameter(title: "Task ID")
    var taskID: String

    init(taskID: String) {
        self.taskID = taskID
    }

    init() {
        self.taskID = ""
    }

    func perform() async throws -> some IntentResult {
        print("🟣 [WidgetIntent] CompleteRoutineTask perform — taskID=\(taskID)")
        defer { reloadRoutineTaskWidgets() }

        guard !taskID.isEmpty else {
            print("🟣 [WidgetIntent] CompleteRoutineTask — empty taskID, bailing")
            return .result()
        }

        print("🟣 [WidgetIntent] CompleteRoutineTask — opening container")
        let container = try LureliaWidgetShared.makeModelContainer()
        print("🟣 [WidgetIntent] CompleteRoutineTask — container OK, creating context")
        let context = ModelContext(container)
        print("🟣 [WidgetIntent] CompleteRoutineTask — context OK, fetching task")

        guard let task = try routineTask(matching: taskID, in: context) else {
            print("🟣 [WidgetIntent] CompleteRoutineTask — task not found for id=\(taskID)")
            return .result()
        }
        print("🟣 [WidgetIntent] CompleteRoutineTask — task found: \(task.title), isPending=\(task.isPending)")

        // Idempotent: if the task was already completed or skipped, we're
        // done — just refresh the widget so the tile disappears next tick.
        guard task.isPending else {
            print("🟣 [WidgetIntent] CompleteRoutineTask — not pending, just reloading widget")
            return .result()
        }

        let occurredAt = Date()
        print("🟣 [WidgetIntent] CompleteRoutineTask — recording completion history")
        try recordRoutineTaskHistory(
            task,
            wasCompleted: true,
            occurredAt: occurredAt,
            context: context
        )

        LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
            for: task,
            on: occurredAt,
            now: occurredAt
        )
        await LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrenceAndWait(
            for: task,
            on: occurredAt,
            now: occurredAt
        )

        // If completing this task finished off the routine, mark the routine
        // itself completed so the routines list / live activity stay in sync.
        if let routine = task.routine {
            print("🟣 [WidgetIntent] CompleteRoutineTask — updating parent routine")
            routine.updatedAt = Date()
            if routine.allTasksDone {
                routine.lastCompletedAt = Date()
            }
        }

        print("🟣 [WidgetIntent] CompleteRoutineTask — saving context")
        try context.save()
        print("🟣 [WidgetIntent] CompleteRoutineTask — save OK")

        return .result()
    }

    private func routineTask(matching itemID: String, in context: ModelContext) throws -> LureliaRoutineTask? {
        let tasks = try context.fetch(FetchDescriptor<LureliaRoutineTask>())

        if let exact = tasks.first(where: { $0.routineScopedTaskID == itemID }) {
            return exact
        }

        let legacyMatches = tasks.filter { $0.matchesRoutineScopedTaskID(itemID) }
        return legacyMatches.count == 1 ? legacyMatches.first : nil
    }

    private func recordRoutineTaskHistory(
        _ task: LureliaRoutineTask,
        wasCompleted: Bool,
        occurredAt: Date,
        context: ModelContext
    ) throws {
        let calendar = Calendar.current
        let existingHistory = task.historyItems ?? []
        let allHistory = try context.fetch(FetchDescriptor<LureliaRoutineTaskHistoryEntry>())

        if let existing = allHistory.first(where: { entry in
            (entry.routineTaskIDString.isEmpty ? entry.task?.routineScopedTaskID : entry.routineTaskIDString) == task.routineScopedTaskID
                && calendar.isDate(entry.date, inSameDayAs: occurredAt)
        }) {
            existing.date = occurredAt
            existing.wasCompleted = wasCompleted
            existing.durationSeconds = 0
            existing.skipReason = ""
            existing.note = ""
            existing.routineTaskIDString = task.routineScopedTaskID
        } else {
            let entry = LureliaRoutineTaskHistoryEntry(
                date: occurredAt,
                durationSeconds: 0,
                wasCompleted: wasCompleted,
                skipReason: "",
                note: ""
            )
            entry.routineTaskIDString = task.routineScopedTaskID
            context.insert(entry)
            entry.task = task
            task.historyItems = existingHistory + [entry]
        }

        if calendar.isDateInToday(occurredAt) {
            task.markCompleted()
        } else {
            task.updatedAt = Date()
        }

        task.routine?.refreshCurrentContractStatusIfNeeded()
    }

    private func reloadRoutineTaskWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaDueRoutinesWidget")
    }
}
