//
//  HabitCardView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import UIKit
import Combine
import WidgetKit

private extension View {
    func habitCardTextMaterial(opacity: Double = 1) -> some View {
        foregroundStyle(.white)
            .bubblyIconMaterial(tint: .white)
            .opacity(opacity)
            .shadow(color: Color.black.opacity(0.42), radius: 1.5, x: 0, y: 1)
    }
}

struct LureliaHabitCard: View {
    @Environment(\.modelContext) private var modelContext

    let habit: LureliaHabit
    let onEdit: () -> Void
    let onHistory: () -> Void

    @State private var isExpanded = false
    @State private var showDeleteConfirm = false
    @State private var showResetConfirm = false
    @State private var statusNow = Date()

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }
    private var todaysLog: LureliaHabitLog? { habit.todaysLog() }
    private var todaysSkip: LureliaHabitSkip? { habit.todaysSkip() }

    private var accent: Color { habit.color }

    private var isPurpleAccent: Bool {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard UIColor(accent).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            return false
        }

        return saturation >= 0.10 && (0.68...0.92).contains(hue)
    }

    private var progressFillTint: Color {
        isPurpleAccent ? .white : accent
    }

    private var todayKanbanFireDates: [Date] {
        habit.fireDates(on: todayStart, calendar: .current)
    }

    private var isKanbanCompletionSynchronized: Bool {
        guard habit.isCompletedToday else { return false }
        guard !todayKanbanFireDates.isEmpty else { return true }
        guard let todaysLog else { return false }

        let requiredCompletionCount = min(habit.target, todayKanbanFireDates.count)
        let recordedCompletionCount = todayKanbanFireDates.reduce(into: 0) { count, fireDate in
            if todaysLog.isCompleted(atFireDate: fireDate) {
                count += 1
            }
        }

        return recordedCompletionCount >= requiredCompletionCount
    }

    // MARK: - Scheduled fire times

    private var todayScheduledFireTimes: [Date] {
        guard habit.reminderEnabled else { return [] }

        let times = habit.timesOfDay.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !times.isEmpty else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: statusNow)
        let weekday = calendar.component(.weekday, from: today)
        let allowedWeekdays = Set(habit.reminderDaysOfWeek)

        if !allowedWeekdays.isEmpty && !allowedWeekdays.contains(weekday) {
            return []
        }

        return times.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else { return nil }

            var components = calendar.dateComponents([.year, .month, .day], from: today)
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.date(from: components)
        }
        .sorted()
    }

    private var nextUncompletedFire: Date? {
        let completedCount = habit.todaysCount
        let scheduled = todayScheduledFireTimes
        guard completedCount < scheduled.count else { return nil }
        return scheduled[completedCount]
    }

    private var timeSlotLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current

        return todayScheduledFireTimes.map { date in
            let minutes = Calendar.current.component(.minute, from: date)
            formatter.dateFormat = minutes == 0 ? "ha" : "h:mma"
            return formatter.string(from: date).uppercased()
        }
    }

    /// Structured status so the bottom-row pill can render "Label · Time"
    /// rather than a plain interpolated string.
    private enum StatusPillContent {
        case labelled(String, String)   // e.g. ("Due", "1:00 PM")
        case plain(String)              // e.g. "Completed today"
    }

    private var statusPill: StatusPillContent {
        if habit.isCompletedToday { return .plain("Completed today") }
        if todaysSkip != nil { return .plain("Skipped today") }

        if let next = nextUncompletedFire {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            let label = formatter.string(from: next)
            return .labelled(next <= statusNow ? "Due" : "Next", label)
        }

        if habit.reminderEnabled == false && habit.target > habit.todaysCount {
            let remaining = habit.target - habit.todaysCount
            return .plain("\(remaining) left today")
        }

        return .plain("None today")
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Row 1: icon + title + count
            HStack(alignment: .center, spacing: 10) {
                LureliaHabitIconPreview(
                    iconName: habit.iconName ?? "flame",
                    tint: accent,
                    usesDarkCardTreatment: true
                )
                    .frame(width: 30, height: 30)

                Text(habit.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .habitCardTextMaterial()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                Text("\(habit.todaysCount)/\(habit.target)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .habitCardTextMaterial()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.22), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 1)
                    )

                // Pencil edit button — separate tap target, does NOT navigate.
                Button {
                    onEdit()
                } label: {
                    Image("pencil")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accent)
                        .bubblyIconMaterial(tint: accent)
                        .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 1)
                        .frame(width: 24, height: 24)
                        .background(accent.opacity(0.14), in: Circle())
                        .overlay(Circle().strokeBorder(accent.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {})

                completionButton
            }

            // Row 2 (combined): each occurrence is a compact vertical unit
            // (circle stacked directly over its time-label pill). Units sit
            // in a leading-aligned HStack with consistent spacing — no
            // full-width spreading, so 1-occurrence habits hug the leading
            // side and 5-occurrence habits stay dense.
            occurrenceRow
                .padding(.top, 2) // small breathing room after the icon row

            // Row 3: status pill (leading) + streak+chevron cluster (trailing).
            HStack(alignment: .center, spacing: 8) {
                statusPillView

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    Image("flame")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(accent)
                        .bubblyIconMaterial(tint: accent)
                        .shadow(color: Color.black.opacity(0.42), radius: 1.5, x: 0, y: 1)

                    Text("\(habit.dailyStreak) \(habit.dailyStreak == 1 ? "day" : "days")")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .habitCardTextMaterial()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))

                // Chevron — separate tap target, does NOT navigate.
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(isExpanded ? "chevup" : "chevdown")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accent)
                        .bubblyIconMaterial(tint: accent)
                        .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 1)
                        .frame(width: 24, height: 24)
                        .background(accent.opacity(0.14), in: Circle())
                        .overlay(Circle().strokeBorder(accent.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                // Prevent the surrounding NavigationLink from firing.
                .simultaneousGesture(TapGesture().onEnded {})
            }

            // Expanded management controls
            if isExpanded {
                Rectangle()
                    .fill(accent.opacity(0.25))
                    .frame(height: 1)
                    .padding(.top, 2)

                expandedControls
            }
        }
        .padding(14)
        .background {
            BubblyCardMaterial(
                tint: accent,
                cornerRadius: 20
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: accent.opacity(0.13), radius: 14, x: 0, y: 7)
        .alert("Delete Habit?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteHabit() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete this habit and all of its history.")
        }
        .alert("Reset Stats?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { resetStats() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Streaks and stats will restart from today. Past log history is kept.")
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
            statusNow = now
        }
    }

    // MARK: - Progress dots + time pills (two independent leading rows)

    private var completionButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                quickLog()
            }
        } label: {
            ZStack {
                if isKanbanCompletionSynchronized {
                    BubblyIconMaterial(tint: accent)
                        .clipShape(Circle())
                        .opacity(0.72)
                }

                Circle()
                    .strokeBorder(accent.opacity(0.85), lineWidth: 1.5)
                    .bubblyIconMaterial(tint: accent)

                if isKanbanCompletionSynchronized {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(.white)
                        .bubblyIconMaterial(tint: .white)
                        .shadow(color: Color.black.opacity(0.42), radius: 1.5, x: 0, y: 1)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isKanbanCompletionSynchronized)
        .opacity(isKanbanCompletionSynchronized ? 0.72 : 1)
        .simultaneousGesture(TapGesture().onEnded {})
        .accessibilityLabel(isKanbanCompletionSynchronized ? "Habit completed today" : "Complete habit")
    }

    @ViewBuilder
    private var occurrenceRow: some View {
        let count = habit.target
        let labels = timeSlotLabels

        VStack(alignment: .leading, spacing: 6) {
            // Progress indicator: single-occurrence habits get a slim bar,
            // multi-occurrence habits keep the compact dot row.
            if count == 1 {
                singleProgressBar
            } else {
                HStack(spacing: 7) {
                    ForEach(0..<count, id: \.self) { i in
                        let filled = i < habit.todaysCount
                        Circle()
                            .fill(filled ? accent : Color.clear)
                            .frame(width: 11, height: 11)
                            .overlay(
                                Circle().strokeBorder(
                                    filled ? accent : accent.opacity(0.45),
                                    lineWidth: 1.4
                                )
                            )
                            .bubblyIconMaterial(tint: accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Time pills: their own leading-aligned horizontal row, not tied
            // to the dot positions.
            if !labels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        timePill(label)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.spring(duration: 0.35), value: habit.todaysCount)
    }

    // MARK: - Single-Occurrence Progress Bar

    @ViewBuilder
    private var singleProgressBar: some View {
        // Slim capsule bar tinted with the habit's color. Fills when the
        // one-per-day habit is completed.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                BubblyCardMaterial(
                    tint: accent,
                    cornerRadius: 4
                )
                .clipShape(Capsule())
                .opacity(0.34)

                BubblyCardMaterial(
                    tint: progressFillTint,
                    cornerRadius: 4
                )
                .frame(width: geo.size.width * habit.progress)
                .clipShape(Capsule())
            }
            .overlay {
                Capsule()
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1)
            }
        }
        .frame(height: 8)
        .animation(.spring(duration: 0.35), value: habit.progress)
    }

    // MARK: - Time / Status Pills (habit-tinted)

    @ViewBuilder
    private func timePill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .habitCardTextMaterial(opacity: 0.9)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(accent.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
    }

    @ViewBuilder
    private var statusPillView: some View {
        HStack(spacing: 5) {
            switch statusPill {
            case .labelled(let label, let time):
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .habitCardTextMaterial(opacity: 0.9)

                Circle()
                    .fill(accent.opacity(0.7))
                    .frame(width: 3, height: 3)

                Text(time)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .habitCardTextMaterial()

            case .plain(let text):
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .habitCardTextMaterial(opacity: 0.85)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(accent.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
    }

    // MARK: - Expanded Controls

    @ViewBuilder
    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                actionButton("Edit", icon: "pencil") { onEdit() }
                actionButton("Clear", icon: "arrow.counterclockwise") { clearToday() }
                actionButton(
                    todaysSkip == nil ? "Skip" : "Skipped",
                    icon: "skipwavy",
                    isAsset: true
                ) { toggleSkip() }
                actionButton("Reset", icon: "arrow.clockwise") { showResetConfirm = true }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                actionButton("History", icon: "clock.arrow.circlepath") { onHistory() }
                destructiveButton("Delete", icon: "trash", isAsset: true) { showDeleteConfirm = true }
                Spacer()
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .imageScale(.small)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButton(
        _ title: String,
        icon: String,
        isAsset: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Group {
                    if isAsset {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                    } else {
                        Image(systemName: icon)
                    }
                }
                .foregroundStyle(.white)
                .bubblyIconMaterial(tint: .white)
                .shadow(color: Color.black.opacity(0.42), radius: 1.5, x: 0, y: 1)

                Text(title)
                    .habitCardTextMaterial(opacity: 0.85)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(accent.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {})
    }

    @ViewBuilder
    private func destructiveButton(
        _ title: String,
        icon: String,
        isAsset: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Group {
                    if isAsset {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                    } else {
                        Image(systemName: icon)
                    }
                }
                .foregroundStyle(.white)
                .bubblyIconMaterial(tint: .white)
                .shadow(color: Color.black.opacity(0.42), radius: 1.5, x: 0, y: 1)

                Text(title)
                    .habitCardTextMaterial()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                BubblyIconMaterial(tint: accent)
                    .clipShape(Capsule())
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {})
    }

    // MARK: - Actions

    private func quickLog() {
        let cap = habit.target
        let calendar = Calendar.current

        if let existingSkip = todaysSkip {
            modelContext.delete(existingSkip)
            habit.skips = (habit.skips ?? []).filter {
                $0.persistentModelID != existingSkip.persistentModelID
            }
        }

        if let existing = todaysLog {
            existing.habitIDString = habit.id.uuidString

            let recordedScheduledCount = todayKanbanFireDates.reduce(into: 0) { count, fireDate in
                if existing.isCompleted(atFireDate: fireDate, calendar: calendar) {
                    count += 1
                }
            }
            let representedCount = min(existing.count, todayKanbanFireDates.count)

            if recordedScheduledCount < representedCount,
               let unsynchronizedFireDate = todayKanbanFireDates.first(where: {
                   !existing.isCompleted(atFireDate: $0, calendar: calendar)
               }) {
                existing.markCompleted(atFireDate: unsynchronizedFireDate, calendar: calendar)
            } else if existing.count < cap,
                      let nextFireDate = todayKanbanFireDates.first(where: {
                          !existing.isCompleted(atFireDate: $0, calendar: calendar)
                      }) {
                existing.markCompleted(atFireDate: nextFireDate, calendar: calendar)
            } else if existing.count < cap {
                existing.count = min(cap, existing.count + 1)
                existing.updatedAt = Date()
            }

            habit.updatedAt = Date()
            habit.logs = (habit.logs ?? []).map { log in
                log.persistentModelID == existing.persistentModelID ? existing : log
            }

            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()
            return
        }

        let newLog = LureliaHabitLog(
            habit: habit,
            dayStart: todayStart,
            count: 1
        )

        modelContext.insert(newLog)
        habit.logs = (habit.logs ?? []) + [newLog]

        if let firstFireDate = todayKanbanFireDates.first {
            newLog.markCompleted(atFireDate: firstFireDate, calendar: calendar)
        }

        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    private func clearToday() {
        let cal = Calendar.current

        let todayLogs = (habit.logs ?? []).filter {
            cal.isDate($0.dayStart, inSameDayAs: todayStart)
        }

        for log in todayLogs {
            modelContext.delete(log)
        }

        habit.logs = (habit.logs ?? []).filter {
            !cal.isDate($0.dayStart, inSameDayAs: todayStart)
        }

        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    private func toggleSkip() {
        if let existing = todaysSkip {
            modelContext.delete(existing)
            habit.skips = (habit.skips ?? []).filter {
                $0.persistentModelID != existing.persistentModelID
            }
            habit.updatedAt = Date()

            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()
            return
        }

        if let log = todaysLog, log.count > 0 {
            return
        }

        let skip = LureliaHabitSkip(
            habit: habit,
            dayStart: todayStart
        )
        skip.habitIDString = habit.id.uuidString

        modelContext.insert(skip)
        habit.skips = (habit.skips ?? []) + [skip]
        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    private func resetStats() {
        habit.statsResetAt = Date()
        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    private func deleteHabit() {
        HabitManager.shared.cancel(habit)

        for log in habit.logs ?? [] {
            modelContext.delete(log)
        }

        for skip in habit.skips ?? [] {
            modelContext.delete(skip)
        }

        modelContext.delete(habit)

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }
}
