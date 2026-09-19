//
//  RoutineEntity.swift
//  Lurelia
//
//  Shortcuts / App Intents representation of a saved Lurelia routine
//  (`LureliaRoutine`). This is a thin, Sendable value type — the source of
//  truth remains the existing SwiftData store, reached through
//  `LureliaRoutineIntentStore`.
//

import Foundation
import AppIntents

struct RoutineEntity: AppEntity, Identifiable {

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Routine")
    }

    static var defaultQuery = RoutineEntityQuery()

    /// Stable identifier tied to the real routine (`LureliaRoutine.persistentID`).
    var id: String

    /// The routine's real display name, exposed to Shortcuts as a property so
    /// it can be pulled out as a Magic Variable ("Routine Name").
    @Property(title: "Routine Name")
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// Builds the entity from the live model without letting the model escape.
    init(routine: LureliaRoutine) {
        self.id = routine.persistentID
        self.name = routine.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - Query

/// Backs the Routine parameter picker with the user's actual saved routines,
/// read live from Lurelia's persistence. Names are never hardcoded.
struct RoutineEntityQuery: EntityQuery, EntityStringQuery {

    /// Resolve a previously-selected routine by identifier.
    func entities(for identifiers: [RoutineEntity.ID]) async throws -> [RoutineEntity] {
        try await LureliaRoutineIntentStore.routines(for: identifiers)
    }

    /// Populate the picker with every saved routine.
    func suggestedEntities() async throws -> [RoutineEntity] {
        try await LureliaRoutineIntentStore.allRoutines()
    }

    /// Type-to-filter search within the picker.
    func entities(matching string: String) async throws -> [RoutineEntity] {
        try await LureliaRoutineIntentStore.routines(matching: string)
    }
}
