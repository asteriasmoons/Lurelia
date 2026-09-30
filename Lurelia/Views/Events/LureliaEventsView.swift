//
//  LureliaEventsView.swift
//  Lurelia
//

import SwiftData
import SwiftUI

enum LureliaEventsTab: String, CaseIterable, Identifiable {
    case agenda = "Agenda"
    case month = "Month"
    case week = "Week"

    var id: String { rawValue }
}

struct LureliaEventsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Query(sort: \LureliaEvent.startDate) private var events: [LureliaEvent]
    @Query(sort: \LureliaEventTag.name) private var tags: [LureliaEventTag]
    @Query private var settings: [UserSettings]
    /// Observed so a change to any calendar's `isHidden` in the Event
    /// Settings sheet invalidates this view and re-runs `localOccurrences`.
    /// Without this query the events list would keep showing rows from a
    /// calendar the user just hid — the events themselves haven't changed,
    /// so the `events` @Query wouldn't fire on its own.
    @Query private var lureliaCalendars: [LureliaCalendar]

    @StateObject private var eventService = LureliaEventService.shared
    @State private var selectedTab: LureliaEventsTab = .agenda
    @State private var focusedDate = Date()
    @State private var showCalendarGate = false
    @State private var calendarForNewEvent: LureliaCalendar?
    @State private var pendingCalendarForNewEvent: LureliaCalendar?
    @State private var editingEvent: LureliaEvent?
    @State private var selectedEvent: LureliaEvent?
    @State private var selectedAppleOccurrence: LureliaExternalCalendarOccurrence?
    @State private var selectedAppleShadowEvent: LureliaEvent?
    @State private var showCalendarSettings = false
    @State private var showAddCalendar = false
    @State private var externalOccurrences: [LureliaExternalCalendarOccurrence] = []
    @State private var showSharedEvents = false

    private var calendar: Calendar { .current }

    private var settingsObject: UserSettings {
        if let existing = settings.first {
            return existing
        }

        let created = UserSettings()
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    private var selectedAppleCalendarIDs: Set<String> {
        Set(settings.first?.selectedAppleCalendarIDs ?? [])
    }

    private var displayInterval: DateInterval {
        switch selectedTab {
        case .agenda:
            return calendar.dateInterval(of: .weekOfYear, for: focusedDate) ?? DateInterval(start: focusedDate, duration: 7 * 86_400)
        case .month:
            return calendar.dateInterval(of: .month, for: focusedDate) ?? DateInterval(start: focusedDate, duration: 30 * 86_400)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: focusedDate) ?? DateInterval(start: focusedDate, duration: 7 * 86_400)
        }
    }

    private var localOccurrences: [LureliaEventOccurrence] {
        // Build a fresh hidden-calendar id set directly from the calendars
        // @Query instead of reading `event.calendar?.isHidden`. The inverse
        // relationship can hand back a stale snapshot after the settings
        // sheet toggles `isHidden`. Trusting only the primary-key id keeps
        // this stable.
        let hiddenCalendarIDs = Set(
            lureliaCalendars.filter(\.isHidden).map(\.id)
        )

        // Apple-imported events become local `LureliaEvent`s with
        // `event.calendar = nil` but `event.appleCalendarIdentifier` set to
        // the source Apple calendar's UUID string. Honor the user's Apple
        // Calendar visibility picks for those shadow records too —
        // otherwise hiding an Apple calendar from Event Settings hides
        // the live Apple overlay but leaves these imported copies
        // stranded on the timeline.
        let userSettings = settings.first
        let hasConfiguredApple = userSettings?.hasConfiguredAppleCalendarSelection ?? false
        let visibleAppleIDs = Set(userSettings?.selectedAppleCalendarIDs ?? [])

        return events
            .filter { event in
                // Rule 1: hidden Lurelia primary calendar.
                if let cal = event.calendar,
                   hiddenCalendarIDs.contains(cal.id) {
                    return false
                }

                // Rule 2: imported Apple-owned events with no Lurelia
                // primary — honor the user's Apple calendar visibility.
                if event.isAppleImportedShadow,
                   event.calendar == nil,
                   let appleID = event.appleCalendarIdentifier,
                   !appleID.isEmpty,
                   hasConfiguredApple,
                   !visibleAppleIDs.contains(appleID) {
                    return false
                }

                return true
            }
            .flatMap { $0.occurrences(in: displayInterval, calendar: calendar) }
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LureliaBackgroundAlt()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        tabPicker

                        Group {
                            switch selectedTab {
                            case .agenda:
                                LureliaAgendaView(
                                    focusedDate: $focusedDate,
                                    interval: displayInterval,
                                    localOccurrences: localOccurrences,
                                    externalOccurrences: visibleExternalOccurrences,
                                    events: events,
                                    onSelect: selectOccurrence,
                                    onDelete: deleteOccurrence
                                )
                            case .month:
                                LureliaMonthCalendarView(
                                    focusedDate: $focusedDate,
                                    localOccurrences: localOccurrences,
                                    externalOccurrences: visibleExternalOccurrences,
                                    events: events,
                                    onSelect: selectOccurrence,
                                    onDelete: deleteOccurrence
                                )
                            case .week:
                                LureliaWeekScheduleView(
                                    focusedDate: $focusedDate,
                                    localOccurrences: localOccurrences,
                                    externalOccurrences: visibleExternalOccurrences,
                                    events: events,
                                    onSelect: selectOccurrence,
                                    onDelete: deleteOccurrence
                                )
                            }
                        }

                        Spacer().frame(height: 120)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showCalendarGate, onDismiss: {
            guard let pendingCalendarForNewEvent else { return }
            calendarForNewEvent = pendingCalendarForNewEvent
            self.pendingCalendarForNewEvent = nil
        }) {
            LureliaEventCalendarGateSheet { calendar in
                pendingCalendarForNewEvent = calendar
                showCalendarGate = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $calendarForNewEvent) { calendar in
            LureliaEventEditorView(
                event: nil,
                tags: tags,
                settings: settingsObject,
                initialCalendar: calendar
            )
            .id(calendar.id)
        }
        .sheet(item: $editingEvent) { event in
            LureliaEventEditorView(event: event, tags: tags, settings: settingsObject)
        }
        .sheet(item: $selectedEvent) { event in
            LureliaEventDetailView(event: event) {
                selectedEvent = nil
                editingEvent = event
            }
        }
        .sheet(item: $selectedAppleOccurrence) { occurrence in
            LureliaAppleEventDetailView(occurrence: occurrence)
        }
        .sheet(item: $selectedAppleShadowEvent) { event in
            LureliaAppleEventDetailView(event: event)
        }
        .sheet(isPresented: $showCalendarSettings) {
            LureliaEventCalendarSettingsView(settings: settingsObject)
        }
        .sheet(isPresented: $showAddCalendar) {
            LureliaAddCalendarSheet()
        }
        .sheet(isPresented: $showSharedEvents) {
            SharedEventsView()
        }
        .task {
            eventService.refreshAuthorizationStatus()
            migrateEventOriginsIfNeeded()
            loadExternalOccurrences()
            if let savedTab = LureliaEventsTab(rawValue: settingsObject.defaultEventsViewRaw) {
                selectedTab = savedTab
            }
        }
        .onChange(of: focusedDate) { _, _ in loadExternalOccurrences() }
        .onChange(of: selectedTab) { _, _ in loadExternalOccurrences() }
        .onChange(of: settings.first?.selectedAppleCalendarIDs ?? []) { _, _ in loadExternalOccurrences() }
        .onChange(of: settings.first?.showAppleCalendarEvents ?? true) { _, _ in loadExternalOccurrences() }
    }

    private var visibleExternalOccurrences: [LureliaExternalCalendarOccurrence] {
        guard settings.first?.showAppleCalendarEvents ?? true else { return [] }
        let appleShadows = events.filter(\.isAppleImportedShadow)
        let importedAppleOccurrenceKeys = Set(appleShadows.compactMap(\.resolvedAppleOccurrenceKey))
        let importedAppleOccurrenceSignatures = Set(
            appleShadows.flatMap { appleOccurrenceSignatures(for: $0) }
        )
        let mirroredRecurringAppleIDs = Set(
            events
                .filter { $0.recurrence != nil }
                .compactMap(\.resolvedAppleSeriesIdentifier)
                .filter { !$0.isEmpty }
        )
        return externalOccurrences.filter { occurrence in
            let occurrenceKey = occurrence.appleOccurrenceKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let occurrenceSignatures = appleOccurrenceSignatures(for: occurrence)

            return !importedAppleOccurrenceKeys.contains(occurrenceKey) &&
                !mirroredRecurringAppleIDs.contains(occurrence.appleSeriesIdentifier) &&
                occurrenceSignatures.isDisjoint(with: importedAppleOccurrenceSignatures)
        }
    }

    private struct AppleOccurrenceSignature: Hashable {
        let source: String
        let start: Int
        let end: Int
    }

    private func appleOccurrenceSignatures(for event: LureliaEvent) -> [AppleOccurrenceSignature] {
        let start = normalizedOccurrenceTime(event.startDate)
        let end = normalizedOccurrenceTime(event.endDate ?? event.startDate.addingTimeInterval(max(0, event.duration)))
        var signatures: [AppleOccurrenceSignature] = []

        if let seriesIdentifier = event.resolvedAppleSeriesIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !seriesIdentifier.isEmpty {
            signatures.append(
                AppleOccurrenceSignature(
                    source: "series:\(seriesIdentifier)",
                    start: start,
                    end: end
                )
            )
        }

        if let calendarIdentifier = event.appleCalendarIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !calendarIdentifier.isEmpty {
            signatures.append(
                AppleOccurrenceSignature(
                    source: legacyAppleOccurrenceSource(
                        calendarIdentifier: calendarIdentifier,
                        title: event.title
                    ),
                    start: start,
                    end: end
                )
            )
        }

        return signatures
    }

    private func appleOccurrenceSignatures(
        for occurrence: LureliaExternalCalendarOccurrence
    ) -> Set<AppleOccurrenceSignature> {
        let start = normalizedOccurrenceTime(occurrence.start)
        let end = normalizedOccurrenceTime(occurrence.end)
        var signatures = Set<AppleOccurrenceSignature>()

        let seriesIdentifier = occurrence.appleSeriesIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !seriesIdentifier.isEmpty {
            signatures.insert(
                AppleOccurrenceSignature(
                    source: "series:\(seriesIdentifier)",
                    start: start,
                    end: end
                )
            )
        }

        let calendarIdentifier = occurrence.calendarIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !calendarIdentifier.isEmpty {
            signatures.insert(
                AppleOccurrenceSignature(
                    source: legacyAppleOccurrenceSource(
                        calendarIdentifier: calendarIdentifier,
                        title: occurrence.title
                    ),
                    start: start,
                    end: end
                )
            )
        }

        return signatures
    }

    private func legacyAppleOccurrenceSource(calendarIdentifier: String, title: String) -> String {
        let cleanTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "legacy:\(calendarIdentifier):\(cleanTitle)"
    }

    private func normalizedOccurrenceTime(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Events")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
            }

            Spacer()

            Button {
                showSharedEvents = true
            } label: {
                eventHeaderIcon(
                    "chatsparkle",
                    size: 24,
                    tint: theme.palette.primaryAction
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shared events")

            Button {
                showAddCalendar = true
            } label: {
                eventHeaderIcon(
                    "addwavy",
                    size: 27,
                    tint: theme.palette.secondaryAccent
                )
            }
            .buttonStyle(.plain)

            Button {
                showCalendarSettings = true
            } label: {
                eventHeaderIcon(
                    "settings",
                    size: 24,
                    tint: theme.palette.indicators
                )
            }
            .buttonStyle(.plain)

            Button {
                calendarForNewEvent = nil
                pendingCalendarForNewEvent = nil
                showCalendarGate = true
            } label: {
                eventHeaderIcon(
                    "writingpencil",
                    size: 28,
                    tint: theme.palette.primaryAction
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }

    private var tabPicker: some View {
        tabPickerContent
            .padding(.horizontal, 24)
    }

    private var tabPickerContent: some View {
        HStack(spacing: 10) {
            ForEach(LureliaEventsTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    let accent = tabAccent(for: tab)

                    ZStack {
                        if selectedTab == tab {
                            BubblyIconMaterial(tint: accent)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(theme.palette.surface)
                        }

                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(selectedTab == tab ? Color.black : theme.palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                selectedTab == tab ? accent : theme.palette.textPrimary.opacity(0.12),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .agenda: return "Upcoming commitments"
        case .month: return focusedDate.formatted(.dateTime.month(.wide).year())
        case .week: return "Seven-day schedule"
        }
    }

    private func tabAccent(for tab: LureliaEventsTab) -> Color {
        switch tab {
        case .agenda:
            return theme.palette.primaryAction
        case .month:
            return theme.palette.secondaryAccent
        case .week:
            return theme.palette.indicators
        }
    }

    private func eventHeaderIcon(
        _ name: String,
        size: CGFloat,
        tint: Color
    ) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .bubblyIconMaterial(tint: tint)
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
    }

    private func selectEvent(_ occurrence: LureliaEventOccurrence) {
        guard let event = events.first(where: { $0.id == occurrence.eventID }) else { return }

        if event.isAppleImportedShadow {
            selectedAppleShadowEvent = event
        } else {
            selectedEvent = event
        }
    }

    /// Routes a tap on any row to the correct detail sheet — local events
    /// without Apple identity open `LureliaEventDetailView`, live Apple
    /// occurrences and persisted Apple shadows open `LureliaAppleEventDetailView`.
    private func selectOccurrence(_ occurrence: LureliaEventUnifiedOccurrence) {
        switch occurrence {
        case .local(let local):
            selectEvent(local)
        case .apple(let apple):
            selectedAppleOccurrence = apple
        }
    }

    private func deleteOccurrence(_ occurrence: LureliaEventUnifiedOccurrence) {
        switch occurrence {
        case .local(let local):
            guard let event = events.first(where: { $0.id == local.eventID }) else { return }

            LureliaEventNotificationManager.shared.cancelNotifications(for: event)

            if event.isAppleImportedShadow {
                if let identifier = event.appleEventIdentifier {
                    try? eventService.deleteAppleOccurrence(eventIdentifier: identifier)
                }
            } else {
                try? eventService.deleteFromAppleCalendar(event)
            }

            modelContext.delete(event)
            try? modelContext.save()

        case .apple(let apple):
            try? eventService.deleteAppleOccurrence(eventIdentifier: apple.appleEventIdentifier)
        }

        loadExternalOccurrences()
        LureliaWidgetReloads.reloadAll()
    }

    private func loadExternalOccurrences() {
        guard eventService.hasCalendarAccess,
              settings.first?.showAppleCalendarEvents ?? true
        else {
            externalOccurrences = []
            if LureliaWidgetShared.saveExternalEventSnapshots([]) {
                LureliaWidgetReloads.reloadAll()
            }
            return
        }

        // If the user has explicitly saved their Apple Calendar visibility
        // (via the calendar settings sheet) and chose to hide every
        // calendar, honor that literally — surface no Apple events. Without
        // this guard, `fetchAppleOccurrences` treats an empty set as "no
        // filter" and returns every calendar, which is the bug the user
        // reported: hidden calendars were still showing.
        let hasConfigured = settings.first?.hasConfiguredAppleCalendarSelection ?? false
        if hasConfigured && selectedAppleCalendarIDs.isEmpty {
            externalOccurrences = []
            if LureliaWidgetShared.saveExternalEventSnapshots([]) {
                LureliaWidgetReloads.reloadAll()
            }
            return
        }

        if settings.first?.twoWayAppleCalendarSyncEnabled == true {
            eventService.importAppleEvents(
                into: modelContext,
                from: displayInterval.start,
                to: displayInterval.end,
                calendarIdentifiers: selectedAppleCalendarIDs
            )
        }

        let fetchedExternalOccurrences = eventService.fetchAppleOccurrences(
            from: displayInterval.start,
            to: displayInterval.end,
            calendarIdentifiers: selectedAppleCalendarIDs
        )
        let resolvedExternalOccurrences = fetchedExternalOccurrences.map { occurrence in
            occurrence.withIcon(iconForExternalOccurrence(occurrence))
        }
        externalOccurrences = resolvedExternalOccurrences
        debugExternalOccurrencesForWidgetExport(resolvedExternalOccurrences)
        let widgetSnapshots = resolvedExternalOccurrences.map {
            LureliaWidgetExternalEventSnapshot(
                id: $0.id,
                appleEventIdentifier: $0.appleEventIdentifier,
                appleSeriesIdentifier: $0.appleSeriesIdentifier,
                appleOccurrenceKey: $0.appleOccurrenceKey,
                calendarIdentifier: $0.calendarIdentifier,
                calendarTitle: $0.calendarTitle,
                title: $0.title,
                icon: $0.icon,
                colorHex: $0.colorHex,
                start: $0.start,
                end: $0.end,
                isAllDay: $0.isAllDay
            )
        }
        debugWidgetSnapshotExport(widgetSnapshots)
        if LureliaWidgetShared.saveExternalEventSnapshots(widgetSnapshots) {
            LureliaWidgetReloads.reloadAll()
        }
    }

    private func iconForExternalOccurrence(_ occurrence: LureliaExternalCalendarOccurrence) -> String? {
        let occurrenceKey = occurrence.appleOccurrenceKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let appleSeriesIdentifier = occurrence.appleSeriesIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let exactIcon = events.first { event in
            event.isAppleImportedShadow &&
            !occurrenceKey.isEmpty &&
            event.resolvedAppleOccurrenceKey == occurrenceKey
        }?
        .displayIcon
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let seriesIcon = events
            .filter { event in
                event.isAppleImportedShadow &&
                !appleSeriesIdentifier.isEmpty &&
                event.resolvedAppleSeriesIdentifier == appleSeriesIdentifier
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
            .first { event in
                let icon = event.displayIcon.trimmingCharacters(in: .whitespacesAndNewlines)
                return !icon.isEmpty && icon != "starcal"
            }?
            .displayIcon
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let icon = exactIcon != nil && exactIcon != "starcal"
            ? exactIcon!
            : (seriesIcon ?? exactIcon ?? "")
        return icon.isEmpty ? nil : icon
    }

    private func migrateEventOriginsIfNeeded() {
        var didChange = false
        for event in events where event.applyInferredEventOriginIfNeeded() {
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
    }

    private func debugExternalOccurrencesForWidgetExport(_ occurrences: [LureliaExternalCalendarOccurrence]) {
        #if DEBUG
        print("[LureliaEventDebug] EXTERNAL OCCURRENCES BEFORE WIDGET SNAPSHOT count: \(occurrences.count)")
        for occurrence in occurrences {
            print("""
            [LureliaEventDebug] EXTERNAL OCCURRENCE FOR SNAPSHOT
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
            icon: \(occurrence.icon ?? "nil")
            """)
        }
        #endif
    }

    private func debugWidgetSnapshotExport(_ snapshots: [LureliaWidgetExternalEventSnapshot]) {
        #if DEBUG
        print("[LureliaEventDebug] WIDGET SNAPSHOT EXPORT count: \(snapshots.count)")
        for snapshot in snapshots {
            print("""
            [LureliaEventDebug] WIDGET SNAPSHOT EXPORT ITEM
            title: \(snapshot.title)
            appleEventIdentifier: \(snapshot.appleEventIdentifier)
            appleSeriesIdentifier: \(snapshot.appleSeriesIdentifier)
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
}
