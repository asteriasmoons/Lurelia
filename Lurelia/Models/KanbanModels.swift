//
//  KanbanModels.swift
//  Lurelia
//

import Foundation
import SwiftData

// MARK: - Card Type

enum KanbanCardType: String, Codable {
    case reminder = "reminder"
    case routine = "routine"
    case routineTask = "routineTask"
    case habit = "habit"
    case quickTask = "quickTask"
}

extension LureliaHabit {
    var kanbanItemID: String {
        id.uuidString
    }

    func matchesKanbanItemID(_ itemID: String) -> Bool {
        itemID == kanbanItemID
    }
}

extension LureliaRoutineTask {
    var kanbanItemID: String {
        "\(routine?.persistentID ?? "unlinked")::\(stableTaskID)"
    }

    func matchesKanbanItemID(_ itemID: String) -> Bool {
        itemID == kanbanItemID || itemID == stableTaskID
    }
}

// MARK: - KanbanBoard

@Model
final class KanbanBoard {

    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "starcal"
    var colorHex: String = "#03dbfc"
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \KanbanColumn.board)
    var columns: [KanbanColumn]?

    init(name: String, icon: String = "starcal", colorHex: String = "#03dbfc", sortOrder: Int = 0) {
        self.id        = UUID()
        self.name      = name
        self.icon      = icon
        self.colorHex  = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedColumns: [KanbanColumn] {
        (columns ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - KanbanColumn

@Model
final class KanbanColumn {

    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#03dbfc"
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var board: KanbanBoard?

    @Relationship(deleteRule: .cascade, inverse: \KanbanCard.column)
    var cards: [KanbanCard]?

    @Relationship(deleteRule: .cascade, inverse: \KanbanQuickTask.column)
    var quickTasks: [KanbanQuickTask]?

    init(name: String, colorHex: String = "#03dbfc", sortOrder: Int = 0) {
        self.id        = UUID()
        self.name      = name
        self.colorHex  = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var sortedCards: [KanbanCard] {
        (cards ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - KanbanQuickTask

@Model
final class KanbanQuickTask {

    var id: UUID = UUID()
    var name: String = ""
    var details: String = ""
    var taskDate: Date?
    var taskTime: Date?
    var isCompleted: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var column: KanbanColumn?

    init(
        name: String,
        details: String = "",
        taskDate: Date? = nil,
        taskTime: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.details = details
        self.taskDate = taskDate
        self.taskTime = taskDate == nil ? nil : taskTime
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kanbanItemID: String {
        id.uuidString
    }

    func matchesKanbanItemID(_ itemID: String) -> Bool {
        itemID == kanbanItemID
    }

    func timelineDate(calendar: Calendar = .current) -> Date? {
        guard let taskDate else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: taskDate)
        if let taskTime {
            let timeComponents = calendar.dateComponents([.hour, .minute], from: taskTime)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
        } else {
            components.hour = 0
            components.minute = 0
        }
        components.second = 0

        return calendar.date(from: components)
    }
}

// MARK: - KanbanCard

@Model
final class KanbanCard {

    var id: UUID = UUID()
    var cardType: KanbanCardType = KanbanCardType.reminder
    var itemID: String = ""   // Stable ID of the linked Kanban item
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var column: KanbanColumn?

    init(cardType: KanbanCardType, itemID: UUID, sortOrder: Int = 0) {
        self.id        = UUID()
        self.cardType  = cardType
        self.itemID    = itemID.uuidString
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
