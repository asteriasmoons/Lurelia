//
//  CompleteHabitWidgetIntent.swift
//  Lurelia
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData

struct CompleteHabitWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Habit"
    static var description = IntentDescription("Logs a completion for a habit from the widget.")

    @Parameter(title: "Habit ID")
    var habitID: String

    init() { }

    init(habitID: String) {
        self.habitID = habitID
    }

    func perform() async throws -> some IntentResult {
        print("🟣 [WidgetIntent] CompleteHabit perform — habitID=\(habitID)")
        defer { reloadHabitWidgets() }

        guard let id = UUID(uuidString: habitID) else {
            print("🟣 [WidgetIntent] CompleteHabit — invalid UUID, bailing")
            return .result()
        }

        let container = try LureliaWidgetShared.makeModelContainer()
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<LureliaHabit>(
            predicate: #Predicate<LureliaHabit> { habit in
                habit.id == id
            }
        )

        guard let habit = try context.fetch(descriptor).first else {
            return .result()
        }

        try logHabitCompletion(habit, in: context)
        try context.save()

        return .result()
    }

    private func logHabitCompletion(_ habit: LureliaHabit, in context: ModelContext) throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let target = habit.target

        let todaysLogs = try context.fetch(FetchDescriptor<LureliaHabitLog>())
            .filter { log in
                (UUID(uuidString: log.habitIDString) ?? log.habit?.id) == habit.id
                    && calendar.isDate(log.dayStart, inSameDayAs: todayStart)
            }

        let log: LureliaHabitLog
        let isNewLog: Bool
        if let existingLog = todaysLogs.max(by: { effectiveCount($0) < effectiveCount($1) }) {
            log = existingLog
            isNewLog = false
            log.habitIDString = habit.id.uuidString
        } else {
            let newLog = LureliaHabitLog(habit: habit, dayStart: todayStart, count: 1)
            log = newLog
            isNewLog = true
            context.insert(log)
            habit.logs = (habit.logs ?? []) + [log]
        }

        let priorCount = isNewLog ? 0 : effectiveCount(log)
        guard priorCount < target else { return }

        let fireDates = habit.fireDates(on: todayStart, calendar: calendar)
        if let fireDate = nextFireDateToComplete(from: fireDates, log: log, calendar: calendar) {
            log.markCompleted(atFireDate: fireDate, calendar: calendar)
            log.count = min(target, max(effectiveCount(log), priorCount + 1))
            log.updatedAt = Date()
        } else {
            log.count = min(target, priorCount + 1)
            log.updatedAt = Date()
        }

        try removeTodaySkip(for: habit, calendar: calendar, todayStart: todayStart, context: context)
        habit.updatedAt = Date()
    }

    private func effectiveCount(_ log: LureliaHabitLog) -> Int {
        max(log.count, log.completedFireTimes.count)
    }

    private func nextFireDateToComplete(
        from fireDates: [Date],
        log: LureliaHabitLog,
        calendar: Calendar
    ) -> Date? {
        guard !fireDates.isEmpty else { return nil }

        let now = Date()
        return fireDates.first {
            $0 <= now && !log.isCompleted(atFireDate: $0, calendar: calendar)
        } ?? fireDates.first {
            !log.isCompleted(atFireDate: $0, calendar: calendar)
        }
    }

    private func removeTodaySkip(
        for habit: LureliaHabit,
        calendar: Calendar,
        todayStart: Date,
        context: ModelContext
    ) throws {
        let todaysSkips = try context.fetch(FetchDescriptor<LureliaHabitSkip>())
            .filter { skip in
                (UUID(uuidString: skip.habitIDString) ?? skip.habit?.id) == habit.id
                    && calendar.isDate(skip.dayStart, inSameDayAs: todayStart)
            }

        for todaySkip in todaysSkips {
            context.delete(todaySkip)
        }

        if !todaysSkips.isEmpty {
            let skipIDs = Set(todaysSkips.map(\.persistentModelID))
            habit.skips = (habit.skips ?? []).filter {
                !skipIDs.contains($0.persistentModelID)
            }
        }
    }

    private func reloadHabitWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaHabitsWidget")
    }
}
