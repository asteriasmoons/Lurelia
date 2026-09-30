//
//  KanbanTimelineEngine.swift
//  Lurelia
//
//  Shared Kanban Timeline occurrence engine — extracted from
//  `KanbanTimelineView` so widgets (and any other future consumer) can
//  reuse the exact same "which cards fire when, for which column, on
//  which day" logic without reimplementing it.
//
//  Public surface:
//    • `KanbanTimelineOccurrenceKind` — item kind + associated identity
//    • `KanbanTimelineOccurrence` — one card firing at one time
//    • `KanbanTimelineColumnOccurrence` — one (column × fireDate) pair,
//      used by the app's timeline layout
//    • `KanbanTimelineEngine.occurrences(...)` — per-card list across
//      every column of a board (what the Timeline widget consumes)
//    • `KanbanTimelineEngine.columnOccurrences(...)` — deduped (column,
//      fireDate) list (what the app's Kanban Timeline scroll view
//      consumes)
//
//  Adding this file to the widget target lets `LureliaKanbanTimelineWidget`
//  reuse the same code path the in-app timeline already uses.
//

import Foundation
import SwiftData

// MARK: - Occurrence kinds / models

enum KanbanTimelineOccurrenceKind: Hashable {
    case reminder(String)
    case routine(String)
    case routineTask(String)
    case habit(String)
    case quickTask(String)

    var idFragment: String {
        switch self {
        case .reminder(let id):     return "reminder-\(id)"
        case .routine(let id):      return "routine-\(id)"
        case .routineTask(let id):  return "routineTask-\(id)"
        case .habit(let id):        return "habit-\(id)"
        case .quickTask(let id):    return "quickTask-\(id)"
        }
    }
}

struct KanbanTimelineOccurrence: Identifiable {
    let card: KanbanCard
    let kind: KanbanTimelineOccurrenceKind
    let fireDate: Date
    let column: KanbanColumn?

    init(
        card: KanbanCard,
        kind: KanbanTimelineOccurrenceKind,
        fireDate: Date,
        column: KanbanColumn? = nil
    ) {
        self.card = card
        self.kind = kind
        self.fireDate = fireDate
        self.column = column ?? card.column
    }

    var id: String {
        "\(card.id.uuidString)-\(kind.idFragment)-\(fireDate.timeIntervalSince1970)"
    }
}

struct KanbanTimelineColumnOccurrence: Identifiable {
    let column: KanbanColumn
    let fireDate: Date

    var id: String {
        "\(column.id.uuidString)-\(fireDate.timeIntervalSince1970)"
    }
}

// MARK: - Engine

enum KanbanTimelineEngine {

    // MARK: Public API

