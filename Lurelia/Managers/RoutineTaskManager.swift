//
//  RoutineTaskManager.swift
//  Lurelia
//
//  Handles per-task local notifications and AlarmKit alarms for individual
//  routine tasks (LureliaRoutineTask), plus recording of completion / skip
//  history that powers each task's statistics.
//
//  NOTE: The existing `TaskManager` type manages the standalone daily-task
//  system (LureliaTask) and is unrelated to routines, so this dedicated
//  manager keeps routine-task scheduling isolated and non-breaking.
//
//  NOTIFICATION IDENTIFIERS
//  ────────────────────────
//  Base ID = "lurelia.routinetask.<routineScopedTaskID>"
//  Each lead-time offset uses a suffix: baseID.0, baseID.1, ...
//

import Foundation
import SwiftData
import SwiftUI
import Combine
import UserNotifications
import ActivityKit
import AlarmKit
import WidgetKit
import UIKit

@MainActor
final class RoutineTaskManager: ObservableObject {

    static let shared = RoutineTaskManager()

    private static let notificationPrefix = LureliaRoutineTaskOccurrenceNotifications.notificationPrefix
    static let categoryID = LureliaRoutineTaskOccurrenceNotifications.categoryID

    private var modelContainer: ModelContainer?
    private var hasRegisteredForegroundObserver = false
    private var isRescheduling = false
    private var lastRescheduleAt: Date?
    private let rescheduleDebounce: TimeInterval = 5

    private init() {}

    // MARK: - Setup

