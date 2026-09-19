//
//  CompleteRoutineWidgetIntent.swift
//  Lurelia
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData

struct CompleteRoutineWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Routine"
    static var description = IntentDescription("Completes a pending routine from the widget.")

    @Parameter(title: "Routine ID")
    var routineID: String

    @Parameter(title: "Phase ID")
    var phaseID: String?

    init(routineID: String, phaseID: String?) {
        self.routineID = routineID
        self.phaseID = phaseID
    }

    init() {
        self.routineID = ""
        self.phaseID = nil
    }

    func perform() async throws -> some IntentResult {
        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<LureliaRoutine>(
            predicate: #Predicate<LureliaRoutine> { routine in
                routine.persistentID == routineID
            }
        )

        guard let routine = try context.fetch(descriptor).first else {
            return .result()
        }

        if routine.phasesEnabled {
            completeTargetPhase(routine)
        } else {
            routine.completeRoutine()
        }

        try context.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaDueRoutinesWidget")

        return .result()
    }

    private func completeTargetPhase(_ routine: LureliaRoutine) {
        let phases = routine.sortedPhases

        let targetPhase: LureliaRoutinePhase?

        if let phaseID,
           let matchingPhase = phases.first(where: { $0.persistentID == phaseID }) {
            targetPhase = matchingPhase
        } else {
            targetPhase = phases.first { phase in
                routine.tasksForPhase(phase).contains { $0.isPending }
            }
        }

        guard let phase = targetPhase else {
            routine.completeRoutine()
            return
        }

        let phaseTasks = routine.tasksForPhase(phase)

        for task in phaseTasks where task.isPending {
            task.markCompleted()
        }

        routine.updatedAt = Date()

        if routine.allTasksDone {
            routine.lastCompletedAt = Date()
        }
    }

    private func phaseDate(hour: Int, minute: Int, now: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps) ?? now
    }
}