    /// Every card in `board` that has at least one fire date on `day`,
    /// exploded per fire date (so a 3-times-a-day habit produces three
    /// occurrences). Same rules as the in-app timeline, including the
    /// "keep completed items visible on today's timeline" and the
    /// "only show most-recent missed occurrence for overdue reminders
    /// on today" rules.
    static func occurrences(
        for board: KanbanBoard,
        on day: Date,
        allReminders: [LureliaReminder],
        allRoutines: [LureliaRoutine],
        allRoutineTasks: [LureliaRoutineTask],
        allHabits: [LureliaHabit],
        allQuickTasks: [KanbanQuickTask] = [],
        calendar: Calendar = .current
    ) -> [KanbanTimelineOccurrence] {
        let ctx = Context(
            selectedDay: day,
            calendar: calendar,
            allReminders: allReminders,
            allRoutines: allRoutines,
            allRoutineTasks: allRoutineTasks,
            allHabits: allHabits,
            allQuickTasks: allQuickTasks
        )

        var result: [KanbanTimelineOccurrence] = []

        for column in board.sortedColumns {
            for card in column.sortedCards {
                let fireDates = expandFireDates(for: card, in: ctx)
                for fireDate in fireDates {
                    let kind = kindFor(card: card, in: ctx)
                    result.append(
                        KanbanTimelineOccurrence(
                            card: card,
                            kind: kind,
                            fireDate: fireDate,
                            column: column
                        )
                    )
                }
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate {
                return lhs.fireDate < rhs.fireDate
            }
            let lSort = lhs.column?.sortOrder ?? 0
            let rSort = rhs.column?.sortOrder ?? 0
            if lSort != rSort { return lSort < rSort }
            return lhs.card.sortOrder < rhs.card.sortOrder
        }
    }

    /// Deduped (column × fireDate) pairs, sorted by fireDate then column
    /// sort order. This is what the in-app Kanban Timeline scroll view
    /// consumes so each fireDate → column combo renders exactly once.
    static func columnOccurrences(
        for board: KanbanBoard,
        on day: Date,
        allReminders: [LureliaReminder],
        allRoutines: [LureliaRoutine],
        allRoutineTasks: [LureliaRoutineTask],
        allHabits: [LureliaHabit],
        allQuickTasks: [KanbanQuickTask] = [],
        calendar: Calendar = .current
    ) -> [KanbanTimelineColumnOccurrence] {
        let raw = occurrences(
            for: board,
            on: day,
            allReminders: allReminders,
            allRoutines: allRoutines,
            allRoutineTasks: allRoutineTasks,
            allHabits: allHabits,
            allQuickTasks: allQuickTasks,
            calendar: calendar
        )

        var seen: Set<String> = []
        var result: [KanbanTimelineColumnOccurrence] = []
        for occ in raw {
            guard let column = occ.column else { continue }
            let key = "\(column.id.uuidString)::\(occ.fireDate.timeIntervalSince1970)"
            if seen.insert(key).inserted {
                result.append(
                    KanbanTimelineColumnOccurrence(
                        column: column,
                        fireDate: occ.fireDate
                    )
                )
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.column.sortOrder < rhs.column.sortOrder
        }
    }

    // MARK: Internal per-day context

    private struct Context {
        let selectedDay: Date
        let calendar: Calendar
        let allReminders: [LureliaReminder]
        let allRoutines: [LureliaRoutine]
        let allRoutineTasks: [LureliaRoutineTask]
        let allHabits: [LureliaHabit]
        let allQuickTasks: [KanbanQuickTask]

        let remindersByID: [String: LureliaReminder]
        let routinesByID: [String: LureliaRoutine]
        let habitsByKanbanID: [String: LureliaHabit]
        let routineTasksByKanbanID: [String: LureliaRoutineTask]
        let quickTasksByKanbanID: [String: KanbanQuickTask]
        let startOfSelectedDay: Date
        let timelineStart: Date
        let timelineEnd: Date
        let showOverdue: Bool

        init(
            selectedDay: Date,
            calendar: Calendar,
            allReminders: [LureliaReminder],
            allRoutines: [LureliaRoutine],
            allRoutineTasks: [LureliaRoutineTask],
            allHabits: [LureliaHabit],
            allQuickTasks: [KanbanQuickTask]
        ) {
            self.selectedDay = selectedDay
            self.calendar = calendar
            self.allReminders = allReminders
            self.allRoutines = allRoutines
            self.allRoutineTasks = allRoutineTasks
            self.allHabits = allHabits
            self.allQuickTasks = allQuickTasks

            self.remindersByID = Dictionary(
                uniqueKeysWithValues: allReminders.map { ($0.id.uuidString, $0) }
            )
            self.routinesByID = Dictionary(
                uniqueKeysWithValues: allRoutines.map { ($0.persistentID, $0) }
            )
            self.habitsByKanbanID = Dictionary(
                allHabits.map { ($0.kanbanItemID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            self.routineTasksByKanbanID = Dictionary(
                allRoutineTasks.map { ($0.kanbanItemID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            self.quickTasksByKanbanID = Dictionary(
                allQuickTasks.map { ($0.kanbanItemID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let start = calendar.startOfDay(for: selectedDay)
            self.startOfSelectedDay = start
            self.timelineStart = start
            self.timelineEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? selectedDay
            self.showOverdue = calendar.isDateInToday(selectedDay)
        }
    }

    // MARK: Helpers (mirrors of the pre-extraction view helpers)

    private static func expandFireDates(
        for card: KanbanCard,
        in ctx: Context
    ) -> [Date] {
        switch card.cardType {
        case .reminder:
            return reminderFireDates(for: card, in: ctx)
        case .routine:
            return routineFireDates(for: card, in: ctx)
        case .routineTask:
            return routineTaskFireDates(for: card, in: ctx)
        case .habit:
            return habitFireDates(for: card, in: ctx)
        case .quickTask:
            return quickTaskFireDates(for: card, in: ctx)
        }
    }

    private static func kindFor(
        card: KanbanCard,
        in ctx: Context
    ) -> KanbanTimelineOccurrenceKind {
        switch card.cardType {
        case .reminder:
            return .reminder(card.itemID)
        case .routine:
            return .routine(card.itemID)
        case .routineTask:
            let resolved = routineTaskLookup(card.itemID, in: ctx)?.kanbanItemID ?? card.itemID
            return .routineTask(resolved)
        case .habit:
            return .habit(card.itemID)
        case .quickTask:
            return .quickTask(card.itemID)
        }
    }

    // MARK: - Quick Tasks

    private static func quickTaskFireDates(
        for card: KanbanCard,
        in ctx: Context
    ) -> [Date] {
        guard let task = ctx.quickTasksByKanbanID[card.itemID],
              let fireDate = task.timelineDate(calendar: ctx.calendar),
              ctx.calendar.isDate(fireDate, inSameDayAs: ctx.selectedDay)
        else {
            return []
        }

        return [fireDate]
    }

    // MARK: - Reminders

    private static func reminderFireDates(
        for card: KanbanCard,
        in ctx: Context
    ) -> [Date] {
        guard let reminder = ctx.remindersByID[card.itemID] else { return [] }

        var result: [Date] = []

        if reminder.isDue(on: ctx.selectedDay, calendar: ctx.calendar) {
            let dayFireDates = fireDates(for: reminder, on: ctx.selectedDay, in: ctx)
            for fireDate in dayFireDates
                where fireDate >= ctx.timelineStart && fireDate < ctx.timelineEnd {
                result.append(fireDate)
            }
        }

        if ctx.showOverdue {
            for missedDay in overdueDays(for: reminder, before: ctx.startOfSelectedDay, in: ctx) {
                let dayFireDates = fireDates(for: reminder, on: missedDay, in: ctx)
                for fireDate in dayFireDates
                    where !isOccurrenceCompleted(reminder, fireDate: fireDate, allFireDates: dayFireDates, on: missedDay, in: ctx) {
                    result.append(fireDate)
                }
            }
        }

        return result
    }

    private static func fireDates(
        for reminder: LureliaReminder,
        on day: Date,
        in ctx: Context
    ) -> [Date] {
        let dayComponents = ctx.calendar.dateComponents([.year, .month, .day], from: day)
        let times = resolvedTimesOfDay(for: reminder, in: ctx)

        return times.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else { return nil }

            var components = dayComponents
            components.hour = hour
            components.minute = minute
            components.second = 0
            return ctx.calendar.date(from: components)
        }
        .sorted()
    }

    private static func resolvedTimesOfDay(
        for reminder: LureliaReminder,
        in ctx: Context
    ) -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }
        if !stored.isEmpty { return stored }

        let hour = reminder.primaryHour != -1
            ? reminder.primaryHour
            : ctx.calendar.component(.hour, from: reminder.scheduledDate)
        let minute = reminder.primaryMinute != -1
            ? reminder.primaryMinute
            : ctx.calendar.component(.minute, from: reminder.scheduledDate)

        var times = [String(format: "%02d:%02d", hour, minute)]
        for fireTime in reminder.additionalFireTimes {
            times.append(String(format: "%02d:%02d", fireTime.hour, fireTime.minute))
        }
        return times
    }

    private static func overdueDays(
        for reminder: LureliaReminder,
        before startOfDay: Date,
        in ctx: Context
    ) -> [Date] {
        guard reminder.kind == .standalone, reminder.isEnabled else { return [] }

        let scheduledDay = ctx.calendar.startOfDay(for: reminder.scheduledDate)
        guard scheduledDay < startOfDay else { return [] }

        if reminder.repeatUnit == .none {
            return reminder.isCompleted ? [] : [scheduledDay]
        }

        let daysBetween = ctx.calendar.dateComponents([.day], from: scheduledDay, to: startOfDay).day ?? 0
        let lookback = min(max(daysBetween, 0), 30)
        guard lookback > 0 else { return [] }

        for daysBack in 1...lookback {
            guard let pastDay = ctx.calendar.date(byAdding: .day, value: -daysBack, to: startOfDay) else { continue }

            if reminder.isDue(on: pastDay, calendar: ctx.calendar) {
                if reminder.wasCompleted(on: pastDay, calendar: ctx.calendar) {
                    return []
                }
                return [pastDay]
            }
        }
        return []
    }

    private static func isOccurrenceCompleted(
        _ reminder: LureliaReminder,
        fireDate: Date,
        allFireDates: [Date],
        on day: Date,
        in ctx: Context
    ) -> Bool {
        let completions = ([reminder.completedAt].compactMap { $0 } + reminder.completionTimestamps)
            .filter { ctx.calendar.isDate($0, inSameDayAs: day) }

        guard !completions.isEmpty else { return false }

        let sortedFireDates = allFireDates.sorted()
        guard let index = sortedFireDates.firstIndex(of: fireDate) else {
            return reminder.wasCompleted(on: day, calendar: ctx.calendar)
        }

        let nextFireDate: Date? = {
            let nextIndex = index + 1
            guard sortedFireDates.indices.contains(nextIndex) else { return nil }
            return sortedFireDates[nextIndex]
        }()

        return completions.contains { completedAt in
            completedAt >= fireDate &&
            (nextFireDate == nil || completedAt < nextFireDate!)
        }
    }

    // MARK: - Routines

    private static func routineFireDates(
        for card: KanbanCard,
        in ctx: Context
    ) -> [Date] {
        guard let routine = ctx.routinesByID[card.itemID],
              let fireDate = routineFireDate(routine, on: ctx.selectedDay, in: ctx),
              fireDate >= ctx.timelineStart,
              fireDate < ctx.timelineEnd
        else { return [] }
        return [fireDate]
    }

    private static func routineFireDate(
        _ routine: LureliaRoutine,
        on day: Date,
        in ctx: Context
    ) -> Date? {
        guard routine.scheduleEnabled else { return nil }
        let weekday = ctx.calendar.component(.weekday, from: day)
        if !routine.scheduledDays.isEmpty, !routine.scheduledDays.contains(weekday) {
            return nil
        }
        return dateOn(day: day, hour: routine.startHour, minute: routine.startMinute, in: ctx)
    }

    // MARK: - Routine tasks

    private static func routineTaskFireDates(
        for card: KanbanCard,
        in ctx: Context
    ) -> [Date] {
        guard let task = routineTaskLookup(card.itemID, in: ctx),
              let fireDate = routineTaskFireDate(task, on: ctx.selectedDay, in: ctx),
              fireDate >= ctx.timelineStart,
              fireDate < ctx.timelineEnd
        else { return [] }
        return [fireDate]
    }

    private static func routineTaskLookup(
        _ itemID: String,
        in ctx: Context
    ) -> LureliaRoutineTask? {
        if let hit = ctx.routineTasksByKanbanID[itemID] { return hit }
        // Legacy bare-stableTaskID fallback: only return if EXACTLY one
        // task matches so we don't silently bind to the wrong routine's
        // task when two share the same title+sortOrder.
        let matches = ctx.allRoutineTasks.filter { $0.matchesKanbanItemID(itemID) }
        return matches.count == 1 ? matches.first : nil
    }

    private static func routineTaskFireDate(
        _ task: LureliaRoutineTask,
        on day: Date,
        in ctx: Context
    ) -> Date? {
        guard task.hasDueTime else { return nil }
        let weekday = ctx.calendar.component(.weekday, from: day)

        if task.repeatsOnDays {
            if !task.scheduledDays.isEmpty, !task.scheduledDays.contains(weekday) {
                return nil
            }
        } else if let routine = task.routine,
                  routine.scheduleEnabled,
                  !routine.scheduledDays.isEmpty,
                  !routine.scheduledDays.contains(weekday) {
            return nil
        }

        return dateOn(day: day, hour: task.dueHour, minute: task.dueMinute, in: ctx)
    }

    // MARK: - Habits

    private static func habitFireDates(
        for card: KanbanCard,
        in ctx: Context
    ) -> [Date] {
        guard let habit = ctx.habitsByKanbanID[card.itemID] else { return [] }
        return habit.fireDates(on: ctx.selectedDay, calendar: ctx.calendar)
            .filter { $0 >= ctx.timelineStart && $0 < ctx.timelineEnd }
    }

    // MARK: - Utility

    private static func dateOn(day: Date, hour: Int, minute: Int, in ctx: Context) -> Date? {
        var components = ctx.calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return ctx.calendar.date(from: components)
    }
}
