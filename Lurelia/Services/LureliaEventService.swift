//
//  LureliaEventService.swift
//  Lurelia
//

import EventKit
import Combine
import Foundation
import SwiftData
import SwiftUI

struct LureliaAppleCalendarSource: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsContentModifications: Bool
}

struct LureliaExternalCalendarOccurrence: Identifiable, Hashable {
    let id: String
    let appleEventIdentifier: String
    let appleSeriesIdentifier: String
    let appleOccurrenceKey: String
    let calendarIdentifier: String
    let calendarTitle: String
    let title: String
    let notes: String?
    let location: String?
    let colorHex: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isRecurring: Bool
    let icon: String?

    func withIcon(_ icon: String?) -> LureliaExternalCalendarOccurrence {
        LureliaExternalCalendarOccurrence(
            id: id,
            appleEventIdentifier: appleEventIdentifier,
            appleSeriesIdentifier: appleSeriesIdentifier,
            appleOccurrenceKey: appleOccurrenceKey,
            calendarIdentifier: calendarIdentifier,
            calendarTitle: calendarTitle,
            title: title,
            notes: notes,
            location: location,
            colorHex: colorHex,
            start: start,
            end: end,
            isAllDay: isAllDay,
            isRecurring: isRecurring,
            icon: icon
        )
    }
}

@MainActor
final class LureliaEventService: ObservableObject {
    static let shared = LureliaEventService()

    @Published private(set) var authorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var appleCalendars: [LureliaAppleCalendarSource] = []

    private let eventStore = EKEventStore()
    private init() {}

