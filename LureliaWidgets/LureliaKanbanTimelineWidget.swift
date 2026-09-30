//
//  LureliaKanbanTimelineWidget.swift
//  Lurelia
//
//  Timeline widget — mirrors the in-app Kanban Timeline for the
//  currently-selected board using the shared `KanbanTimelineEngine`
//  (same logic that drives the app's timeline). Each row is rendered
//  using the Routine Task widget's card style so the widget family
//  feels consistent.
//
//  The engine handles: column membership, per-item fire-time expansion,
//  "keep completed items visible on today", overdue reminders, legacy
//  routine-task lookup ambiguity — none of that is reimplemented here.
//

import WidgetKit
import SwiftUI
import SwiftData
import AppIntents
import UIKit

// MARK: - Widget Item

/// One rendered row on the Timeline widget. Flattens whatever the engine
/// gives us into the display fields the Routine-Task-style card needs.
struct LureliaWidgetKanbanTimelineItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let columnName: String
    let tintHex: String            // parent column color
    let fireDate: Date
    let status: LureliaWidgetKanbanTimelineStatus
    let itemKind: LureliaWidgetKanbanTimelineItemKind
    /// Item identifier for widget-intent hookups. Routine tasks use the
    /// routine-scoped Kanban ID so same-named tasks in different routines do
    /// not collide.
    let itemActionID: String
    /// Whether this row's item type has a skip action available.
    let canSkip: Bool
}

enum LureliaWidgetKanbanTimelineStatus: String, Hashable {
    case dueNow = "Due Now"
    case soon = "Soon"
    case completed = "Completed"
    case skipped = "Skipped"
}

enum LureliaWidgetKanbanTimelineItemKind: String, Hashable {
    case reminder, habit, routineTask, routine
}

// MARK: - Timeline Entry

struct LureliaKanbanTimelineEntry: TimelineEntry {
    let date: Date
    let boardName: String
    let boardColorHex: String
    let items: [LureliaWidgetKanbanTimelineItem]
}

// MARK: - Provider

