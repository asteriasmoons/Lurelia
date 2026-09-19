//
//  LureliaHabitsWidget.swift
//  Lurelia
//

import WidgetKit
import SwiftUI
import AppIntents
import SwiftData
import UIKit

// MARK: - Widget Item

struct LureliaWidgetHabitItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let icon: String
    let count: Int
    let target: Int
    let status: LureliaWidgetHabitStatus
    let streak: Int
    let firedCount: Int
    /// User-selected habit color hex (falls back to the app default
    /// `#7d19f7` for legacy habits with no color set).
    let colorHex: String
}

enum LureliaWidgetHabitStatus: String, Hashable {
    case dueNow = "Due Now"
    case soon = "Soon"
    case partial = "In Progress"
    case done = "Done"
    case skipped = "Skipped"
}

// MARK: - Timeline Entry

struct LureliaHabitsEntry: TimelineEntry {
    let date: Date
    let habits: [LureliaWidgetHabitItem]
    let debugInfo: String
}

// MARK: - Timeline Provider

struct LureliaHabitsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LureliaHabitsEntry {
        LureliaHabitsEntry(
            date: Date(),
            habits: [
                LureliaWidgetHabitItem(
                    id: UUID(),
                    title: "Meditate",
                    icon: "sparklesfill",
                    count: 1,
                    target: 1,
                    status: .done,
                    streak: 12,
                    firedCount: 1,
                    colorHex: "#7d19f7"
                ),
                LureliaWidgetHabitItem(
                    id: UUID(),
                    title: "Read",
                    icon: "bookfill",
                    count: 0,
                    target: 1,
                    status: .soon,
                    streak: 5,
                    firedCount: 0,
                    colorHex: "#03dbfc"
                )
            ],
            debugInfo: "placeholder"
        )
    }

    func snapshot(
        for configuration: LureliaContentWidgetConfigurationIntent,
        in context: Context
    ) async -> LureliaHabitsEntry {
        let now = Date()
        let result = fetchWidgetHabits(now: now)
        return LureliaHabitsEntry(
            date: now,
            habits: result.items,
            debugInfo: result.debugInfo
        )
    }

    func timeline(
        for configuration: LureliaContentWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<LureliaHabitsEntry> {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )

        // Collect all upcoming fire times from all habits today
        var fireDates: [Date] = [now]
        let upcomingTimes = collectUpcomingFireTimes(now: now, calendar: calendar)
        fireDates.append(contentsOf: upcomingTimes)
        fireDates.append(tomorrow)

        // Deduplicate and sort
        let uniqueDates = Array(Set(fireDates)).sorted()

        // Generate an entry for each date so the widget refreshes at each fire time
        let entries: [LureliaHabitsEntry] = uniqueDates.map { date in
            let result = fetchWidgetHabits(now: date)
            return LureliaHabitsEntry(
                date: date,
                habits: result.items,
                debugInfo: result.debugInfo
            )
        }

        return Timeline(
            entries: entries,
            policy: .after(tomorrow)
        )
    }

    private func collectUpcomingFireTimes(now: Date, calendar: Calendar) -> [Date] {
        guard let container = try? LureliaWidgetShared.makeModelContainer() else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LureliaHabit>()
        guard let habits = try? context.fetch(descriptor) else { return [] }

        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        var dates: [Date] = []

        for habit in habits where !habit.isArchived && habit.isActiveOn(now, calendar: calendar) {
            guard let data = habit.timesOfDayStorage.data(using: .utf8),
                  let times = try? JSONDecoder().decode([String].self, from: data) else { continue }

            for timeStr in times {
                let parts = timeStr.split(separator: ":")
                guard parts.count == 2,
                      let hour = Int(parts[0]),
                      let minute = Int(parts[1]) else { continue }

                var fireComponents = todayComponents
                fireComponents.hour = hour
                fireComponents.minute = minute
                fireComponents.second = 0

                if let fireDate = calendar.date(from: fireComponents), fireDate > now {
                    dates.append(fireDate)
                }
            }
        }

        return dates
    }

    private func fetchWidgetHabits(now: Date) -> (items: [LureliaWidgetHabitItem], debugInfo: String) {
        do {
            let container = try LureliaWidgetShared.makeModelContainer()
            let context = ModelContext(container)

            let descriptor = FetchDescriptor<LureliaHabit>(
                sortBy: [SortDescriptor(\.title)]
            )

            let allHabits = try context.fetch(descriptor)
            let allLogs = try context.fetch(FetchDescriptor<LureliaHabitLog>())
            let allSkips = try context.fetch(FetchDescriptor<LureliaHabitSkip>())
            let calendar = Calendar.current

            // Filter: active (not archived) and scheduled for today
            let todaysHabits = allHabits.filter { habit in
                !habit.isArchived && habit.isActiveOn(now, calendar: calendar)
            }

            let todayStart = calendar.startOfDay(for: now)
            let todayLogsByHabitID = logsByHabitID(
                from: allLogs,
                habits: allHabits,
                todayStart: todayStart,
                calendar: calendar
            )
            let skippedHabitIDs = skippedHabitIDs(
                from: allSkips,
                habits: allHabits,
                todayStart: todayStart,
                calendar: calendar
            )

            let items: [LureliaWidgetHabitItem] = todaysHabits.compactMap { habit in
                let target = habit.target
                let count = effectiveCompletionCount(
                    for: todayLogsByHabitID[habit.id] ?? [],
                    target: target
                )
                let fired = firedCountToday(habit, now: now, calendar: calendar)

                let status: LureliaWidgetHabitStatus
                if skippedHabitIDs.contains(habit.id) && count == 0 {
                    status = .skipped
                } else if count >= target {
                    status = .done
                } else if fired > count {
                    // A fire time passed and she hasn't completed it yet
                    status = .dueNow
                } else if count > 0 {
                    // Caught up with all fired times, waiting for next
                    status = .partial
                } else {
                    // Nothing fired yet, nothing done
                    status = .soon
                }

                let hex = habit.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)

                return LureliaWidgetHabitItem(
                    id: habit.id,
                    title: habit.title,
                    icon: habit.iconName ?? "repeatfill",
                    count: count,
                    target: target,
                    status: status,
                    streak: habit.dailyStreak,
                    firedCount: 0,
                    colorHex: hex.isEmpty ? "#7d19f7" : hex
                )
            }
            .sorted { a, b in
                // Due now first, then partial, then soon, then done/skipped
                let order: [LureliaWidgetHabitStatus] = [.dueNow, .partial, .soon, .done, .skipped]
                let aIdx = order.firstIndex(of: a.status) ?? 0
                let bIdx = order.firstIndex(of: b.status) ?? 0
                if aIdx != bIdx { return aIdx < bIdx }
                return a.title.localizedCompare(b.title) == .orderedAscending
            }
            .prefix(4)
            .map { $0 }

            let debug = "raw=\(allHabits.count) today=\(todaysHabits.count) shown=\(items.count)"
            return (items, debug)
        } catch {
            return ([], "SwiftData error: \(error.localizedDescription)")
        }
    }

    private func logsByHabitID(
        from logs: [LureliaHabitLog],
        habits: [LureliaHabit],
        todayStart: Date,
        calendar: Calendar
    ) -> [UUID: [LureliaHabitLog]] {
        var result: [UUID: [LureliaHabitLog]] = [:]
        var seenLogIDs = Set<UUID>()

        for log in logs where calendar.isDate(log.dayStart, inSameDayAs: todayStart) {
            let storedID = UUID(uuidString: log.habitIDString)
            guard let habitID = storedID ?? log.habit?.id else { continue }
            result[habitID, default: []].append(log)
            seenLogIDs.insert(log.id)
        }

        for habit in habits {
            for log in habit.logs ?? [] where calendar.isDate(log.dayStart, inSameDayAs: todayStart) {
                guard !seenLogIDs.contains(log.id) else { continue }
                result[habit.id, default: []].append(log)
                seenLogIDs.insert(log.id)
            }
        }

        return result
    }

    private func skippedHabitIDs(
        from skips: [LureliaHabitSkip],
        habits: [LureliaHabit],
        todayStart: Date,
        calendar: Calendar
    ) -> Set<UUID> {
        var result = Set<UUID>()

        for skip in skips where calendar.isDate(skip.dayStart, inSameDayAs: todayStart) {
            let storedID = UUID(uuidString: skip.habitIDString)
            if let habitID = storedID ?? skip.habit?.id {
                result.insert(habitID)
            }
        }

        for habit in habits {
            if (habit.skips ?? []).contains(where: { calendar.isDate($0.dayStart, inSameDayAs: todayStart) }) {
                result.insert(habit.id)
            }
        }

        return result
    }

    private func effectiveCompletionCount(for logs: [LureliaHabitLog], target: Int) -> Int {
        let storedCount = logs.map(\.count).max() ?? 0
        let fireTimeCount = Set(logs.flatMap { $0.completedFireTimes }).count
        return min(target, max(storedCount, fireTimeCount))
    }

    private func habitHasFiredToday(_ habit: LureliaHabit, now: Date, calendar: Calendar) -> Bool {
        return firedCountToday(habit, now: now, calendar: calendar) > 0
    }

    private func firedCountToday(_ habit: LureliaHabit, now: Date, calendar: Calendar) -> Int {
        guard let data = habit.timesOfDayStorage.data(using: .utf8),
              let times = try? JSONDecoder().decode([String].self, from: data),
              !times.isEmpty else {
            return 0
        }

        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        var count = 0

        for timeStr in times {
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { continue }

            var fireComponents = todayComponents
            fireComponents.hour = hour
            fireComponents.minute = minute
            fireComponents.second = 0

            if let fireDate = calendar.date(from: fireComponents), fireDate <= now {
                count += 1
            }
        }

        return count
    }
}

