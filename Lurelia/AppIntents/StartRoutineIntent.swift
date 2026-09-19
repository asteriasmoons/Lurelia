//
//  StartRoutineIntent.swift
//  Lurelia
//
//  "Start Routine" Shortcuts action — the programmatic equivalent of tapping
//  the in-app "Run" button. It deliberately does NOT reimplement any
//  start-routine behavior: it calls the exact same pathway the button calls,
//  `RoutineManager.shared.startRun(for:context:)`, which creates/updates the
//  active routine run, seeds the run tasks, and starts the Live Activity /
//  Dynamic Island via `LureliaLiveActivityBridge`. Both entry points therefore
//  share one definition of "start routine".
//
//  Runs in the app's process against the shared App Group store (same access
//  pattern the interactive widget intents use), so when the automation's
//  "Open App" step foregrounds Lurelia, it sees the routine already running and
//  renders the existing running-routine UI.
//

import Foundation
import AppIntents
import SwiftData

struct StartRoutineIntent: AppIntent {

    static var title: LocalizedStringResource = "Start Routine"

    static var description = IntentDescription(
        "Starts a Lurelia routine — exactly like tapping Run in the app — beginning the active session and its Live Activity. Pair with Open App to see the running routine."
    )

    /// The routine to start. Accepts the Magic Variable returned by "Get Routine".
    @Parameter(title: "Routine")
    var routine: RoutineEntity

    init() {}

    init(routine: RoutineEntity) {
        self.routine = routine
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$routine)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<RoutineEntity> {
        let entity = try await startRoutine(routineID: routine.id)
        return .result(value: entity)
    }

    /// Enters the shared start-routine pathway on the main actor, using the
    /// same App Group store the app and widgets use.
    @MainActor
    private func startRoutine(routineID: String) throws -> RoutineEntity {
        let container = try LureliaWidgetShared.makeModelContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<LureliaRoutine>(
            predicate: #Predicate<LureliaRoutine> { routine in
                routine.persistentID == routineID
            }
        )

        guard let routine = try context.fetch(descriptor).first else {
            throw StartRoutineError.routineNotFound
        }

        // Same call the "Run" button makes — single source of truth for
        // starting a routine (active run + run tasks + Live Activity).
        _ = RoutineManager.shared.startRun(for: routine, context: context)
        try? context.save()

        // Mirror the button's follow-up so widgets reflect the active routine.
        LureliaWidgetReloads.reloadAll()

        return RoutineEntity(routine: routine)
    }
}

// MARK: - Error

enum StartRoutineError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case routineNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .routineNotFound:
            return "That routine could no longer be found in Lurelia."
        }
    }
}