struct LureliaKanbanTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> LureliaKanbanTimelineEntry {
        LureliaKanbanTimelineEntry(
            date: Date(),
            boardName: "Daily Tasks",
            boardColorHex: "#7d19f7",
            items: [
                LureliaWidgetKanbanTimelineItem(
                    id: "placeholder-1",
                    title: "Hydrate",
                    icon: "glass",
                    columnName: "Morning",
                    tintHex: "#7d19f7",
                    fireDate: Date(),
                    status: .dueNow,
                    itemKind: .habit,
                    itemActionID: "placeholder-1",
                    canSkip: true
                ),
                LureliaWidgetKanbanTimelineItem(
                    id: "placeholder-2",
                    title: "Take vitamins",
                    icon: "pillfill",
                    columnName: "Morning",
                    tintHex: "#7d19f7",
                    fireDate: Date().addingTimeInterval(1800),
                    status: .soon,
                    itemKind: .routineTask,
                    itemActionID: "placeholder-2",
                    canSkip: true
                )
            ]
        )
    }

    func snapshot(
        for configuration: KanbanTimelineWidgetConfigurationIntent,
        in context: Context
    ) async -> LureliaKanbanTimelineEntry {
        fetch(configuration: configuration, now: Date())
    }

    func timeline(
        for configuration: KanbanTimelineWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<LureliaKanbanTimelineEntry> {
        let now = Date()
        let entry = fetch(configuration: configuration, now: now)

        // Refresh every 15 minutes so status labels roll over as time
        // passes (same cadence as the other Lurelia widgets).
        let nextRefresh = now.addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    // MARK: Fetch

    private func fetch(
        configuration: KanbanTimelineWidgetConfigurationIntent,
        now: Date
    ) -> LureliaKanbanTimelineEntry {
        do {
            let container = try LureliaWidgetShared.makeModelContainer()
            let ctx = ModelContext(container)

            // Resolve the configured board id → KanbanBoard. If nothing
            // is configured yet or the previously-selected board was
            // deleted, fall back to the first board sorted by
            // sortOrder so the widget still shows something useful.
            let allBoards = try ctx.fetch(
                FetchDescriptor<KanbanBoard>(sortBy: [SortDescriptor(\.sortOrder)])
            )
            let selectedBoard: KanbanBoard?
            if let entity = configuration.board,
               let uuid = UUID(uuidString: entity.id) {
                selectedBoard = allBoards.first { $0.id == uuid } ?? allBoards.first
            } else {
                selectedBoard = allBoards.first
            }

            guard let board = selectedBoard else {
                return LureliaKanbanTimelineEntry(
                    date: Date(),
                    boardName: configuration.board?.name ?? "Timeline",
                    boardColorHex: configuration.board?.colorHex ?? "#7d19f7",
                    items: []
                )
            }

            let allReminders = try ctx.fetch(FetchDescriptor<LureliaReminder>())
            let allRoutines = try ctx.fetch(FetchDescriptor<LureliaRoutine>())
            let allHabits = try ctx.fetch(FetchDescriptor<LureliaHabit>())
            let allRoutineTasks = allRoutines.flatMap { $0.sortedTasks }

            // Same engine + rules the in-app timeline uses.
            let occurrences = KanbanTimelineEngine.occurrences(
                for: board,
                on: now,
                allReminders: allReminders,
                allRoutines: allRoutines,
                allRoutineTasks: allRoutineTasks,
                allHabits: allHabits
            )

            // Fast id maps for status resolution during row assembly.
            let remindersByID = Dictionary(
                uniqueKeysWithValues: allReminders.map { ($0.id.uuidString, $0) }
            )
            let habitsByKanbanID = Dictionary(
                allHabits.map { ($0.kanbanItemID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let routineTasksByKanbanID = Dictionary(
                allRoutineTasks.map { ($0.kanbanItemID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let calendar = Calendar.current
            var items: [LureliaWidgetKanbanTimelineItem] = []

            for occ in occurrences {
                guard let column = occ.column else { continue }

                let display = displayItem(
                    for: occ,
                    column: column,
                    now: now,
                    calendar: calendar,
                    remindersByID: remindersByID,
                    habitsByKanbanID: habitsByKanbanID,
                    routineTasksByKanbanID: routineTasksByKanbanID
                )

                guard let display else { continue }

                // The widget is a "still-to-do" glance — filter out
                // anything the user has already resolved (completed or
                // skipped). Keeping them here would waste tiles and
                // defeat the widget's purpose.
                switch display.status {
                case .completed, .skipped:
                    continue
                case .dueNow, .soon:
                    items.append(display)
                }
            }

            return LureliaKanbanTimelineEntry(
                date: Date(),
                boardName: board.name,
                boardColorHex: board.colorHex,
                items: items
            )
        } catch {
            return LureliaKanbanTimelineEntry(
                date: Date(),
                boardName: configuration.board?.name ?? "Timeline",
                boardColorHex: configuration.board?.colorHex ?? "#7d19f7",
                items: []
            )
        }
    }

    // MARK: Display translation

    private func displayItem(
        for occ: KanbanTimelineOccurrence,
        column: KanbanColumn,
        now: Date,
        calendar: Calendar,
        remindersByID: [String: LureliaReminder],
        habitsByKanbanID: [String: LureliaHabit],
        routineTasksByKanbanID: [String: LureliaRoutineTask]
    ) -> LureliaWidgetKanbanTimelineItem? {
        let columnName = column.name
        let tintHex = column.colorHex

        switch occ.kind {
        case .reminder(let id):
            guard let reminder = remindersByID[id] else { return nil }
            return LureliaWidgetKanbanTimelineItem(
                id: occ.id,
                title: reminder.title,
                icon: reminder.icon.isEmpty ? "bellfill" : reminder.icon,
                columnName: columnName,
                tintHex: tintHex,
                fireDate: occ.fireDate,
                status: reminderStatus(
                    reminder,
                    fireDate: occ.fireDate,
                    now: now,
                    calendar: calendar
                ),
                itemKind: .reminder,
                itemActionID: reminder.id.uuidString,
                canSkip: true
            )

        case .habit(let kanbanID):
            guard let habit = habitsByKanbanID[kanbanID] else { return nil }
            return LureliaWidgetKanbanTimelineItem(
                id: occ.id,
                title: habit.title,
                icon: habit.iconName ?? "flame",
                columnName: columnName,
                tintHex: tintHex,
                fireDate: occ.fireDate,
                status: habitStatus(
                    habit,
                    fireDate: occ.fireDate,
                    now: now,
                    calendar: calendar
                ),
                itemKind: .habit,
                itemActionID: habit.id.uuidString,
                canSkip: true
            )

        case .routineTask(let kanbanID):
            guard let task = routineTasksByKanbanID[kanbanID] else { return nil }
            return LureliaWidgetKanbanTimelineItem(
                id: occ.id,
                title: task.title,
                icon: task.icon.isEmpty ? "sparkle" : task.icon,
                columnName: columnName,
                tintHex: tintHex,
                fireDate: occ.fireDate,
                status: routineTaskStatus(
                    task,
                    fireDate: occ.fireDate,
                    now: now,
                    calendar: calendar
                ),
                itemKind: .routineTask,
                itemActionID: task.kanbanItemID,
                canSkip: true
            )

        case .routine:
            // Whole-routine cards aren't first-class in this widget —
            // the app timeline expands them per-task via routineTask
            // cards. Nothing to render at this level.
            return nil

        case .quickTask:
            // Quick Tasks are currently an in-app Kanban Timeline surface.
            return nil
        }
    }

    // MARK: - Status helpers

    private func reminderStatus(
        _ reminder: LureliaReminder,
        fireDate: Date,
        now: Date,
        calendar: Calendar
    ) -> LureliaWidgetKanbanTimelineStatus {
        // Completed for this occurrence?
        let completedOnDay = ([reminder.completedAt].compactMap { $0 } + reminder.completionTimestamps)
            .contains { calendar.isDate($0, inSameDayAs: fireDate) }
        if completedOnDay { return .completed }

        // Skipped for this occurrence?
        let skippedOnDay = reminder.skippedTimestamps
            .contains { calendar.isDate($0, inSameDayAs: fireDate) }
        if skippedOnDay { return .skipped }

        return fireDate <= now ? .dueNow : .soon
    }

    private func habitStatus(
        _ habit: LureliaHabit,
        fireDate: Date,
        now: Date,
        calendar: Calendar
    ) -> LureliaWidgetKanbanTimelineStatus {
        if let log = habit.log(on: fireDate, calendar: calendar),
           log.isCompleted(atFireDate: fireDate, calendar: calendar) {
            return .completed
        }
        if habit.skip(on: fireDate, calendar: calendar) != nil {
            return .skipped
        }
        return fireDate <= now ? .dueNow : .soon
    }

    private func routineTaskStatus(
        _ task: LureliaRoutineTask,
        fireDate: Date,
        now: Date,
        calendar: Calendar
    ) -> LureliaWidgetKanbanTimelineStatus {
        // Match the in-app routine task status resolver: history entries
        // are authoritative, then completedAt/skippedAt on the task.
        if let entry = task.sortedHistory.first(where: { calendar.isDate($0.date, inSameDayAs: fireDate) }) {
            return entry.wasCompleted ? .completed : .skipped
        }

        let completedOnDay = task.completedAt.flatMap {
            calendar.isDate($0, inSameDayAs: fireDate) ? $0 : nil
        }
        let skippedOnDay = task.skippedAt.flatMap {
            calendar.isDate($0, inSameDayAs: fireDate) ? $0 : nil
        }

        if let completedOnDay, let skippedOnDay {
            return completedOnDay >= skippedOnDay ? .completed : .skipped
        }
        if completedOnDay != nil { return .completed }
        if skippedOnDay != nil { return .skipped }

        return fireDate <= now ? .dueNow : .soon
    }
}

// MARK: - Widget View

struct LureliaKanbanTimelineWidgetView: View {
    let entry: LureliaKanbanTimelineEntry

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

            if entry.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(entry.items.prefix(maxItems)) { item in
                        itemRow(item)
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
            // Rendered exactly the way every other Lurelia widget renders
            // its title icon: white-color mask over a template-rendered
            // custom PDF asset, `.scaledToFit()`, in a 14pt frame. This
            // is what the Routine Tasks / Habits / Reminders widget
            // headers all use — nothing more, nothing less.
            if let uiImage = LureliaWidgetShared.widgetIcon(for: "ringstarcal") {
                Color.white
                    .mask(
                        Image(uiImage: uiImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    )
                    .frame(width: 14, height: 14)
            } else {
                Color.clear.frame(width: 14, height: 14)
            }

            Text(entry.boardName.isEmpty ? "Timeline" : entry.boardName)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    /// Material-masked row icon. The shared icon material supplies the
    /// tint treatment while the custom asset remains the exact mask.
    @ViewBuilder
    private func materialAssetIcon(
        _ name: String,
        tint: Color,
        size: CGFloat
    ) -> some View {
        if let uiImage = LureliaWidgetShared.widgetIcon(for: name) {
            BubblyIconMaterial(tint: tint)
                .mask {
                    Image(uiImage: uiImage)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    /// Native-color variant. Preserves the icon's own RGB pixels so
    /// solid-silhouette assets (jars, pill bottles, etc.) render as the
    /// designer drew them instead of getting flattened into a colored
    /// blob by `Color.mask`. Used for the per-item row icon where each
    /// icon is chosen for its own visual identity.
    @ViewBuilder
    private func nativeAssetIcon(_ name: String, size: CGFloat) -> some View {
        if let uiImage = LureliaWidgetShared.widgetIcon(for: name) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private var emptyState: some View {
        Text("Nothing on this board today")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    // MARK: Item row — Routine Task widget card style

    private func itemRow(_ item: LureliaWidgetKanbanTimelineItem) -> some View {
        let tint = Color(widgetHex: item.tintHex)

        return HStack(alignment: .center, spacing: 7) {
            widgetIcon(item.icon, tint: tint, size: 22)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.columnName.isEmpty ? " " : item.columnName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            statusPill(item.status, tint: tint)

            if item.canSkip && !isTerminal(item.status) {
                skipButton(for: item, tint: tint)
            }

            completeButton(for: item, tint: tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(tint: tint, cornerRadius: 12)
                .allowsHitTesting(false)
        }
    }

    private func isTerminal(_ status: LureliaWidgetKanbanTimelineStatus) -> Bool {
        status == .completed || status == .skipped
    }

    // MARK: Pills / buttons (matches the Routine Task widget)

    private func statusPill(
        _ status: LureliaWidgetKanbanTimelineStatus,
        tint: Color
    ) -> some View {
        let materialTint: Color
        let foreground: Color
        switch status {
        case .dueNow:
            materialTint = tint
            foreground = tint.adaptivePrimaryText
        case .completed:
            materialTint = tint
            foreground = tint.adaptivePrimaryText
        case .skipped:
            materialTint = LColors.neutralPearl
            foreground = .black
        case .soon:
            materialTint = LColors.neutralPearl
            foreground = .black
        }

        return Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                BubblyIconMaterial(tint: materialTint)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
    }

    /// Skip button — structurally identical to the Routines widget's
    /// skip button: Button-with-intent whose label is the tinted glyph
    /// inside a fixed 24pt frame with `.contentShape(Rectangle())`
    /// applied directly to the label. No Group wrapper, no nested
    /// ZStack — anything that adds ambiguous hit-test geometry between
    /// the Button and its label can silently swallow taps in a widget.
    @ViewBuilder
    private func skipButton(
        for item: LureliaWidgetKanbanTimelineItem,
        tint: Color
    ) -> some View {
        if let kindString = timelineKindString(item.itemKind) {
            Button(
                intent: SkipTimelineItemWidgetIntent(
                    itemKind: kindString,
                    itemID: item.itemActionID,
                    fireDate: item.fireDate
                )
            ) {
                skipGlyphLabel(tint: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip \(item.title)")
        } else {
            skipGlyphLabel(tint: tint)
        }
    }

    /// The label used inside every skip Button. Kept as a plain Group
    /// (no ZStack) so the Button's layout child is the same 24×24 shape
    /// SwiftUI hit-tests against — matches the working Routines widget.
    private func skipGlyphLabel(tint: Color) -> some View {
        Group {
            if let uiImage = LureliaWidgetShared.widgetIcon(for: "skipwavy") {
                BubblyIconMaterial(tint: tint)
                    .mask {
                        Image(uiImage: uiImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    }
            } else {
                Color.clear
            }
        }
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }

    /// Complete circle — structurally identical to the Routines widget's
    /// complete button. Flat stroked circle with an optional checkmark
    /// overlay via `.overlay` (not ZStack); the Button's label is the
    /// sized circle directly with `.contentShape(Circle())` inside the
    /// label so the tap target is exactly the visible 24pt circle.
    @ViewBuilder
    private func completeButton(
        for item: LureliaWidgetKanbanTimelineItem,
        tint: Color
    ) -> some View {
        if let kindString = timelineKindString(item.itemKind) {
            Button(
                intent: CompleteTimelineItemWidgetIntent(
                    itemKind: kindString,
                    itemID: item.itemActionID,
                    fireDate: item.fireDate
                )
            ) {
                completeCircleLabel(tint: tint, filled: item.status == .completed)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
        } else {
            completeCircleLabel(tint: tint, filled: false)
        }
    }

    /// Maps the widget-side item kind enum to the string constant the
    /// Timeline widget's dedicated intents use. Returns `nil` for
    /// `.routine` (whole-routine cards don't get interactive buttons on
    /// the Timeline widget).
    private func timelineKindString(_ kind: LureliaWidgetKanbanTimelineItemKind) -> String? {
        switch kind {
        case .habit:       return TimelineItemKindString.habit
        case .reminder:    return TimelineItemKindString.reminder
        case .routineTask: return TimelineItemKindString.routineTask
        case .routine:     return nil
        }
    }

    private func completeCircleLabel(tint: Color, filled: Bool) -> some View {
        ZStack {
            BubblyIconMaterial(tint: tint)
                .mask {
                    Circle().strokeBorder(lineWidth: 1.6)
                }

            if filled,
               let uiImage = LureliaWidgetShared.widgetIcon(for: "checkwavy") {
                tint.adaptivePrimaryText
                    .mask(
                        Image(uiImage: uiImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    )
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 24, height: 24)
        .contentShape(Circle())
    }

    @ViewBuilder
    private func widgetIcon(_ name: String, tint: Color, size: CGFloat) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = trimmed.isEmpty ? "sparkle" : trimmed

        // Row icons render tinted with the column color — matches how
        // they rendered before. The white template silhouette exported
        // by the app gets colorized via `Color.mask(Image)`.
        if LureliaWidgetShared.widgetIcon(for: iconName) != nil {
            materialAssetIcon(iconName, tint: tint, size: size)
        } else {
            materialAssetIcon("sparkle", tint: tint, size: size)
        }
    }
}

// MARK: - Widget

struct LureliaKanbanTimelineWidget: Widget {
    let kind = "LureliaKanbanTimelineWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: KanbanTimelineWidgetConfigurationIntent.self,
            provider: LureliaKanbanTimelineProvider()
        ) { entry in
            LureliaKanbanTimelineWidgetView(entry: entry)
        }
        .configurationDisplayName("Timeline")
        .description("Your Kanban Timeline for the day. Long-press → Edit Widget to pick a board.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
