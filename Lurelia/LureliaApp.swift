//
//  LureliaApp.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import WidgetKit
import UIKit

@main
struct LureliaApp: App {
    @UIApplicationDelegateAdaptor(LureliaAppDelegate.self) var delegate

    var sharedModelContainer: ModelContainer = {
        LureliaWidgetShared.migrateLocalStoreToAppGroupIfNeeded()

        do {
            return try LureliaWidgetShared.makeModelContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase
    @State private var routineMidnightResetTask: Task<Void, Never>?
    @StateObject private var reportRouter = LureliaReportRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(reportRouter)
                .task {
                    await purgeOrphanedReminders()
                    await backfillReminderFireTimes()
                    await backfillReminderHistoryEntries()
                    await migrateReminderModelsToAppGroup()
                    await migrateTaskModelsToAppGroup()
                    await migrateKanbanModelsToAppGroup()
                    await migrateHabitModelsToAppGroup()
                    await migrateHabitLogsAndSkipsToAppGroup()
                    await backfillHabitCompletionFireTimes()
                    await migrateJourneyModelsToAppGroup()
                    await migrateRoutineModelsToAppGroup()
                    await migrateRoutineStatsAndUserSettingsToAppGroup()
                    await deduplicateModelsAfterSchemaRepair()
                    await deduplicateAllChildEntities()
                    await exportReminderIconsForWidget()
                    HabitManager.shared.setup(container: sharedModelContainer)
                    RoutineTaskManager.shared.setup(container: sharedModelContainer)
                    RoutineManager.shared.resetRoutinesIfNewDay(context: sharedModelContainer.mainContext)
                    scheduleRoutineMidnightReset()


                    print("🧪 LureliaApp directly triggering notification reschedule")

                    LureliaNotificationManager.shared.dumpAllNotificationCenterState(source: "LureliaApp before direct reschedule")

                    LureliaNotificationManager.shared.rescheduleAll(from: sharedModelContainer)
                    LureliaEventNotificationManager.shared.rescheduleAll(from: sharedModelContainer)

                    // Shared event platform: bind the offline mutation
                    // queue to the SwiftData context and kick off the
                    // drain so any mutations captured while offline get
                    // replayed to vox-api on next launch.
                    OfflineMutationQueue.shared.bind(to: sharedModelContainer.mainContext)
                    OfflineMutationQueue.shared.startDraining(
                        applyMutation: SharedEventsService.replay,
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        LureliaNotificationManager.shared.dumpAllNotificationCenterState(source: "LureliaApp after direct reschedule")
                        LureliaNotificationManager.shared.dumpLureliaPendingNotifications(source: "LureliaApp after direct reschedule")
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Replay any mutations queued while offline.
                        OfflineMutationQueue.shared.startDraining(
                            applyMutation: SharedEventsService.replay,
                        )
                        Task {
                            RoutineManager.shared.resetRoutinesIfNewDay(context: sharedModelContainer.mainContext)
                            scheduleRoutineMidnightReset()
                            await exportReminderIconsForWidget()
                            LureliaWidgetReloads.reloadAll()
                            LureliaWidgetReloads.reloadAll()
                            LureliaWidgetReloads.reloadAll()
                        }
                    } else if newPhase == .background {
                        routineMidnightResetTask?.cancel()
                        routineMidnightResetTask = nil
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func scheduleRoutineMidnightReset() {
        routineMidnightResetTask?.cancel()

        let now = Date()
        let nextMidnight = Calendar.current.dateInterval(of: .day, for: now)?.end
            ?? Calendar.current.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(24 * 60 * 60)
        let delay = max(1, nextMidnight.timeIntervalSince(now))
        let nanoseconds = UInt64(delay * 1_000_000_000)

        routineMidnightResetTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            RoutineManager.shared.resetRoutinesIfNewDay(context: sharedModelContainer.mainContext)
            scheduleRoutineMidnightReset()
        }
    }

    // Backfills timesOfDay and primaryHour/primaryMinute for all existing reminders
    // that were created before these fields existed. Runs once on launch, is a no-op
    // for reminders already backfilled.
    private func backfillReminderFireTimes() async {
        let context = sharedModelContainer.mainContext
        let cal = Calendar.current
        guard let reminders = try? context.fetch(FetchDescriptor<LureliaReminder>()) else { return }

        var changed = false
        for reminder in reminders {
            // Already backfilled
            if !reminder.timesOfDay.isEmpty && reminder.primaryHour != -1 { continue }

            let scheduledDate = reminder.scheduledDate

            // Derive primary hour/minute from scheduledDate
            let ph = reminder.primaryHour != -1
                ? reminder.primaryHour
                : cal.component(.hour, from: scheduledDate)
            let pm = reminder.primaryMinute != -1
                ? reminder.primaryMinute
                : cal.component(.minute, from: scheduledDate)

            if reminder.primaryHour == -1 {
                reminder.primaryHour = ph
                reminder.primaryMinute = pm
            }

            if reminder.timesOfDay.isEmpty {
                var times = [String(format: "%02d:%02d", ph, pm)]
                for ft in reminder.additionalFireTimes {
                    times.append(String(format: "%02d:%02d", ft.hour, ft.minute))
                }
                reminder.timesOfDay = times
            }

            changed = true
        }

        if changed {
            try? context.save()
            print("[Lurelia] Backfilled timesOfDay for existing reminders")
        }
    }

    // Creates history rows from the old completion/skipped timestamp arrays.
    // This lets the new overview counts use LureliaReminderHistory without losing old data.
    private func backfillReminderHistoryEntries() async {
        let context = sharedModelContainer.mainContext
        let cal = Calendar.current

        guard let reminders = try? context.fetch(FetchDescriptor<LureliaReminder>()) else { return }
        let existingHistory = (try? context.fetch(FetchDescriptor<LureliaReminderHistory>())) ?? []
        var existingKeys = Set<String>()

        for entry in existingHistory {
            existingKeys.insert(historyBackfillKey(
                reminderID: entry.reminderID,
                action: entry.action,
                occurrenceDate: entry.occurrenceDate,
                calendar: cal
            ))
        }

        var changed = false

        for reminder in reminders {
            for occurrenceDate in reminder.completionTimestamps {
                let key = historyBackfillKey(
                    reminderID: reminder.id,
                    action: .completed,
                    occurrenceDate: occurrenceDate,
                    calendar: cal
                )

                guard !existingKeys.contains(key) else { continue }

                let entry = LureliaReminderHistory(
                    reminder: reminder,
                    action: .completed,
                    occurrenceDate: occurrenceDate,
                    actionDate: occurrenceDate
                )

                context.insert(entry)
                existingKeys.insert(key)
                changed = true
            }

            for occurrenceDate in reminder.skippedTimestamps {
                let key = historyBackfillKey(
                    reminderID: reminder.id,
                    action: .skipped,
                    occurrenceDate: occurrenceDate,
                    calendar: cal
                )

                guard !existingKeys.contains(key) else { continue }

                let entry = LureliaReminderHistory(
                    reminder: reminder,
                    action: .skipped,
                    occurrenceDate: occurrenceDate,
                    actionDate: occurrenceDate
                )

                context.insert(entry)
                existingKeys.insert(key)
                changed = true
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Backfilled reminder history entries")
        }
    }

    private func migrateTaskModelsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateTaskModelsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        var changed = false

        if let tasks = try? context.fetch(FetchDescriptor<LureliaTask>()) {
            for task in tasks {
                let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if task.title != trimmedTitle {
                    task.title = trimmedTitle
                    changed = true
                }

                if task.title.isEmpty {
                    task.title = "Untitled Task"
                    changed = true
                }

                let trimmedCategory = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
                if task.category != trimmedCategory {
                    task.category = trimmedCategory
                    changed = true
                }

                if task.stableTaskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    task.stableTaskID = "task::\(task.title.lowercased())::\(task.id.uuidString)"
                    changed = true
                }

                if let notes = task.notes {
                    let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedNotes.isEmpty {
                        task.notes = nil
                        changed = true
                    } else if task.notes != trimmedNotes {
                        task.notes = trimmedNotes
                        changed = true
                    }
                }

                if task.coinReward < 0 {
                    task.coinReward = 0
                    changed = true
                }

                if task.isCompleted, task.completedAt == nil {
                    task.completedAt = Date()
                    changed = true
                }

                if !task.isCompleted, task.completedAt != nil {
                    task.completedAt = nil
                    changed = true
                }

                if task.isCompleted, task.isMarkedIncomplete {
                    task.isMarkedIncomplete = false
                    changed = true
                }

                if task.hasReminder, task.reminderDate == nil {
                    task.hasReminder = false
                    changed = true
                }

                if !task.hasReminder, task.reminderDate != nil {
                    task.reminderDate = nil
                    changed = true
                }

                if task.hasTimeBlock {
                    if task.startTime == nil || task.endTime == nil {
                        task.hasTimeBlock = false
                        task.startTime = nil
                        task.endTime = nil
                        changed = true
                    } else if let start = task.startTime,
                              let end = task.endTime,
                              end <= start {
                        task.endTime = Calendar.current.date(byAdding: .minute, value: 30, to: start)
                        changed = true
                    }
                } else if task.startTime != nil || task.endTime != nil {
                    task.startTime = nil
                    task.endTime = nil
                    changed = true
                }

                if let routineName = task.routineName {
                    let trimmedRoutineName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedRoutineName.isEmpty {
                        task.routineName = nil
                        task.isRoutineTask = false
                        task.routineOrder = 0
                        changed = true
                    } else if task.routineName != trimmedRoutineName {
                        task.routineName = trimmedRoutineName
                        changed = true
                    }
                }

                if task.routineName == nil, task.isRoutineTask {
                    task.isRoutineTask = false
                    task.routineOrder = 0
                    changed = true
                }

                if task.routineOrder < 0 {
                    task.routineOrder = 0
                    changed = true
                }

                if task.createdAt > Date() {
                    task.createdAt = Date()
                    changed = true
                }

                if task.updatedAt < task.createdAt {
                    task.updatedAt = task.createdAt
                    changed = true
                }

                if task.isSelectedToday, task.selectedDate == nil {
                    task.selectedDate = Date()
                    changed = true
                }

                if !task.isSelectedToday, task.selectedDate != nil, !Calendar.current.isDateInToday(task.selectedDate ?? Date.distantPast) {
                    task.selectedDate = nil
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated task models to App Group container")
        }

        defaults.set(true, forKey: migrationKey)
    }

    private func migrateReminderModelsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateReminderModelsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        let calendar = Calendar.current
        var changed = false

        if let reminders = try? context.fetch(FetchDescriptor<LureliaReminder>()) {
            for reminder in reminders {
                let trimmedTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if reminder.title != trimmedTitle {
                    reminder.title = trimmedTitle
                    changed = true
                }

                if reminder.title.isEmpty {
                    reminder.title = "Untitled Reminder"
                    changed = true
                }

                if reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reminder.icon = "bellfill"
                    changed = true
                }

                let trimmedCategory = reminder.category.trimmingCharacters(in: .whitespacesAndNewlines)
                if reminder.category != trimmedCategory {
                    reminder.category = trimmedCategory
                    changed = true
                }

                if reminder.repeatInterval < 1 {
                    reminder.repeatInterval = 1
                    changed = true
                }

                if reminder.notificationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    reminder.notificationID = UUID().uuidString
                    changed = true
                }

                let scheduledComponents = calendar.dateComponents([.hour, .minute], from: reminder.scheduledDate)
                let scheduledHour = scheduledComponents.hour ?? 0
                let scheduledMinute = scheduledComponents.minute ?? 0

                if reminder.primaryHour == -1 {
                    reminder.primaryHour = scheduledHour
                    changed = true
                }

                if reminder.primaryMinute == -1 {
                    reminder.primaryMinute = scheduledMinute
                    changed = true
                }

                if !isValidTimeStringArrayJSON(reminder.timesOfDayStorage) || reminder.timesOfDay.isEmpty {
                    var times = [String(format: "%02d:%02d", reminder.primaryHour, reminder.primaryMinute)]
                    for fireTime in reminder.additionalFireTimes {
                        times.append(String(format: "%02d:%02d", fireTime.hour, fireTime.minute))
                    }
                    reminder.timesOfDay = Array(Set(times)).sorted()
                    changed = true
                }

                if !isValidAdditionalFireTimesJSON(reminder.additionalFireTimesStorage) {
                    reminder.additionalFireTimesStorage = "[]"
                    changed = true
                }

                if !isValidDateArrayJSON(reminder.completionTimestampsStorage) {
                    reminder.completionTimestampsStorage = "[]"
                    changed = true
                }

                if !isValidDateArrayJSON(reminder.skippedTimestampsStorage) {
                    reminder.skippedTimestampsStorage = "[]"
                    changed = true
                }

                if !isValidChecklistItemsJSON(reminder.checklistItemsStorage) {
                    reminder.checklistItemsStorage = "[]"
                    changed = true
                } else {
                    var items = reminder.checklistItems
                    var checklistChanged = false

                    for index in items.indices {
                        let trimmedItemTitle = items[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if items[index].title != trimmedItemTitle {
                            items[index].title = trimmedItemTitle
                            checklistChanged = true
                        }

                        if items[index].title.isEmpty {
                            items[index].title = "Checklist Item"
                            checklistChanged = true
                        }

                        if items[index].updatedAt < items[index].createdAt {
                            items[index].updatedAt = items[index].createdAt
                            checklistChanged = true
                        }
                    }

                    if checklistChanged {
                        reminder.checklistItems = items
                        changed = true
                    }
                }

                let sanitizedWeekdays = Array(Set(reminder.repeatWeekdays))
                    .filter { (1...7).contains($0) }
                    .sorted()
                if reminder.repeatWeekdays != sanitizedWeekdays {
                    reminder.repeatWeekdays = sanitizedWeekdays
                    changed = true
                }

                if let monthDay = reminder.repeatMonthDay {
                    let clampedMonthDay = max(1, min(31, monthDay))
                    if reminder.repeatMonthDay != clampedMonthDay {
                        reminder.repeatMonthDay = clampedMonthDay
                        changed = true
                    }
                }

                if reminder.repeatUnit == .none, reminder.nextFireAt == nil, !reminder.isCompleted {
                    reminder.nextFireAt = reminder.scheduledDate
                    changed = true
                }

                if reminder.repeatUnit != .none, reminder.nextFireAt == nil {
                    reminder.nextFireAt = reminder.scheduledDate
                    changed = true
                }

                if reminder.isCompleted, reminder.completedAt == nil {
                    reminder.completedAt = reminder.completionTimestamps.last ?? Date()
                    changed = true
                }

                if !reminder.isCompleted, reminder.repeatUnit != .none, reminder.completedAt != nil {
                    reminder.completedAt = nil
                    changed = true
                }

                if reminder.createdAt > Date() {
                    reminder.createdAt = Date()
                    changed = true
                }

                if reminder.updatedAt < reminder.createdAt {
                    reminder.updatedAt = reminder.createdAt
                    changed = true
                }

                if reminder.historyEntries == nil {
                    reminder.historyEntries = []
                    changed = true
                }
            }
        }

        if let histories = try? context.fetch(FetchDescriptor<LureliaReminderHistory>()) {
            let reminders = (try? context.fetch(FetchDescriptor<LureliaReminder>())) ?? []
            let remindersByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })

            for history in histories {
                if history.reminder == nil, let reminder = remindersByID[history.reminderID] {
                    history.reminder = reminder
                    changed = true
                }

                if history.reminderID == UUID(), let reminder = history.reminder {
                    history.reminderID = reminder.id
                    changed = true
                }

                if history.reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    history.reminderTitle = history.reminder?.title ?? ""
                    changed = true
                }

                if history.reminderIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    history.reminderIcon = history.reminder?.icon ?? "bellfill"
                    changed = true
                }

                let trimmedCategory = history.reminderCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                if history.reminderCategory != trimmedCategory {
                    history.reminderCategory = trimmedCategory
                    changed = true
                }

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: history.occurrenceDate)
                let year = components.year ?? 0
                let month = components.month ?? 0
                let day = components.day ?? 0
                let hour = components.hour ?? 0
                let minute = components.minute ?? 0

