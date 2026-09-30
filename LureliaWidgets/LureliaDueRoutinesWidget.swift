//
//  LureliaDueRoutinesWidget.swift
//  Lurelia
//
//  Shows individual routine TASKS (aggregated across every routine) that
//  are soon/due. Each task tile is tinted with its parent routine's color
//  and uses the same custom-asset icon treatment as the rest of the app.
//

import WidgetKit
import SwiftUI
import AppIntents
import SwiftData
import UIKit

// MARK: - Widget Item

struct LureliaWidgetRoutineTaskItem: Identifiable, Hashable {
    /// Unique per row (routine-scoped task ID + due time), to keep ForEach stable when
    /// the same task appears at multiple times of day in future revisions.
    let id: String
    /// Exact action target. Bare `stableTaskID` is not unique across routines.
    let actionID: String
    let stableTaskID: String
    let title: String
    let icon: String
    let routineName: String
    let routineColorHex: String
    /// Actual due time — used for correct chronological sorting. Do NOT sort
    /// on `dueTimeLabel`, which is a display string ("10:10 PM" would sort
    /// before "3:45 PM" alphabetically).
    let dueDate: Date
    let dueTimeLabel: String
    let status: LureliaWidgetTaskStatus
}

enum LureliaWidgetTaskStatus: String, Hashable {
    case dueNow = "Due Now"
    case soon = "Soon"
}

// MARK: - Timeline

struct LureliaDueRoutinesEntry: TimelineEntry {
    let date: Date
    let tasks: [LureliaWidgetRoutineTaskItem]
}

// MARK: - Provider

