//
//  LureliaWidgetShared.swift
//  Lurelia
//

import Foundation
import ActivityKit
import AlarmKit
import SQLite3
import SwiftData
import UIKit
import UserNotifications

@available(iOS 26.0, *)
struct LureliaReminderAlarmMetadata: AlarmMetadata {
    let reminderID: UUID
    let notificationID: String
    let title: String
    let icon: String
}

@available(iOS 26.0, *)
struct LureliaHabitAlarmMetadata: AlarmMetadata {
    let habitID: UUID
    let title: String
    let icon: String
}

@available(iOS 26.0, *)
struct LureliaRoutineTaskAlarmMetadata: AlarmMetadata {
    let stableTaskID: String
    let routineName: String
    let title: String
    let icon: String
}

enum LureliaRoutineTaskOccurrenceNotifications {
    static let notificationPrefix = "lurelia.routinetask."
    static let categoryID = "LURELIA_ROUTINE_TASK"

    private static func sanitized(_ stableID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = stableID.unicodeScalars.map {
            allowed.contains($0) ? String($0) : "-"
        }.joined()
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

    static func notificationBaseID(for task: LureliaRoutineTask) -> String {
        "\(notificationPrefix)\(sanitized(task.routineScopedTaskID))"
    }

    static func legacyNotificationBaseID(for task: LureliaRoutineTask) -> String {
        "\(notificationPrefix)\(sanitized(task.stableTaskID))"
    }

    @discardableResult
    static func scheduleUpcomingOccurrences(
        for task: LureliaRoutineTask,
        occurrenceCount: Int = 2,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        guard occurrenceCount > 0,
              task.notificationsEnabled,
              task.hasDueTime else {
            return []
        }

        var dueDates: [Date] = []
        var reference = now
        var attempts = 0

        while dueDates.count < occurrenceCount,
              attempts < 32,
              let dueDate = task.nextDueDate(after: reference, calendar: calendar) {
            reference = dueDate
            attempts += 1

            guard !isResolvedOccurrence(
                task,
                dueDate: dueDate,
                now: now,
                calendar: calendar
            ) else {
                continue
            }

            dueDates.append(dueDate)
        }

        return dueDates.flatMap {
            scheduleOccurrence(for: task, dueDate: $0, now: now, calendar: calendar)
        }
    }

    @discardableResult
    static func cancelPendingOccurrence(
        for task: LureliaRoutineTask,
        on occurrenceDay: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        guard let dueDate = occurrenceDueDate(for: task, on: occurrenceDay, calendar: calendar),
              dueDate > now else {
            return []
        }

        var identifiers = notificationIDs(for: task, dueDate: dueDate)

        // Remove pre-occurrence-ID requests left by older app versions only
        // when this is today's still-pending occurrence.
        if calendar.isDate(dueDate, inSameDayAs: now) {
            identifiers.append(contentsOf: legacyNotificationIDs(for: task))
        }

        let uniqueIdentifiers = Array(Set(identifiers))
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: uniqueIdentifiers)

        let removed = Set(uniqueIdentifiers)
        task.notificationIDs.removeAll { removed.contains($0) }
        task.updatedAt = now

        if let nextDueDate = task.nextDueDate(after: dueDate, calendar: calendar) {
            scheduleOccurrence(
                for: task,
                dueDate: nextDueDate,
                now: now,
                calendar: calendar
            )
        }

        return uniqueIdentifiers
    }

    @discardableResult
    static func restorePendingOccurrence(
        for task: LureliaRoutineTask,
        on occurrenceDay: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        guard let dueDate = occurrenceDueDate(for: task, on: occurrenceDay, calendar: calendar),
              dueDate > now else {
            return []
        }

        return scheduleOccurrence(
            for: task,
            dueDate: dueDate,
            now: now,
            calendar: calendar
        )
    }

    static func cancelAll(for task: LureliaRoutineTask) {
        let center = UNUserNotificationCenter.current()
        let knownIDs = Array(Set(task.notificationIDs + legacyNotificationIDs(for: task)))

        center.removePendingNotificationRequests(withIdentifiers: knownIDs)
        center.removeDeliveredNotifications(withIdentifiers: knownIDs)

        task.notificationIDs = []
    }

