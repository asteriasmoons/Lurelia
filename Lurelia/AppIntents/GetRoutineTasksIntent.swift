//
//  GetRoutineTasksIntent.swift
//  Lurelia
//
//  "Get Routine Tasks" Shortcuts action. Accepts a routine (typically the
//  Magic Variable from "Get Routine") and returns only the tasks that actually
//  belong to that routine, read live from Lurelia's store. The returned list
//  becomes a Magic Variable whose per-item "Task Name" property can be
//  extracted by Apple's standard Shortcuts actions.
//

import Foundation
import AppIntents

struct GetRoutineTasksIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Routine Tasks"

    static var description = IntentDescription(
        "Returns the tasks that belong to a Lurelia routine, in the routine's own order."
    )

    /// The routine whose tasks to fetch. Accepts the Magic Variable returned
    /// by "Get Routine".
    @Parameter(title: "Routine")
    var routine: RoutineEntity

    init() {}

    init(routine: RoutineEntity) {
        self.routine = routine
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get tasks in \(\.$routine)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[RoutineTaskEntity]> {
        let tasks = try await LureliaRoutineIntentStore.tasks(forRoutineID: routine.id)
        return .result(value: tasks)
    }
}
