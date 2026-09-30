//
//  RemindersView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(sort: \LureliaReminder.scheduledDate)
    private var reminders: [LureliaReminder]

    @Query(sort: \LureliaReminderHistory.occurrenceDate, order: .reverse)
    private var reminderHistory: [LureliaReminderHistory]
    
    @Query private var userSettings: [UserSettings]
    
    private var reminderDebugCounts: Void {
        let standalone = reminders.filter { $0.kind == .standalone }
        let tasks = reminders.filter { $0.kind == .task }
        let routines = reminders.filter { $0.kind == .routine }

        print("📊 REMINDERSVIEW REMINDER KIND COUNTS")
        print("   • All reminders: \(reminders.count)")
        print("   • Standalone: \(standalone.count)")
        print("   • Task: \(tasks.count)")
        print("   • Routine: \(routines.count)")

        for reminder in reminders {
            print("   • \(reminder.title) | kind=\(reminder.kind.rawValue) | enabled=\(reminder.isEnabled) | notificationID=\(reminder.notificationID)")
        }
    }

    @State private var showAddReminder = false
    @State private var showReminderHistory = false
    @State private var editingReminder: LureliaReminder?
    @State private var showCompletionBanner = false
    
    private var useFullScreenCover: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private var hideCompletedReminders: Bool {
        userSettings.first?.hideCompletedReminders ?? false
    }
    
    private func toggleHideCompletedReminders() {
        let settings: UserSettings

        if let existing = userSettings.first {
            settings = existing
        } else {
            let created = UserSettings()
            modelContext.insert(created)
            settings = created
        }

        settings.hideCompletedReminders.toggle()
        settings.updatedAt = Date()
        try? modelContext.save()
    }

    private func triggerBanner() {
        showCompletionBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCompletionBanner = false
        }
    }

    private var filteredReminders: [LureliaReminder] {
        reminders
            .filter { reminder in
                guard reminder.kind == .standalone else { return false }

                if hideCompletedReminders,
                   reminder.repeatUnit == .none,
                   reminder.isCompleted {
                    return false
                }

                return true
            }
            .sorted {
                let lDone = $0.isCompleted && $0.repeatUnit == .none
                let rDone = $1.isCompleted && $1.repeatUnit == .none
                if lDone != rDone { return !lDone }
                if $0.isEnabled != $1.isEnabled { return $0.isEnabled }
                let lDate = $0.nextFireAt ?? $0.scheduledDate
                let rDate = $1.nextFireAt ?? $1.scheduledDate
                return lDate < rDate
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()
                let _ = reminderDebugCounts

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        HStack {
                            Text("Reminders")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()

                            HStack(spacing: 14) {
                                Button { showReminderHistory = true } label: {
                                    Image("timebook")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(theme.palette.primaryAction)
                                        .bubblyIconMaterial(tint: theme.palette.primaryAction)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                        toggleHideCompletedReminders()
                                    }
                                } label: {
                                    Image(hideCompletedReminders ? "eye" : "eyeslash")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(theme.palette.indicators)
                                        .bubblyIconMaterial(tint: theme.palette.indicators)
                                }
                                .buttonStyle(.plain)

                                Button { showAddReminder = true } label: {
                                    Image("addwavy")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(.white)
                                        .bubblyIconMaterial(tint: .white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // Overview card intentionally hidden. Keep the
                        // implementation below available for a future return.
                        // overviewCard
                        //     .padding(.horizontal, 24)

                        if filteredReminders.isEmpty {
                            emptyState
                                .padding(.top, 40)
                                .padding(.horizontal, 24)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(filteredReminders) { reminder in
                                    NavigationLink(value: reminder.id) {
                                    LureliaReminderCard(
                                        reminder: reminder,
                                        onEdit: { editingReminder = reminder },
                                        onDelete: {
                                            print("🟥 CARD onDelete CLOSURE FIRED")
                                            print("   • Title: \(reminder.title)")
                                            print("   • UUID: \(reminder.id)")
                                            print("   • Notification ID: \(reminder.notificationID)")
                                            delete(reminder)
                                        },
                                        onComplete: { triggerBanner() }
                                    )
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                                }
                            }
                            .animation(.spring(response: 0.36, dampingFraction: 0.9), value: filteredReminders.map(\.id))
                            .padding(.horizontal, 24)
                        }

                        Spacer().frame(height: 120)
                    }
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: Binding(
                get: { !useFullScreenCover && showAddReminder },
                set: { showAddReminder = $0 }
            )) {
                LureliaReminderCreationFlow()
            }
            .fullScreenCover(isPresented: Binding(
                get: { useFullScreenCover && showAddReminder },
                set: { showAddReminder = $0 }
            )) {
                LureliaReminderCreationFlow()
            }
            .sheet(item: Binding(
                get: { useFullScreenCover ? nil : editingReminder },
                set: { editingReminder = $0 }
            )) { reminder in
                AddReminderView(editingReminder: reminder)
            }
            .fullScreenCover(item: Binding(
                get: { useFullScreenCover ? editingReminder : nil },
                set: { editingReminder = $0 }
            )) { reminder in
                AddReminderView(editingReminder: reminder)
            }
            .fullScreenCover(isPresented: $showReminderHistory) {
                LureliaReminderHistoryView()
            }
            .navigationDestination(for: UUID.self) { reminderID in
                if let reminder = reminders.first(where: { $0.id == reminderID }) {
                    ReminderDetailView(reminder: reminder)
                }
            }
        }
        .completionBanner(isShowing: showCompletionBanner, message: "Reminder completed!")
    }

    // MARK: - Overview

    private var standaloneReminders: [LureliaReminder] {
        reminders.filter { $0.kind == .standalone }
    }

    private func resolvedTimesOfDay(_ reminder: LureliaReminder) -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }
        if !stored.isEmpty { return stored }
        let cal = Calendar.current
        let ph = reminder.primaryHour != -1 ? reminder.primaryHour : cal.component(.hour, from: reminder.scheduledDate)
        let pm = reminder.primaryMinute != -1 ? reminder.primaryMinute : cal.component(.minute, from: reminder.scheduledDate)
        var times = [String(format: "%02d:%02d", ph, pm)]
        for ft in reminder.additionalFireTimes {
            times.append(String(format: "%02d:%02d", ft.hour, ft.minute))
        }
        return times
    }

    private func allFireDates(_ reminder: LureliaReminder, on date: Date) -> [Date] {
        let cal = Calendar.current
        let dayComponents = cal.dateComponents([.year, .month, .day], from: date)
        let times = resolvedTimesOfDay(reminder)
        return times.compactMap { timeStr -> Date? in
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var c = dayComponents; c.hour = h; c.minute = m; c.second = 0
            return cal.date(from: c)
        }.sorted()
    }

    private func occurrenceKey(_ date: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(c.hour ?? 0)-\(c.minute ?? 0)"
    }

    private func uniqueFireDates(_ reminder: LureliaReminder, on date: Date) -> [Date] {
        var seen = Set<String>()
        return allFireDates(reminder, on: date).filter { fireDate in
            seen.insert(occurrenceKey(fireDate)).inserted
        }
    }

    // scheduledDate advances forward as occurrences complete. Walk it back by one interval
    // if needed to find the effective anchor for checking if this reminder fires on `date`.
    private func isReminderScheduledForDate(_ reminder: LureliaReminder, date: Date) -> Bool {
        let cal = Calendar.current
        let targetStart = cal.startOfDay(for: date)
        let scheduledStart = cal.startOfDay(for: reminder.scheduledDate)

        switch reminder.repeatUnit {
        case .none:
            return cal.isDate(reminder.scheduledDate, inSameDayAs: date)

        case .minutes, .hours:
            if scheduledStart <= targetStart { return true }
            if let nf = reminder.nextFireAt, cal.isDate(nf, inSameDayAs: date) { return true }
            return false

        case .days:
            let effectiveStart: Date
            if scheduledStart <= targetStart {
                effectiveStart = scheduledStart
            } else {
                let interval = max(reminder.repeatInterval, 1)
                guard let walked = cal.date(byAdding: .day, value: -interval, to: scheduledStart),
                      cal.startOfDay(for: walked) <= targetStart else {
                    if let nf = reminder.nextFireAt, cal.isDate(nf, inSameDayAs: date) { return true }
                    return false
                }
                effectiveStart = cal.startOfDay(for: walked)
            }
            let days = cal.dateComponents([.day], from: effectiveStart, to: targetStart).day ?? 0
            return days % max(reminder.repeatInterval, 1) == 0

        case .weeks:
            let effectiveStart: Date
            if scheduledStart <= targetStart {
                effectiveStart = scheduledStart
            } else {
                let interval = max(reminder.repeatInterval, 1)
                guard let walked = cal.date(byAdding: .weekOfYear, value: -interval, to: scheduledStart),
                      cal.startOfDay(for: walked) <= targetStart else {
                    if let nf = reminder.nextFireAt, cal.isDate(nf, inSameDayAs: date) { return true }
                    return false
                }
                effectiveStart = cal.startOfDay(for: walked)
            }
            let todayWeekday = cal.component(.weekday, from: date)
            if !reminder.repeatWeekdays.isEmpty {
                guard reminder.repeatWeekdays.contains(todayWeekday) else { return false }
            }
            let weeks = cal.dateComponents([.weekOfYear], from: effectiveStart, to: targetStart).weekOfYear ?? 0
            return weeks % max(reminder.repeatInterval, 1) == 0

        case .months:
            let effectiveStart: Date
            if scheduledStart <= targetStart {
                effectiveStart = scheduledStart
            } else {
                let interval = max(reminder.repeatInterval, 1)
                guard let walked = cal.date(byAdding: .month, value: -interval, to: scheduledStart),
                      cal.startOfDay(for: walked) <= targetStart else {
                    if let nf = reminder.nextFireAt, cal.isDate(nf, inSameDayAs: date) { return true }
                    return false
                }
                effectiveStart = cal.startOfDay(for: walked)
            }
            let scheduledDay = cal.component(.day, from: effectiveStart)
            let targetDay = cal.component(.day, from: date)
            guard scheduledDay == targetDay else { return false }
            let months = cal.dateComponents([.month], from: effectiveStart, to: targetStart).month ?? 0
            return months % max(reminder.repeatInterval, 1) == 0

        case .years:
            let effectiveStart: Date
            if scheduledStart <= targetStart {
                effectiveStart = scheduledStart
            } else {
                let interval = max(reminder.repeatInterval, 1)
                guard let walked = cal.date(byAdding: .year, value: -interval, to: scheduledStart),
                      cal.startOfDay(for: walked) <= targetStart else {
                    if let nf = reminder.nextFireAt, cal.isDate(nf, inSameDayAs: date) { return true }
                    return false
                }
                effectiveStart = cal.startOfDay(for: walked)
            }
            let effMonth = cal.component(.month, from: effectiveStart)
            let effDay = cal.component(.day, from: effectiveStart)
            let targetMonth = cal.component(.month, from: date)
            let targetDay = cal.component(.day, from: date)
            guard effMonth == targetMonth && effDay == targetDay else { return false }
            let years = cal.dateComponents([.year], from: effectiveStart, to: targetStart).year ?? 0
            return years % max(reminder.repeatInterval, 1) == 0
        }
    }

    // MARK: - Unified Reminder Overview Snapshot

    private struct ReminderOverviewSnapshot {
        var total: Int = 0
        var upcoming: Int = 0
        var done: Int = 0
        var skipped: Int = 0
    }

    private var reminderOverviewSnapshot: ReminderOverviewSnapshot {
        let cal = Calendar.current
        let now = Date()
        let today = now

        var snapshot = ReminderOverviewSnapshot()

        for reminder in standaloneReminders {
            guard reminder.isEnabled || reminder.isCompleted || !reminder.completionTimestamps.isEmpty || !reminder.skippedTimestamps.isEmpty else { continue }
            guard isReminderScheduledForDate(reminder, date: today) else { continue }

            let todayFires = uniqueFireDates(reminder, on: today)
            guard !todayFires.isEmpty else { continue }

            let todayFireKeys = Set(todayFires.map { occurrenceKey($0) })
            snapshot.total += todayFires.count

            // Count completions and skips using BOTH key-matched history entries AND raw timestamp counts.
            // Raw counts handle legacy data where timestamps were wall-clock times, not exact fire times.
            // Take the max of both, capped at fire count.

            let historyCompletedKeys = Set(reminderHistory
                .filter { $0.reminderID == reminder.id && $0.action == .completed && cal.isDate($0.occurrenceDate, inSameDayAs: today) }
                .map { occurrenceKey($0.occurrenceDate) }
            ).filter { todayFireKeys.contains($0) }

            let historySkippedKeys = Set(reminderHistory
                .filter { $0.reminderID == reminder.id && $0.action == .skipped && cal.isDate($0.occurrenceDate, inSameDayAs: today) }
                .map { occurrenceKey($0.occurrenceDate) }
            ).filter { todayFireKeys.contains($0) }

            let rawCompletedCount = reminder.completionTimestamps.filter { cal.isDate($0, inSameDayAs: today) }.count
            let rawSkippedCount = reminder.skippedTimestamps.filter { cal.isDate($0, inSameDayAs: today) }.count

            var doneCount = min(max(historyCompletedKeys.count, rawCompletedCount), todayFires.count)
            let skippedCount = min(max(historySkippedKeys.count, rawSkippedCount), max(0, todayFires.count - doneCount))

            // Non-repeating reminders marked done today
            if reminder.repeatUnit == .none && reminder.isCompleted {
                let completedToday = (reminder.completedAt.map { cal.isDate($0, inSameDayAs: today) } ?? false)
                    || reminder.completionTimestamps.contains { cal.isDate($0, inSameDayAs: today) }
                if completedToday { doneCount = todayFires.count }
            }

            let actionedCount = min(doneCount + skippedCount, todayFires.count)
            let futureFireCount = todayFires.filter { $0 >= now }.count
            let pastFireCount = todayFires.count - futureFireCount
            let pastActioned = min(actionedCount, pastFireCount)
            let futureActioned = max(0, actionedCount - pastActioned)
            let upcomingCount = max(0, futureFireCount - futureActioned)

            snapshot.done += doneCount
            snapshot.skipped += skippedCount
            snapshot.upcoming += upcomingCount
        }

        return snapshot
    }

    private var upcomingTodayCount: Int { reminderOverviewSnapshot.upcoming }
    private var totalTodayCount: Int { reminderOverviewSnapshot.total }
    private var doneTodayCount: Int { reminderOverviewSnapshot.done }
    private var skippedTodayCount: Int { reminderOverviewSnapshot.skipped }

    private var nextUpReminder: LureliaReminder? {
        let now = Date()
        return standaloneReminders
            .filter { $0.isEnabled && !$0.isCompleted && ($0.nextFireAt ?? $0.scheduledDate) > now }
            .sorted { ($0.nextFireAt ?? $0.scheduledDate) < ($1.nextFireAt ?? $1.scheduledDate) }
            .first
    }

    private var encouragingText: String {
        if doneTodayCount > 0 && upcomingTodayCount == 0 { return "You've completed all your reminders for today." }
        if doneTodayCount > 0 { return "You've completed \(doneTodayCount) reminder\(doneTodayCount == 1 ? "" : "s") today. Keep going." }
        if totalTodayCount > 0 { return "You have \(totalTodayCount) reminder\(totalTodayCount == 1 ? "" : "s") scheduled for today." }
        return "You're all caught up for now."
    }

    private var overviewCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            overviewCardContent(now: context.date)
        }
    }

    private func overviewCardContent(now: Date) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image("bellfill")
                        .renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 20, height: 20).foregroundStyle(LGradients.header)
                    Text("Overview")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                    Spacer()
                    if let next = nextUpReminder {
                        Text("Next: \((next.nextFireAt ?? next.scheduledDate).formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.85).opacity(0.12), in: Capsule())
                    }
                }
                Text(encouragingText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    LureliaReminderStatCard(value: upcomingTodayCount, label: "Upcoming Today")
                    LureliaReminderStatCard(value: doneTodayCount, label: "Done Today")
                    LureliaReminderStatCard(value: totalTodayCount, label: "Total Today")
                    LureliaReminderStatCard(value: skippedTodayCount, label: "Skipped Today")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("bellfill")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 48, height: 48).foregroundStyle(LGradients.header)
            Text("No Reminders Yet")
                .font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(LColors.textPrimary)
            Text("Create standalone reminders to track anything you need to remember.")
                .font(.system(size: 14, design: .rounded)).foregroundStyle(LColors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 18)
            Button { showAddReminder = true } label: {
                Text("Create Reminder")
                    .font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(Color.white.adaptivePrimaryText)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LGradients.header))
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .padding(22)
        .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(LColors.glassBorder, lineWidth: 1))
    }

    private func delete(_ reminder: LureliaReminder) {
        ReminderActionManager.deleteReminder(reminder, in: modelContext)
    }
}