    @discardableResult
    private static func scheduleOccurrence(
        for task: LureliaRoutineTask,
        dueDate: Date,
        now: Date,
        calendar: Calendar
    ) -> [String] {
        guard task.notificationsEnabled, task.hasDueTime else { return [] }

        let leadOffsets = task.notificationLeadMinutes.isEmpty
            ? [0]
            : task.notificationLeadMinutes
        let requestIDs = notificationIDs(for: task, dueDate: dueDate)
        var scheduledIDs: [String] = []

        for (index, lead) in leadOffsets.enumerated() {
            let safeLead = max(0, lead)
            let fireDate = calendar.date(
                byAdding: .minute,
                value: -safeLead,
                to: dueDate
            ) ?? dueDate

            guard fireDate > now, requestIDs.indices.contains(index) else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            let trimmedNotes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            content.body = trimmedNotes.isEmpty
                ? (safeLead > 0 ? "Coming up in \(safeLead) min" : "Time to start")
                : trimmedNotes
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.userInfo = [
                "routineTaskStableID": task.stableTaskID,
                "routineTaskOccurrenceDueAt": dueDate.timeIntervalSince1970,
                "routineName": task.routine?.name ?? ""
            ]

            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            components.second = components.second ?? 0
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            let requestID = requestIDs[index]
            let request = UNNotificationRequest(
                identifier: requestID,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    print(
                        "[RoutineTaskNotifications] Failed to schedule \(requestID): \(error)"
                    )
                }
            }
            scheduledIDs.append(requestID)
        }

        if !scheduledIDs.isEmpty {
            task.notificationIDs = Array(Set(task.notificationIDs + scheduledIDs)).sorted()
            task.updatedAt = now
        }

        return scheduledIDs
    }

    static func occurrenceDueDate(
        for task: LureliaRoutineTask,
        on occurrenceDay: Date,
        calendar: Calendar
    ) -> Date? {
        guard task.hasDueTime else { return nil }

        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: occurrenceDay
        )
        components.hour = task.dueHour
        components.minute = task.dueMinute
        components.second = 0

        guard let dueDate = calendar.date(from: components) else { return nil }

        if task.repeatsOnDays,
           !task.scheduledDays.isEmpty,
           !task.scheduledDays.contains(calendar.component(.weekday, from: dueDate)) {
            return nil
        }

        return dueDate
    }

    private static func notificationIDs(
        for task: LureliaRoutineTask,
        dueDate: Date
    ) -> [String] {
        let leadOffsets = task.notificationLeadMinutes.isEmpty
            ? [0]
            : task.notificationLeadMinutes
        let occurrenceToken = Int(dueDate.timeIntervalSince1970)
        let baseID = notificationBaseID(for: task)

        return leadOffsets.indices.map {
            "\(baseID).occurrence.\(occurrenceToken).\($0)"
        }
    }

    static func isResolvedOccurrence(
        _ task: LureliaRoutineTask,
        dueDate: Date,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if task.isPending,
           calendar.isDate(dueDate, inSameDayAs: now) {
            return false
        }

        if task.isCompleted,
           let completedAt = task.completedAt,
           calendar.isDate(completedAt, inSameDayAs: dueDate) {
            return true
        }

        if task.isSkipped,
           let skippedAt = task.skippedAt,
           calendar.isDate(skippedAt, inSameDayAs: dueDate) {
            return true
        }

        return (task.historyItems ?? []).contains {
            calendar.isDate($0.date, inSameDayAs: dueDate)
        }
    }

    private static func legacyNotificationIDs(for task: LureliaRoutineTask) -> [String] {
        let currentBaseID = notificationBaseID(for: task)
        let legacyBaseID = legacyNotificationBaseID(for: task)
        var identifiers = [currentBaseID, legacyBaseID]

        for index in 0..<20 {
            identifiers.append("\(currentBaseID).\(index)")
            identifiers.append("\(legacyBaseID).\(index)")
        }

        return identifiers
    }
}

