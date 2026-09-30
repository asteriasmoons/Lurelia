//
//  LureliaApp+ChildDedup.swift
//  Lurelia
//
//  Nuclear dedup: groups every entity by its `id` UUID.
//  If two rows share the same id, one is a migration ghost — delete it.
//  Models without `id: UUID` use content-based keys instead.
//

import Foundation
import SwiftData

// MARK: - Protocol for id-based dedup

protocol LureliaDeduplicatable: PersistentModel {
    var deduplicationID: UUID { get }
}

extension LureliaHabitLog: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaHabitSkip: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaReminderHistory: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension KanbanBoard: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension KanbanColumn: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension KanbanCard: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension KanbanQuickTask: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaRoutineStats: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaJourneyMilestone: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaJourneyStep: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaJourneyTimelineItem: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaJourneyNote: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaJourneyCheckIn: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaChallengeAction: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaChallengeEntry: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaChallengeProgressReport: LureliaDeduplicatable { var deduplicationID: UUID { id } }
extension LureliaChallengeReportResponse: LureliaDeduplicatable { var deduplicationID: UUID { id } }

// MARK: - Dedup implementation

extension LureliaApp {

    func deduplicateAllChildEntities() async {
        let context = sharedModelContainer.mainContext

        printEntityCounts(context: context, label: "BEFORE dedup")

        var totalDeleted = 0

        // --- ID-based dedup for child entities only ---
        // Parent entities (Habit, Reminder, Task, Journey, Challenge) are handled
        // by deduplicateModelsAfterSchemaRepair() which safely reassigns children first.

        totalDeleted += deduplicateByID(LureliaHabitLog.self, label: "HabitLog", in: context)
        totalDeleted += deduplicateByID(LureliaHabitSkip.self, label: "HabitSkip", in: context)
        totalDeleted += deduplicateByID(LureliaReminderHistory.self, label: "ReminderHistory", in: context)
        totalDeleted += deduplicateByID(KanbanBoard.self, label: "KanbanBoard", in: context)
        totalDeleted += deduplicateByID(KanbanColumn.self, label: "KanbanColumn", in: context)
        totalDeleted += deduplicateByID(KanbanCard.self, label: "KanbanCard", in: context)
        totalDeleted += deduplicateByID(KanbanQuickTask.self, label: "KanbanQuickTask", in: context)
        totalDeleted += deduplicateByID(LureliaRoutineStats.self, label: "RoutineStats", in: context)
        totalDeleted += deduplicateByID(LureliaJourneyMilestone.self, label: "Milestone", in: context)
        totalDeleted += deduplicateByID(LureliaJourneyStep.self, label: "Step", in: context)
        totalDeleted += deduplicateByID(LureliaJourneyTimelineItem.self, label: "TimelineItem", in: context)
        totalDeleted += deduplicateByID(LureliaJourneyNote.self, label: "Note", in: context)
        totalDeleted += deduplicateByID(LureliaJourneyCheckIn.self, label: "CheckIn", in: context)
        totalDeleted += deduplicateByID(LureliaChallengeAction.self, label: "ChallengeAction", in: context)
        totalDeleted += deduplicateByID(LureliaChallengeEntry.self, label: "ChallengeEntry", in: context)
        totalDeleted += deduplicateByID(LureliaChallengeProgressReport.self, label: "ProgressReport", in: context)
        totalDeleted += deduplicateByID(LureliaChallengeReportResponse.self, label: "ReportResponse", in: context)

        // --- Content-based dedup for models WITHOUT `id: UUID` ---

        totalDeleted += deduplicateRoutineTasksByContent(in: context)
        totalDeleted += deduplicateRoutineRunsByContent(in: context)
        totalDeleted += deduplicateRoutineRunTasksByContent(in: context)

        // --- Singleton: UserSettings ---

        totalDeleted += deduplicateUserSettings(in: context)

        // --- Save ---

        if totalDeleted > 0 {
            do {
                try context.save()
                print("[Lurelia] ✅ Dedup complete. Deleted \(totalDeleted) total duplicates.")
            } catch {
                print("[Lurelia] ❌ Dedup SAVE FAILED: \(error)")
            }
        } else {
            print("[Lurelia] ℹ️ Dedup found 0 duplicates across all entity types.")
        }

        printEntityCounts(context: context, label: "AFTER dedup")
    }

