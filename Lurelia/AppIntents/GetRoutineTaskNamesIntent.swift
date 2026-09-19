//
//  GetRoutineTaskNamesIntent.swift
//  Lurelia
//
//  "Get Routine Task Names" Shortcuts action. Takes the routine tasks returned
//  by "Get Routine Tasks" (the [RoutineTaskEntity] Magic Variable) and returns
//  their names as a plain list of Text ([String]).
//
//  Why this exists: a Shortcuts Text action cannot reliably pull a property
//  out of a list of custom AppEntities -- it keeps them as "Routine Task"
//  objects. A native [String] output, by contrast, drops straight into a Text
//  action (or Combine Text) and resolves as the actual task names. This is the
//  piece that makes the morning-briefing Text action work; it does not replace
//  Get Routine Tasks or the RoutineTaskEntity, it consumes them.
//

import Foundation
import AppIntents

struct GetRoutineTaskNamesIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Routine Task Names"

    static var description = IntentDescription(
        "Returns the task names as text for the given Lurelia routine tasks — ready to drop straight into a Text action."
    )

    /// The tasks whose names to extract. Accepts the [Routine Tasks] Magic
    /// Variable returned by "Get Routine Tasks".
    @Parameter(title: "Tasks")
    var tasks: [RoutineTaskEntity]

    init() {}

    init(tasks: [RoutineTaskEntity]) {
        self.tasks = tasks
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get task names from \(\.$tasks)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        // `name` is the RoutineTaskEntity's real task title. Returning [String]
        // (a list of Text) is what makes the values usable directly in a Text
        // action / Combine Text.
        let names = tasks.map { $0.name }
        return .result(value: names)
    }
}