enum LureliaRoutineTaskOccurrenceAlarms {
    private struct ScheduleSnapshot: Sendable {
        let alarmID: UUID
        let alarmDate: Date
        let title: String
        let stableTaskID: String
        let routineName: String
        let icon: String
        let soundName: String?
    }

    static func scheduleNextOccurrence(
        for task: LureliaRoutineTask,
        after reference: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard task.alarmEnabled, task.hasDueTime else { return }

        var cursor = reference
        var attempts = 0

        while attempts < 32,
              let dueDate = task.nextDueDate(after: cursor, calendar: calendar) {
            cursor = dueDate
            attempts += 1

            guard !LureliaRoutineTaskOccurrenceNotifications.isResolvedOccurrence(
                task,
                dueDate: dueDate,
                now: reference,
                calendar: calendar
            ) else {
                continue
            }

            schedule(task: task, at: dueDate)
            return
        }
    }

    static func cancelPendingOccurrence(
        for task: LureliaRoutineTask,
        on occurrenceDay: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard task.alarmEnabled,
              let dueDate = LureliaRoutineTaskOccurrenceNotifications.occurrenceDueDate(
                for: task,
                on: occurrenceDay,
                calendar: calendar
              ),
              dueDate > now else {
            return
        }

        cancelCurrentAlarm(for: task)

        if let nextDueDate = task.nextDueDate(after: dueDate, calendar: calendar) {
            schedule(task: task, at: nextDueDate)
        }
    }

    static func cancelPendingOccurrenceAndWait(
        for task: LureliaRoutineTask,
        on occurrenceDay: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard task.alarmEnabled,
              let dueDate = LureliaRoutineTaskOccurrenceNotifications.occurrenceDueDate(
                for: task,
                on: occurrenceDay,
                calendar: calendar
              ),
              dueDate > now else {
            return
        }

        cancelCurrentAlarm(for: task)

        guard let nextDueDate = task.nextDueDate(after: dueDate, calendar: calendar),
              let snapshot = scheduleSnapshot(for: task, at: nextDueDate) else {
            return
        }

        await schedule(snapshot)
    }

    static func restorePendingOccurrence(
        for task: LureliaRoutineTask,
        on occurrenceDay: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard task.alarmEnabled,
              let dueDate = LureliaRoutineTaskOccurrenceNotifications.occurrenceDueDate(
                for: task,
                on: occurrenceDay,
                calendar: calendar
              ),
              dueDate > now else {
            return
        }

        cancelCurrentAlarm(for: task)
        schedule(task: task, at: dueDate)
    }

    static func cancelAll(for task: LureliaRoutineTask) {
        cancelCurrentAlarm(for: task)
    }

    private static func schedule(task: LureliaRoutineTask, at alarmDate: Date) {
        guard let snapshot = scheduleSnapshot(for: task, at: alarmDate) else { return }

        Task {
            await schedule(snapshot)
        }
    }

    private static func scheduleSnapshot(
        for task: LureliaRoutineTask,
        at alarmDate: Date
    ) -> ScheduleSnapshot? {
        guard #available(iOS 26.0, *) else { return nil }

        let alarmID: UUID
        if let raw = task.alarmIDString,
           let existing = UUID(uuidString: raw) {
            alarmID = existing
        } else {
            alarmID = UUID()
            task.alarmIDString = alarmID.uuidString
        }

        return ScheduleSnapshot(
            alarmID: alarmID,
            alarmDate: alarmDate,
            title: task.title,
            stableTaskID: task.stableTaskID,
            routineName: task.routine?.name ?? "",
            icon: task.icon,
            soundName: task.alarmSoundName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    private static func schedule(_ snapshot: ScheduleSnapshot) async {
        guard #available(iOS 26.0, *) else { return }

        do {
            switch AlarmManager.shared.authorizationState {
            case .authorized:
                break
            case .notDetermined:
                let state = try await AlarmManager.shared.requestAuthorization()
                guard state == .authorized else { return }
            case .denied:
                return
            @unknown default:
                return
            }

            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: snapshot.title)
            )
            let metadata = LureliaRoutineTaskAlarmMetadata(
                stableTaskID: snapshot.stableTaskID,
                routineName: snapshot.routineName,
                title: snapshot.title,
                icon: snapshot.icon
            )
            let attributes = AlarmAttributes(
                presentation: AlarmPresentation(alert: alert),
                metadata: metadata,
                tintColor: LColors.gradientBlue
            )
            let sound: AlertConfiguration.AlertSound = snapshot.soundName?.isEmpty == false
                ? .named(snapshot.soundName!)
                : .default
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(snapshot.alarmDate),
                attributes: attributes,
                sound: sound
            )

            try? AlarmManager.shared.cancel(id: snapshot.alarmID)
            try await AlarmManager.shared.schedule(
                id: snapshot.alarmID,
                configuration: configuration
            )
        } catch {
            print("[RoutineTaskAlarms] Failed to schedule \(snapshot.alarmID): \(error)")
        }
    }

    private static func cancelCurrentAlarm(for task: LureliaRoutineTask) {
        guard #available(iOS 26.0, *),
              let raw = task.alarmIDString,
              let alarmID = UUID(uuidString: raw) else {
            return
        }

        do {
            try AlarmManager.shared.cancel(id: alarmID)
        } catch {
            print("[RoutineTaskAlarms] Failed to cancel \(alarmID): \(error)")
        }
    }
}