    var hasCalendarAccess: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if hasCalendarAccess {
            reloadCalendars()
        }
    }

    @discardableResult
    func requestCalendarAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { didGrant, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: didGrant)
                        }
                    }
                }
            }

            refreshAuthorizationStatus()
            return granted
        } catch {
            print("❌ [LureliaEventService] Calendar access failed: \(error)")
            refreshAuthorizationStatus()
            return false
        }
    }

    func reloadCalendars() {
        guard hasCalendarAccess else {
            appleCalendars = []
            if LureliaWidgetShared.saveAppleCalendarSnapshots([]) {
                LureliaWidgetReloads.reloadAll()
            }
            return
        }

        appleCalendars = eventStore.calendars(for: .event)
            .map { calendar in
                LureliaAppleCalendarSource(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    colorHex: calendar.cgColor?.lureliaHexString ?? "#03dbfc",
                    allowsContentModifications: calendar.allowsContentModifications
                )
            }
            .sorted { $0.title < $1.title }

        let snapshots = appleCalendars.map {
            LureliaWidgetAppleCalendarSnapshot(
                id: $0.id,
                title: $0.title,
                colorHex: $0.colorHex,
                allowsContentModifications: $0.allowsContentModifications
            )
        }
        debugAppleCalendarSnapshotExport(snapshots)
        if LureliaWidgetShared.saveAppleCalendarSnapshots(snapshots) {
            LureliaWidgetReloads.reloadAll()
        }
    }

    func fetchAppleOccurrences(
        from start: Date,
        to end: Date,
        calendarIdentifiers: Set<String>
    ) -> [LureliaExternalCalendarOccurrence] {
        guard hasCalendarAccess else { return [] }

        let calendars = eventStore.calendars(for: .event).filter {
            calendarIdentifiers.isEmpty || calendarIdentifiers.contains($0.calendarIdentifier)
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)

        return eventStore.events(matching: predicate).compactMap { event in
            guard let eventIdentifier = event.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !eventIdentifier.isEmpty
            else {
                return nil
            }

            let seriesIdentifier = event.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let appleSeriesIdentifier = seriesIdentifier.isEmpty ? eventIdentifier : seriesIdentifier
            let calendarColor = event.calendar.cgColor?.lureliaHexString ?? "#03dbfc"
            let isRecurring = event.hasRecurrenceRules
            let occurrenceKey = LureliaEvent.appleShadowKey(
                appleEventIdentifier: appleSeriesIdentifier,
                occurrenceStart: event.startDate,
                occurrenceEnd: event.endDate,
                isRecurring: isRecurring
            )
            guard !occurrenceKey.isEmpty else { return nil }

            let occurrence = LureliaExternalCalendarOccurrence(
                id: occurrenceKey,
                appleEventIdentifier: eventIdentifier,
                appleSeriesIdentifier: appleSeriesIdentifier,
                appleOccurrenceKey: occurrenceKey,
                calendarIdentifier: event.calendar.calendarIdentifier,
                calendarTitle: event.calendar.title,
                title: event.title ?? "Untitled Event",
                notes: event.notes,
                location: event.location,
                colorHex: calendarColor,
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                isRecurring: isRecurring,
                icon: nil
            )
            debugAppleOccurrenceLoad(occurrence)
            return occurrence
        }
        .sorted { $0.start < $1.start }
    }

    func appleSeriesIdentifier(for eventIdentifier: String) -> String? {
        let identifier = eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasCalendarAccess,
              !identifier.isEmpty,
              let event = eventStore.event(withIdentifier: identifier)
        else {
            return nil
        }

        let seriesIdentifier = event.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return seriesIdentifier.isEmpty ? identifier : seriesIdentifier
    }

    func saveToAppleCalendar(_ event: LureliaEvent, calendarIdentifier: String?) throws {
        guard hasCalendarAccess else { return }

        // Apple-owned shadows are display/organization records only. Never
        // write them back through the native Lurelia -> Apple save path.
        guard !event.isAppleImportedShadow else {
            print("[Sync] Skipping Apple-owned shadow '\(event.title)' during Lurelia -> Apple save.")
            return
        }
        event.markNativeLureliaEvent()

        let appleEvent: EKEvent
        if let identifier = event.appleEventIdentifier,
           let existing = eventStore.event(withIdentifier: identifier) {
            appleEvent = existing
        } else {
            appleEvent = EKEvent(eventStore: eventStore)
        }

        appleEvent.title = event.title
        appleEvent.notes = [event.eventDescription, event.notes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil }
            .joined(separator: "\n\n")
        appleEvent.location = event.address ?? event.locationName
        appleEvent.isAllDay = event.isAllDay
        appleEvent.startDate = event.occurrenceStart()
        appleEvent.endDate = event.occurrenceEnd(for: appleEvent.startDate)
        appleEvent.alarms = (event.notifications ?? [])
            .filter(\.isEnabled)
            .map { EKAlarm(relativeOffset: TimeInterval(-$0.offsetMinutes * 60)) }

        if let recurrence = event.recurrence {
            appleEvent.recurrenceRules = [ekRecurrenceRule(from: recurrence)]
        } else {
            appleEvent.recurrenceRules = nil
        }

        if let calendarIdentifier,
           let calendar = eventStore.calendar(withIdentifier: calendarIdentifier),
           calendar.allowsContentModifications {
            appleEvent.calendar = calendar
        } else if appleEvent.calendar == nil {
            appleEvent.calendar = eventStore.defaultCalendarForNewEvents
        }

        try eventStore.save(appleEvent, span: .futureEvents)
        event.appleEventIdentifier = appleEvent.eventIdentifier
        let seriesIdentifier = appleEvent.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEventIdentifier = appleEvent.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.appleSeriesIdentifier = seriesIdentifier.isEmpty ? savedEventIdentifier : seriesIdentifier
        event.appleCalendarIdentifier = appleEvent.calendar.calendarIdentifier
        event.appleCalendarTitle = appleEvent.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.appleCalendarColor = appleEvent.calendar.cgColor?.lureliaHexString ?? event.appleCalendarColor
        event.syncsWithAppleCalendar = true
        event.modifiedDate = Date()
        // Stamp with the same `lastModifiedDate` Apple just wrote, so the
        // next import cycle sees our version and Apple's version as
        // identical and skips re-writing this row.
        event.lastAppleSyncAt = appleEvent.lastModifiedDate ?? Date()
    }

    /// Pushes Lurelia-authored events to Apple Calendar in one pass. Used
    /// when the user turns on Two-Way Sync and expects existing events —
    /// not just events created after the toggle — to appear in Apple.
    ///
    /// Skips any event that already has an `appleEventIdentifier` — that
    /// event either originated in Apple (was imported) or was already
    /// mirrored to Apple in a previous save, so it's already present in
    /// Apple's store and doesn't need a bulk re-push. Editor saves handle
    /// updates for those normally.
    ///
    /// Errors on individual events are logged and skipped so one bad row
    /// doesn't kill the whole batch.
    func syncAllLocalEventsToApple(
        context: ModelContext,
        defaultCalendarID: String?
    ) {
        guard hasCalendarAccess else { return }

        let descriptor = FetchDescriptor<LureliaEvent>()
        let events = (try? context.fetch(descriptor)) ?? []

        // Bulk export is strictly Lurelia -> Apple. Apple-imported shadows
        // must never be pushed back into EventKit, even if their occurrence
        // identifier is temporarily missing/stale. Treating identifier-less
        // shadows as new native events can duplicate an Apple event/series.
        let unmirrored = events.filter { event in
            !event.isAppleImportedShadow &&
                event.appleEventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        guard !unmirrored.isEmpty else {
            print("[Sync] Bulk push — nothing new to mirror.")
            return
        }

        var pushedCount = 0

        for event in unmirrored {
            do {
                try saveToAppleCalendar(event, calendarIdentifier: defaultCalendarID)
                pushedCount += 1
            } catch {
                print("🚨 [Sync] Failed to push '\(event.title)' to Apple: \(error)")
            }
        }

        try? context.save()
        print("[Sync] Bulk push complete — \(pushedCount) new event(s) mirrored to Apple.")
    }

    func deleteAppleOccurrence(eventIdentifier: String) throws {
        guard hasCalendarAccess else { return }

        let identifier = eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let appleEvent = eventStore.event(withIdentifier: identifier)
        else { return }

        try eventStore.remove(appleEvent, span: .thisEvent, commit: true)
    }

    func deleteFromAppleCalendar(_ event: LureliaEvent) throws {
        guard hasCalendarAccess,
              let identifier = event.appleEventIdentifier,
              let appleEvent = eventStore.event(withIdentifier: identifier)
        else {
            return
        }

        try eventStore.remove(appleEvent, span: .futureEvents)
        event.appleEventIdentifier = nil
        event.appleSeriesIdentifier = nil
        event.appleCalendarIdentifier = nil
        event.syncsWithAppleCalendar = false
        event.modifiedDate = Date()
    }

    /// Imports Apple Calendar events into Lurelia's store. Designed to be
    /// idempotent and safe to call on every navigation:
    ///
    ///  1. Deduplicates by Lurelia's Apple-shadow occurrence key. One-off
    ///     Apple events still collapse to one local row by EventKit identifier;
    ///     recurring occurrences keep distinct keys so one assigned occurrence
    ///     cannot swallow the whole series.
    ///  2. Skips recurring Apple events entirely. Recurrence rule round-trip
    ///     is fragile, and recurring Apple events already render via the
    ///     read-only external-occurrence overlay. Importing them would
    ///     require importing the full EKRecurrenceRule so Lurelia could
    ///     generate the same occurrences — out of scope for this pass.
    ///  3. On an *existing* imported row, updates fields Apple owns
    ///     (title, notes, location, dates, calendar identifier, calendar
    ///     color). Preserves everything the user may have customized in
    ///     Lurelia: `icon`, `categoryName`, `calendar`, `notifications`,
    ///     `tags`, `attachments`. Lurelia primary calendar color still wins
    ///     when a local primary calendar is assigned.
    ///  4. On a *fresh* import, sets sensible local defaults but leaves
    ///     `categoryName` nil so the LureliaEventCategory enum picker isn't
    ///     hijacked by the Apple calendar's title.
    ///
    /// Never deletes Lurelia rows even if the Apple event disappears —
    /// that avoids clobbering data if EventKit is temporarily unavailable.
    /// Orphans can be cleaned up by the user via the normal delete action.
    func importAppleEvents(
        into context: ModelContext,
        from start: Date,
        to end: Date,
        calendarIdentifiers: Set<String>
    ) {
        guard hasCalendarAccess else { return }

        let occurrences = fetchAppleOccurrences(
            from: start,
            to: end,
            calendarIdentifiers: calendarIdentifiers
        )
        guard !occurrences.isEmpty else { return }

        // Dedupe by Lurelia's Apple-shadow occurrence key. Non-recurring
        // events still collapse to one row by EventKit identifier; recurring
        // occurrences keep distinct keys so one occurrence can be organized
        // without swallowing the whole series.
        var seenOccurrenceKeys = Set<String>()
        let uniqueOccurrences = occurrences.filter {
            seenOccurrenceKeys.insert($0.appleOccurrenceKey).inserted
        }

        let descriptor = FetchDescriptor<LureliaEvent>()
        let existing = (try? context.fetch(descriptor)) ?? []

        var didInsertOrUpdate = false
        for event in existing {
            let before = event.eventOriginRaw
            if event.applyInferredEventOriginIfNeeded() {
                debugEventOriginMigration(event, previousOriginRaw: before)
                didInsertOrUpdate = true
            }
        }

        for external in uniqueOccurrences {
            // Fetch the master EKEvent so we work from authoritative
            // start/end dates (not a windowed occurrence's shifted dates).
            guard let ekEvent = eventStore.event(withIdentifier: external.appleEventIdentifier) else {
                continue
            }

            // Skip recurring events. They stay as read-only overlay via
            // `fetchAppleOccurrences` on the display side.
            if ekEvent.hasRecurrenceRules { continue }

            let candidates = LureliaEvent.appleShadowCandidates(
                in: existing,
                appleEventIdentifier: external.appleEventIdentifier,
                appleSeriesIdentifier: external.appleSeriesIdentifier,
                appleOccurrenceKey: external.appleOccurrenceKey
            )
            if let target = LureliaEvent.preferredAppleShadow(
                in: existing,
                appleEventIdentifier: external.appleEventIdentifier,
                appleSeriesIdentifier: external.appleSeriesIdentifier,
                appleOccurrenceKey: external.appleOccurrenceKey
            ) {
                debugAppleImportTarget(stage: "existing-before-update", target: target, external: external, ekEvent: ekEvent)
                target.markAppleImportedShadow()
                target.appleSeriesIdentifier = external.appleSeriesIdentifier
                target.appleOccurrenceKey = external.appleOccurrenceKey
                for duplicate in candidates where duplicate.id != target.id {
                    mergeAppleShadow(duplicate, into: target)
                    context.delete(duplicate)
                    didInsertOrUpdate = true
                }

                // Skip if Apple's copy hasn't changed since our last import.
                // Uses strict `>` on `lastModifiedDate` so equal timestamps
                // (which is what happens right after we push our own edits
                // to Apple) don't cause a redundant round-trip write.
                if let appleModified = ekEvent.lastModifiedDate,
                   let lastSync = target.lastAppleSyncAt,
                   appleModified <= lastSync {

                    // Even when the full apply-fields path is skipped,
                    // backfill the cached Apple-calendar attribution
                    // metadata if it's missing. Otherwise events that
                    // were imported before this cache field existed
                    // would forever show "All day" with no calendar
                    // name, because their sync fingerprint prevents a
                    // re-import.
                    let currentTitle = target.appleCalendarTitle?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let liveTitle = ekEvent.calendar.title
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if currentTitle != liveTitle && !liveTitle.isEmpty {
                        target.appleCalendarTitle = liveTitle
                        didInsertOrUpdate = true
                    }

                    if target.appleCalendarIdentifier != external.calendarIdentifier {
                        target.appleCalendarIdentifier = external.calendarIdentifier
                        didInsertOrUpdate = true
                    }

                    let liveColor = ekEvent.calendar.cgColor?.lureliaHexString ?? external.colorHex
                    let currentColor = target.appleCalendarColor?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if currentColor.caseInsensitiveCompare(liveColor) != .orderedSame {
                        target.appleCalendarColor = liveColor
                        if target.calendar == nil {
                            target.color = liveColor
                        }
                        didInsertOrUpdate = true
                    }

                    debugAppleImportTarget(stage: "existing-skip-apple-unchanged", target: target, external: external, ekEvent: ekEvent)
                    continue
                }
                applyAppleOwnedFields(
                    to: target,
                    from: ekEvent,
                    calendarIdentifier: external.calendarIdentifier
                )
                debugAppleImportTarget(stage: "existing-after-apply-apple-fields", target: target, external: external, ekEvent: ekEvent)
                didInsertOrUpdate = true
            } else {
                let target = LureliaEvent()
                context.insert(target)
                target.markAppleImportedShadow()
                applyAppleOwnedFields(
                    to: target,
                    from: ekEvent,
                    calendarIdentifier: external.calendarIdentifier
                )
                // Local-side defaults set only on fresh insert.
                target.icon = "starcal"
                target.color = target.appleCalendarColor ?? external.colorHex
                target.categoryName = nil
                target.appleEventIdentifier = external.appleEventIdentifier
                target.appleSeriesIdentifier = external.appleSeriesIdentifier
                target.appleOccurrenceKey = external.appleOccurrenceKey
                target.syncsWithAppleCalendar = true
                debugAppleImportTarget(stage: "fresh-shadow-created", target: target, external: external, ekEvent: ekEvent)
                didInsertOrUpdate = true
            }
        }

        if didInsertOrUpdate {
            try? context.save()
        }
    }

    /// Copies Apple-owned fields from an `EKEvent` onto a `LureliaEvent`.
    /// Everything the user may have customized locally (icon, categoryName,
    /// calendar relationship, notifications, tags, attachments) is deliberately
    /// not touched here. The cached Apple calendar color is updated because it
    /// is the display color authority for Apple-owned rows without a Lurelia
    /// primary calendar.
    private func applyAppleOwnedFields(
        to target: LureliaEvent,
        from ekEvent: EKEvent,
        calendarIdentifier: String
    ) {
        target.markAppleImportedShadow()
        target.title = ekEvent.title ?? "Untitled Event"
        target.eventDescription = ekEvent.notes
        target.locationName = ekEvent.location
        target.startDate = ekEvent.startDate
        target.endDate = ekEvent.endDate
        target.startTime = ekEvent.isAllDay ? nil : ekEvent.startDate
        target.endTime = ekEvent.isAllDay ? nil : ekEvent.endDate
        target.duration = max(0, ekEvent.endDate.timeIntervalSince(ekEvent.startDate))
        target.isAllDay = ekEvent.isAllDay
        let seriesIdentifier = ekEvent.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        target.appleSeriesIdentifier = seriesIdentifier.isEmpty
            ? target.appleEventIdentifier
            : seriesIdentifier
        target.appleCalendarIdentifier = calendarIdentifier
        // Cache the source Apple calendar's display title so the events
        // list can show "Rare Days • All day" for imported shadow events
        // whose Lurelia primary calendar is nil. Without this cache the
        // row would just say "All day" with no calendar attribution.
        target.appleCalendarTitle = ekEvent.calendar.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let calendarColor = ekEvent.calendar.cgColor?.lureliaHexString ?? "#03dbfc"
        target.appleCalendarColor = calendarColor
        if target.calendar == nil {
            target.color = calendarColor
        }
        target.modifiedDate = Date()
        // Stamp the sync fingerprint so the next import can compare and
        // skip when Apple hasn't changed since this write.
        target.lastAppleSyncAt = ekEvent.lastModifiedDate ?? Date()
    }

    private func mergeAppleShadow(_ duplicate: LureliaEvent, into target: LureliaEvent) {
        target.markAppleImportedShadow()

        if target.calendar == nil {
            target.calendar = duplicate.calendar
        }

        let targetIcon = target.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duplicateIcon = duplicate.icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if (targetIcon.isEmpty || targetIcon == "starcal"), !duplicateIcon.isEmpty {
            target.icon = duplicateIcon
        }

        let targetCategory = target.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duplicateCategory = duplicate.categoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if targetCategory.isEmpty, !duplicateCategory.isEmpty {
            target.categoryName = duplicateCategory
        }

        if (target.notifications ?? []).isEmpty,
           let duplicateNotifications = duplicate.notifications,
           !duplicateNotifications.isEmpty {
            target.notifications = duplicateNotifications
            duplicateNotifications.forEach { $0.event = target }
        }

        if (target.attachments ?? []).isEmpty,
           let duplicateAttachments = duplicate.attachments,
           !duplicateAttachments.isEmpty {
            target.attachments = duplicateAttachments
            duplicateAttachments.forEach { $0.event = target }
        }

        if (target.tags ?? []).isEmpty,
           let duplicateTags = duplicate.tags,
           !duplicateTags.isEmpty {
            target.tags = duplicateTags
        }

        if duplicate.modifiedDate > target.modifiedDate {
            target.modifiedDate = duplicate.modifiedDate
        }
    }

    private func ekRecurrenceRule(from recurrence: LureliaEventRecurrence) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch recurrence.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }

        let daysOfWeek = recurrence.weekdays.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0.rawValue) ?? .sunday) }
        let daysOfMonth = recurrence.dayOfMonth.map { [NSNumber(value: $0)] }
        let monthsOfYear = recurrence.month.map { [NSNumber(value: $0)] }

        let end: EKRecurrenceEnd?
        switch recurrence.endType {
        case .never:
            end = nil
        case .onDate:
            end = recurrence.endDate.map { EKRecurrenceEnd(end: $0) }
        case .afterOccurrences:
            end = recurrence.occurrenceCount.map { EKRecurrenceEnd(occurrenceCount: max(1, $0)) }
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, recurrence.interval),
            daysOfTheWeek: daysOfWeek.isEmpty ? nil : daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private func debugAppleCalendarSnapshotExport(_ snapshots: [LureliaWidgetAppleCalendarSnapshot]) {
        #if DEBUG
        print("[LureliaEventDebug] APPLE CALENDAR SNAPSHOT EXPORT count: \(snapshots.count)")
        for snapshot in snapshots {
            print("""
            [LureliaEventDebug] APPLE CALENDAR SNAPSHOT
            id: \(snapshot.id)
            title: \(snapshot.title)
            colorHex: \(snapshot.colorHex)
            allowsContentModifications: \(snapshot.allowsContentModifications)
            iconField: not present in LureliaWidgetAppleCalendarSnapshot
            """)
        }
        #endif
    }

    private func debugAppleOccurrenceLoad(_ occurrence: LureliaExternalCalendarOccurrence) {
        #if DEBUG
        print("""
        [LureliaEventDebug] APPLE EVENT LOAD
        title: \(occurrence.title)
        appleEventIdentifier: \(occurrence.appleEventIdentifier)
        appleSeriesIdentifier: \(occurrence.appleSeriesIdentifier)
        appleOccurrenceKey: \(occurrence.appleOccurrenceKey)
        appleCalendarID: \(occurrence.calendarIdentifier)
        appleCalendarTitle: \(occurrence.calendarTitle)
        appleCalendarColor: \(occurrence.colorHex)
        start: \(occurrence.start)
        end: \(occurrence.end)
        isAllDay: \(occurrence.isAllDay)
        isRecurring: \(occurrence.isRecurring)
        iconField: not present in LureliaExternalCalendarOccurrence
        """)
        #endif
    }

    private func debugEventOriginMigration(_ event: LureliaEvent, previousOriginRaw: String?) {
        #if DEBUG
        print("""
        [LureliaEventDebug] EVENT ORIGIN INFERRED
        id: \(event.id.uuidString)
        title: \(event.title)
        previousOriginRaw: \(previousOriginRaw ?? "nil")
        newOriginRaw: \(event.eventOriginRaw ?? "nil")
        resolvedOrigin: \(event.eventOrigin.rawValue)
        appleEventIdentifier: \(event.appleEventIdentifier ?? "nil")
        appleSeriesIdentifier: \(event.appleSeriesIdentifier ?? "nil")
        appleOccurrenceKey: \(event.appleOccurrenceKey ?? "nil")
        appleCalendarID: \(event.appleCalendarIdentifier ?? "nil")
        appleCalendarColor: \(event.appleCalendarColor ?? "nil")
        lureliaCalendar: \(event.calendar?.name ?? "nil")
        lureliaCalendarColor: \(event.calendar?.color ?? "nil")
        eventColor: \(event.colorHex)
        icon: \(event.displayIcon)
        """)
        #endif
    }

    private func debugAppleImportTarget(
        stage: String,
        target: LureliaEvent,
        external: LureliaExternalCalendarOccurrence,
        ekEvent: EKEvent
    ) {
        #if DEBUG
        let liveColor = ekEvent.calendar.cgColor?.lureliaHexString ?? external.colorHex
        print("""
        [LureliaEventDebug] APPLE IMPORT TARGET
        stage: \(stage)
        targetID: \(target.id.uuidString)
        title: \(target.title)
        originRaw: \(target.eventOriginRaw ?? "nil")
        resolvedOrigin: \(target.eventOrigin.rawValue)
        appleEventIdentifier: \(target.appleEventIdentifier ?? "nil")
        externalAppleEventIdentifier: \(external.appleEventIdentifier)
        appleSeriesIdentifier: \(target.appleSeriesIdentifier ?? "nil")
        externalAppleSeriesIdentifier: \(external.appleSeriesIdentifier)
        appleOccurrenceKey: \(target.appleOccurrenceKey ?? "nil")
        externalAppleOccurrenceKey: \(external.appleOccurrenceKey)
        appleCalendarID: \(target.appleCalendarIdentifier ?? "nil")
        externalAppleCalendarID: \(external.calendarIdentifier)
        appleCalendarTitle: \(target.appleCalendarTitle ?? "nil")
        externalAppleCalendarTitle: \(external.calendarTitle)
        appleCalendarColor: \(target.appleCalendarColor ?? "nil")
        externalAppleCalendarColor: \(external.colorHex)
        liveAppleCalendarColor: \(liveColor)
        lureliaCalendar: \(target.calendar?.name ?? "nil")
        lureliaCalendarID: \(target.calendar?.id.uuidString ?? "nil")
        lureliaCalendarColor: \(target.calendar?.color ?? "nil")
        eventColor: \(target.colorHex)
        displayColor: \(target.displayColorHex)
        icon: \(target.displayIcon)
        """)
        #endif
    }
}

private extension CGColor {
    var lureliaHexString: String? {
        guard let components = converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else {
            return nil
        }

        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