// MARK: - Widget View

struct LureliaHabitsWidgetView: View {
    let entry: LureliaHabitsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.habits.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(entry.habits.prefix(4)) { habit in
                        habitRow(habit)
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

    private var header: some View {
        HStack(spacing: 8) {
            widgetIcon("clockfill", size: 17)

            Text("Habits")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text("Today")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No habits for today")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(entry.debugInfo)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private func habitRow(_ habit: LureliaWidgetHabitItem) -> some View {
        let tint = Color(widgetHex: habit.colorHex)

        return HStack(spacing: 9) {
            // Complete button
            if habit.status == .done {
                completedCircle(tint: tint)
            } else if habit.status == .skipped {
                skippedCircle
            } else {
                Button(
                    intent: CompleteHabitWidgetIntent(
                        habitID: habit.id.uuidString
                    )
                ) {
                    progressCircle(habit: habit, tint: tint)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            widgetIcon(habit.icon, tint: tint, size: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(statusLabel(for: habit))
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(statusColor(for: habit.status, tint: tint))
                }
            }

            Spacer(minLength: 0)

            // Skip button (only for dueNow/soon/partial)
            if habit.status == .dueNow || habit.status == .soon || habit.status == .partial {
                Button(
                    intent: SkipHabitWidgetIntent(
                        habitID: habit.id.uuidString
                    )
                ) {
                    skipIcon(size: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.55), lineWidth: 1)
        )
    }

    // MARK: - Circle States

    private func progressCircle(habit: LureliaWidgetHabitItem, tint: Color) -> some View {
        let size: CGFloat = 28
        let dotCount = 16
        let dotRadius: CGFloat = 1.5
        let ringRadius: CGFloat = (size / 2) - dotRadius
        let filledDots = habit.target > 1
            ? Int(round(Double(dotCount) * Double(habit.count) / Double(habit.target)))
            : 0

        return ZStack {
            // Background dots
            ForEach(0..<dotCount, id: \.self) { i in
                let angle = (2 * .pi / Double(dotCount)) * Double(i) - .pi / 2
                let x = cos(angle) * Double(ringRadius)
                let y = sin(angle) * Double(ringRadius)

                Circle()
                    .fill(tint.opacity(0.28))
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .offset(x: x, y: y)
            }

            // Progress dots (tinted with habit color)
            let visibleFilled = habit.target > 1 && habit.count > 0 ? filledDots : dotCount
            ForEach(0..<visibleFilled, id: \.self) { i in
                let angle = (2 * .pi / Double(dotCount)) * Double(i) - .pi / 2
                let x = cos(angle) * Double(ringRadius)
                let y = sin(angle) * Double(ringRadius)

                Circle()
                    .fill(tint)
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: size, height: size)
    }

    private func completedCircle(tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint)
                .frame(width: 28, height: 28)

            if let uiImage = LureliaWidgetShared.widgetIcon(for: "checkwavy") {
                Image(uiImage: uiImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white)
            }
        }
    }

    private var skippedCircle: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 28, height: 28)

            if let uiImage = LureliaWidgetShared.widgetIcon(for: "minuswavy") {
                Image(uiImage: uiImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Status

    private func statusLabel(for habit: LureliaWidgetHabitItem) -> String {
        switch habit.status {
        case .done:
            return habit.target > 1 ? "Done · \(habit.count)/\(habit.target)" : "Done"
        case .skipped:
            return "Skipped"
        case .partial:
            return "In Progress · \(habit.count)/\(habit.target)"
        case .dueNow:
            return habit.count > 0
                ? "Due Now · \(habit.count)/\(habit.target)"
                : (habit.target > 1 ? "Due Now · 0/\(habit.target)" : "Due Now")
        case .soon:
            return habit.target > 1 ? "Soon · 0/\(habit.target)" : "Soon"
        }
    }

    private func statusColor(for status: LureliaWidgetHabitStatus, tint: Color) -> Color {
        switch status {
        case .dueNow, .soon, .partial, .done:
            return tint
        case .skipped:
            return .white.opacity(0.45)
        }
    }

    @ViewBuilder
    private func skipIcon(size: CGFloat) -> some View {
        if let uiImage = LureliaWidgetShared.widgetIcon(for: "skipwavy") {
            Image(uiImage: uiImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.white.opacity(0.35))
        } else {
            Image(systemName: "forward.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    @ViewBuilder
    private func widgetIcon(
        _ name: String,
        tint: Color = .white,
        size: CGFloat
    ) -> some View {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let iconName = trimmedName.isEmpty ? "repeatfill" : trimmedName

        if let uiImage = LureliaWidgetShared.widgetIcon(for: iconName) {
            tint
                .mask(
                    Image(uiImage: uiImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                )
                .frame(width: size, height: size)
        } else if let fallbackImage = LureliaWidgetShared.widgetIcon(for: "repeatfill") {
            tint
                .mask(
                    Image(uiImage: fallbackImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                )
                .frame(width: size, height: size)
        } else {
            Image(systemName: "repeat")
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Widget Configuration

struct LureliaHabitsWidget: Widget {
    let kind = "LureliaHabitsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: LureliaContentWidgetConfigurationIntent.self,
            provider: LureliaHabitsProvider()
        ) { entry in
            LureliaHabitsWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Habits")
        .description("Track and complete your daily habits.")
        .supportedFamilies([
            .systemLarge
        ])
    }
}
