//
//  SkipHabitWidgetIntent.swift
//  Lurelia
//

import Foundation
import AppIntents
import WidgetKit
import SwiftData

struct SkipHabitWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Habit"
    static var description = IntentDescription("Skips a habit for today from the widget.")

    @Parameter(title: "Habit ID")
    var habitID: String

    init() { }

    init(habitID: String) {
        self.habitID = habitID
    }

    func perform() async throws -> some IntentResult {
        print("🟣 [WidgetIntent] SkipHabit perform — habitID=\(habitID)")
        defer { reloadHabitWidgets() }

        guard let id = UUID(uuidString: habitID) else {
            print("🟣 [WidgetIntent] SkipHabit — invalid UUID, bailing")
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

        try skipHabitToday(habit, in: context)
        try context.save()

        return .result()
    }

    private func skipHabitToday(_ habit: LureliaHabit, in context: ModelContext) throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        let logs = try context.fetch(FetchDescriptor<LureliaHabitLog>())
        let skips = try context.fetch(FetchDescriptor<LureliaHabitSkip>())

        let hasLog = logs.contains { log in
            (UUID(uuidString: log.habitIDString) ?? log.habit?.id) == habit.id
                && calendar.isDate(log.dayStart, inSameDayAs: todayStart)
                && max(log.count, log.completedFireTimes.count) > 0
        }
        guard !hasLog else { return }

        let hasSkip = skips.contains { skip in
            (UUID(uuidString: skip.habitIDString) ?? skip.habit?.id) == habit.id
                && calendar.isDate(skip.dayStart, inSameDayAs: todayStart)
        }
        guard !hasSkip else { return }

        let skip = LureliaHabitSkip(habit: habit, dayStart: todayStart)
        skip.habitIDString = habit.id.uuidString
        context.insert(skip)
        habit.skips = (habit.skips ?? []) + [skip]
        habit.updatedAt = Date()
    }

    private func reloadHabitWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "LureliaHabitsWidget")
    }
}