    /// Binds routine-task scheduling to the shared store and refreshes the
    /// one-shot requests whenever the app launches or returns to foreground.
    func setup(container: ModelContainer) {
        modelContainer = container
        print("🛠️ [RoutineTaskManager] Setup attached to the shared model container")

        if !hasRegisteredForegroundObserver {
            hasRegisteredForegroundObserver = true
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let container = self.modelContainer else { return }
                    print("🛠️ [RoutineTaskManager] App entered foreground; requesting a full rebuild")
                    self.rescheduleAll(from: container)
                }
            }
        }

        rescheduleAll(from: container)
    }

    // MARK: - Sync

    /// Cancels any existing notifications / alarms for the task and rebuilds
    /// them from the task's current configuration. Call after editing a task.
    func sync(task: LureliaRoutineTask) {
        cancel(task: task)

        guard task.hasDueTime else { return }

        scheduleNotifications(for: task)
        scheduleAlarmIfNeeded(for: task)
    }

    /// Rebuilds every task notification from persisted task configuration.
    /// Routine-task requests are non-repeating, so without this reconciliation
    /// a task stops notifying after its previously queued request fires.
    func rescheduleAll(from container: ModelContainer) {
        guard !isRescheduling else {
            print("🛠️ [RoutineTaskManager] Rebuild skipped because one is already running")
            return
        }
        if let lastRescheduleAt,
           Date().timeIntervalSince(lastRescheduleAt) < rescheduleDebounce {
            print("🛠️ [RoutineTaskManager] Rebuild skipped by the \(Int(rescheduleDebounce))-second debounce")
            return
        }

        isRescheduling = true
        lastRescheduleAt = Date()
        print("🛠️ [RoutineTaskManager] Starting full routine-task scheduling rebuild")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRescheduling = false }

            let context = container.mainContext

            do {
                let tasks = try context.fetch(FetchDescriptor<LureliaRoutineTask>())
                let center = UNUserNotificationCenter.current()
                let notificationSettings = await center.notificationSettings()
                let pending = await center.pendingNotificationRequests()
                let oldIDs = pending
                    .map(\.identifier)
                    .filter { $0.hasPrefix(Self.notificationPrefix) }

                print(
                    "🛠️ [RoutineTaskManager] Notification settings | authorization=\(authorizationLabel(notificationSettings.authorizationStatus)) alerts=\(notificationSettingLabel(notificationSettings.alertSetting)) sounds=\(notificationSettingLabel(notificationSettings.soundSetting))"
                )
                print(
                    "🛠️ [RoutineTaskManager] Fetched \(tasks.count) routine tasks and found \(oldIDs.count) stale pending requests"
                )

                if !oldIDs.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: oldIDs)
                    print("🛠️ [RoutineTaskManager] Removed \(oldIDs.count) stale routine-task requests")
                }

                for task in tasks {
                    task.notificationIDs = []
                    self.cancelAlarmIfNeeded(for: task)
                }

                let activeTasks = tasks.filter {
                    $0.hasDueTime && ($0.notificationsEnabled || $0.alarmEnabled)
                }

                let notificationTasks = activeTasks.filter(\.notificationsEnabled)
                let alarmTasks = activeTasks.filter(\.alarmEnabled)
                let missingDueTimeTasks = tasks.filter {
                    ($0.notificationsEnabled || $0.alarmEnabled) && !$0.hasDueTime
                }
                print(
                    "🛠️ [RoutineTaskManager] Rebuilding \(notificationTasks.count) notification-enabled tasks and \(alarmTasks.count) alarm-enabled tasks"
                )

                for task in missingDueTimeTasks {
                    print(
                        "🛠️ [RoutineTaskManager] Skipping '\(task.title)' because notifications or alarms are enabled without a due time"
                    )
                }

                for task in activeTasks {
                    let daySummary = task.repeatsOnDays
                        ? (task.scheduledDays.isEmpty ? "daily" : task.scheduledDays.map { String($0) }.joined(separator: ","))
                        : "next occurrence"
                    print(
                        "🛠️ [RoutineTaskManager] Processing '\(task.title)' | due=\(String(format: "%02d:%02d", task.dueHour, task.dueMinute)) days=\(daySummary) leads=\(task.notificationLeadMinutes) notifications=\(task.notificationsEnabled) alarm=\(task.alarmEnabled)"
                    )
                    self.scheduleNotifications(for: task)
                    self.scheduleAlarmIfNeeded(for: task)
                }

                try context.save()
                print("🛠️ [RoutineTaskManager] Rebuild finished for \(activeTasks.count) routine tasks")
            } catch {
                print("🛠️ [RoutineTaskManager] Rebuild failed: \(error)")
            }
        }
    }

    // MARK: - Notifications

    private func scheduleNotifications(for task: LureliaRoutineTask) {
        let scheduledIDs = LureliaRoutineTaskOccurrenceNotifications
            .scheduleUpcomingOccurrences(for: task)
        print(
            "🛠️ [RoutineTaskManager] '\(task.title)' produced \(scheduledIDs.count) pending notification request IDs"
        )
    }

    private func authorizationLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    private func notificationSettingLabel(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Cancel

    func cancel(task: LureliaRoutineTask) {
        LureliaRoutineTaskOccurrenceNotifications.cancelAll(for: task)
        cancelAlarmIfNeeded(for: task)
    }

    // MARK: - AlarmKit

    private func scheduleAlarmIfNeeded(for task: LureliaRoutineTask) {
        LureliaRoutineTaskOccurrenceAlarms.scheduleNextOccurrence(for: task)
    }

    private func cancelAlarmIfNeeded(for task: LureliaRoutineTask) {
        LureliaRoutineTaskOccurrenceAlarms.cancelAll(for: task)
    }

    // MARK: - History / Statistics

    /// Records a completion event and saves. The task's *live* state
    /// (`state`, `completedAt`) is only flipped to "completed" when the
    /// occurrence being completed is today — completing yesterday's row
    /// from the Kanban timeline just appends a history entry dated to that
    /// day and leaves today's instance untouched.
    func recordCompletion(
        task: LureliaRoutineTask,
        durationSeconds: Int = 0,
        note: String = "",
        occurredAt: Date = Date(),
        context: ModelContext
    ) {
        let entry = LureliaRoutineTaskHistoryEntry(
            date: occurredAt,
            durationSeconds: max(0, durationSeconds),
            wasCompleted: true,
            skipReason: "",
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        entry.routineTaskIDString = task.routineScopedTaskID
        context.insert(entry)
        entry.task = task
        if task.historyItems == nil { task.historyItems = [] }
        task.historyItems?.append(entry)

        if Calendar.current.isDateInToday(occurredAt) {
            task.markCompleted()
        } else {
            // Historical completion — bump updatedAt for sync, but leave
            // the live state so today's card doesn't flip to completed.
            task.updatedAt = Date()
        }

        LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
            for: task,
            on: occurredAt
        )
        LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrence(
            for: task,
            on: occurredAt
        )

        task.routine?.refreshCurrentContractStatusIfNeeded()

        do {
            try context.save()
        } catch {
            print("🚨 [RoutineTaskManager] recordCompletion SAVE FAILED: \(error)")
        }
        LureliaWidgetReloads.reloadAll()
    }

    /// Records a skip event and saves. Same rule as `recordCompletion` —
    /// live `state`/`skippedAt` only mutate when the occurrence is today.
    func recordSkip(
        task: LureliaRoutineTask,
        reason: String = "",
        occurredAt: Date = Date(),
        context: ModelContext
    ) {
        let entry = LureliaRoutineTaskHistoryEntry(
            date: occurredAt,
            durationSeconds: 0,
            wasCompleted: false,
            skipReason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            note: ""
        )
        entry.routineTaskIDString = task.routineScopedTaskID
        context.insert(entry)
        entry.task = task
        if task.historyItems == nil { task.historyItems = [] }
        task.historyItems?.append(entry)

        if Calendar.current.isDateInToday(occurredAt) {
            task.markSkipped()
        } else {
            task.updatedAt = Date()
        }

        LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
            for: task,
            on: occurredAt
        )
        LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrence(
            for: task,
            on: occurredAt
        )

        task.routine?.refreshCurrentContractStatusIfNeeded()

        do {
            try context.save()
        } catch {
            print("🚨 [RoutineTaskManager] recordSkip SAVE FAILED: \(error)")
        }
        LureliaWidgetReloads.reloadAll()
    }

    func resetStatus(
        task: LureliaRoutineTask,
        on day: Date = Date(),
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let existingHistory = task.historyItems ?? []
        let remainingHistory = existingHistory.filter {
            !calendar.isDate($0.date, inSameDayAs: day)
        }

        for entry in existingHistory where calendar.isDate(entry.date, inSameDayAs: day) {
            context.delete(entry)
        }

        task.historyItems = remainingHistory

        if let completedAt = task.completedAt,
           calendar.isDate(completedAt, inSameDayAs: day) {
            task.completedAt = nil
        }

        if let skippedAt = task.skippedAt,
           calendar.isDate(skippedAt, inSameDayAs: day) {
            task.skippedAt = nil
        }

        if calendar.isDateInToday(day) {
            task.resetState()
        } else {
            task.updatedAt = Date()
        }

        LureliaRoutineTaskOccurrenceNotifications.restorePendingOccurrence(
            for: task,
            on: day
        )
        LureliaRoutineTaskOccurrenceAlarms.restorePendingOccurrence(
            for: task,
            on: day
        )

        task.routine?.refreshCurrentContractStatusIfNeeded()

        do {
            try context.save()
        } catch {
            print("🚨 [RoutineTaskManager] resetStatus SAVE FAILED: \(error)")
        }
        LureliaWidgetReloads.reloadAll()
    }
}
