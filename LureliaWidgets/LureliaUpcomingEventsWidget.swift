//
//  LureliaUpcomingEventsWidget.swift
//  Lurelia
//
//  Upcoming events in chronological order. Each row is tinted with its
//  calendar color: Lurelia primary calendar for in-app events, Apple source
//  calendar for imported Apple events. Read-only at-a-glance widget; no completion/skip
//  controls (events aren't completable in the same way habits/reminders
//  are, and the spec explicitly said not to add unneeded interactions).
//
//  Visually a sibling of LureliaDueRemindersWidget / LureliaHabitsWidget /
//  LureliaDueRoutinesWidget — same padding, corner radii, font sizes,
//  container background, and icon-mask treatment.
//

import WidgetKit
import SwiftUI
import SwiftData
import UIKit
import AppIntents

// MARK: - Widget Item

struct LureliaWidgetEventItem: Identifiable, Hashable {
    /// Unique per row — event ID plus the specific occurrence's start,
    /// so recurring events don't collide.
    let id: String
    let title: String
    let icon: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// Hex color from the event's color authority: Lurelia primary calendar
    /// for in-app events, Apple source calendar for Apple events.
    let colorHex: String
    /// Name of the source calendar, or nil if unassigned. Used for the tiny
    /// caption under the title.
    let calendarName: String?
}

// MARK: - Timeline Entry

struct LureliaUpcomingEventsEntry: TimelineEntry {
    let date: Date
    let events: [LureliaWidgetEventItem]
}

// MARK: - Timeline Provider

struct LureliaUpcomingEventsProvider: AppIntentTimelineProvider {

    /// Widget looks 7 days out. Anything further out is a lot to render at
    /// a glance and is better handled in the app.
    private let lookaheadDays: Int = 7

    func placeholder(in context: Context) -> LureliaUpcomingEventsEntry {
        LureliaUpcomingEventsEntry(
            date: Date(),
            events: [
                LureliaWidgetEventItem(
                    id: "placeholder-1",
                    title: "Team Standup",
                    icon: "starcal",
                    start: Date(),
                    end: Date().addingTimeInterval(1800),
                    isAllDay: false,
                    colorHex: "#7d19f7",
                    calendarName: "Work"
                ),
                LureliaWidgetEventItem(
                    id: "placeholder-2",
                    title: "Dentist",
                    icon: "starcal",
                    start: Date().addingTimeInterval(3 * 3600),
                    end: Date().addingTimeInterval(4 * 3600),
                    isAllDay: false,
                    colorHex: "#03dbfc",
                    calendarName: "Personal"
                )
            ]
        )
    }

    func snapshot(
        for configuration: UpcomingEventsWidgetConfigurationIntent,
        in context: Context
    ) async -> LureliaUpcomingEventsEntry {
        fetchUpcoming(now: Date(), configuration: configuration)
    }