struct LureliaWidgetAppleCalendarSnapshot: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

struct LureliaWidgetExternalEventSnapshot: Codable, Hashable, Identifiable {
    let id: String
    let appleEventIdentifier: String
    let appleSeriesIdentifier: String?
    let appleOccurrenceKey: String?
    let calendarIdentifier: String
    let calendarTitle: String
    let title: String
    let icon: String?
    let colorHex: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

enum LureliaWidgetShared {
    static let appGroupID = "group.com.asteriasmoons.Lurelia"
    static let sharedStoreFileName = "default.store"
    private static let appleCalendarsSnapshotKey = "lurelia.widget.appleCalendars.v1"
    private static let externalEventsSnapshotKey = "lurelia.widget.externalEvents.v1"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static var widgetIconsDirectoryURL: URL {
        appGroupContainerURL.appendingPathComponent("widget_icons", isDirectory: true)
    }

    static func iconURL(for iconName: String) -> URL {
        widgetIconsDirectoryURL.appendingPathComponent("\(iconName).png")
    }

    static func widgetIcon(for iconName: String) -> UIImage? {
        let url = iconURL(for: iconName)

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else {
            return nil
        }

        return image
    }

    @discardableResult
    static func saveAppleCalendarSnapshots(_ snapshots: [LureliaWidgetAppleCalendarSnapshot]) -> Bool {
        let normalized = snapshots
            .map {
                LureliaWidgetAppleCalendarSnapshot(
                    id: $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorHex: $0.colorHex.trimmingCharacters(in: .whitespacesAndNewlines),
                    allowsContentModifications: $0.allowsContentModifications
                )
            }
            .filter { !$0.id.isEmpty && !$0.title.isEmpty }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        guard let data = try? JSONEncoder().encode(normalized),
              let defaults = UserDefaults(suiteName: appGroupID)
        else {
            return false
        }

        if defaults.data(forKey: appleCalendarsSnapshotKey) == data {
            debugAppleCalendarSnapshotSave(normalized, changed: false)
            return false
        }

        defaults.set(data, forKey: appleCalendarsSnapshotKey)
        debugAppleCalendarSnapshotSave(normalized, changed: true)
        return true
    }

    static func loadAppleCalendarSnapshots() -> [LureliaWidgetAppleCalendarSnapshot] {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: appleCalendarsSnapshotKey),
              let decoded = try? JSONDecoder().decode([LureliaWidgetAppleCalendarSnapshot].self, from: data)
        else {
            return []
        }

        debugAppleCalendarSnapshotLoad(decoded)
        return decoded
    }