    // MARK: - Generic ID-based dedup

    private func deduplicateByID<T: LureliaDeduplicatable>(
        _ type: T.Type,
        label: String,
        in context: ModelContext
    ) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<T>()) else {
            print("[Lurelia] ⚠️ \(label): fetch failed")
            return 0
        }

        let grouped = Dictionary(grouping: all) { $0.deduplicationID }
        var deletedCount = 0

        for (_, duplicates) in grouped where duplicates.count > 1 {
            for duplicate in duplicates.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] 🗑 \(label): deleted \(deletedCount) duplicates (had \(all.count) rows)")
        }

        return deletedCount
    }

    // MARK: - Content-based dedup: LureliaRoutineTask

    private func deduplicateRoutineTasksByContent(in context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<LureliaRoutineTask>()) else {
            print("[Lurelia] ⚠️ RoutineTask: fetch failed")
            return 0
        }

        let grouped = Dictionary(grouping: all) { task -> String in
            let routineID = task.routine?.persistentID ?? "orphan"
            return "\(routineID)|\(task.stableTaskID)"
        }

        var deletedCount = 0

        for (_, duplicates) in grouped where duplicates.count > 1 {
            let sorted = duplicates.sorted { $0.createdAt < $1.createdAt }
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] 🗑 RoutineTask: deleted \(deletedCount) duplicates (had \(all.count) rows)")
        }

        return deletedCount
    }

    // MARK: - Content-based dedup: LureliaRoutineRun

    private func deduplicateRoutineRunsByContent(in context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<LureliaRoutineRun>()) else {
            print("[Lurelia] ⚠️ RoutineRun: fetch failed")
            return 0
        }

        let grouped = Dictionary(grouping: all) { run -> String in
            let routineID = run.routine?.persistentID ?? "orphan"
            let startKey = Int(run.startedAt.timeIntervalSince1970)
            return "\(routineID)|\(startKey)|\(run.routineName.lowercased())"
        }

        var deletedCount = 0

        for (_, duplicates) in grouped where duplicates.count > 1 {
            let sorted = duplicates.sorted { lhs, rhs in
                if lhs.wasCompleted != rhs.wasCompleted { return lhs.wasCompleted }
                let lhsTasks = (lhs.tasks ?? []).count
                let rhsTasks = (rhs.tasks ?? []).count
                if lhsTasks != rhsTasks { return lhsTasks > rhsTasks }
                return true
            }

            guard let keeper = sorted.first else { continue }

            for duplicate in sorted.dropFirst() {
                if let runTasks = duplicate.tasks {
                    for runTask in runTasks {
                        runTask.run = keeper
                    }
                }
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] 🗑 RoutineRun: deleted \(deletedCount) duplicates (had \(all.count) rows)")
        }

        return deletedCount
    }

    // MARK: - Content-based dedup: LureliaRoutineRunTask

    private func deduplicateRoutineRunTasksByContent(in context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<LureliaRoutineRunTask>()) else {
            print("[Lurelia] ⚠️ RoutineRunTask: fetch failed")
            return 0
        }

        let grouped = Dictionary(grouping: all) { task -> String in
            let runKey: String
            if let run = task.run {
                let routineID = run.routine?.persistentID ?? "unknown"
                runKey = "\(routineID)|\(Int(run.startedAt.timeIntervalSince1970))"
            } else {
                runKey = "orphan"
            }
            return "\(runKey)|\(task.taskName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(task.sortOrder)|\(task.sourceStableTaskID)"
        }

        var deletedCount = 0

        for (_, duplicates) in grouped where duplicates.count > 1 {
            // Keep completed > skipped > pending
            let stateOrder: [String: Int] = ["completed": 0, "skipped": 1, "pending": 2]
            let sorted = duplicates.sorted { lhs, rhs in
                let lo = stateOrder[lhs.state] ?? 3
                let ro = stateOrder[rhs.state] ?? 3
                return lo < ro
            }

            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            print("[Lurelia] 🗑 RoutineRunTask: deleted \(deletedCount) duplicates (had \(all.count) rows)")
        }

        return deletedCount
    }

    // MARK: - Singleton: UserSettings

    private func deduplicateUserSettings(in context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<UserSettings>()),
              all.count > 1 else { return 0 }

        let sorted = all.sorted { lhs, rhs in
            if lhs.hasCompletedOnboarding != rhs.hasCompletedOnboarding { return lhs.hasCompletedOnboarding }
            if lhs.coinBalance != rhs.coinBalance { return lhs.coinBalance > rhs.coinBalance }
            return lhs.createdAt < rhs.createdAt
        }

        var deletedCount = 0
        for duplicate in sorted.dropFirst() {
            context.delete(duplicate)
            deletedCount += 1
        }

        if deletedCount > 0 {
            print("[Lurelia] 🗑 UserSettings: deleted \(deletedCount) duplicates (had \(all.count) rows)")
        }

        return deletedCount
    }

    // MARK: - Diagnostics

    private func printEntityCounts(context: ModelContext, label: String) {
        print("[Lurelia] === Entity counts \(label) ===")
        printCount(of: LureliaReminder.self, label: "Reminders", in: context)
        printCount(of: LureliaReminderHistory.self, label: "ReminderHistory", in: context)
        printCount(of: LureliaHabit.self, label: "Habits", in: context)
        printCount(of: LureliaHabitLog.self, label: "HabitLogs", in: context)
        printCount(of: LureliaHabitSkip.self, label: "HabitSkips", in: context)
        printCount(of: LureliaTask.self, label: "Tasks", in: context)
        printCount(of: KanbanBoard.self, label: "KanbanBoards", in: context)
        printCount(of: KanbanColumn.self, label: "KanbanColumns", in: context)
        printCount(of: KanbanCard.self, label: "KanbanCards", in: context)
        printCount(of: KanbanQuickTask.self, label: "KanbanQuickTasks", in: context)
        printCount(of: LureliaRoutine.self, label: "Routines", in: context)
        printCount(of: LureliaRoutineTask.self, label: "RoutineTasks", in: context)
        printCount(of: LureliaRoutineRun.self, label: "RoutineRuns", in: context)
        printCount(of: LureliaRoutineRunTask.self, label: "RoutineRunTasks", in: context)
        printCount(of: LureliaRoutineStats.self, label: "RoutineStats", in: context)
        printCount(of: LureliaJourney.self, label: "Journeys", in: context)
        printCount(of: LureliaJourneyMilestone.self, label: "Milestones", in: context)
        printCount(of: LureliaJourneyStep.self, label: "Steps", in: context)
        printCount(of: LureliaJourneyTimelineItem.self, label: "TimelineItems", in: context)
        printCount(of: LureliaJourneyNote.self, label: "Notes", in: context)
        printCount(of: LureliaJourneyCheckIn.self, label: "CheckIns", in: context)
        printCount(of: LureliaChallenge.self, label: "Challenges", in: context)
        printCount(of: LureliaChallengeAction.self, label: "ChallengeActions", in: context)
        printCount(of: LureliaChallengeEntry.self, label: "ChallengeEntries", in: context)
        printCount(of: LureliaChallengeProgressReport.self, label: "ProgressReports", in: context)
        printCount(of: LureliaChallengeReportResponse.self, label: "ReportResponses", in: context)
        printCount(of: UserSettings.self, label: "UserSettings", in: context)
        print("[Lurelia] === End counts ===")
    }

    private func printCount<T: PersistentModel>(of type: T.Type, label: String, in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
        print("[Lurelia]   \(label): \(count)")
    }
}
