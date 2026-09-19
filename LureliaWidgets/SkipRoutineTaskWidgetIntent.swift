//
//  SkipRoutineTaskWidgetIntent.swift
//  Lurelia
//
//  Task-level skip intent used by LureliaDueRoutinesWidget's task tiles.
//  Marks one `LureliaRoutineTask` skipped by its routine-scoped action ID —
//  same behavior as the in-app skip action.
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData

struct SkipRoutineTaskWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Routine Task"
    static var description = IntentDescription(
        "Skips a single routine task from the widget."
    )

    @Parameter(title: "Task ID")
    var taskID: String

    init(taskID: String) {
        self.taskID = taskID
    }

    init() {
        self.taskID = ""
    }

    func perform() async throws -> some IntentResult {
        print("🟣 [WidgetIntent] SkipRoutineTask perform — taskID=\(taskID)")
        defer { reloadRoutineTaskWidgets() }

        guard !taskID.isEmpty else {
            print("🟣 [WidgetIntent] SkipRoutineTask — empty taskID, bailing")
            return .result()
        }

        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        guard let task = try routineTask(matching: taskID, in: context) else {
            return .result()
        }

        // Idempotent: if already skipped/completed, just refresh the widget.
        guard task.isPending else {
            return .result()
        }

        try recordRoutineTaskHistory(
            task,
            wasCompleted: false,
            occurredAt: Date(),
            context: context
        )

        if let routine = task.routine {
            routine.updatedAt = Date()
            if routine.allTasksDone {
                routine.lastCompletedAt = Date()
            }
        }

        try context.save()

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
            existing.skipReason = wasCompleted ? "" : "Skipped from Routine Tasks widget"
            existing.note = ""
            existing.routineTaskIDString = task.routineScopedTaskID
        } else {
            let entry = LureliaRoutineTaskHistoryEntry(
                date: occurredAt,
                durationSeconds: 0,
                wasCompleted: wasCompleted,
                skipReason: wasCompleted ? "" : "Skipped from Routine Tasks widget",
                note: ""
            )
            entry.routineTaskIDString = task.routineScopedTaskID
            context.insert(entry)
            entry.task = task
            task.historyItems = existingHistory + [entry]
        }

        if calendar.isDateInToday(occurredAt) {
            task.markSkipped()
        } else {
            task.updatedAt = Date()
        }

        task.routine?.refreshCurrentContractStatusIfNeeded()
    }

    private func reloadRoutineTaskWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaDueRoutinesWidget")
    }
}
