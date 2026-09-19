//
//  LureliaRoutineIntentStore.swift
//  Lurelia
//
//  Read-only bridge between the App Intents / Shortcuts layer and Lurelia's
//  existing SwiftData persistence. Every lookup here opens the *same* shared
//  App Group store the app and widgets use (`LureliaWidgetShared`), so
//  Shortcuts always sees the user's real, current routines and tasks. No
//  separate storage is created.
//
//  The helpers return lightweight, Sendable value structs (`RoutineEntity` /
//  `RoutineTaskEntity`) built synchronously from the fetched `@Model` objects,
//  so no SwiftData model instance ever escapes the local `ModelContext`.
//

import Foundation
import SwiftData

enum LureliaRoutineIntentStore {

    // MARK: - Context

    /// Opens a context onto Lurelia's shared SwiftData store. Mirrors the
    /// access pattern used by the widget App Intents.
    private static func makeContext() throws -> ModelContext {
        let container = try LureliaWidgetShared.makeModelContainer()
        return ModelContext(container)
    }

    // MARK: - Routines

    /// Every saved routine, ordered the same way the app lists them
    /// (sortOrder, then creation date). Powers the Shortcuts routine picker.
    static func allRoutines() throws -> [RoutineEntity] {
        let context = try makeContext()
        let routines = try context.fetch(FetchDescriptor<LureliaRoutine>())
        return sortedEntities(from: routines)
    }

    /// Resolves specific routines by their stable identifier
    /// (`LureliaRoutine.persistentID`). Used by the EntityQuery to rebuild a
    /// previously-selected routine.
    static func routines(for ids: [String]) throws -> [RoutineEntity] {
        let context = try makeContext()
        let routines = try context.fetch(FetchDescriptor<LureliaRoutine>())
        let byID = Dictionary(routines.map { ($0.persistentID, $0) }) { first, _ in first }
        return ids.compactMap { byID[$0] }.map(RoutineEntity.init(routine:))
    }

    /// Routines whose name contains the given search string (case/diacritic
    /// insensitive). Backs type-to-filter in the Shortcuts picker.
    static func routines(matching query: String) throws -> [RoutineEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try allRoutines() }

        let context = try makeContext()
        let routines = try context.fetch(FetchDescriptor<LureliaRoutine>())
        let matches = routines.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return sortedEntities(from: matches)
    }

    private static func sortedEntities(from routines: [LureliaRoutine]) -> [RoutineEntity] {
        routines
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
            .map(RoutineEntity.init(routine:))
    }

    // MARK: - Routine Tasks

    /// The real tasks belonging to a single routine, in the routine's own
    /// task order (`LureliaRoutine.sortedTasks`).
    static func tasks(forRoutineID routineID: String) throws -> [RoutineTaskEntity] {
        let context = try makeContext()
        let descriptor = FetchDescriptor<LureliaRoutine>(
            predicate: #Predicate<LureliaRoutine> { routine in
                routine.persistentID == routineID
            }
        )
        guard let routine = try context.fetch(descriptor).first else { return [] }
        return routine.sortedTasks.map(RoutineTaskEntity.init(task:))
    }

    /// Resolves specific tasks by their routine-scoped identifier. Also accepts
    /// a bare `stableTaskID` for backwards compatibility, matching the widget
    /// intents' lenient resolution.
    static func tasks(for ids: [String]) throws -> [RoutineTaskEntity] {
        let context = try makeContext()
        let tasks = try context.fetch(FetchDescriptor<LureliaRoutineTask>())

        return ids.compactMap { id in
            if let exact = tasks.first(where: { $0.routineScopedTaskID == id }) {
                return RoutineTaskEntity(task: exact)
            }
            let legacy = tasks.filter { $0.matchesRoutineScopedTaskID(id) }
            return legacy.count == 1 ? legacy.first.map(RoutineTaskEntity.init(task:)) : nil
        }
    }
}