    func timeline(
        for configuration: UpcomingEventsWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<LureliaUpcomingEventsEntry> {
        let now = Date()
        let entry = fetchUpcoming(now: now, configuration: configuration)

        // Refresh every 15 minutes so events roll in/out as time passes,
        // matching what the other widgets do.
        let nextRefresh = now.addingTimeInterval(15 * 60)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    // MARK: - Fetch

    private func fetchUpcoming(
        now: Date,
        configuration: UpcomingEventsWidgetConfigurationIntent
    ) -> LureliaUpcomingEventsEntry {
        do {
            let container = try LureliaWidgetShared.makeModelContainer()
            let context = ModelContext(container)

            let allEvents = try context.fetch(FetchDescriptor<LureliaEvent>())

            // Build a UUID→calendar map once. Also captures the hidden
            // flag so we can filter events whose primary calendar has
            // been hidden by the user.
            let calendars = try context.fetch(FetchDescriptor<LureliaCalendar>())
            let calendarByID: [UUID: LureliaCalendar] = Dictionary(
                uniqueKeysWithValues: calendars.map { ($0.id, $0) }
            )

            let userSettings = try? context.fetch(FetchDescriptor<UserSettings>()).first
            let hasConfiguredApple = userSettings?.hasConfiguredAppleCalendarSelection ?? false
            let visibleAppleIDs = Set(userSettings?.selectedAppleCalendarIDs ?? [])
            let importedAppleOccurrenceKeys = Set(allEvents.compactMap(\.resolvedAppleOccurrenceKey))
            let mirroredRecurringAppleIDs = Set(
                allEvents
                    .filter { $0.recurrence != nil }
                    .compactMap(\.resolvedAppleSeriesIdentifier)
                    .filter { !$0.isEmpty }
            )

            // Optional calendar filter from the widget's config sheet.
            // `nil` means "show every visible calendar".
            let calendarFilter = EventWidgetCalendarFilter(entityID: configuration.calendar?.id)

            let interval = DateInterval(
                start: now,
                end: now.addingTimeInterval(TimeInterval(lookaheadDays * 24 * 60 * 60))
            )

            var items: [LureliaWidgetEventItem] = []

            for event in allEvents {
                let primary = event.calendar

                // Hidden-calendar filter for Lurelia primary calendars.
                if let primary, primary.isHidden { continue }

                // Imported Apple-owned events with no Lurelia primary mirror
                // the main Events page visibility rule.
                if event.isAppleImportedShadow,
                   primary == nil,
                   let appleID = event.appleCalendarIdentifier,
                   !appleID.isEmpty,
                   hasConfiguredApple,
                   !visibleAppleIDs.contains(appleID) {
                    continue
                }

                if let calendarFilter {
                    switch calendarFilter {
                    case .lurelia(let calendarID):
                        guard let primary, primary.id == calendarID else { continue }
                    case .apple(let calendarID):
                        guard event.appleCalendarIdentifier == calendarID else { continue }
                    }
                }

                let occurrences = event.occurrences(in: interval)
                for occ in occurrences where occ.end > now {
                    let hex = eventWidgetColorHex(for: event, primary: primary, occurrence: occ)
                    let calendarName = primary?.name
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nonEmptyOrNilForWidget
                        ?? event.appleCalendarTitle?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nonEmptyOrNilForWidget

                    // Additional calendar colors are deliberately ignored:
                    // the row color is always the event's primary/source
                    // calendar color, not a blend of every membership.
                    _ = event.additionalCalendarIDs.compactMap { calendarByID[$0] }

                    let item = LureliaWidgetEventItem(
                        id: "\(event.id.uuidString)-\(Int(occ.start.timeIntervalSince1970))",
                        title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        icon: event.displayIcon,
                        start: occ.start,
                        end: occ.end,
                        isAllDay: occ.isAllDay,
                        colorHex: hex,
                        calendarName: calendarName
                    )
                    debugWidgetLocalEventItem(event: event, occurrence: occ, primary: primary, item: item)
                    items.append(item)
                }
            }

            for snapshot in LureliaWidgetShared.loadExternalEventSnapshots() {
                let snapshotOccurrenceKey = snapshot.appleOccurrenceKey?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmptyOrNilForWidget
                    ?? LureliaEvent.appleShadowKey(
                        appleEventIdentifier: snapshot.appleSeriesIdentifier ?? snapshot.appleEventIdentifier,
                        occurrenceStart: snapshot.start,
                        occurrenceEnd: snapshot.end,
                        isRecurring: false
                    )
                guard snapshot.end > now,
                      snapshot.start < interval.end,
                      snapshot.end > interval.start,
                      !importedAppleOccurrenceKeys.contains(snapshotOccurrenceKey),
                      !mirroredRecurringAppleIDs.contains(snapshot.appleSeriesIdentifier ?? snapshot.appleEventIdentifier)
                else {
                    continue
                }

                if hasConfiguredApple,
                   !visibleAppleIDs.contains(snapshot.calendarIdentifier) {
                    continue
                }

                if let calendarFilter {
                    switch calendarFilter {
                    case .lurelia:
                        continue
                    case .apple(let calendarID):
                        guard snapshot.calendarIdentifier == calendarID else { continue }
                    }
                }

                let snapshotIcon = snapshot.icon?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmptyOrNilForWidget
                    ?? widgetSeriesIcon(for: snapshot, events: allEvents)
                    ?? "starcal"

                let item = LureliaWidgetEventItem(
                    id: "apple-\(snapshot.id)",
                    title: snapshot.title,
                    icon: snapshotIcon,
                    start: snapshot.start,
                    end: snapshot.end,
                    isAllDay: snapshot.isAllDay,
                    colorHex: snapshot.colorHex,
                    calendarName: snapshot.calendarTitle
                )
                debugWidgetExternalSnapshotItem(snapshot: snapshot, item: item)
                items.append(item)
            }

            // Chronological, cap at what the widget can show.
            let sorted = items.sorted { $0.start < $1.start }
            debugWidgetFinalItems(sorted)

            return LureliaUpcomingEventsEntry(date: Date(), events: sorted)
        } catch {
            return LureliaUpcomingEventsEntry(date: Date(), events: [])
        }
    }
}

private enum EventWidgetCalendarFilter {
    case lurelia(UUID)
    case apple(String)

    init?(entityID: String?) {
        guard let entityID else { return nil }

        if let appleID = LureliaCalendarEntity.appleCalendarIdentifier(from: entityID) {
            self = .apple(appleID)
            return
        }

        guard let uuid = UUID(uuidString: entityID) else { return nil }
        self = .lurelia(uuid)
    }
}

private func eventWidgetColorHex(
    for event: LureliaEvent,
    primary: LureliaCalendar?,
    occurrence: LureliaEventOccurrence
) -> String {
    let primaryColor = primary?.color
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNilForWidget

    if event.isAppleImportedShadow,
       let appleColor = event.appleCalendarColor?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNilForWidget {
        debugWidgetColorResolution(
            event: event,
            primary: primary,
            occurrence: occurrence,
            resolvedColor: appleColor,
            reason: "appleImportedShadow.appleCalendarColor"
        )
        return appleColor
    }

    let resolvedColor = primaryColor
    ?? occurrence.colorHex
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNilForWidget
    ?? event.colorHex
    let reason: String
    if primaryColor != nil {
        reason = "lureliaPrimaryCalendar.color"
    } else if occurrence.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNilForWidget != nil {
        reason = "occurrence.colorHex"
    } else {
        reason = "event.colorHex"
    }
    debugWidgetColorResolution(
        event: event,
        primary: primary,
        occurrence: occurrence,
        resolvedColor: resolvedColor,
        reason: reason
    )
    return resolvedColor
}

private func widgetSeriesIcon(
    for snapshot: LureliaWidgetExternalEventSnapshot,
    events: [LureliaEvent]
) -> String? {
    let occurrenceKey = snapshot.appleOccurrenceKey?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNilForWidget
    let appleEventIdentifier = snapshot.appleEventIdentifier
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let appleSeriesIdentifier = snapshot.appleSeriesIdentifier?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNilForWidget
        ?? appleEventIdentifier

    let exactIcon = events.first { event in
        event.isAppleImportedShadow &&
        occurrenceKey != nil &&
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

    if let exactIcon, !exactIcon.isEmpty, exactIcon != "starcal" {
        return exactIcon
    }

    return seriesIcon ?? exactIcon
}

private func debugWidgetLocalEventItem(
    event: LureliaEvent,
    occurrence: LureliaEventOccurrence,
    primary: LureliaCalendar?,
    item: LureliaWidgetEventItem
) {
    #if DEBUG
    print("""
    [LureliaEventDebug] WIDGET RECEIVED LOCAL/SWIFTDATA EVENT
    eventID: \(event.id.uuidString)
    title: \(event.title)
    originRaw: \(event.eventOriginRaw ?? "nil")
    resolvedOrigin: \(event.eventOrigin.rawValue)
    isAppleImportedShadow: \(event.isAppleImportedShadow)
    appleEventIdentifier: \(event.appleEventIdentifier ?? "nil")
    appleSeriesIdentifier: \(event.appleSeriesIdentifier ?? "nil")
    appleOccurrenceKey: \(event.appleOccurrenceKey ?? "nil")
    appleCalendarID: \(event.appleCalendarIdentifier ?? "nil")
    appleCalendarTitle: \(event.appleCalendarTitle ?? "nil")
    appleCalendarColor: \(event.appleCalendarColor ?? "nil")
    lureliaCalendar: \(primary?.name ?? "nil")
    lureliaCalendarColor: \(primary?.color ?? "nil")
    eventColor: \(event.colorHex)
    occurrenceColor: \(occurrence.colorHex)
    itemColor: \(item.colorHex)
    eventIcon: \(event.displayIcon)
    itemIcon: \(item.icon)
    occurrenceStart: \(occurrence.start)
    occurrenceEnd: \(occurrence.end)
    """)
    #endif
}

private func debugWidgetExternalSnapshotItem(
    snapshot: LureliaWidgetExternalEventSnapshot,
    item: LureliaWidgetEventItem
) {
    #if DEBUG
    print("""
    [LureliaEventDebug] WIDGET RECEIVED EXTERNAL SNAPSHOT ITEM
    title: \(snapshot.title)
    appleEventIdentifier: \(snapshot.appleEventIdentifier)
    appleSeriesIdentifier: \(snapshot.appleSeriesIdentifier ?? "nil")
    appleOccurrenceKey: \(snapshot.appleOccurrenceKey ?? "nil")
    calendarIdentifier: \(snapshot.calendarIdentifier)
    calendarTitle: \(snapshot.calendarTitle)
    snapshotColor: \(snapshot.colorHex)
    itemColor: \(item.colorHex)
    snapshotIcon: \(snapshot.icon ?? "nil")
    itemIcon: \(item.icon)
    start: \(snapshot.start)
    end: \(snapshot.end)
    isAllDay: \(snapshot.isAllDay)
    """)
    #endif
}

private func debugWidgetFinalItems(_ items: [LureliaWidgetEventItem]) {
    #if DEBUG
    print("[LureliaEventDebug] WIDGET FINAL ITEMS count: \(items.count)")
    for item in items {
        print("""
        [LureliaEventDebug] WIDGET FINAL ITEM
        id: \(item.id)
        title: \(item.title)
        icon: \(item.icon)
        colorHex: \(item.colorHex)
        calendarName: \(item.calendarName ?? "nil")
        start: \(item.start)
        end: \(item.end)
        isAllDay: \(item.isAllDay)
        """)
    }
    #endif
}

private func debugWidgetColorResolution(
    event: LureliaEvent,
    primary: LureliaCalendar?,
    occurrence: LureliaEventOccurrence,
    resolvedColor: String,
    reason: String
) {
    #if DEBUG
    print("""
    [LureliaEventDebug] WIDGET COLOR RESOLUTION
    eventID: \(event.id.uuidString)
    title: \(event.title)
    originRaw: \(event.eventOriginRaw ?? "nil")
    resolvedOrigin: \(event.eventOrigin.rawValue)
    isAppleImportedShadow: \(event.isAppleImportedShadow)
    appleCalendarColor: \(event.appleCalendarColor ?? "nil")
    appleSeriesIdentifier: \(event.appleSeriesIdentifier ?? "nil")
    lureliaCalendar: \(primary?.name ?? "nil")
    lureliaCalendarColor: \(primary?.color ?? "nil")
    eventColor: \(event.colorHex)
    occurrenceColor: \(occurrence.colorHex)
    resolvedColor: \(resolvedColor)
    reason: \(reason)
    icon: \(event.displayIcon)
    """)
    #endif
}

private func debugWidgetIconRender(
    requestedName: String,
    resolvedIconName: String,
    renderPath: String
) {
    #if DEBUG
    print("""
    [LureliaEventDebug] WIDGET ICON RENDER
    requestedName: \(requestedName)
    resolvedIconName: \(resolvedIconName)
    renderPath: \(renderPath)
    requestedAssetExists: \(LureliaWidgetShared.widgetIcon(for: resolvedIconName) != nil)
    starcalFallbackExists: \(LureliaWidgetShared.widgetIcon(for: "starcal") != nil)
    """)
    #endif
}

// MARK: - View

struct LureliaUpcomingEventsWidgetView: View {
    let entry: LureliaUpcomingEventsEntry

    @Environment(\.widgetFamily) private var family

    private var maxItems: Int {
        switch family {
        case .systemSmall: return 2
        case .systemMedium: return 3
        case .systemLarge: return 5
        case .systemExtraLarge: return 7
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.events.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(entry.events.prefix(maxItems)) { event in
                        eventRow(event)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            LureliaBackgroundAlt()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let uiImage = LureliaWidgetShared.widgetIcon(for: "starcal") {
                Color.white
                    .mask(
                        Image(uiImage: uiImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    )
                    .frame(width: 15, height: 15)
            } else {
                Image(systemName: "calendar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
            }

            Text("Upcoming Events")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private var emptyState: some View {
        Text("Nothing coming up")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }

    // MARK: Row (tinted with source calendar color)

    private func eventRow(_ event: LureliaWidgetEventItem) -> some View {
        let tint = Color(widgetHex: event.colorHex)

        return HStack(spacing: 10) {
            widgetIcon(event.icon, tint: tint, size: 20)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "Untitled event" : event.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(timeString(for: event))
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .bubblyIconMaterial(tint: tint)

                    if let calendarName = event.calendarName {
                        Text("·")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))

                        Text(calendarName)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { widgetEventCardSurface(tint: tint, cornerRadius: 14) }
    }

    private func widgetEventCardSurface(tint: Color, cornerRadius: CGFloat) -> some View {
        BubblyCardMaterial(tint: tint, cornerRadius: cornerRadius)
            .allowsHitTesting(false)
    }

    /// Compact time label: All-day, today/tomorrow shortcuts, or the
    /// weekday+time for anything further out.
    private func timeString(for event: LureliaWidgetEventItem) -> String {
        if event.isAllDay {
            let df = DateFormatter()
            df.dateFormat = "EEE, MMM d"
            return "\(df.string(from: event.start)) · All day"
        }

        let cal = Calendar.current
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short

        if cal.isDateInToday(event.start) {
            return "Today · \(timeFmt.string(from: event.start))"
        }
        if cal.isDateInTomorrow(event.start) {
            return "Tomorrow · \(timeFmt.string(from: event.start))"
        }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE"
        return "\(dayFmt.string(from: event.start)) · \(timeFmt.string(from: event.start))"
    }

    @ViewBuilder
    private func widgetIcon(
        _ name: String,
        tint: Color,
        size: CGFloat
    ) -> some View {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = trimmedName.isEmpty ? "starcal" : trimmedName

        if let uiImage = LureliaWidgetShared.widgetIcon(for: iconName) {
            let _ = debugWidgetIconRender(
                requestedName: name,
                resolvedIconName: iconName,
                renderPath: "requested-widget-png"
            )
            BubblyIconMaterial(tint: tint)
                .mask {
                    Image(uiImage: uiImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
        } else if let fallbackImage = LureliaWidgetShared.widgetIcon(for: "starcal") {
            let _ = debugWidgetIconRender(
                requestedName: name,
                resolvedIconName: iconName,
                renderPath: "starcal-widget-png-fallback"
            )
            BubblyIconMaterial(tint: tint)
                .mask {
                    Image(uiImage: fallbackImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
        } else {
            let _ = debugWidgetIconRender(
                requestedName: name,
                resolvedIconName: iconName,
                renderPath: "system-calendar-fallback"
            )
            BubblyIconMaterial(tint: tint)
                .mask {
                    Image(systemName: "calendar")
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
        }
    }
}

// MARK: - Widget

struct LureliaUpcomingEventsWidget: Widget {
    let kind = "LureliaUpcomingEventsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: UpcomingEventsWidgetConfigurationIntent.self,
            provider: LureliaUpcomingEventsProvider()
        ) { entry in
            LureliaUpcomingEventsWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming Events")
        .description("See your next events at a glance, tinted by their calendar. Long-press → Edit Widget to pick a specific calendar.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Local string helper (widget scope)

private extension String {
    /// Distinct name from any similar helpers in the widget bundle so it
    /// can't collide during linking.
    var nonEmptyOrNilForWidget: String? {
        isEmpty ? nil : self
    }
}
