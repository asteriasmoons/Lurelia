//
//  RoutineTaskEntity.swift
//  Lurelia
//
//  Shortcuts / App Intents representation of a saved routine task
//  (`LureliaRoutineTask`). Only real, already-stored fields are exposed —
//  nothing is invented. The properties are marked `@Property` so Apple's
//  standard Shortcuts actions can extract them (especially "Task Name") from
//  a returned list of tasks.
//

import Foundation
import AppIntents

struct RoutineTaskEntity: AppEntity, Identifiable {

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Routine Task")
    }

    static var defaultQuery = RoutineTaskEntityQuery()

    /// Stable, routine-scoped identifier (`LureliaRoutineTask.routineScopedTaskID`),
    /// unique across routines.
    var id: String

    /// The task's real title.
    @Property(title: "Task Name")
    var name: String

    /// The name of the routine this task belongs to.
    @Property(title: "Routine")
    var routineName: String

    /// The task's stable identifier, exposed for advanced Shortcuts use.
    @Property(title: "Task ID")
    var taskID: String

    /// The task's notes (empty string when none).
    @Property(title: "Notes")
    var notes: String

    /// Whether the task is currently completed.
    @Property(title: "Is Completed")
    var isCompleted: Bool

    /// Raw task state: "pending" | "completed" | "skipped".
    @Property(title: "Status")
    var status: String

    init(
        id: String,
        name: String,
        routineName: String,
        taskID: String,
        notes: String,
        isCompleted: Bool,
        status: String
    ) {
        self.id = id
        self.name = name
        self.routineName = routineName
        self.taskID = taskID
        self.notes = notes
        self.isCompleted = isCompleted
        self.status = status
    }

    /// Builds the entity from the live model without letting the model escape.
    init(task: LureliaRoutineTask) {
        self.id = task.routineScopedTaskID
        self.name = task.title
        self.routineName = task.routine?.name ?? ""
        self.taskID = task.stableTaskID
        self.notes = task.notes
        self.isCompleted = task.isCompleted
        self.status = task.state
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = routineName.isEmpty ? nil : LocalizedStringResource(stringLiteral: routineName)
        return DisplayRepresentation(title: "\(name)", subtitle: subtitle)
    }
}

// MARK: - Query

/// Backs BOTH id-resolution (so a chosen task persists across a shortcut's
/// steps) AND the dependent picker for `GetRoutineTaskIntent`: `suggestedEntities()`
/// reads the routine already chosen on that intent (via `@IntentParameterDependency`)
/// and returns only that routine's tasks, by name. This is what makes the
/// Shortcuts editor render the task list under the selected routine. There is
/// intentionally NO global/all-tasks listing — with no routine selected the
/// picker is empty rather than the whole library.
struct RoutineTaskEntityQuery: EntityQuery {

    @IntentParameterDependency<GetRoutineTaskIntent>(\.$routine)
    var getRoutineTask

    /// Resolve previously-chosen tasks by identifier (used at run time).
    func entities(for identifiers: [RoutineTaskEntity.ID]) async throws -> [RoutineTaskEntity] {
        try await LureliaRoutineIntentStore.tasks(for: identifiers)
    }

    /// Populate the Task picker with ONLY the selected routine's tasks.
    func suggestedEntities() async throws -> [RoutineTaskEntity] {
        guard let routine = getRoutineTask?.routine else { return [] }
        return try await LureliaRoutineIntentStore.tasks(forRoutineID: routine.id)
    }
}