// MARK: - Reminder Card

struct LureliaReminderCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: LureliaReminder
    @State private var showDeleteConfirmation = false
    @State private var isCompleting = false
    @State private var checklistIsExpanded = false

    let onEdit: () -> Void
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    private var accent: Color { reminder.isEnabled ? reminder.color : LColors.textSecondary }
    private var dateText: String { reminder.scheduledDate.formatted(date: .abbreviated, time: .omitted) }

    private var allFireDates: [Date] {
        let cal = Calendar.current
        let anchor = reminder.nextFireAt ?? reminder.scheduledDate
        let dayComponents = cal.dateComponents([.year, .month, .day], from: anchor)
        let times = resolvedTimesOfDay()
        return times.compactMap { timeStr -> Date? in
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var c = dayComponents; c.hour = h; c.minute = m; c.second = 0
            return cal.date(from: c)
        }.sorted()
    }

    private func resolvedTimesOfDay() -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }
        if !stored.isEmpty { return stored }
        let cal = Calendar.current
        let ph = reminder.primaryHour != -1 ? reminder.primaryHour : cal.component(.hour, from: reminder.scheduledDate)
        let pm = reminder.primaryMinute != -1 ? reminder.primaryMinute : cal.component(.minute, from: reminder.scheduledDate)
        var times = [String(format: "%02d:%02d", ph, pm)]
        for ft in reminder.additionalFireTimes { times.append(String(format: "%02d:%02d", ft.hour, ft.minute)) }
        return times
    }

    private var isDoneToday: Bool {
        guard reminder.repeatUnit == .none else { return false }
        let cal = Calendar.current
        if let completedAt = reminder.completedAt, cal.isDateInToday(completedAt) { return true }
        return reminder.completionTimestamps.contains { cal.isDateInToday($0) }
    }

    private func isOverdue(now: Date) -> Bool {
        guard !isDoneToday && reminder.isEnabled else { return false }
        if reminder.repeatUnit == .none && reminder.isCompleted { return false }
        let startOfToday = Calendar.current.startOfDay(for: now)
        return (reminder.nextFireAt ?? reminder.scheduledDate) < startOfToday
    }

    private func isDueNow(now: Date) -> Bool {
        guard !isDoneToday && reminder.isEnabled else { return false }
        if reminder.repeatUnit == .none && reminder.isCompleted { return false }
        let nextFire = reminder.nextFireAt ?? reminder.scheduledDate
        if reminder.repeatUnit != .none {
            let startOfToday = Calendar.current.startOfDay(for: now)
            if nextFire < startOfToday { return false }
        }
        return nextFire <= now
    }

    private func isUpcoming(now: Date) -> Bool {
        guard !isDoneToday && reminder.isEnabled else { return false }
        if reminder.repeatUnit == .none && reminder.isCompleted { return false }
        let nextFire = reminder.nextFireAt ?? reminder.scheduledDate
        guard nextFire > now else { return false }
        return nextFire <= now.addingTimeInterval(24 * 60 * 60)
    }

    private var compactRepeatText: String {
        guard reminder.repeatUnit != .none else { return "No repeat" }
        let interval = max(1, reminder.repeatInterval)
        if interval == 1 {
            switch reminder.repeatUnit {
            case .minutes: return "Every min"
            case .hours:   return "Hourly"
            case .days:    return "Daily"
            case .weeks:
                if reminder.repeatWeekdays.isEmpty { return "Weekly" }
                return "Weekly: \(reminder.repeatWeekdays.sorted().compactMap { weekdayName($0) }.joined(separator: ", "))"
            case .months:  return "Monthly"
            case .years:   return "Yearly"
            case .none:    return "No repeat"
            }
        }
        switch reminder.repeatUnit {
        case .minutes: return "Every \(interval) min"
        case .hours:   return "Every \(interval) hr"
        case .days:    return "Every \(interval) days"
        case .weeks:   return "Every \(interval) wks"
        case .months:  return "Every \(interval) mos"
        case .years:   return "Every \(interval) yrs"
        case .none:    return "No repeat"
        }
    }

    private var reminderIcon: String {
        reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bellfill" : reminder.icon
    }

    private func debugDate(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private func debugReminderState(_ label: String) {
        print("""
        🧪 [ReminderDebug] \(label)
        title=\(reminder.title)
        id=\(reminder.id)
        repeatUnit=\(reminder.repeatUnit.rawValue)
        repeatInterval=\(reminder.repeatInterval)
        isEnabled=\(reminder.isEnabled)
        isCompleted=\(reminder.isCompleted)
        scheduledDate=\(debugDate(reminder.scheduledDate))
        nextFireAt=\(debugDate(reminder.nextFireAt))
        completedAt=\(debugDate(reminder.completedAt))
        completionTimestamps=\(reminder.completionTimestamps.map { debugDate($0) })
        skippedTimestamps=\(reminder.skippedTimestamps.map { debugDate($0) })
        timesOfDay=\(resolvedTimesOfDay())
        additionalFireTimes=\(reminder.additionalFireTimes.map { String(format: "%02d:%02d", $0.hour, $0.minute) })
        repeatWeekdays=\(reminder.repeatWeekdays)
        checklistCompleted=\(reminder.checklistCompletedCount)/\(reminder.checklistTotalCount)
        """)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            cardContent(
                overdue:  isOverdue(now: now),
                dueNow:   isDueNow(now: now),
                upcoming: isUpcoming(now: now)
            )
        }
    }

    @ViewBuilder
    private func cardContent(overdue: Bool, dueNow: Bool, upcoming: Bool) -> some View {
        VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.42))
                            .frame(width: 54, height: 54)

                        Circle()
                            .strokeBorder(reminder.color, lineWidth: 1.8)
                            .bubblyIconMaterial(tint: reminder.color)
                            .frame(width: 54, height: 54)

                        LureliaIconView(iconId: reminderIcon, size: 33)
                            .foregroundStyle(reminder.color)
                            .bubblyIconMaterial(tint: reminder.color)
                    }
                    .frame(width: 54, height: 54)
                    .layoutPriority(1)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(reminder.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !reminder.category.isEmpty {
                            Text(reminder.category)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 4)
                                .background(accent.opacity(0.12), in: Capsule())
                        }
                        if let notes = reminder.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(notes)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.black).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                    Spacer(minLength: 8)

                    completionCircle
                        .frame(width: 30, height: 30)
                        .layoutPriority(1)
                }

                Divider().overlay(LColors.glassBorder)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        reminderMetaPill(icon: "dotscal", title: dateText)
                        reminderRepeatLine(icon: "repeatfill", title: compactRepeatText)
                    }
                    fireTimesGrid
                    if overdue || dueNow || upcoming {
                        HStack {
                            if overdue { reminderBubbleText("OVERDUE", color: Color(lureliaHex: "#ff9be6")) }
                            else if dueNow { reminderBubbleText("DUE NOW", color: Color(lureliaHex: "#b476ff")) }
                            else if upcoming { reminderBubbleText("UPCOMING", color: Color(lureliaHex: "#7eedff")) }
                            Spacer(minLength: 0)
                        }
                    }

                    checklistSection
                }

                HStack(spacing: 10) {
                    Button { onEdit() } label: { reminderActionButton(title: "Edit", icon: "settings") }.buttonStyle(.plain)
                    Button { skipReminderOccurrence() } label: { reminderActionButton(title: "Skip", icon: "skipwavy") }
                        .buttonStyle(.plain)
                        .disabled(!reminder.isEnabled || (reminder.repeatUnit == .none && reminder.isCompleted))
                        .opacity((!reminder.isEnabled || (reminder.repeatUnit == .none && reminder.isCompleted)) ? 0.4 : 1)
                    Button(role: .destructive) {
                        print("🟥 DELETE BUTTON TAPPED ON CARD")
                        print("   • Title: \(reminder.title)")
                        print("   • UUID: \(reminder.id)")
                        print("   • Notification ID: \(reminder.notificationID)")
                        showDeleteConfirmation = true
                    } label: { reminderActionButton(title: "Delete", icon: "trash") }
                        .buttonStyle(.plain)
                }
        }
        .padding(18)
        .background {
            BubblyCardMaterial(tint: reminder.color, cornerRadius: 24)
        }
        .opacity(isCompleting ? 0.72 : (reminder.isEnabled ? 1 : 0.65))
        .scaleEffect(isCompleting ? 0.985 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.86), value: isCompleting)
        .confirmationDialog("Delete Reminder?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Reminder", role: .destructive) {
                print("🟥 CONFIRM DELETE TAPPED")
                print("   • Title: \(reminder.title)")
                print("   • UUID: \(reminder.id)")
                print("   • Notification ID: \(reminder.notificationID)")
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete \"\(reminder.title)\" and cancel its scheduled notifications.")
        }
    }

    // MARK: Sub-views

    private var completionCircle: some View {
        Button { completeReminderOccurrence() } label: {
            ZStack {
                Circle()
                    .fill(
                        reminder.isCompleted && reminder.repeatUnit == .none
                        ? AnyShapeStyle(reminder.color)
                        : AnyShapeStyle(Color.clear)
                    )
                    .frame(width: 30, height: 30)
                Circle()
                    .strokeBorder(reminder.color, lineWidth: 2)
                    .bubblyIconMaterial(tint: reminder.color)
                    .frame(width: 30, height: 30)
                if reminder.isCompleted && reminder.repeatUnit == .none {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var fireTimesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .center, spacing: 8) {
            ForEach(Array(allFireDates.enumerated()), id: \.offset) { _, d in
                reminderTimePill(d.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    @ViewBuilder
    private var checklistSection: some View {
        let items = sortedChecklistItems

        if !items.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        checklistIsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image("checkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(reminder.color)
                            .frame(width: 18, height: 18)

                        Text("Completion Steps")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.black)

                        Text("\(reminder.checklistCompletedCount)/\(reminder.checklistTotalCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)

                        Spacer()

                        Image(checklistIsExpanded ? "chevup" : "chevdown")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(reminder.color)
                            .frame(width: 18, height: 18)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if checklistIsExpanded {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            checklistItemRow(item)

                            if index != items.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.055))
                                    .frame(height: 1)
                                    .padding(.leading, 34)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                reminder.color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(reminder.color.opacity(0.4), lineWidth: 1)
            )
        }
    }

    private var sortedChecklistItems: [LureliaReminderChecklistItem] {
        reminder.checklistItems
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func checklistItemRow(_ item: LureliaReminderChecklistItem) -> some View {
        Button {
            toggleChecklistItem(item)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(item.isCompleted ? AnyShapeStyle(reminder.color) : AnyShapeStyle(Color.clear))
                        .frame(width: 18, height: 18)

                    Circle()
                        .strokeBorder(
                            item.isCompleted ? AnyShapeStyle(Color.clear) : AnyShapeStyle(reminder.color),
                            lineWidth: 1.3
                        )
                        .frame(width: 18, height: 18)

                    if item.isCompleted {
                        Image("checkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .frame(width: 10, height: 10)
                    }
                }

                Text(item.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .strikethrough(item.isCompleted, color: Color.black.opacity(0.7))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reminderBubbleText(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1).minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background {
                BubblyIconMaterial(tint: reminder.color)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(reminder.color.opacity(0.7), lineWidth: 1))
    }

    private func reminderTimePill(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image("clockfill")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.black)

            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            BubblyIconMaterial(tint: reminder.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(reminder.color.opacity(0.7), lineWidth: 1)
        )
    }

    private func reminderMetaPill(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background {
            BubblyIconMaterial(tint: reminder.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(reminder.color.opacity(0.7), lineWidth: 1))
    }

    private func reminderRepeatLine(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(icon).renderingMode(.template).resizable().scaledToFit().frame(width: 14, height: 14)
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
        .background {
            BubblyIconMaterial(tint: reminder.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(reminder.color.opacity(0.7), lineWidth: 1))
    }

    private func reminderActionButton(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity).frame(height: 40)
        .background {
            BubblyIconMaterial(tint: reminder.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(reminder.color.opacity(0.78), lineWidth: 1))
    }

    private func weekdayName(_ weekday: Int) -> String? {
        guard weekday >= 1 && weekday <= 7 else { return nil }
        return Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    // MARK: Actions

    private func toggleChecklistItem(_ item: LureliaReminderChecklistItem) {
        var items = reminder.checklistItems
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].isCompleted.toggle()
        items[index].updatedAt = Date()

        reminder.checklistItems = items
        reminder.updatedAt = Date()
        try? modelContext.save()
    }

    private func completeReminderOccurrence() {
        guard !isCompleting else { return }
        debugReminderState("COMPLETE tapped - BEFORE")

        withAnimation(.spring(response: 0.2, dampingFraction: 0.86)) {
            isCompleting = true
        }

        Task {
            await ReminderActionManager.completeReminderOccurrence(
                reminder,
                in: modelContext
            )

            await MainActor.run {
                debugReminderState("COMPLETE tapped - AFTER MANAGER")
                onComplete?()

                withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                    isCompleting = false
                }
            }
        }
    }

    private func skipReminderOccurrence() {
        guard !isCompleting else { return }
        debugReminderState("SKIP tapped - BEFORE")

        withAnimation(.spring(response: 0.2, dampingFraction: 0.86)) {
            isCompleting = true
        }

        Task {
            await ReminderActionManager.skipReminderOccurrence(
                reminder,
                in: modelContext
            )

            await MainActor.run {
                debugReminderState("SKIP tapped - AFTER MANAGER")

                withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                    isCompleting = false
                }
            }
        }
    }
}

// MARK: - Stat Card

struct LureliaReminderStatCard: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LColors.textSecondary).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 76).padding(.horizontal, 8)
        .background(LColors.glassSurface2, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LColors.glassBorder, lineWidth: 1))
    }
}