struct LureliaDueRoutinesProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> LureliaDueRoutinesEntry {
        LureliaDueRoutinesEntry(
            date: Date(),
            tasks: [
                LureliaWidgetRoutineTaskItem(
                    id: "placeholder-1",
                    actionID: "placeholder-1",
                    stableTaskID: "placeholder-1",
                    title: "Hydrate",
                    icon: "glass",
                    routineName: "Morning Ritual",
                    routineColorHex: "#7d19f7",
                    dueDate: Date(),
                    dueTimeLabel: "8:00 AM",
                    status: .dueNow
                ),
                LureliaWidgetRoutineTaskItem(
                    id: "placeholder-2",
                    actionID: "placeholder-2",
                    stableTaskID: "placeholder-2",
                    title: "Stretch",
                    icon: "sparkle",
                    routineName: "Morning Ritual",
                    routineColorHex: "#7d19f7",
                    dueDate: Date().addingTimeInterval(15 * 60),
                    dueTimeLabel: "8:15 AM",
                    status: .soon
                ),
                LureliaWidgetRoutineTaskItem(
                    id: "placeholder-3",
                    actionID: "placeholder-3",
                    stableTaskID: "placeholder-3",
                    title: "Wind Down",
                    icon: "moonzs",
                    routineName: "Evening Wind Down",
                    routineColorHex: "#03dbfc",
                    dueDate: Date().addingTimeInterval(3 * 3600),
                    dueTimeLabel: "9:30 PM",
                    status: .soon
                )
            ]
        )
    }

    func snapshot(
        for configuration: LureliaContentWidgetConfigurationIntent,
        in context: Context
    ) async -> LureliaDueRoutinesEntry {
        fetchTasks()
    }

    func timeline(
        for configuration: LureliaContentWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<LureliaDueRoutinesEntry> {
        let entry = fetchTasks()
        // Refresh every 15 minutes — routine tasks slide from "soon" to "due
        // now" and off the list on a short cadence.
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    // MARK: - Fetch

    private func fetchTasks() -> LureliaDueRoutinesEntry {
        do {
            let container = try LureliaWidgetShared.makeModelContainer()
            let context = ModelContext(container)

            let routines = try context.fetch(FetchDescriptor<LureliaRoutine>())

            // Fetch tasks directly rather than via `routine.tasks` — the
            // relationship can hand back a cached snapshot even on a fresh
            // ModelContext, which is exactly the failure mode that made the
            // widget keep hiding a task after the app un-completed it.
            // Direct queries always read live state from disk.
            let allTasks = try context.fetch(FetchDescriptor<LureliaRoutineTask>())
            let allHistory = try context.fetch(FetchDescriptor<LureliaRoutineTaskHistoryEntry>())
            var didBackfillWidgetIDs = false
            let tasksByRoutineID = Dictionary(grouping: allTasks) { task in
                if !task.routinePersistentIDString.isEmpty {
                    return task.routinePersistentIDString
                }

                if let routineID = task.routine?.persistentID {
                    task.routinePersistentIDString = routineID
                    didBackfillWidgetIDs = true
                    return routineID
                }

                return ""
            }

            let now = Date()
            let calendar = Calendar.current
            let todayWeekday = calendar.component(.weekday, from: now)
            let completedOrSkippedTaskIDsToday = todayHistoryTaskIDs(
                from: allHistory,
                now: now,
                calendar: calendar,
                didBackfillWidgetIDs: &didBackfillWidgetIDs
            )

            var items: [LureliaWidgetRoutineTaskItem] = []
            var didResetStaleTasks = false

            for routine in routines {
                // NO routine-level gate: a task with its own due time is
                // valid regardless of whether the routine's schedule fields
                // happen to include today. The task's due time and
                // pending-state are the source of truth.
                let colorHex = routine.colorHex.isEmpty ? "#7d19f7" : routine.colorHex
                let routineTasks = tasksByRoutineID[routine.persistentID] ?? []

                for task in routineTasks {
                    let actionID = task.routineScopedTaskID

                    if completedOrSkippedTaskIDsToday.contains(actionID)
                        || taskHasTodayResolvedState(task, now: now, calendar: calendar)
                    {
                        continue
                    }

                    if resetStaleTaskStateIfNeeded(task, now: now, calendar: calendar) {
                        didResetStaleTasks = true
                    }

                    guard task.isPending else { continue }

                    guard let dueDate = taskDueDate(
                        task: task,
                        routine: routine,
                        now: now,
                        weekday: todayWeekday,
                        calendar: calendar
                    ) else {
                        continue
                    }

                    let status = classify(dueDate: dueDate, now: now)
                    guard let status else { continue }

                    items.append(
                        LureliaWidgetRoutineTaskItem(
                            id: "\(actionID)::\(Int(dueDate.timeIntervalSince1970))",
                            actionID: actionID,
                            stableTaskID: task.stableTaskID,
                            title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            icon: task.icon.isEmpty ? "sparkle" : task.icon,
                            routineName: routine.name,
                            routineColorHex: colorHex,
                            dueDate: dueDate,
                            dueTimeLabel: dueTimeString(dueDate),
                            status: status
                        )
                    )
                }
            }

            if didResetStaleTasks || didBackfillWidgetIDs {
                try context.save()
            }

            // True chronological order. Do not group every Due Now item ahead
            // of Soon items; the visible widget rows use prefix(maxItems), so
            // status-first sorting can hide the actual next tasks by time.
            let sorted = items.sorted { lhs, rhs in
                return lhs.dueDate < rhs.dueDate
            }

            return LureliaDueRoutinesEntry(date: Date(), tasks: sorted)
        } catch {
            return LureliaDueRoutinesEntry(date: Date(), tasks: [])
        }
    }

    // MARK: - Scheduling helpers

    /// Best-effort due date for `task` on today. If the task has its own
    /// due time, always honor it — the user set it, so it belongs on the
    /// widget today. Only respect `repeatsOnDays + scheduledDays` when both
    /// are actually populated. Falls back to the routine/phase start time
    /// when the task has no explicit time.
    private func taskDueDate(
        task: LureliaRoutineTask,
        routine: LureliaRoutine,
        now: Date,
        weekday: Int,
        calendar: Calendar
    ) -> Date? {
        if task.hasDueTime {
            // Only honor a per-task weekday restriction when the user has
            // actually populated it — an empty `scheduledDays` array with
            // `repeatsOnDays == true` is treated as "no restriction".
            if task.repeatsOnDays
                && !task.scheduledDays.isEmpty
                && !task.scheduledDays.contains(weekday)
            {
                return nil
            }
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = task.dueHour
            comps.minute = task.dueMinute
            comps.second = 0
            return calendar.date(from: comps)
        }

        // Task has no due time — fall back to the routine's start time IF
        // the routine is scheduled today, or to the earliest phase start.
        if routine.scheduleEnabled && routine.scheduledDays.contains(weekday) {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = routine.startHour
            comps.minute = routine.startMinute
            comps.second = 0
            return calendar.date(from: comps)
        }

        if routine.phasesEnabled {
            let earliest = (routine.phases ?? [])
                .filter { $0.scheduleEnabled && $0.scheduledDays.contains(weekday) }
                .map { $0.startHour * 60 + $0.startMinute }
                .min()
            if let earliest {
                var comps = calendar.dateComponents([.year, .month, .day], from: now)
                comps.hour = earliest / 60
                comps.minute = earliest % 60
                comps.second = 0
                return calendar.date(from: comps)
            }
        }

        // Routine has no schedule at all — treat the task as due at the
        // start of today rather than dropping it. Keeps unscheduled routine
        // tasks visible instead of vanishing off the widget.
        if !routine.scheduleEnabled && !routine.phasesEnabled {
            return calendar.startOfDay(for: now)
        }

        return nil
    }

    private func classify(dueDate: Date, now: Date) -> LureliaWidgetTaskStatus? {
        // Anything scheduled for a day that isn't today is out.
        guard Calendar.current.isDate(dueDate, inSameDayAs: now) else { return nil }

        let delta = dueDate.timeIntervalSince(now)

        // Past due → Due Now, and it stays Due Now until the task is
        // completed or skipped (which drops it via the pending filter).
        // No grace-window cutoff — a task the user didn't touch shouldn't
        // silently disappear from the widget.
        if delta <= 0 { return .dueNow }

        // Match the Timeline widget: due/past tasks are Due Now, and anything
        // later today is still Soon.
        return .soon
    }

    private func dueTimeString(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let isPM = hour >= 12
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let meridiem = isPM ? "PM" : "AM"
        if minute == 0 {
            return "\(displayHour) \(meridiem)"
        }
        return "\(displayHour):\(String(format: "%02d", minute)) \(meridiem)"
    }

    @discardableResult
    private func resetStaleTaskStateIfNeeded(
        _ task: LureliaRoutineTask,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard !task.isPending else { return false }

        let completedToday = task.completedAt.map {
            calendar.isDate($0, inSameDayAs: now)
        } ?? false
        let skippedToday = task.skippedAt.map {
            calendar.isDate($0, inSameDayAs: now)
        } ?? false

        guard !completedToday && !skippedToday else { return false }

        task.resetState()
        task.routine?.updatedAt = now
        return true
    }

    private func todayHistoryTaskIDs(
        from history: [LureliaRoutineTaskHistoryEntry],
        now: Date,
        calendar: Calendar,
        didBackfillWidgetIDs: inout Bool
    ) -> Set<String> {
        Set(
            history.compactMap { entry in
                guard calendar.isDate(entry.date, inSameDayAs: now) else { return nil }

                if !entry.routineTaskIDString.isEmpty {
                    return entry.routineTaskIDString
                }

                guard let task = entry.task else { return nil }
                let taskID = task.routineScopedTaskID
                entry.routineTaskIDString = taskID
                didBackfillWidgetIDs = true
                return taskID
            }
        )
    }

    private func taskHasTodayResolvedState(
        _ task: LureliaRoutineTask,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if let completedAt = task.completedAt,
           calendar.isDate(completedAt, inSameDayAs: now) {
            return true
        }

        if let skippedAt = task.skippedAt,
           calendar.isDate(skippedAt, inSameDayAs: now) {
            return true
        }

        return false
    }
}

// MARK: - View

struct LureliaDueRoutinesWidgetView: View {
    let entry: LureliaDueRoutinesEntry

    @Environment(\.widgetFamily) private var family

    /// Maximum number of task tiles per widget family. Sized to match the
    /// Habits widget's larger tile dimensions — systemLarge fits 5.
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

            if entry.tasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(entry.tasks.prefix(maxItems)) { task in
                        taskRow(task)
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
            if let uiImage = LureliaWidgetShared.widgetIcon(for: "repeatfill") {
                Color.white
                    .mask(
                        Image(uiImage: uiImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    )
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "checklist")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
            }

            Text("Routine Tasks")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private var emptyState: some View {
        Text("Nothing due soon")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }

    // MARK: Task row (tinted with parent routine's color)

    private func taskRow(_ task: LureliaWidgetRoutineTaskItem) -> some View {
        let tint = Color(widgetHex: task.routineColorHex)

        return HStack(alignment: .center, spacing: 7) {
            // Task icon — same custom-asset masking treatment as the app.
            widgetIcon(task.icon, tint: tint, size: 18)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title.isEmpty ? "Untitled task" : task.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(task.routineName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            statusPill(task.status, tint: tint)
            skipButton(for: task, tint: tint)
            completeButton(for: task, tint: tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(tint: tint, cornerRadius: 12)
                .allowsHitTesting(false)
        }
    }

    private func statusPill(_ status: LureliaWidgetTaskStatus, tint: Color) -> some View {
        let materialTint: Color = status == .dueNow
            ? tint
            : LColors.neutralPearl
        let foreground: Color = status == .dueNow
            ? tint.adaptivePrimaryText
            : .black

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

    /// Skip button — bare `skipwavy` glyph tinted with the routine color.
    /// Sized to match the completion circle's 24pt footprint so it still
    /// aligns cleanly next to it.
    private func skipButton(
        for task: LureliaWidgetRoutineTaskItem,
        tint: Color
    ) -> some View {
        Button(intent: SkipRoutineTaskWidgetIntent(taskID: task.actionID)) {
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
                    BubblyIconMaterial(tint: tint)
                        .mask {
                            Image(systemName: "forward.fill")
                                .resizable()
                                .scaledToFit()
                        }
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip \(task.title)")
    }

    /// Tap-target circular completion button — outline only until the task
    /// completes (completed tasks are filtered out of the timeline).
    private func completeButton(
        for task: LureliaWidgetRoutineTaskItem,
        tint: Color
    ) -> some View {
        Button(intent: CompleteRoutineTaskWidgetIntent(taskID: task.actionID)) {
            ZStack {
                BubblyIconMaterial(tint: tint)
                    .mask {
                        Circle().strokeBorder(lineWidth: 1.6)
                    }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Complete \(task.title)")
    }

    @ViewBuilder
    private func widgetIcon(_ name: String, tint: Color, size: CGFloat) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = trimmed.isEmpty ? "sparkle" : trimmed

        if let uiImage = LureliaWidgetShared.widgetIcon(for: iconName) {
            BubblyIconMaterial(tint: tint)
                .mask {
                    Image(uiImage: uiImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
        } else {
            BubblyIconMaterial(tint: tint)
                .mask {
                    Image(systemName: iconName)
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
        }
    }
}

// MARK: - Color hex helper (local widget scope)

extension Color {
    init(widgetHex: String) {
        let hex = widgetHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Widget

struct LureliaDueRoutinesWidget: Widget {
    let kind = "LureliaDueRoutinesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: LureliaContentWidgetConfigurationIntent.self,
            provider: LureliaDueRoutinesProvider()
        ) { entry in
            LureliaDueRoutinesWidgetView(entry: entry)
        }
        .configurationDisplayName("Routine Tasks")
        .description("See the routine tasks that are soon or due right now, tinted by their routine.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