    @discardableResult
    static func saveExternalEventSnapshots(_ snapshots: [LureliaWidgetExternalEventSnapshot]) -> Bool {
        let normalized = snapshots
            .map {
                LureliaWidgetExternalEventSnapshot(
                    id: $0.id.trimmingCharacters(in: .whitespacesAndNewlines),
                    appleEventIdentifier: $0.appleEventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                    appleSeriesIdentifier: $0.appleSeriesIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                    appleOccurrenceKey: $0.appleOccurrenceKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                    calendarIdentifier: $0.calendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                    calendarTitle: $0.calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    icon: $0.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorHex: $0.colorHex.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: $0.start,
                    end: $0.end,
                    isAllDay: $0.isAllDay
                )
            }
            .filter { !$0.id.isEmpty && !$0.calendarIdentifier.isEmpty && !$0.title.isEmpty }
            .sorted { $0.start < $1.start }

        guard let data = try? JSONEncoder().encode(normalized),
              let defaults = UserDefaults(suiteName: appGroupID)
        else {
            return false
        }

        if defaults.data(forKey: externalEventsSnapshotKey) == data {
            debugExternalEventSnapshotSave(normalized, changed: false)
            return false
        }

        defaults.set(data, forKey: externalEventsSnapshotKey)
        debugExternalEventSnapshotSave(normalized, changed: true)
        return true
    }

    static func loadExternalEventSnapshots() -> [LureliaWidgetExternalEventSnapshot] {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: externalEventsSnapshotKey),
              let decoded = try? JSONDecoder().decode([LureliaWidgetExternalEventSnapshot].self, from: data)
        else {
            return []
        }

