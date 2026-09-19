//
//  RoutineTaskDetailView.swift
//  Lurelia
//
//  Dedicated detail page for an individual task inside a routine.
//  Structured like ReminderDetailView / HabitBlueprintDetailView (same
//  background, typography, custom asset icons, section layout) but rendered in
//  the routine color language: per-routine `routineTint` fills and borders
//  instead of the brand gradient. Presented as a pushed page you reach by
//  tapping a task.
//

import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct RoutineTaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var task: LureliaRoutineTask
    var routineTint: Color = LColors.gradientPurple

    @State private var showEditor = false

    // Tiny Nudge
    @State private var frictionEditing = false
    @State private var frictionDraft = ""
    @State private var isGeneratingTinyNudge = false
    @State private var tinyNudgeResponse: TinyNudgeResponse?
    @State private var tinyNudgeError: String?

    // History pagination
    @State private var historyVisibleCount = 4

    /// Stable start date for the status TimelineView schedule. Created once so
    /// the schedule identity never changes between renders.
    @State private var timelineStart = Date()

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    init(task: LureliaRoutineTask, routineTint: Color = LColors.gradientPurple) {
        self._task = Bindable(task)
        self.routineTint = routineTint
    }

    private var taskIcon: String {
        let icon = task.icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "sparkle" : icon
    }

    private var cleanedNotes: String {
        task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            LureliaBackgroundAlt()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header

                    identityCard

                    // MARK: - Present State

                    // NOTE: the schedule start date is stored once (see
                    // `timelineStart`). Using `.now` here would build a brand-new
                    // schedule on every body evaluation, continuously
                    // invalidating the view.
                    TimelineView(.periodic(from: timelineStart, by: 30)) { context in
                        let now = context.date
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader(title: "Status & Time", icon: "dotlovering")

                            HStack(spacing: 12) {
                                statusTile(now: now)
                                timeRemainingTile(now: now)
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    completionActions

                    // MARK: - Timing & Execution

                    scheduleSection

                    stepsSection

                    // MARK: - Purpose

                    if !task.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Purpose", icon: "loveflame") {
                            sectionLabel("Why does this task exist?")
                            sectionBody(task.purpose)
                        }
                    }

                    // MARK: - Preparation & Support

                    if task.triggerType != nil
                        || !task.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Trigger", icon: "sparkbolt") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let type = task.triggerType {
                                    HStack(spacing: 10) {
                                        Image(type.iconName)
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(routineTint)

                                        Text(type.label)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                                }

                                if !task.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sectionLabel("Trigger")
                                    sectionBody(task.trigger)
                                }
                            }
                        }
                    }

                    if !task.environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Environment", icon: "houseoutline") {
                            sectionLabel("Where is this normally done?")
                            sectionBody(task.environment)
                        }
                    }

                    if !task.sortedSupplies.isEmpty {
                        suppliesSection
                    }

                    // MARK: - Obstacles & Recovery

                    if !task.sortedObstacles.isEmpty {
                        obstaclesSection
                    }

                    if !task.friction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Friction", icon: "warnwavy") {
                            sectionLabel("What is making this harder right now?")
                            sectionBody(task.friction)
                        }
                    }

                    sectionCard(title: "Tiny Nudge", icon: "starchat") {
                        frictionBox
                    }

                    let rewardText = task.reward.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (task.rewardEnabled ?? !rewardText.isEmpty) && !rewardText.isEmpty {
                        sectionCard(title: "Rewards", icon: "starhandtrophy") {
                            sectionLabel("What do I get for completing this?")
                            sectionBody(rewardText)
                        }
                    }

                    let consequenceText = task.consequence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (task.consequenceEnabled ?? !consequenceText.isEmpty) && !consequenceText.isEmpty {
                        sectionCard(title: "Consequence", icon: "minuswavy") {
                            sectionLabel("What happens if this gets skipped?")
                            sectionBody(consequenceText)
                        }
                    }

                    // MARK: - Performance & History

                    statisticsSection

                    if !task.sortedHistory.isEmpty {
                        completionHistorySection
                    }

                    Spacer().frame(height: 140)
                }
                .padding(.top, 6)
                .routinePageWidthLocked()
            }
            .routinePageScrollClipped()
            .onTapGesture {
                if frictionEditing {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        frictionEditing = false
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(
            AdaptiveEditorPresentation(
                isPad: isPad,
                isPresented: $showEditor
            ) {
                RoutineTaskEditorView(task: task, routineTint: routineTint)
            }
        )
    }

    // MARK: - Header

    private var adaptiveTintTextColor: Color {
        routineTint.wcagContrastingSolidTextColor
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Task")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button { showEditor = true } label: {
                Image("settings")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(adaptiveTintTextColor)
                    .wcagContrastLift(on: routineTint)
                    .frame(width: 40, height: 40)
                    .background(routineTint, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(adaptiveTintTextColor)
                    .wcagContrastLift(on: routineTint)
                    .frame(width: 40, height: 40)
                    .background(routineTint, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Identity

    private var identityCard: some View {
        tintedCard(role: .hero) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(routineTint.opacity(0.18))
                        .frame(width: 64, height: 64)

                    Circle()
                        .strokeBorder(routineTint.opacity(0.6), lineWidth: 1.15)
                        .frame(width: 64, height: 64)

                    LureliaIconView(iconId: taskIcon, size: 38)
                        .foregroundStyle(routineTint)
                }

                Text(task.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if !cleanedNotes.isEmpty {
                    Text(cleanedNotes)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let routineName = task.routine?.name, !routineName.isEmpty {
                    HStack(spacing: 6) {
                        Image("repeatfill")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(routineTint)

                        Text(routineName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .tracking(0.6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Status

    private enum TaskStatus {
        case notStarted, inProgress, dueSoon, overdue, paused, completed, skipped

        var label: String {
            switch self {
            case .notStarted: return "NOT STARTED"
            case .inProgress: return "IN PROGRESS"
            case .dueSoon: return "DUE SOON"
            case .overdue: return "OVERDUE"
            case .paused: return "PAUSED"
            case .completed: return "COMPLETED"
            case .skipped: return "SKIPPED"
            }
        }
    }

    private func resolvedStatus(now: Date) -> TaskStatus {
        if task.isCompleted { return .completed }
        if task.isSkipped { return .skipped }

        if let run = task.routine?.activeRun {
            if run.isPaused { return .paused }
            return .inProgress
        }

        guard task.hasDueTime, let dueToday = todaysDueDate() else { return .notStarted }

        let diff = dueToday.timeIntervalSince(now)
        if diff < 0 { return .overdue }
        if diff <= 60 * 60 { return .dueSoon }
        return .notStarted
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .completed: return LColors.success
        case .overdue: return Color(lureliaHex: "#ff9be6")
        case .skipped, .paused: return .white.opacity(0.5)
        case .notStarted, .dueSoon, .inProgress: return routineTint
        }
    }

    private func statusTile(now: Date) -> some View {
        let status = resolvedStatus(now: now)
        return tintedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("STATUS")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.6)

                Text(status.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor(status))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeRemainingTile(now: Date) -> some View {
        tintedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("TIME")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.6)

                Text(timeRemainingText(now: now))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(timeRemainingColor(now: now))
                    .minimumScaleFactor(0.78)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todaysDueDate() -> Date? {
        guard task.hasDueTime else { return nil }
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = task.dueHour
        comps.minute = task.dueMinute
        comps.second = 0
        return calendar.date(from: comps)
    }

    private func timeRemainingText(now: Date) -> String {
        if task.isCompleted {
            if let last = task.sortedHistory.first(where: { $0.wasCompleted })?.date ?? task.completedAt {
                return "Done \(last.formatted(date: .omitted, time: .shortened))"
            }
            return "Completed"
        }

        if task.isSkipped { return "Skipped" }

        guard task.hasDueTime, let dueToday = todaysDueDate() else { return "No deadline" }

        let diff = dueToday.timeIntervalSince(now)
        let magnitude = abs(diff)
        let overdue = diff < 0

        if magnitude < 60 { return overdue ? "Just overdue" : "Due now" }
        if magnitude < 3600 {
            let mins = Int(magnitude / 60)
            return overdue ? "Overdue \(mins) min" : "In \(mins) min"
        }
        let hours = Int(magnitude / 3600)
        return overdue ? "Overdue \(hours) hr" : "In \(hours) hr"
    }

    private func timeRemainingColor(now: Date) -> Color {
        if task.isCompleted { return LColors.success }
        guard task.hasDueTime, let dueToday = todaysDueDate() else { return .white.opacity(0.75) }
        return dueToday.timeIntervalSince(now) < 0 ? Color(lureliaHex: "#ff9be6") : .white
    }

    // MARK: - Completion Actions

    private var completionActions: some View {
        HStack(spacing: 12) {
            if task.isPending {
                actionButton(
                    title: "Complete",
                    icon: "checkwavy",
                    filled: true
                ) {
                    RoutineTaskManager.shared.recordCompletion(task: task, context: modelContext)
                }

                actionButton(
                    title: "Skip",
                    icon: "skipwavy",
                    filled: false
                ) {
                    RoutineTaskManager.shared.recordSkip(task: task, context: modelContext)
                }
            } else {
                actionButton(
                    title: "Reset to Pending",
                    icon: "repeatfill",
                    filled: false
                ) {
                    task.resetState()
                    do {
                        try modelContext.save()
                    } catch {
                        print("🚨 [RoutineTaskDetail] reset save failed: \(error)")
                    }
                    LureliaWidgetReloads.reloadAll()
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func actionButton(
        title: String,
        icon: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(filled ? AnyShapeStyle(routineTint.wcagContrastingSolidTextColor) : AnyShapeStyle(routineTint))
                    .wcagContrastLift(on: routineTint, isActive: filled)

                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(filled ? routineTint.wcagContrastingSolidTextColor : .white.opacity(0.85))
                    .wcagContrastLift(on: routineTint, isActive: filled)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(routineTint)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Schedule", icon: "ringstarcal")

            tintedCard {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        metricTile(icon: "repeatfill", label: "Repeats", value: repeatsSummary)
                        metricTile(icon: "dotscal", label: "Due", value: task.hasDueTime ? task.formattedDueTime : "No time")
                    }
                    HStack(spacing: 10) {
                        metricTile(icon: "bellfill", label: "Notifications", value: notificationsSummary)
                        metricTile(icon: "clockfill", label: "Alarm", value: alarmSummary)
                    }
                    HStack(spacing: 10) {
                        metricTile(icon: "hourglassfill", label: "Est. Duration", value: durationSummary)
                        metricTile(icon: "starcal", label: "Days", value: daysSummary)
                    }

                    if task.repeatsOnDays && !task.scheduledDays.isEmpty && task.scheduledDays.count < 7 {
                        weekdayChips
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var repeatsSummary: String {
        guard task.repeatsOnDays else { return "Once" }
        if task.scheduledDays.isEmpty { return "Daily" }
        if task.scheduledDays.count == 7 { return "Every day" }
        let weekdayValues = Set([2, 3, 4, 5, 6])
        if Set(task.scheduledDays) == weekdayValues { return "Weekdays" }
        if Set(task.scheduledDays) == Set([1, 7]) { return "Weekends" }
        return "\(task.scheduledDays.count) days"
    }

    private var notificationsSummary: String {
        guard task.notificationsEnabled else { return "Off" }
        let count = task.notificationCount
        return count == 1 ? "1" : "\(count)"
    }

    private var durationSummary: String {
        task.estimatedDurationMinutes > 0 ? "\(task.estimatedDurationMinutes) min" : "—"
    }

    private var alarmSummary: String {
        guard task.alarmEnabled else { return "Off" }
        let name = task.alarmSoundName ?? "radiate.m4a"
        // Cheap dictionary lookup — avoid scanning the bundle during rendering.
        return LureliaReminderAlarmSound.displayNames[name]
            ?? name.replacingOccurrences(of: ".m4a", with: "").capitalized
    }

    private var daysSummary: String {
        guard task.repeatsOnDays, !task.scheduledDays.isEmpty else { return "Any" }
        if task.scheduledDays.count == 7 { return "All" }
        return "\(task.scheduledDays.count)"
    }

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(weekdayList, id: \.value) { wd in
                let active = task.scheduledDays.contains(wd.value)
                Text(wd.short)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(active ? .white : .white.opacity(0.25))
                    .frame(width: 34, height: 30)
                    .background(
                        active
                        ? AnyShapeStyle(routineTint)
                        : AnyShapeStyle(Color.white.opacity(0.06))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Steps

    /// Steps shown on the detail page — capped at 9 to match the
    /// 1wavy...9wavy numbered asset icons.
    private var displaySteps: [LureliaRoutineTaskStep] {
        Array(task.sortedSteps.prefix(9))
    }

    private var stepsSection: some View {
        sectionCard(title: "Steps", icon: "starblist") {
            if displaySteps.isEmpty {
                emptyStateRow(icon: "listcircle", text: "No steps yet. Add the smaller actions needed to complete this task.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(stepsCompletedCount) / \(displaySteps.count) completed")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Text("\(Int(stepsProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 4).fill(routineTint)
                                .frame(width: geo.size.width * stepsProgress, height: 6)
                        }
                    }
                    .frame(height: 6)

                    ForEach(Array(displaySteps.enumerated()), id: \.element.id) { index, step in
                        Button {
                            toggleStep(step)
                        } label: {
                            HStack(spacing: 10) {
                                stepCircle(active: step.isCompleted)

                                Text(step.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(step.isCompleted ? .white.opacity(0.45) : .white.opacity(0.88))
                                    .strikethrough(step.isCompleted, color: .white.opacity(0.3))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if step.isCompleted {
                                    Image("checkwavy")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 13, height: 13)
                                        .foregroundStyle(LColors.success)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var stepsCompletedCount: Int {
        displaySteps.filter { $0.isCompleted }.count
    }

    private var stepsProgress: Double {
        let total = displaySteps.count
        guard total > 0 else { return 0 }
        return Double(stepsCompletedCount) / Double(total)
    }

    private func toggleStep(_ step: LureliaRoutineTaskStep) {
        step.isCompleted.toggle()
        step.updatedAt = Date()
        try? modelContext.save()

        // Auto-complete the task once every step is checked off.
        if task.isPending,
           !displaySteps.isEmpty,
           displaySteps.allSatisfy({ $0.isCompleted }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                RoutineTaskManager.shared.recordCompletion(task: task, context: modelContext)
            }
        }
    }

    // MARK: - Supplies

    private var suppliesSection: some View {
        sectionCard(title: "Supplies", icon: "backpack") {
            FlowChips(items: task.sortedSupplies.map { $0.name }, tint: routineTint)
        }
    }

    // MARK: - Obstacles & Solutions

    private var obstaclesSection: some View {
        sectionCard(title: "Obstacles & Solutions", icon: "crossroads") {
            VStack(alignment: .leading, spacing: 14) {
                // Capped at 9 to match the 1wavy...9wavy numbered asset icons.
                let obstacles = Array(task.sortedObstacles.prefix(9))
                ForEach(Array(obstacles.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            wavyNumberIcon(index + 1)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.obstacle)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                let solution = item.solution.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !solution.isEmpty {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image("rightwavy")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .foregroundStyle(LColors.success)

                                        Text(solution)
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundStyle(LColors.success.opacity(0.85))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if index < obstacles.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Statistics

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Statistics", icon: "starbars")

            if !task.hasStatistics {
                tintedCard {
                    VStack(spacing: 8) {
                        Image("starbars")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(routineTint)
                            .opacity(0.7)

                        Text("No history yet")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))

                        Text("Complete this task to start building your stats.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                tintedCard {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            metricTile(icon: "checkwavy", label: "Completed", value: "\(task.completedHistoryCount)")
                            metricTile(icon: "skipwavy", label: "Skipped", value: "\(task.skippedHistoryCount)")
                        }
                        HStack(spacing: 10) {
                            metricTile(icon: "starbars", label: "Rate", value: "\(Int(task.completionRate * 100))%")
                            metricTile(icon: "clockfill", label: "Avg Time", value: durationText(task.averageDurationSeconds))
                        }
                        HStack(spacing: 10) {
                            metricTile(icon: "boltprogress", label: "Fastest", value: durationText(task.fastestDurationSeconds))
                            metricTile(icon: "levelup", label: "Streak", value: "\(task.currentStreak)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private func durationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem > 0 ? "\(hours)h \(rem)m" : "\(hours)h"
    }

    // MARK: - Completion History

    private var completionHistorySection: some View {
        let all = task.sortedHistory
        let visible = Array(all.prefix(historyVisibleCount))

        return sectionCard(title: "Completion History", icon: "timebook") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(visible, id: \.id) { entry in
                    historyRow(entry)
                    if entry.id != visible.last?.id {
                        Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    }
                }

                HStack(spacing: 10) {
                    if historyVisibleCount < all.count {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                historyVisibleCount = min(historyVisibleCount + 4, all.count)
                            }
                        } label: {
                            historyButtonLabel("Load More")
                        }
                        .buttonStyle(.plain)
                    }

                    if historyVisibleCount > 4 {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                historyVisibleCount = max(historyVisibleCount - 4, 4)
                            }
                        } label: {
                            historyButtonLabel("See Less")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func historyButtonLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(routineTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )
    }

    private func historyRow(_ entry: LureliaRoutineTaskHistoryEntry) -> some View {
        let color = entry.wasCompleted ? LColors.success : Color.white.opacity(0.4)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color.opacity(0.35)).frame(width: 8, height: 8)

                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if entry.wasCompleted && entry.durationSeconds > 0 {
                    Text(durationText(entry.durationSeconds))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(entry.wasCompleted ? "COMPLETED" : "SKIPPED")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(color.opacity(0.12), in: Capsule())
            }

            if !entry.skipReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(entry.skipReason)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 16)
            }

            if !entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(entry.note)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 16)
            }
        }
    }

    // MARK: - Tiny Nudge (replicated from reference detail views)

    @ViewBuilder
    private var frictionBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            if frictionEditing {
                TextField("What is making this harder?", text: $frictionDraft, axis: .vertical)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onTapGesture { }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { dismissKeyboard() }
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                    }

                Button {
                    saveFriction()

                    Task {
                        isGeneratingTinyNudge = true
                        tinyNudgeError = nil

                        do {
                            tinyNudgeResponse = try await TinyNudgeService.shared.convinceMe(
                                taskType: .routine,
                                taskName: task.title,
                                friction: task.friction
                            )
                        } catch {
                            tinyNudgeError = error.localizedDescription
                        }

                        isGeneratingTinyNudge = false
                    }
                } label: {
                    Text("Convince Me")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(routineTint.wcagContrastingSolidTextColor)
                        .wcagContrastLift(on: routineTint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(routineTint)
                        )
                }
                .buttonStyle(.plain)

            } else {
                Button {
                    frictionDraft = task.friction

                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        frictionEditing = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(routineTint)

                        Text(task.friction.isEmpty ? "Add Friction" : "Update Friction")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if isGeneratingTinyNudge {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Writing your nudge...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let tinyNudgeResponse {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Convince Me")
                    sectionBody(tinyNudgeResponse.encouragement)

                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)

                    sectionLabel("Reduce Friction")
                    sectionBody(tinyNudgeResponse.frictionSuggestion)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let tinyNudgeError {
                Text(tinyNudgeError)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(lureliaHex: "#ff9be6"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(lureliaHex: "#ff9be6").opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func saveFriction() {
        task.friction = frictionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        task.updatedAt = Date()
        try? modelContext.save()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            frictionEditing = false
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    // MARK: - Reusable

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(routineTint)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: title, icon: icon)
            tintedCard {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    /// Routine-tinted card container (no brand gradient), matching the
    /// per-routine color language used across RoutineDetailView.
    private func tintedCard<Content: View>(
        role: LureliaUserChoiceSurfaceRole = .supporting,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(18)
            .background {
                LureliaUserChoiceSurface(
                    tint: routineTint,
                    role: role,
                    cornerRadius: 22
                )
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.6)
    }

    private func sectionBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Hollow completion circle for steps — empty outline when pending,
    /// tint-filled with a check when completed.
    private func stepCircle(active: Bool) -> some View {
        ZStack {
            Circle()
                .fill(active ? AnyShapeStyle(routineTint) : AnyShapeStyle(Color.clear))
                .frame(width: 26, height: 26)
            Circle()
                .strokeBorder(active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(routineTint), lineWidth: 1.5)
                .frame(width: 26, height: 26)

            if active {
                Image("checkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(routineTint.wcagContrastingSolidTextColor)
                    .wcagContrastLift(on: routineTint)
            }
        }
    }

    /// Numbered list marker using the custom 1wavy...9wavy asset icons.
    private func wavyNumberIcon(_ number: Int, dimmed: Bool = false) -> some View {
        Image("\(min(max(number, 1), 9))wavy")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(dimmed ? routineTint.opacity(0.45) : routineTint)
    }

    private func metricTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(routineTint)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .tracking(0.5)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func numberedCircle(_ number: Int, active: Bool) -> some View {
        ZStack {
            Circle()
                .fill(active ? AnyShapeStyle(routineTint) : AnyShapeStyle(Color.clear))
                .frame(width: 26, height: 26)
            Circle()
                .strokeBorder(active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(routineTint), lineWidth: 1.5)
                .frame(width: 26, height: 26)

            if active {
                Image("checkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(routineTint.wcagContrastingSolidTextColor)
                    .wcagContrastLift(on: routineTint)
            } else {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func emptyStateRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.white.opacity(0.35))

            Text(text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private let weekdayList: [(value: Int, short: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]
}

// MARK: - Adaptive Editor Presentation

private struct AdaptiveEditorPresentation<SheetContent: View>: ViewModifier {
    let isPad: Bool
    @Binding var isPresented: Bool
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        if isPad {
            content.fullScreenCover(isPresented: $isPresented) { sheetContent() }
        } else {
            content.sheet(isPresented: $isPresented) { sheetContent() }
        }
    }
}

// MARK: - Supply Chips

private struct FlowChips: View {
    let items: [String]
    let tint: Color

    var body: some View {
        TagFlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, name in
                HStack(spacing: 6) {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(tint)

                    Text(name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