                if history.occurrenceYear != year {
                    history.occurrenceYear = year
                    changed = true
                }

                if history.occurrenceMonth != month {
                    history.occurrenceMonth = month
                    changed = true
                }

                if history.occurrenceDay != day {
                    history.occurrenceDay = day
                    changed = true
                }

                if history.occurrenceHour != hour {
                    history.occurrenceHour = hour
                    changed = true
                }

                if history.occurrenceMinute != minute {
                    history.occurrenceMinute = minute
                    changed = true
                }

                if history.createdAt > Date() {
                    history.createdAt = Date()
                    changed = true
                }

                if history.updatedAt < history.createdAt {
                    history.updatedAt = history.createdAt
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated reminder models to App Group container")
        }

        defaults.set(true, forKey: migrationKey)
    }

    private func historyBackfillKey(
        reminderID: UUID,
        action: LureliaReminderHistoryAction,
        occurrenceDate: Date,
        calendar cal: Calendar
    ) -> String {
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: occurrenceDate)
        return "\(reminderID.uuidString)-\(action.rawValue)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(c.hour ?? 0)-\(c.minute ?? 0)"
    }

    // MARK: - Widget sync

    /// One-time purge of orphaned reminders by name.
    private func purgeOrphanedReminders() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didPurgeOrphanedReminders_v1") else { return }

        let context = sharedModelContainer.mainContext
        guard let reminders = try? context.fetch(FetchDescriptor<LureliaReminder>()) else { return }

        let killList: Set<String> = [
            "Wind Down",
            "Morning Motions",
            "Self-Care Reset"
        ]

        var deleted = 0
        for reminder in reminders where killList.contains(reminder.title) {
            context.delete(reminder)
            deleted += 1
        }

        if deleted > 0 {
            try? context.save()
            print("[Lurelia] Purged \(deleted) orphaned reminders")
        }

        defaults.set(true, forKey: "didPurgeOrphanedReminders_v1")
    }

    private func migrateKanbanModelsToAppGroup() async {
        let context = sharedModelContainer.mainContext
        let cal = Calendar.current

        guard let boards = try? context.fetch(FetchDescriptor<KanbanBoard>()) else { return }

        var changed = false

        for board in boards {
            // Copy columns
            if let columns = board.columns {
                for column in columns {
                    // Ensure colorHex is set
                    if column.colorHex.isEmpty { column.colorHex = "#03dbfc"; changed = true }

                    // Copy cards
                    if let cards = column.cards {
                        for card in cards {
                            if card.itemID.isEmpty { card.itemID = UUID().uuidString; changed = true }
                        }
                    }
                }
            }

            // Ensure board has colorHex and icon
            if board.colorHex.isEmpty { board.colorHex = "#03dbfc"; changed = true }
            if board.icon.isEmpty { board.icon = "starcal"; changed = true }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated Kanban models to App Group container")
        }
    }

    private func migrateHabitModelsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateHabitModelsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        guard let habits = try? context.fetch(FetchDescriptor<LureliaHabit>()) else { return }

        var changed = false

        for habit in habits {
            let trimmedTitle = habit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if habit.title != trimmedTitle {
                habit.title = trimmedTitle
                changed = true
            }

            if habit.title.isEmpty {
                habit.title = "Untitled Habit"
                changed = true
            }

            if let iconName = habit.iconName, iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                habit.iconName = nil
                changed = true
            }

            let clampedDaysPerWeek = max(1, min(7, habit.daysPerWeek))
            if habit.daysPerWeek != clampedDaysPerWeek {
                habit.daysPerWeek = clampedDaysPerWeek
                changed = true
            }

            let clampedTimesPerDay = max(1, habit.timesPerDay)
            if habit.timesPerDay != clampedTimesPerDay {
                habit.timesPerDay = clampedTimesPerDay
                changed = true
            }

            if !isValidIntArrayJSON(habit.activeWeekdaysStorage) {
                habit.activeWeekdaysStorage = "[1,2,3,4,5,6,7]"
                habit.daysPerWeek = 7
                changed = true
            } else {
                let sanitized = sanitizedWeekdayStorage(habit.activeWeekdaysStorage)
                if habit.activeWeekdaysStorage != sanitized.storage {
                    habit.activeWeekdaysStorage = sanitized.storage
                    habit.daysPerWeek = sanitized.count
                    changed = true
                }
            }

            if !isValidStringArrayJSON(habit.timesOfDayStorage) {
                habit.timesOfDayStorage = "[]"
                changed = true
            }

            if !isValidIntArrayJSON(habit.reminderDaysOfWeekStorage) {
                habit.reminderDaysOfWeekStorage = "[]"
                changed = true
            }

            if habit.createdAt > Date() {
                habit.createdAt = Date()
                changed = true
            }

            if habit.updatedAt < habit.createdAt {
                habit.updatedAt = habit.createdAt
                changed = true
            }

            if let logs = habit.logs {
                for log in logs {
                    let normalizedDay = Calendar.current.startOfDay(for: log.dayStart)
                    if log.dayStart != normalizedDay {
                        log.dayStart = normalizedDay
                        changed = true
                    }

                    if log.count < 0 {
                        log.count = 0
                        changed = true
                    }

                    if log.createdAt < habit.createdAt {
                        log.createdAt = habit.createdAt
                        changed = true
                    }
                }
            }

            if let skips = habit.skips {
                for skip in skips {
                    let normalizedDay = Calendar.current.startOfDay(for: skip.dayStart)
                    if skip.dayStart != normalizedDay {
                        skip.dayStart = normalizedDay
                        changed = true
                    }

                    if skip.createdAt < habit.createdAt {
                        skip.createdAt = habit.createdAt
                        changed = true
                    }
                }
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated habit models to App Group container")
        }

        defaults.set(true, forKey: migrationKey)
    }

    private func migrateHabitLogsAndSkipsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateHabitLogsAndSkipsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        var changed = false

        if let logs = try? context.fetch(FetchDescriptor<LureliaHabitLog>()) {
            for log in logs {
                let normalizedDay = Calendar.current.startOfDay(for: log.dayStart)
                if log.dayStart != normalizedDay {
                    log.dayStart = normalizedDay
                    changed = true
                }

                let clampedCount = max(1, log.count)
                if log.count != clampedCount {
                    log.count = clampedCount
                    changed = true
                }

                if log.createdAt > Date() {
                    log.createdAt = Date()
                    changed = true
                }

                if log.updatedAt < log.createdAt {
                    log.updatedAt = log.createdAt
                    changed = true
                }
            }
        }

        if let skips = try? context.fetch(FetchDescriptor<LureliaHabitSkip>()) {
            for skip in skips {
                let normalizedDay = Calendar.current.startOfDay(for: skip.dayStart)
                if skip.dayStart != normalizedDay {
                    skip.dayStart = normalizedDay
                    changed = true
                }

                if skip.createdAt > Date() {
                    skip.createdAt = Date()
                    changed = true
                }

                if skip.updatedAt < skip.createdAt {
                    skip.updatedAt = skip.createdAt
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated habit logs and skips to App Group container")
        }

        defaults.set(true, forKey: migrationKey)
    }

    private func backfillHabitCompletionFireTimes() async {
        let context = sharedModelContainer.mainContext
        let calendar = Calendar.current

        guard let habits = try? context.fetch(FetchDescriptor<LureliaHabit>()),
              let logs = try? context.fetch(FetchDescriptor<LureliaHabitLog>())
        else {
            return
        }

        var habitsByID: [String: LureliaHabit] = [:]
        for habit in habits where habitsByID[habit.id.uuidString] == nil {
            habitsByID[habit.id.uuidString] = habit
        }
        var changed = false

        for log in logs where log.count > 0 {
            guard let habit = log.habit ?? habitsByID[log.habitIDString] else {
                continue
            }

            if log.habit == nil {
                log.habit = habit
                changed = true
            }

            if log.habitIDString != habit.id.uuidString {
                log.habitIDString = habit.id.uuidString
                changed = true
            }

            let fireDates = habit.fireDates(on: log.dayStart, calendar: calendar)
            if log.backfillCompletedFireTimes(from: fireDates, calendar: calendar) {
                changed = true
            }
        }

        guard changed else { return }

        try? context.save()
        LureliaWidgetReloads.reloadAll()
        print("[Lurelia] Backfilled habit completion fire times")
    }

    private func migrateJourneyModelsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateJourneyModelsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        var changed = false

        if let journeys = try? context.fetch(FetchDescriptor<LureliaJourney>()) {
            for journey in journeys {
                let trimmedTitle = journey.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if journey.title != trimmedTitle {
                    journey.title = trimmedTitle
                    changed = true
                }

                if journey.title.isEmpty {
                    journey.title = "Untitled Journey"
                    changed = true
                }

                if journey.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    journey.iconName = "journey"
                    changed = true
                }

                if journey.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    journey.colorHex = "#8B5CF6"
                    changed = true
                }

                if LureliaJourneyStatus(rawValue: journey.statusRaw) == nil {
                    journey.statusRaw = LureliaJourneyStatus.active.rawValue
                    changed = true
                }

                if journey.createdAt > Date() {
                    journey.createdAt = Date()
                    changed = true
                }

                if journey.updatedAt < journey.createdAt {
                    journey.updatedAt = journey.createdAt
                    changed = true
                }

                if let milestones = journey.milestones {
                    for milestone in milestones {
                        if milestone.journey == nil {
                            milestone.journey = journey
                            changed = true
                        }
                    }
                }

                if let timelineItems = journey.timelineItems {
                    for item in timelineItems {
                        if item.journey == nil {
                            item.journey = journey
                            changed = true
                        }
                    }
                }

                if let notes = journey.notes {
                    for note in notes {
                        if note.journey == nil {
                            note.journey = journey
                            changed = true
                        }
                    }
                }
            }
        }

        if let milestones = try? context.fetch(FetchDescriptor<LureliaJourneyMilestone>()) {
            for milestone in milestones {
                let trimmedTitle = milestone.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if milestone.title != trimmedTitle {
                    milestone.title = trimmedTitle
                    changed = true
                }

                if milestone.title.isEmpty {
                    milestone.title = "Untitled Milestone"
                    changed = true
                }

                if LureliaJourneyMilestoneStatus(rawValue: milestone.statusRaw) == nil {
                    milestone.statusRaw = LureliaJourneyMilestoneStatus.notStarted.rawValue
                    changed = true
                }

                if milestone.createdAt > Date() {
                    milestone.createdAt = Date()
                    changed = true
                }

                if milestone.updatedAt < milestone.createdAt {
                    milestone.updatedAt = milestone.createdAt
                    changed = true
                }

                if milestone.status == .completed, milestone.completedAt == nil {
                    milestone.completedAt = Date()
                    changed = true
                }

                if milestone.status != .completed, milestone.completedAt != nil {
                    milestone.completedAt = nil
                    changed = true
                }

                if let steps = milestone.steps {
                    for step in steps {
                        if step.milestone == nil {
                            step.milestone = milestone
                            changed = true
                        }
                    }
                }

                if let timelineItems = milestone.timelineItems {
                    for item in timelineItems {
                        if item.milestone == nil {
                            item.milestone = milestone
                            changed = true
                        }
                    }
                }
            }
        }

        if let steps = try? context.fetch(FetchDescriptor<LureliaJourneyStep>()) {
            for step in steps {
                let trimmedTitle = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if step.title != trimmedTitle {
                    step.title = trimmedTitle
                    changed = true
                }

                if step.title.isEmpty {
                    step.title = "Untitled Step"
                    changed = true
                }

                if LureliaJourneyStepStatus(rawValue: step.statusRaw) == nil {
                    step.statusRaw = LureliaJourneyStepStatus.notStarted.rawValue
                    changed = true
                }

                if step.createdAt > Date() {
                    step.createdAt = Date()
                    changed = true
                }

                if step.updatedAt < step.createdAt {
                    step.updatedAt = step.createdAt
                    changed = true
                }

                if step.status == .completed, step.completedAt == nil {
                    step.completedAt = Date()
                    changed = true
                }

                if step.status != .completed, step.completedAt != nil {
                    step.completedAt = nil
                    changed = true
                }

                if !isValidUUIDStringArrayJSON(step.linkedReminderIDsStorage) {
                    step.linkedReminderIDsStorage = "[]"
                    changed = true
                }

                if !isValidUUIDStringArrayJSON(step.linkedRoutineIDsStorage) {
                    step.linkedRoutineIDsStorage = "[]"
                    changed = true
                }

                if !isValidUUIDStringArrayJSON(step.linkedHabitIDsStorage) {
                    step.linkedHabitIDsStorage = "[]"
                    changed = true
                }

                if let timelineItems = step.timelineItems {
                    for item in timelineItems {
                        if item.step == nil {
                            item.step = step
                            changed = true
                        }
                    }
                }
            }
        }

        if let timelineItems = try? context.fetch(FetchDescriptor<LureliaJourneyTimelineItem>()) {
            for item in timelineItems {
                let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if item.title != trimmedTitle {
                    item.title = trimmedTitle
                    changed = true
                }

                if item.title.isEmpty {
                    item.title = "Untitled Timeline Item"
                    changed = true
                }

                if LureliaJourneyTimelineItemType(rawValue: item.itemTypeRaw) == nil {
                    item.itemTypeRaw = LureliaJourneyTimelineItemType.step.rawValue
                    changed = true
                }

                if !isValidUUIDStringArrayJSON(item.linkedReminderIDsStorage) {
                    item.linkedReminderIDsStorage = "[]"
                    changed = true
                }

                if !isValidUUIDStringArrayJSON(item.linkedRoutineIDsStorage) {
                    item.linkedRoutineIDsStorage = "[]"
                    changed = true
                }
            }
        }

        if let notes = try? context.fetch(FetchDescriptor<LureliaJourneyNote>()) {
            for note in notes {
                let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if note.title != trimmedTitle {
                    note.title = trimmedTitle
                    changed = true
                }

                if note.title.isEmpty {
                    note.title = "Untitled Note"
                    changed = true
                }

                if note.createdAt > Date() {
                    note.createdAt = Date()
                    changed = true
                }

                if note.updatedAt < note.createdAt {
                    note.updatedAt = note.createdAt
                    changed = true
                }
            }
        }

        if let milestones = try? context.fetch(FetchDescriptor<LureliaJourneyMilestone>()) {
            for milestone in milestones {
                let steps = milestone.steps ?? []
                guard !steps.isEmpty else { continue }

                let completedCount = steps.filter { $0.status == .completed }.count
                let correctedStatus: LureliaJourneyMilestoneStatus

                if completedCount == steps.count {
                    correctedStatus = .completed
                } else if completedCount > 0 {
                    correctedStatus = .inProgress
                } else {
                    correctedStatus = .notStarted
                }

                if milestone.status != correctedStatus {
                    milestone.status = correctedStatus
                    milestone.completedAt = correctedStatus == .completed ? (milestone.completedAt ?? Date()) : nil
                    milestone.updatedAt = Date()
                    changed = true
                }
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated journey models to App Group container")
        }

        defaults.set(true, forKey: migrationKey)
    }

    private func isValidIntArrayJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              (try? JSONDecoder().decode([Int].self, from: data)) != nil else {
            return false
        }
        return true
    }

    private func isValidStringArrayJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              (try? JSONDecoder().decode([String].self, from: data)) != nil else {
            return false
        }
        return true
    }

    private func isValidUUIDStringArrayJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }

        return strings.allSatisfy { UUID(uuidString: $0) != nil }
    }

    private func isValidDateArrayJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              (try? JSONDecoder().decode([Date].self, from: data)) != nil else {
            return false
        }
        return true
    }

    private func isValidAdditionalFireTimesJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              (try? JSONDecoder().decode([LureliaAdditionalFireTime].self, from: data)) != nil else {
            return false
        }
        return true
    }

    private func isValidChecklistItemsJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              (try? JSONDecoder().decode([LureliaReminderChecklistItem].self, from: data)) != nil else {
            return false
        }
        return true
    }

    private func isValidTimeStringArrayJSON(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return false
        }

        return strings.allSatisfy { value in
            let parts = value.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else {
                return false
            }
            return (0...23).contains(hour) && (0...59).contains(minute)
        }
    }

    private func sanitizedWeekdayStorage(_ value: String) -> (storage: String, count: Int) {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Int].self, from: data) else {
            return ("[1,2,3,4,5,6,7]", 7)
        }

        let sanitized = Array(Set(decoded))
            .filter { (1...7).contains($0) }
            .sorted()

        let final = sanitized.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : sanitized

        guard let encoded = try? JSONEncoder().encode(final),
              let string = String(data: encoded, encoding: .utf8) else {
            return ("[1,2,3,4,5,6,7]", 7)
        }

        return (string, final.count)
    }

    // MARK: - Routine migration
    private func migrateRoutineModelsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateRoutineModelsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        var changed = false

        // Migrate LureliaRoutine
        if let routines = try? context.fetch(FetchDescriptor<LureliaRoutine>()) {
            for routine in routines {
                // Name and icon non-empty
                let trimmedName = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if routine.name != trimmedName {
                    routine.name = trimmedName
                    changed = true
                }
                if routine.name.isEmpty {
                    routine.name = "Untitled Routine"
                    changed = true
                }
                let trimmedIcon = routine.icon.trimmingCharacters(in: .whitespacesAndNewlines)
                if routine.icon != trimmedIcon {
                    routine.icon = trimmedIcon
                    changed = true
                }
                if routine.icon.isEmpty {
                    routine.icon = "routine"
                    changed = true
                }
                // colorHex set
                if routine.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    routine.colorHex = "#F59E42"
                    changed = true
                }
                // scheduledDays: only 1-7
                let sanitizedDays = Array(Set(routine.scheduledDays)).filter { (1...7).contains($0) }.sorted()
                if routine.scheduledDays != sanitizedDays {
                    routine.scheduledDays = sanitizedDays
                    changed = true
                }
            }
        }

        // Migrate LureliaRoutineTask
        if let tasks = try? context.fetch(FetchDescriptor<LureliaRoutineTask>()) {
            for task in tasks {
                let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if task.title != trimmedTitle {
                    task.title = trimmedTitle
                    changed = true
                }
                if task.title.isEmpty {
                    task.title = "Routine Task"
                    changed = true
                }
                if task.stableTaskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    task.stableTaskID = UUID().uuidString
                    changed = true
                }
            }
        }

        // Migrate LureliaRoutineRun
        if let runs = try? context.fetch(FetchDescriptor<LureliaRoutineRun>()) {
            for run in runs {
                if run.routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let routine = run.routine {
                    run.routineName = routine.name
                    changed = true
                }

                if run.routineIcon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let routine = run.routine {
                    run.routineIcon = routine.icon
                    changed = true
                }

                if run.routineColorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let routine = run.routine {
                    run.routineColorHex = routine.colorHex
                    changed = true
                }

                if LureliaRoutineTimeOfDay(rawValue: run.routineTimeOfDayRaw) == nil {
                    run.routineTimeOfDayRaw = run.routine?.timeOfDay.rawValue ?? LureliaRoutineTimeOfDay.anytime.rawValue
                    changed = true
                }

                if run.totalPausedSeconds < 0 {
                    run.totalPausedSeconds = 0
                    changed = true
                }

                if run.isPaused, run.pausedAt == nil {
                    run.pausedAt = Date()
                    changed = true
                }

                if !run.isPaused, run.pausedAt != nil {
                    run.pausedAt = nil
                    changed = true
                }

                if let tasks = run.tasks {
                    for task in tasks {
                        let validStates: Set<String> = ["pending", "completed", "skipped"]
                        if !validStates.contains(task.state) {
                            task.state = "pending"
                            changed = true
                        }

                        let trimmedTaskName = task.taskName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if task.taskName != trimmedTaskName {
                            task.taskName = trimmedTaskName
                            changed = true
                        }

                        if task.taskName.isEmpty {
                            task.taskName = "Routine Task"
                            changed = true
                        }

                        if task.sourceStableTaskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            task.sourceStableTaskID = "run-task::\(task.taskName.lowercased())::\(task.sortOrder)"
                            changed = true
                        }
                    }
                }
            }
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated routine models to App Group container")
        }
        defaults.set(true, forKey: migrationKey)
    }

    private func migrateRoutineStatsAndUserSettingsToAppGroup() async {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateRoutineStatsAndUserSettingsToAppGroup_v1"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let context = sharedModelContainer.mainContext
        var changed = false

        if let stats = try? context.fetch(FetchDescriptor<LureliaRoutineStats>()) {
            for stat in stats {
                if stat.routineTimeSpentMinutes < 0 {
                    stat.routineTimeSpentMinutes = 0
                    changed = true
                }

                if stat.routineTimeMissedMinutes < 0 {
                    stat.routineTimeMissedMinutes = 0
                    changed = true
                }

                if stat.routineTimeCreditMinutes < 0 {
                    stat.routineTimeCreditMinutes = 0
                    changed = true
                }

                if stat.totalBuybacksUsed < 0 {
                    stat.totalBuybacksUsed = 0
                    changed = true
                }

                if stat.totalCoinsSpentOnBuybacks < 0 {
                    stat.totalCoinsSpentOnBuybacks = 0
                    changed = true
                }

                if let lastBuybackAt = stat.lastBuybackAt,
                   lastBuybackAt > Date() {
                    stat.lastBuybackAt = nil
                    changed = true
                }

                if stat.createdAt > Date() {
                    stat.createdAt = Date()
                    changed = true
                }

                if stat.updatedAt < stat.createdAt {
                    stat.updatedAt = stat.createdAt
                    changed = true
                }
            }
        }

        if let settings = try? context.fetch(FetchDescriptor<UserSettings>()) {
            if settings.isEmpty {
                let newSettings = UserSettings()
                context.insert(newSettings)
                changed = true
            } else {
                for setting in settings {
                    if setting.coinBalance < 0 {
                        setting.coinBalance = 0
                        changed = true
                    }

                    if let data = setting.selectedCategoriesStorage,
                       (try? JSONDecoder().decode([String].self, from: data)) == nil {
                        setting.selectedCategoriesStorage = try? JSONEncoder().encode([String]())
                        changed = true
                    }

                    if setting.selectedCategoriesStorage == nil {
                        setting.selectedCategoriesStorage = try? JSONEncoder().encode([String]())
                        changed = true
                    }

                    if let data = setting.selectedStarterRoutinesStorage,
                       (try? JSONDecoder().decode([String].self, from: data)) == nil {
                        setting.selectedStarterRoutinesStorage = try? JSONEncoder().encode([String]())
                        changed = true
                    }

                    if setting.selectedStarterRoutinesStorage == nil {
                        setting.selectedStarterRoutinesStorage = try? JSONEncoder().encode([String]())
                        changed = true
                    }

                    if setting.createdAt > Date() {
                        setting.createdAt = Date()
                        changed = true
                    }

                    if setting.updatedAt < setting.createdAt {
                        setting.updatedAt = setting.createdAt
                        changed = true
                    }
                }
            }
        } else {
            let newSettings = UserSettings()
            context.insert(newSettings)
            changed = true
        }

        if changed {
            try? context.save()
            print("[Lurelia] Migrated routine stats and user settings to App Group container")
        }

        defaults.set(true, forKey: migrationKey)
    }
    // MARK: - Duplicate repair after schema mismatch

    private func deduplicateModelsAfterSchemaRepair() async {
        let context = sharedModelContainer.mainContext
        var changed = false

        var habitIDMap: [UUID: UUID] = [:]
        var reminderIDMap: [UUID: UUID] = [:]
        var routineIDMap: [String: String] = [:]
        var taskIDMap: [UUID: UUID] = [:]
        var journeyIDMap: [UUID: UUID] = [:]
        var challengeIDMap: [UUID: UUID] = [:]

        changed = deduplicateHabits(in: context, idMap: &habitIDMap) || changed
        changed = deduplicateReminders(in: context, idMap: &reminderIDMap) || changed
        changed = deduplicateRoutines(in: context, idMap: &routineIDMap) || changed
        changed = deduplicateTasks(in: context, idMap: &taskIDMap) || changed
        changed = deduplicateJourneys(in: context, idMap: &journeyIDMap) || changed
        changed = deduplicateChallenges(in: context, idMap: &challengeIDMap) || changed

        changed = repairJourneyLinks(
            in: context,
            reminderIDMap: reminderIDMap,
            habitIDMap: habitIDMap,
            routineIDMap: routineIDMap
        ) || changed

        changed = repairChallengeLinks(
            in: context,
            reminderIDMap: reminderIDMap,
            habitIDMap: habitIDMap,
            routineIDMap: routineIDMap
        ) || changed

        if changed {
            try? context.save()
            print("[Lurelia] Deduplicated models after schema repair")
        }
    }

    private func deduplicateHabits(in context: ModelContext, idMap: inout [UUID: UUID]) -> Bool {
        guard let habits = try? context.fetch(FetchDescriptor<LureliaHabit>()) else { return false }

        let grouped = Dictionary(grouping: habits) { $0.id }

        var changed = false
        var deletedCount = 0

        for duplicates in grouped.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: bestHabitFirst)
            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                idMap[duplicate.id] = keeper.id

                if let logs = duplicate.logs {
                    for log in logs {
                        log.habit = keeper
                        changed = true
                    }
                }

                if let skips = duplicate.skips {
                    for skip in skips {
                        skip.habit = keeper
                        changed = true
                    }
                }

                context.delete(duplicate)
                deletedCount += 1
                changed = true
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] Removed \(deletedCount) duplicate habits")
        }

        return changed
    }

    private func deduplicateReminders(in context: ModelContext, idMap: inout [UUID: UUID]) -> Bool {
        guard let reminders = try? context.fetch(FetchDescriptor<LureliaReminder>()) else { return false }

        let grouped = Dictionary(grouping: reminders) { $0.id }

        var changed = false
        var deletedCount = 0

        for duplicates in grouped.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: bestReminderFirst)
            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                idMap[duplicate.id] = keeper.id

                if let historyEntries = duplicate.historyEntries {
                    for entry in historyEntries {
                        entry.reminder = keeper
                        entry.reminderID = keeper.id
                        entry.reminderTitle = keeper.title
                        entry.reminderIcon = keeper.icon
                        entry.reminderCategory = keeper.category
                        changed = true
                    }
                }

                keeper.completionTimestamps = Array(Set(keeper.completionTimestamps + duplicate.completionTimestamps)).sorted()
                keeper.skippedTimestamps = Array(Set(keeper.skippedTimestamps + duplicate.skippedTimestamps)).sorted()

                context.delete(duplicate)
                deletedCount += 1
                changed = true
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] Removed \(deletedCount) duplicate reminders")
        }

        return changed
    }

    private func deduplicateRoutines(in context: ModelContext, idMap: inout [String: String]) -> Bool {
        guard let routines = try? context.fetch(FetchDescriptor<LureliaRoutine>()) else { return false }

        let grouped = Dictionary(grouping: routines) { $0.persistentID }

        var changed = false
        var deletedCount = 0

        for duplicates in grouped.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: bestRoutineFirst)
            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                idMap[duplicate.persistentID] = keeper.persistentID

                if let tasks = duplicate.tasks {
                    for task in tasks {
                        task.attach(to: keeper)
                        changed = true
                    }
                }

                if let runs = duplicate.runs {
                    for run in runs {
                        run.routine = keeper
                        changed = true
                    }
                }

                context.delete(duplicate)
                deletedCount += 1
                changed = true
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] Removed \(deletedCount) duplicate routines")
        }

        return changed
    }

    private func deduplicateTasks(in context: ModelContext, idMap: inout [UUID: UUID]) -> Bool {
        guard let tasks = try? context.fetch(FetchDescriptor<LureliaTask>()) else { return false }

        let grouped = Dictionary(grouping: tasks) { $0.id }

        var changed = false
        var deletedCount = 0

        for duplicates in grouped.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: bestTaskFirst)
            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                idMap[duplicate.id] = keeper.id
                context.delete(duplicate)
                deletedCount += 1
                changed = true
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] Removed \(deletedCount) duplicate tasks")
        }

        return changed
    }

    private func deduplicateJourneys(in context: ModelContext, idMap: inout [UUID: UUID]) -> Bool {
        guard let journeys = try? context.fetch(FetchDescriptor<LureliaJourney>()) else { return false }

        let grouped = Dictionary(grouping: journeys) { $0.id }

        var changed = false
        var deletedCount = 0

        for duplicates in grouped.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: bestJourneyFirst)
            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                idMap[duplicate.id] = keeper.id

                duplicate.milestones?.forEach { $0.journey = keeper }
                duplicate.timelineItems?.forEach { $0.journey = keeper }
                duplicate.notes?.forEach { $0.journey = keeper }
                duplicate.checkIns?.forEach { $0.journey = keeper }

                context.delete(duplicate)
                deletedCount += 1
                changed = true
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] Removed \(deletedCount) duplicate journeys")
        }

        return changed
    }

    private func deduplicateChallenges(in context: ModelContext, idMap: inout [UUID: UUID]) -> Bool {
        guard let challenges = try? context.fetch(FetchDescriptor<LureliaChallenge>()) else { return false }

        let grouped = Dictionary(grouping: challenges) { $0.id }

        var changed = false
        var deletedCount = 0

        for duplicates in grouped.values where duplicates.count > 1 {
            let sorted = duplicates.sorted(by: bestChallengeFirst)
            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                idMap[duplicate.id] = keeper.id

                duplicate.actions?.forEach { $0.challenge = keeper }
                duplicate.systemSteps?.forEach { $0.challenge = keeper }
                duplicate.progressReports?.forEach { $0.challenge = keeper }
                duplicate.entries?.forEach { $0.challenge = keeper }

                context.delete(duplicate)
                deletedCount += 1
                changed = true
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] Removed \(deletedCount) duplicate challenges")
        }

        return changed
    }

    private func repairJourneyLinks(
        in context: ModelContext,
        reminderIDMap: [UUID: UUID],
        habitIDMap: [UUID: UUID],
        routineIDMap: [String: String]
    ) -> Bool {
        guard let steps = try? context.fetch(FetchDescriptor<LureliaJourneyStep>()) else { return false }
        var changed = false

        for step in steps {
            let newReminderIDs = step.linkedReminderIDs.map { reminderIDMap[$0] ?? $0 }
            if newReminderIDs != step.linkedReminderIDs {
                step.linkedReminderIDs = Array(Set(newReminderIDs))
                changed = true
            }

            let newHabitIDs = step.linkedHabitIDs.map { habitIDMap[$0] ?? $0 }
            if newHabitIDs != step.linkedHabitIDs {
                step.linkedHabitIDs = Array(Set(newHabitIDs))
                changed = true
            }

            let newRoutineIDs = step.linkedRoutineIDs.map { oldID in
                if let mapped = routineIDMap[oldID.uuidString], let uuid = UUID(uuidString: mapped) {
                    return uuid
                }
                return oldID
            }

            if newRoutineIDs != step.linkedRoutineIDs {
                step.linkedRoutineIDs = Array(Set(newRoutineIDs))
                changed = true
            }
        }

        return changed
    }

    private func repairChallengeLinks(
        in context: ModelContext,
        reminderIDMap: [UUID: UUID],
        habitIDMap: [UUID: UUID],
        routineIDMap: [String: String]
    ) -> Bool {
        guard let actions = try? context.fetch(FetchDescriptor<LureliaChallengeAction>()) else { return false }
        var changed = false

        for action in actions {
            guard let linkedItemID = action.linkedItemID else { continue }

            switch action.linkedItemType {
            case .reminder:
                if let mapped = reminderIDMap[linkedItemID] {
                    action.linkedItemID = mapped
                    changed = true
                }

            case .habit:
                if let mapped = habitIDMap[linkedItemID] {
                    action.linkedItemID = mapped
                    changed = true
                }

            case .routine:
                if let mapped = routineIDMap[linkedItemID.uuidString], let uuid = UUID(uuidString: mapped) {
                    action.linkedItemID = uuid
                    changed = true
                }

            case .manual:
                break
            }
        }

        return changed
    }

    private func bestHabitFirst(_ left: LureliaHabit, _ right: LureliaHabit) -> Bool {
        let leftActivity = (left.logs?.count ?? 0) + (left.skips?.count ?? 0)
        let rightActivity = (right.logs?.count ?? 0) + (right.skips?.count ?? 0)
        if leftActivity != rightActivity { return leftActivity > rightActivity }
        return left.createdAt < right.createdAt
    }

    private func bestReminderFirst(_ left: LureliaReminder, _ right: LureliaReminder) -> Bool {
        let leftActivity = (left.historyEntries?.count ?? 0) + left.completionTimestamps.count + left.skippedTimestamps.count
        let rightActivity = (right.historyEntries?.count ?? 0) + right.completionTimestamps.count + right.skippedTimestamps.count
        if leftActivity != rightActivity { return leftActivity > rightActivity }
        return left.createdAt < right.createdAt
    }

    private func bestRoutineFirst(_ left: LureliaRoutine, _ right: LureliaRoutine) -> Bool {
        let leftActivity = (left.runs?.count ?? 0) + (left.tasks?.count ?? 0)
        let rightActivity = (right.runs?.count ?? 0) + (right.tasks?.count ?? 0)
        if leftActivity != rightActivity { return leftActivity > rightActivity }
        return left.createdAt < right.createdAt
    }

    private func bestTaskFirst(_ left: LureliaTask, _ right: LureliaTask) -> Bool {
        if left.isCompleted != right.isCompleted { return left.isCompleted }
        return left.createdAt < right.createdAt
    }

    private func bestJourneyFirst(_ left: LureliaJourney, _ right: LureliaJourney) -> Bool {
        let leftActivity = (left.milestones?.count ?? 0) + (left.timelineItems?.count ?? 0) + (left.notes?.count ?? 0) + (left.checkIns?.count ?? 0)
        let rightActivity = (right.milestones?.count ?? 0) + (right.timelineItems?.count ?? 0) + (right.notes?.count ?? 0) + (right.checkIns?.count ?? 0)
        if leftActivity != rightActivity { return leftActivity > rightActivity }
        return left.createdAt < right.createdAt
    }

    private func bestChallengeFirst(_ left: LureliaChallenge, _ right: LureliaChallenge) -> Bool {
        let leftActivity = (left.actions?.count ?? 0) + (left.systemSteps?.count ?? 0) + (left.progressReports?.count ?? 0) + (left.entries?.count ?? 0)
        let rightActivity = (right.actions?.count ?? 0) + (right.systemSteps?.count ?? 0) + (right.progressReports?.count ?? 0) + (right.entries?.count ?? 0)
        if leftActivity != rightActivity { return leftActivity > rightActivity }
        return left.createdAt < right.createdAt
    }

    private func exportReminderIconsForWidget() async {
        let context = sharedModelContainer.mainContext
        let reminders = (try? context.fetch(FetchDescriptor<LureliaReminder>())) ?? []
        let habits = (try? context.fetch(FetchDescriptor<LureliaHabit>())) ?? []
        let routines = (try? context.fetch(FetchDescriptor<LureliaRoutine>())) ?? []
        let events = (try? context.fetch(FetchDescriptor<LureliaEvent>())) ?? []

        var iconNames = Set(reminders.map { reminder in
            let trimmed = reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "bellfill" : trimmed
        })

        for habit in habits {
            if let name = habit.iconName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                iconNames.insert(name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        for routine in routines {
            let routineIcon = routine.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            if !routineIcon.isEmpty {
                iconNames.insert(routineIcon)
            }

            for task in routine.sortedTasks {
                let taskIcon = task.icon.trimmingCharacters(in: .whitespacesAndNewlines)
                if !taskIcon.isEmpty {
                    iconNames.insert(taskIcon)
                }
            }
        }

        for event in events {
            let eventIcon = event.displayIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            if !eventIcon.isEmpty {
                iconNames.insert(eventIcon)
            }
        }

        iconNames.insert("bellfill")
        iconNames.insert("skipwavy")
        iconNames.insert("checkwavy")
        iconNames.insert("clockfill")
        iconNames.insert("playwavy")
        iconNames.insert("repeatfill")
        iconNames.insert("minuswavy")
        // Timeline widget header icon — no user data references it, so
        // without an explicit export the widget's title icon renders
        // blank (LureliaWidgetShared.widgetIcon(for:) returns nil).
        iconNames.insert("ringstarcal")
        iconNames.insert("starcal")

        #if DEBUG
        debugEventIconsForWidgetExport(events, exportedIconNames: iconNames)
        #endif

        let fileManager = FileManager.default
        let iconDirectory = LureliaWidgetShared.appGroupContainerURL.appendingPathComponent("widget_icons", isDirectory: true)

        do {
            try fileManager.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        } catch {
            print("[Lurelia] Failed to create widget icon directory: \(error)")
            return
        }

        let iconSize = CGSize(width: 72, height: 72)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = UIScreen.main.scale
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: iconSize, format: rendererFormat)

        for iconName in iconNames {
            let destinationURL = iconDirectory.appendingPathComponent("\(iconName).png")

            guard let sourceImage = UIImage(named: iconName) else {
                debugWidgetIconExport(iconName: iconName, result: "missing-source-asset")
                continue
            }

            let pngData = renderer.pngData { _ in
                let sourceSize = sourceImage.size
                guard sourceSize.width > 0, sourceSize.height > 0 else { return }

                let scale = min(iconSize.width / sourceSize.width, iconSize.height / sourceSize.height)
                let fittedSize = CGSize(
                    width: sourceSize.width * scale,
                    height: sourceSize.height * scale
                )
                let fittedOrigin = CGPoint(
                    x: (iconSize.width - fittedSize.width) / 2,
                    y: (iconSize.height - fittedSize.height) / 2
                )

                sourceImage.withRenderingMode(.alwaysTemplate)
                    .withTintColor(.white)
                    .draw(in: CGRect(origin: fittedOrigin, size: fittedSize))
            }

            do {
                try pngData.write(to: destinationURL, options: .atomic)
                debugWidgetIconExport(iconName: iconName, result: "exported")
            } catch {
                print("[Lurelia] Failed to export widget icon \(iconName): \(error)")
            }
        }
    }

    private func debugEventIconsForWidgetExport(_ events: [LureliaEvent], exportedIconNames: Set<String>) {
        #if DEBUG
        print("[LureliaEventDebug] WIDGET ICON EXPORT EVENT SCAN count: \(events.count)")
        for event in events {
            let icon = event.displayIcon.trimmingCharacters(in: .whitespacesAndNewlines)
            let action = icon.isEmpty ? "empty-icon-skipped" : (exportedIconNames.contains(icon) ? "queued-for-export" : "not-queued")
            print("[LureliaEventDebug] WIDGET ICON EXPORT EVENT id=\(event.id.uuidString) title=\(event.title) icon=\(icon) origin=\(event.eventOrigin.rawValue) appleEventIdentifier=\(event.appleEventIdentifier ?? "nil") appleSeriesIdentifier=\(event.appleSeriesIdentifier ?? "nil") appleOccurrenceKey=\(event.appleOccurrenceKey ?? "nil") appleCalendarID=\(event.appleCalendarIdentifier ?? "nil") appleCalendarColor=\(event.appleCalendarColor ?? "nil") lureliaCalendar=\(event.calendar?.name ?? "nil") lureliaCalendarColor=\(event.calendar?.color ?? "nil") exporterAction=\(action)")
        }
        #endif
    }

    private func debugWidgetIconExport(iconName: String, result: String) {
        #if DEBUG
        print("[LureliaEventDebug] WIDGET ICON EXPORT RESULT iconName=\(iconName) result=\(result)")
        #endif
    }
}