        debugExternalEventSnapshotLoad(decoded)
        return decoded
    }

    private static func debugAppleCalendarSnapshotSave(
        _ snapshots: [LureliaWidgetAppleCalendarSnapshot],
        changed: Bool
    ) {
        #if DEBUG
        print("[LureliaEventDebug] APP GROUP APPLE CALENDAR SNAPSHOT SAVE changed: \(changed) count: \(snapshots.count)")
        for snapshot in snapshots {
            print("""
            [LureliaEventDebug] APP GROUP APPLE CALENDAR SNAPSHOT SAVE ITEM
            id: \(snapshot.id)
            title: \(snapshot.title)
            colorHex: \(snapshot.colorHex)
            allowsContentModifications: \(snapshot.allowsContentModifications)
            iconField: not present in LureliaWidgetAppleCalendarSnapshot
            """)
        }
        #endif
    }

    private static func debugAppleCalendarSnapshotLoad(_ snapshots: [LureliaWidgetAppleCalendarSnapshot]) {
        #if DEBUG
        print("[LureliaEventDebug] WIDGET RECEIVED APPLE CALENDAR SNAPSHOTS count: \(snapshots.count)")
        for snapshot in snapshots {
            print("""
            [LureliaEventDebug] WIDGET RECEIVED APPLE CALENDAR
            id: \(snapshot.id)
            title: \(snapshot.title)
            colorHex: \(snapshot.colorHex)
            allowsContentModifications: \(snapshot.allowsContentModifications)
            iconField: not present in LureliaWidgetAppleCalendarSnapshot
            """)
        }
        #endif
    }

    private static func debugExternalEventSnapshotSave(
        _ snapshots: [LureliaWidgetExternalEventSnapshot],
        changed: Bool
    ) {
        #if DEBUG
        print("[LureliaEventDebug] APP GROUP EXTERNAL EVENT SNAPSHOT SAVE changed: \(changed) count: \(snapshots.count)")
        for snapshot in snapshots {
            print("""
            [LureliaEventDebug] APP GROUP EXTERNAL EVENT SNAPSHOT SAVE ITEM
            title: \(snapshot.title)
            appleEventIdentifier: \(snapshot.appleEventIdentifier)
            appleSeriesIdentifier: \(snapshot.appleSeriesIdentifier ?? "nil")
            appleOccurrenceKey: \(snapshot.appleOccurrenceKey ?? "nil")
            calendarIdentifier: \(snapshot.calendarIdentifier)
            calendarTitle: \(snapshot.calendarTitle)
            icon: \(snapshot.icon ?? "nil")
            colorHex: \(snapshot.colorHex)
            start: \(snapshot.start)
            end: \(snapshot.end)
            isAllDay: \(snapshot.isAllDay)
            """)
        }
        #endif
    }

    private static func debugExternalEventSnapshotLoad(_ snapshots: [LureliaWidgetExternalEventSnapshot]) {
        #if DEBUG
        print("[LureliaEventDebug] WIDGET RECEIVED EXTERNAL EVENT SNAPSHOTS count: \(snapshots.count)")
        for snapshot in snapshots {
            print("""
            [LureliaEventDebug] WIDGET RECEIVED EXTERNAL EVENT
            title: \(snapshot.title)
            appleEventIdentifier: \(snapshot.appleEventIdentifier)
            appleSeriesIdentifier: \(snapshot.appleSeriesIdentifier ?? "nil")
            appleOccurrenceKey: \(snapshot.appleOccurrenceKey ?? "nil")
            calendarIdentifier: \(snapshot.calendarIdentifier)
            calendarTitle: \(snapshot.calendarTitle)
            icon: \(snapshot.icon ?? "nil")
            colorHex: \(snapshot.colorHex)
            start: \(snapshot.start)
            end: \(snapshot.end)
            isAllDay: \(snapshot.isAllDay)
            """)
        }
        #endif
    }

    static var appGroupContainerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            fatalError("Could not access App Group container: \(appGroupID)")
        }

        return url
    }

    static var sharedStoreURL: URL {
        appGroupContainerURL.appendingPathComponent(sharedStoreFileName)
    }

    static var sharedSchema: Schema {
        Schema([
            Item.self,
            UserSettings.self,
            LureliaReminder.self,
            LureliaRoutine.self,
            LureliaRoutineContract.self,
            LureliaRoutineTask.self,
            RoutineTaskTemplate.self,
            LureliaRoutineTaskStep.self,
            LureliaRoutineTaskSupply.self,
            LureliaRoutineTaskObstacle.self,
            LureliaRoutineTaskHistoryEntry.self,
            LureliaRoutineRunTask.self,
            LureliaRoutineRun.self,
            LureliaRoutineStats.self,
            LureliaTask.self,
            KanbanBoard.self,
            KanbanColumn.self,
            KanbanCard.self,
            KanbanQuickTask.self,
            LureliaHabit.self,
            LureliaHabitLog.self,
            LureliaHabitSkip.self,
            LureliaEvent.self,
            LureliaEventRecurrence.self,
            LureliaEventNotification.self,
            LureliaEventAttachment.self,
            LureliaEventTag.self,
            LureliaCalendar.self,
            LureliaChallenge.self,
            LureliaChallengeAction.self,
            LureliaChallengeSystemStep.self,
            LureliaChallengeEntry.self,
            LureliaChallengeProgressReport.self,
            LureliaChallengeReportResponse.self,
            LureliaJourney.self,
            LureliaJourneyCheckIn.self,
            LureliaJourneyMilestone.self,
            LureliaJourneyStep.self,
            LureliaJourneyTimelineItem.self,
            LureliaJourneyNote.self,
            LureliaReminderHistory.self,
            LureliaPractice.self,
            LureliaRoutinePhase.self,
            // MARK: - Shared Event Platform (Prompt 1A.1)
            SharedEvent.self,
            SharedCalendar.self,
            Attendee.self,
            Invitation.self,
            Comment.self,
            CommentReply.self,
            CommentReaction.self,
            RSVP.self,
            Host.self,
            Permissions.self,
            SyncState.self,
            NotificationSubscription.self,
            Attachment.self,
            EventArtwork.self,
            Announcement.self,
            EventPost.self,
            SharedEventAppleMirror.self,
        ])
    }

    static func makeModelContainer() throws -> ModelContainer {
        let schema = sharedSchema
        let configuration = ModelConfiguration(
            "LureliaShared",
            schema: schema,
            url: sharedStoreURL
        )

        // Attempt 1: open the store as-is.
        do {
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            print("[LureliaWidgetShared] Initial ModelContainer load failed: \(error)")
        }

        // Attempt 2: SQL-repair duplicate CloudKit metadata rows and retry.
        if repairCloudKitRecordMetadataDuplicates(at: sharedStoreURL) {
            print("[LureliaWidgetShared] Retrying ModelContainer load after CloudKit metadata repair.")
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [configuration]
                )
            } catch {
                print("[LureliaWidgetShared] Retry after metadata repair still failed: \(error)")
            }
        }

        // Attempt 3: the store is unrecoverable through in-place migration.
        // Move the corrupt store aside so SwiftData/CloudKit can rebuild a
        // fresh one. NSPersistentCloudKitContainer will re-download records
        // from iCloud on next launch.
        do {
            try backupAndResetCorruptStore(at: sharedStoreURL)
            print("[LureliaWidgetShared] Reset corrupt store; retrying ModelContainer load with fresh store.")
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            print("[LureliaWidgetShared] Reset-and-rebuild failed: \(error)")
            throw error
        }
    }

    private static func backupAndResetCorruptStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let storeDirectory = storeURL.deletingLastPathComponent()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = storeDirectory.appendingPathComponent(
            "corrupt-store-\(timestamp)",
            isDirectory: true
        )

        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        let suffixes = [
            "",
            "-wal",
            "-shm",
            "-ckAssets",
            "-ckAssets-wal",
            "-ckAssets-shm"
        ]

        for suffix in suffixes {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let destination = backupDirectory.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }

        print("[LureliaWidgetShared] Backed up corrupt store to \(backupDirectory.path)")
    }

    static func migrateLocalStoreToAppGroupIfNeeded() {
        let defaultsKey = "didMigrateLocalSwiftDataStoreToAppGroup_v2"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsKey) else { return }

        let fileManager = FileManager.default
        let destination = sharedStoreURL

        guard !fileManager.fileExists(atPath: destination.path) else {
            defaults.set(true, forKey: defaultsKey)
            return
        }

        let searchRoots = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        let oldStoreURL = searchRoots
            .flatMap { root -> [URL] in
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { return [] }

                var matches: [URL] = []
                while let url = enumerator.nextObject() as? URL {
                    let name = url.lastPathComponent
                    guard name == sharedStoreFileName else { continue }
                    guard !url.path.contains("/Shared/AppGroup/") else { continue }
                    guard url.path != destination.path else { continue }
                    matches.append(url)
                }
                return matches
            }
            .first

        guard let oldStoreURL else {
            print("[LureliaWidgetShared] No local SwiftData store found to migrate.")
            return
        }

        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: oldStoreURL.path + suffix)
                let target = URL(fileURLWithPath: destination.path + suffix)

                guard fileManager.fileExists(atPath: source.path) else { continue }

                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }

                try fileManager.copyItem(at: source, to: target)
            }

            defaults.set(true, forKey: defaultsKey)
            print("[LureliaWidgetShared] Migrated local SwiftData store to App Group: \(oldStoreURL.path)")
        } catch {
            print("[LureliaWidgetShared] Failed to migrate local SwiftData store: \(error)")
        }
    }

    private static func repairCloudKitRecordMetadataDuplicates(at storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let database else {
            if let database {
                print("[LureliaWidgetShared] SQLite open failed: \(String(cString: sqlite3_errmsg(database)))")
                sqlite3_close(database)
            }
            return false
        }

        defer { sqlite3_close(database) }

        guard sqliteTableExists("ANSCKRECORDMETADATA", in: database) else {
            return false
        }

        let repairSQL = """
        DELETE FROM ANSCKRECORDMETADATA
        WHERE Z_PK NOT IN (
            SELECT MIN(Z_PK)
            FROM ANSCKRECORDMETADATA
            GROUP BY ZENTITYID, ZENTITYPK
        );
        DELETE FROM ANSCKRECORDMETADATA
        WHERE Z_PK NOT IN (
            SELECT MIN(Z_PK)
            FROM ANSCKRECORDMETADATA
            GROUP BY ZCKRECORDID
        );
        PRAGMA wal_checkpoint(TRUNCATE);
        VACUUM;
        """

        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, repairSQL, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            if let errorMessage {
                print("[LureliaWidgetShared] CloudKit metadata repair failed: \(String(cString: errorMessage))")
                sqlite3_free(errorMessage)
            }
            return false
        }

        print("[LureliaWidgetShared] Repaired duplicate CloudKit metadata rows in ANSCKRECORDMETADATA.")
        return true
    }

    private static func sqliteTableExists(_ tableName: String, in database: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, tableName, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
