//
//  GetRoutineTaskIntent.swift
//  Lurelia
//
//  "Get Routine Task" Shortcuts action — a DEPENDENT entity picker. You pick a
//  Routine, then the Task parameter dynamically offers only that routine's real
//  tasks by name (Wash Face, Take Vitals, …) and you choose one. Add the action
//  again to pick a different task, so individual tasks can be placed at
//  different points in a briefing.
//
//  Mechanism (Apple's documented dependent-picker pattern): the Task parameter
//  is a plain AppEntity parameter, so its Shortcuts-editor picker is driven by
//  RoutineTaskEntity's defaultQuery — RoutineTaskEntityQuery. That query declares
//  `@IntentParameterDependency<GetRoutineTaskIntent>(\.$routine)` and implements
//  `suggestedEntities()` to return ONLY the chosen routine's tasks. (optionsProvider
//  is for value types, not AppEntity params — using it leaves the picker empty.)
//  Output is the chosen RoutineTaskEntity, whose Task Name is a drillable text
//  property for later Text / Speak actions.
//

import Foundation
import AppIntents

struct GetRoutineTaskIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Routine Task"

    static var description = IntentDescription(
        "Pick a Lurelia routine, then pick one of that routine's tasks by name. Returns the chosen task (its Task Name is available as text)."
    )

    /// The routine to pick a task from. Accepts the Magic Variable from "Get Routine".
    @Parameter(title: "Routine")
    var routine: RoutineEntity

    /// The task. Its picker options come from RoutineTaskEntityQuery.suggestedEntities(),
    /// which is scoped to the selected `routine` via @IntentParameterDependency —
    /// so tapping Task shows only that routine's tasks, by name.
    @Parameter(title: "Task")
    var task: RoutineTaskEntity

    init() {}

    init(routine: RoutineEntity, task: RoutineTaskEntity) {
        self.routine = routine
        self.task = task
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$task) from \(\.$routine)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<RoutineTaskEntity> {
        .result(value: task)
    }
}
