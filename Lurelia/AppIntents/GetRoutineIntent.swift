//
//  GetRoutineIntent.swift
//  Lurelia
//
//  "Get Routine" Shortcuts action. Presents a picker of the user's real saved
//  routines and returns the selected one as a `RoutineEntity`, which Shortcuts
//  then exposes as a Magic Variable for later actions (e.g. "Get Routine
//  Tasks").
//

import Foundation
import AppIntents

struct GetRoutineIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Routine"

    static var description = IntentDescription(
        "Choose one of your Lurelia routines. The selected routine can be used as a variable in later actions."
    )

    /// Real AppEntity picker (not free text), backed by Lurelia's routines.
    @Parameter(title: "Routine")
    var routine: RoutineEntity

    init() {}

    init(routine: RoutineEntity) {
        self.routine = routine
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$routine)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<RoutineEntity> {
        .result(value: routine)
    }
}
