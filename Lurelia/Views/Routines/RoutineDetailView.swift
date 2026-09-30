//
//  RoutineDetailView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import WidgetKit
import UserNotifications

struct RoutineDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    
    let routineID: PersistentIdentifier

    @Query private var routines: [LureliaRoutine]
    @Query(sort: \LureliaRoutine.sortOrder) private var allRoutines: [LureliaRoutine]

    private var routine: LureliaRoutine {
        guard let routine = routines.first else {
            fatalError("Routine not found")
        }
        return routine
    }

    init(
        routineID: PersistentIdentifier
    ) {
        self.routineID = routineID

        let descriptor = FetchDescriptor<LureliaRoutine>(
            predicate: #Predicate<LureliaRoutine> { routine in
                routine.id == routineID
            }
        )

        _routines = Query(descriptor)
    }
    
    @State private var routineColorSelection: RoutineEditorLaunchRequest?
    @State private var queuedRoutineEditor: RoutineEditorLaunchRequest?
    @State private var routineEditor: RoutineEditorLaunchRequest?
    @State private var activeRoutine: LureliaRoutine?
    @State private var showCompletionBanner = false
    @State private var bannerMessage = "Done!"
    @State private var editingTask: LureliaRoutineTask?
    @State private var editingPhase: LureliaRoutinePhase?
    @State private var didCheckNotificationPermission = false
    @State private var showContractCreator = false
    @State private var viewingContract: LureliaRoutineContract?
    @State private var offDayPickerExpanded = false
    @State private var pendingOffDayDate = Date()
    @State private var offDayValidationMessage: String?
    @State private var calendarExpanded = false
    @State private var displayedCalendarMonth = Date()
    
    private var routineTint: Color {
        Color(lureliaHex: routine.colorHex)
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private var activeRun: LureliaRoutineRun? {
        routine.activeRun
    }

    // MARK: - Schedule Status

    private enum RoutineScheduleStatus {
        case dueNow, soon, none
    }

    private enum RoutineTaskDayState {
        case pending, completed, skipped
    }

    private enum RoutineDetailAction: String, Identifiable {
        case resume
        case openRun
        case pause
        case end
        case resetTasks
        case complete
        case skip
        case run

        var id: String { rawValue }

        var title: String {
            switch self {
            case .resume: return "Resume"
            case .openRun: return "Open Run"
            case .pause: return "Pause"
            case .end: return "End"
            case .resetTasks: return "Reset Tasks"
            case .complete: return "Complete"
            case .skip: return "Skip"
            case .run: return "Run"
            }
        }

        var icon: String {
            switch self {
            case .resume, .openRun, .run: return "playwavy"
            case .pause: return "pausewavy"
            case .end: return "stopwavy"
            case .resetTasks: return "arrow.counterclockwise"
            case .complete: return "checkwavy"
            case .skip: return "skipwavy"
            }
        }

        var isPrimary: Bool {
            switch self {
            case .resume, .openRun, .resetTasks, .complete:
                return true
            case .pause, .end, .skip, .run:
                return false
            }
        }
    }

    private var scheduleStatus: RoutineScheduleStatus {
        let calendar = Calendar.current
        let now = Date()
        let todayWeekday = calendar.component(.weekday, from: now)

        if routine.phasesEnabled {
            let todayPhases = (routine.phases ?? [])
                .filter { $0.scheduleEnabled && $0.scheduledDays.contains(todayWeekday) }
            guard !todayPhases.isEmpty else { return .none }

            let earliestStart = todayPhases
                .map { $0.startHour * 60 + $0.startMinute }
                .min() ?? 0
            let latestEnd = todayPhases
                .map { $0.endHour * 60 + $0.endMinute }
                .max() ?? 0

            let nowMins = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

            if nowMins >= earliestStart && nowMins <= latestEnd { return .dueNow }
            if nowMins > latestEnd && !routineAllTasksResolvedToday { return .dueNow }
            if nowMins < earliestStart { return .soon }
            return .none
        }

        guard routine.scheduleEnabled, routine.scheduledDays.contains(todayWeekday) else { return .none }

        let startMins = routine.startHour * 60 + routine.startMinute
        let endMins = startMins + routine.durationMinutes
        let nowMins = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        if nowMins >= startMins && nowMins <= endMins { return .dueNow }
        if nowMins > endMins && !routineAllTasksResolvedToday { return .dueNow }
        if nowMins < startMins { return .soon }
        return .none
    }
    
    private var sortedRuns: [LureliaRoutineRun] {
        (routine.runs ?? [])
            .filter { !$0.isActive }
            .sorted { $0.startedAt > $1.startedAt }
    }
    
    private var totalRuns: Int {
        sortedRuns.count
    }
    private var completedRuns: Int {
        sortedRuns.filter { $0.wasCompleted }.count
    }
    
    private var completionRate: Double {
        guard totalRuns > 0 else { return 0 }
        return Double(completedRuns) / Double(totalRuns)
    }
    
    private var averageTasksCompleted: Double {
        guard totalRuns > 0 else { return 0 }
        
        let totalCompleted = sortedRuns.reduce(0) {
            $0 + $1.completedCount
        }
        
        return Double(totalCompleted) / Double(totalRuns)
    }
    
    private var scheduleLabel: String {
        guard routine.scheduleEnabled && !routine.scheduledDays.isEmpty else {
            return "No schedule set"
        }
        
        let symbols = Calendar.current.shortWeekdaySymbols
        
        let days = routine.scheduledDays
            .sorted()
            .compactMap { $0 >= 1 && $0 <= 7 ? symbols[$0 - 1] : nil }
            .joined(separator: ", ")
        
        return "\(days) · \(routine.formattedTimeRange)"
    }
    
    private var routineStatusText: String {
        if let activeRun {
            return activeRun.isPaused ? "Paused" : "Running"
        }
        
        if routineAllTasksResolvedToday { return "Completed" }
        
        return routine.scheduleEnabled ? "Scheduled" : "Ready"
    }
    
    private var routineStatusIcon: String {
        if let activeRun {
            return activeRun.isPaused ? "pausewavy" : "playwavy"
        }
        
        if routineAllTasksResolvedToday { return "checkwavy" }
        
        return routine.scheduleEnabled ? "bellfill" : "sparkle"
    }
    
    private var adaptiveRoutineTextColor: Color {
        .white.opacity(0.92)
    }
    
    private var adaptiveRoutineSecondaryTextColor: Color {
        .white.opacity(0.72)
    }

    private var routineFillTextColor: Color {
        routineTint.wcagContrastingSolidTextColor
    }

    private func taskDayState(
        _ task: LureliaRoutineTask,
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> RoutineTaskDayState {
        if let entry = task.sortedHistory.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            return entry.wasCompleted ? .completed : .skipped
        }

        if let completedAt = task.completedAt,
           calendar.isDate(completedAt, inSameDayAs: day) {
            return .completed
        }

        if let skippedAt = task.skippedAt,
           calendar.isDate(skippedAt, inSameDayAs: day) {
            return .skipped
        }

        if task.isCompleted, task.completedAt == nil {
            return .completed
        }

        if task.isSkipped, task.skippedAt == nil {
            return .skipped
        }

        return .pending
    }

    private var routineAllTasksResolvedToday: Bool {
        let allTasks = routine.sortedTasks
        guard !allTasks.isEmpty else { return false }
        return allTasks.allSatisfy { taskDayState($0) != .pending }
    }
    
    private func requestNotificationPermissionIfNeeded() async {
        guard !didCheckNotificationPermission else { return }
        didCheckNotificationPermission = true

        guard routine.remindersEnabled else { return }

        let status = await LureliaNotificationManager.shared.currentPermissionStatus()

        guard status == .notDetermined else { return }

        _ = await LureliaNotificationManager.shared.requestPermission()
    }
    
    private func processExternalRoutineChanges() {
        modelContext.processPendingChanges()
    }
    
    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    customHeader

                    heroCard

                    if scheduleStatus != .none {
                        scheduleStatusBox
                    }

                    actionStrip
                    
                    statsGrid
                    
                    if !routine.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSectionCard(title: "Purpose", icon: "sparkle") {
                            Text(routine.purpose)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(adaptiveRoutineTextColor)
                        }
                    }
                    
                    if !routine.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSectionCard(title: "Description", icon: "starnote") {
                            Text(routine.descriptionText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(adaptiveRoutineTextColor)
                        }
                    }

                    routineContractCard

                    routineOffDaysCard
                    
                    if routine.scheduleEnabled {
                        scheduledDaysCard
                        scheduleTimeCard
                    }
                    
                    if routine.phasesEnabled {
                        phasesFlowSection
                    } else {
                        taskFlowCard
                    }

                    if !routine.principles.isEmpty {
                        principlesCard
                    }

                    routineCalendarCard
                    
                    historyCard
                    
                    Spacer()
                        .frame(height: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .routinePageWidthLocked()
            }
            .routinePageScrollClipped()
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $routineColorSelection, onDismiss: presentQueuedRoutineEditor) { request in
            RoutineColorSelectionSheet(initialColor: request.color) { color in
                queuedRoutineEditor = RoutineEditorLaunchRequest(
                    routine: request.routine,
                    color: color
                )
            }
        }
        .sheet(item: $routineEditor) { request in
            AddRoutineView(
                editingRoutine: request.routine,
                initialColor: request.color
            )
        }
        .routineTaskEditor(
            isPad: isPad,
            task: $editingTask,
            routineTint: routineTint
        )
        .sheet(item: $editingPhase) { phase in
            EditRoutinePhaseSheet(
                routine: routine,
                phase: phase,
                routineTint: routineTint
            )
        }
        .sheet(isPresented: $showContractCreator) {
            RoutineContractEditorView(routine: routine)
        }
        .sheet(item: $viewingContract) { contract in
            RoutineContractDetailView(
                contract: contract,
                routine: routine
            )
        }
        .task {
            await requestNotificationPermissionIfNeeded()
        }
        .fullScreenCover(item: $activeRoutine) { routine in
            RoutineRunView(routine: routine)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                processExternalRoutineChanges()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            processExternalRoutineChanges()
        }
        .completionBanner(isShowing: showCompletionBanner, message: bannerMessage)
    }

    private func beginRoutineEditor() {
        queuedRoutineEditor = nil
        routineColorSelection = RoutineEditorLaunchRequest(
            routine: routine,
            color: routineTint
        )
    }

    private func presentQueuedRoutineEditor() {
        guard let queuedRoutineEditor else { return }
        self.queuedRoutineEditor = nil
        routineEditor = queuedRoutineEditor
    }
    
    private func triggerBanner(_ message: String) {
        bannerMessage = message
        showCompletionBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCompletionBanner = false
        }
    }

    private func completeCurrentPhase() {
        let calendar = Calendar.current
        let now = Date()
        let todayWeekday = calendar.component(.weekday, from: now)

        let scheduledPhases = routine.sortedPhases
            .filter { $0.scheduleEnabled && $0.scheduledDays.contains(todayWeekday) }

        let currentPhase = scheduledPhases.first { phase in
            let startMins = phase.startHour * 60 + phase.startMinute
            let endMins = phase.endHour * 60 + phase.endMinute
            let nowMins = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let isTimeRelevant = nowMins <= endMins || nowMins >= startMins
            let hasPendingTasks = routine.tasksForPhase(phase).contains {
                taskDayState($0) == .pending
            }
            return isTimeRelevant && hasPendingTasks
        } ?? scheduledPhases.first { phase in
            routine.tasksForPhase(phase).contains {
                taskDayState($0) == .pending
            }
        }

        guard let phase = currentPhase else {
            RoutineManager.shared.completeRoutine(
                routine,
                context: modelContext
            )
            return
        }

        let phaseTasks = routine.tasksForPhase(phase)
        for task in phaseTasks where taskDayState(task) == .pending {
            RoutineTaskManager.shared.recordCompletion(
                task: task,
                context: modelContext
            )
        }

        routine.updatedAt = Date()

        if routineAllTasksResolvedToday {
            routine.lastCompletedAt = Date()
        }
    }
}

// MARK: - Main Cards
extension RoutineDetailView {
    
    private var customHeader: some View {
        HStack(spacing: 12) {

            Text(routine.name)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(routineTint)
                .lineLimit(2)

            Spacer()

            routineHeaderButton(icon: "settings") {
                beginRoutineEditor()
            }

            routineHeaderButton(icon: "xmarkwavy") {
                dismiss()
            }
        }
    }

    private func routineHeaderButton(
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                BubblyIconMaterial(tint: routineTint)
                    .clipShape(Circle())

                routineButtonIcon(
                    icon,
                    size: 17,
                    color: Color.black.opacity(0.88),
                    shadowColor: Color.white.opacity(0.16)
                )
            }
            .frame(width: 40, height: 40)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.48), radius: 7, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 78, height: 78)
                        .overlay(
                            Circle()
                                .strokeBorder(routineTint.opacity(0.85), lineWidth: 1)
                        )
                    
                    LureliaIconView(iconId: routine.icon, size: 36.5)
                        .foregroundStyle(adaptiveRoutineTextColor)
                        .bubblyIconMaterial(tint: routineTint)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(routine.name)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(adaptiveRoutineTextColor)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        heroMetaLabel(
                            icon: routine.timeOfDay.icon,
                            text: routine.timeOfDay.rawValue,
                            color: .white
                        )
                        
                        Text("·")
                            .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                        
                        heroMetaLabel(
                            icon: routineStatusIcon,
                            text: routineStatusText,
                            color: adaptiveRoutineSecondaryTextColor
                        )
                    }
                }
                
                Spacer()
            }
            
            HStack(spacing: 10) {
                routineMiniPill(
                    icon: "starnote",
                    title: "\(displayTaskCount)",
                    subtitle: routine.phasesEnabled ? "Phase Tasks" : "Tasks"
                )

                routineMiniPill(
                    icon: "clockfill",
                    title: displayDurationText,
                    subtitle: "Length"
                )

                routineMiniPill(
                    icon: displayScheduleIcon,
                    title: displayScheduleText,
                    subtitle: "Schedule"
                )
            }
        }
        .padding(18)
        .background {
            BubblyCardMaterial(
                tint: routineTint,
                cornerRadius: 28
            )
        }
        .shadow(color: routineTint.opacity(0.16), radius: 18, x: 0, y: 10)
    }
    
    private var scheduleStatusBox: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(scheduleStatus == .dueNow ? .white : .white.opacity(0.35))
                .frame(width: 8, height: 8)

            Text(scheduleStatus == .dueNow ? "DUE NOW" : "SOON")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(scheduleStatus == .dueNow ? .white : .white.opacity(0.65))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(
                tint: routineTint,
                cornerRadius: 16
            )
        }
    }

    private var actionStrip: some View {
        HStack(spacing: 12) {
            ForEach(actionStripActions) { action in
                routineActionButton(
                    title: action.title,
                    icon: action.icon,
                    isPrimary: action.isPrimary
                ) {
                    performRoutineAction(action)
                }
            }
        }
    }

    private var actionStripActions: [RoutineDetailAction] {
        if let activeRun {
            return activeRun.isPaused
                ? [.resume, .end]
                : [.openRun, .pause, .end]
        }

        if routineAllTasksResolvedToday {
            return [.resetTasks, .run]
        }

        return [.complete, .skip, .run]
    }

    private func performRoutineAction(_ action: RoutineDetailAction) {
        switch action {
        case .resume:
            guard let activeRun else { return }
            RoutineManager.shared.resumeRun(run: activeRun, routine: routine)
            activeRoutine = routine
            LureliaWidgetReloads.reloadAll()

        case .openRun:
            activeRoutine = routine

        case .pause:
            guard let activeRun else { return }
            RoutineManager.shared.pauseRun(run: activeRun, routine: routine)
            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()

        case .end:
            guard let activeRun else { return }
            RoutineManager.shared.finishRun(
                run: activeRun,
                routine: routine,
                wasCompleted: false
            )
            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()

        case .resetTasks:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                let now = Date()
                routine.resetTaskStates()
                for task in routine.sortedTasks {
                    LureliaRoutineTaskOccurrenceNotifications.restorePendingOccurrence(
                        for: task,
                        on: now,
                        now: now
                    )
                    LureliaRoutineTaskOccurrenceAlarms.restorePendingOccurrence(
                        for: task,
                        on: now,
                        now: now
                    )
                }
                try? modelContext.save()
            }
            triggerBanner("Tasks reset!")
            LureliaWidgetReloads.reloadAll()

        case .complete:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                if routine.phasesEnabled {
                    completeCurrentPhase()
                } else {
                    RoutineManager.shared.completeRoutine(
                        routine,
                        context: modelContext
                    )
                }
                try? modelContext.save()
                LureliaWidgetReloads.reloadAll()
            }
            triggerBanner(
                routine.phasesEnabled
                ? (routineAllTasksResolvedToday ? "Routine completed!" : "Phase completed!")
                : "Routine completed!"
            )
            LureliaWidgetReloads.reloadAll()

        case .skip:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                let now = Date()
                let pendingTasks = routine.sortedTasks.filter(\.isPending)
                routine.skipRoutine()
                for task in pendingTasks {
                    LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
                        for: task,
                        on: now,
                        now: now
                    )
                    LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrence(
                        for: task,
                        on: now,
                        now: now
                    )
                }
                try? modelContext.save()
            }
            triggerBanner("Routine skipped")
            LureliaWidgetReloads.reloadAll()

        case .run:
            let run = RoutineManager.shared.startRun(
                for: routine,
                context: modelContext
            )
            try? modelContext.save()
            if run.isActive { activeRoutine = routine }
            LureliaWidgetReloads.reloadAll()
        }
    }
    
    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            statCard(value: "\(totalRuns)", label: "Runs")
            
            VStack(spacing: 5) {
                RoutineTaskDottedProgressRing(
                    progress: routineTaskProgress,
                    size: 38,
                    dotCount: 18,
                    dotDiameter: 3,
                    trackColor: adaptiveRoutineTextColor.opacity(0.18),
                    progressColor: routineTint
                ) {
                    Text(routineTaskProgressPercentText)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(adaptiveRoutineTextColor)
                }

                Text("\(completedRoutineTaskCount)/\(totalRoutineTaskCount) Done")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background {
                BubblyCardMaterial(
                    tint: routineTint,
                    cornerRadius: 20
                )
            }
            
            statCard(value: String(format: "%.1f", averageTasksCompleted), label: "Avg Done")
        }
    }
    
    private var scheduledDaysCard: some View {
        detailSectionCard(title: "Scheduled Days", icon: "writepen") {
            if routine.scheduledDays.isEmpty {
                emptySectionText("No days selected for this routine yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(routine.scheduledDays.sorted().enumerated()), id: \.element) { index, weekday in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.42))
                                    .frame(width: 34, height: 34)
                                Circle()
                                    .strokeBorder(routineTint.opacity(0.85), lineWidth: 1)
                                    .frame(width: 34, height: 34)
                                Text(shortWeekdayLabel(for: weekday))
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(routineTint)
                                    .bubblyIconMaterial(tint: routineTint)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fullWeekdayLabel(for: weekday))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(adaptiveRoutineTextColor)
                                Text("Routine is scheduled for this day")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        if index < routine.scheduledDays.count - 1 { divider }
                    }
                }
            }
        }
    }
    
    private var scheduleTimeCard: some View {
        detailSectionCard(title: "Schedule Time", icon: "clockfill") {
            VStack(spacing: 12) {
                detailRow(icon: "sun", label: "Starts", value: routine.formattedStartTime)
                divider
                detailRow(icon: "moonzs", label: "Ends", value: routine.formattedEndTime)
                divider
                detailRow(icon: "hourglass", label: "Duration", value: "\(routine.durationMinutes) minutes")
            }
        }
    }

    private var routineContractCard: some View {
        detailSectionCard(title: "Routine Contract", icon: "contract") {
            if let contract = routine.currentContract {
                currentContractSummary(contract)
            } else {
                emptyContractSummary
            }
        }
    }

    private var routineOffDaysCard: some View {
        detailSectionCard(title: "Off Days", icon: "snooze") {
            VStack(alignment: .leading, spacing: 12) {
                let offDays = routine.sortedOffDayDates()

                if offDays.isEmpty {
                    emptySectionText("No off days selected.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(offDays, id: \.self) { date in
                            offDayRow(date)
                        }
                    }
                }

                if offDayPickerExpanded {
                    offDayPicker
                }

                if let offDayValidationMessage {
                    Text(offDayValidationMessage)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(routineTint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        pendingOffDayDate = normalizedOffDay(Date())
                        offDayValidationMessage = nil
                        offDayPickerExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        routineButtonIcon(
                            offDayPickerExpanded ? "xmarkwavy" : "addwavy",
                            size: 13,
                            color: .black,
                            shadowColor: .clear
                        )

                        Text(offDayPickerExpanded ? "Close Picker" : "Pick Off Day")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(Color.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        RoutineDetailButtonSurface(
                            tint: routineTint,
                            cornerRadius: 15
                        )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var offDayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            LureliaTintedDateDrumPicker(
                date: $pendingOffDayDate,
                tint: routineTint,
                minimumDate: offDayPickerRange.lowerBound,
                maximumDate: offDayPickerRange.upperBound,
                usesCardMaterial: true,
                usesDarkTypography: true
            )

            Button {
                addPendingOffDay()
            } label: {
                HStack(spacing: 8) {
                    routineButtonIcon(
                        "addwavy",
                        size: 13,
                        color: .black,
                        shadowColor: .clear
                    )

                    Text("Add Off Day")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    BubblyIconMaterial(tint: routineTint)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                }
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(theme.palette.raisedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(routineTint.opacity(0.35), lineWidth: 1)
        }
    }

    private func offDayRow(_ date: Date) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(routineTint.opacity(0.18))
                    .frame(width: 34, height: 34)

                Image("starcal")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(routineTint)
                    .bubblyIconMaterial(tint: routineTint)
                    .shadow(color: Color.black.opacity(0.65), radius: 4, x: 0, y: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(offDayTitle(for: date))
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(adaptiveRoutineTextColor)

                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(adaptiveRoutineSecondaryTextColor)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    routine.removeOffDay(date)
                    routine.refreshCurrentContractStatusIfNeeded()
                    try? modelContext.save()
                    LureliaWidgetReloads.reloadAll()
                }
            } label: {
                Image("minuswavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(routineTint)
                    .bubblyIconMaterial(tint: routineTint)
                    .shadow(color: Color.black.opacity(0.65), radius: 4, x: 0, y: 3)
                    .frame(width: 30, height: 30)
                    .background(routineTint.opacity(0.13), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(routineTint.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(routineTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(routineTint.opacity(0.30), lineWidth: 1)
        }
    }

    private var emptyContractSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(routineTint.opacity(0.20))
                        .frame(width: 48, height: 48)

                    Image("qwill")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 23, height: 23)
                        .foregroundStyle(routineTint)
                        .bubblyIconMaterial(tint: routineTint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("No contract created yet")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(adaptiveRoutineTextColor)

                    Text("Make a formal commitment for this routine when you are ready to sign your name to it.")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            contractActionButton(
                title: "Create Contract",
                icon: "circlefingerprint"
            ) {
                showContractCreator = true
            }
        }
    }

    private func currentContractSummary(_ contract: LureliaRoutineContract) -> some View {
        contractActionButton(
            title: "View Contract",
            icon: "starnote"
        ) {
            viewingContract = contract
        }
    }

    private func contractSummaryPill(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            LureliaIconView(iconId: icon, size: 11)
                .foregroundStyle(routineTint)
                .bubblyIconMaterial(tint: routineTint)

            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(routineTint.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(routineTint.opacity(0.38), lineWidth: 1)
        }
    }

    private func contractActionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                routineButtonIcon(icon, size: 15)

                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.68), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoutineDetailButtonSurface(
                    tint: routineTint,
                    cornerRadius: 16
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var taskFlowCard: some View {
        detailSectionCard(title: "Routine Flow", icon: "starnote") {
            if routine.sortedTasks.isEmpty {
                emptySectionText("No tasks have been added to this routine yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(routine.sortedTasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(task: task)
                        if index < routine.sortedTasks.count - 1 { divider }
                    }
                }
            }
        }
    }
    
    
    // MARK: - Reusable Task Row
    
    @ViewBuilder
    private func taskRow(task: LureliaRoutineTask) -> some View {
        let dayState = taskDayState(task)
        let isPendingToday = dayState == .pending
        let isCompletedToday = dayState == .completed
        let isSkippedToday = dayState == .skipped

        HStack(spacing: 12) {
            NavigationLink(value: task.id) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.42))
                            .frame(width: 34, height: 34)
                        Circle()
                            .strokeBorder(routineTint.opacity(0.85), lineWidth: 1)
                            .frame(width: 34, height: 34)
                        LureliaIconView(iconId: task.icon, size: 15)
                            .foregroundStyle(isPendingToday ? routineTint : adaptiveRoutineSecondaryTextColor)
                            .bubblyIconMaterial(tint: routineTint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(isPendingToday ? adaptiveRoutineTextColor : adaptiveRoutineSecondaryTextColor)
                            .strikethrough(!isPendingToday, color: adaptiveRoutineSecondaryTextColor)
                            .multilineTextAlignment(.leading)

                        let cleanedNotes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanedNotes.isEmpty {
                            Text(cleanedNotes)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if isSkippedToday {
                            HStack(spacing: 5) {
                                Image("skipwavy").renderingMode(.template).resizable().scaledToFit()
                                    .frame(width: 11, height: 11)
                                    .bubblyIconMaterial(tint: routineTint)
                                Text("Skipped").font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        if isCompletedToday {
                            RoutineTaskManager.shared.resetStatus(task: task, context: modelContext)
                        } else {
                            RoutineTaskManager.shared.recordCompletion(task: task, context: modelContext)
                        }
                    }
                } label: {
                    ZStack {
                        if isCompletedToday {
                            BubblyIconMaterial(tint: routineTint)
                                .clipShape(Circle())
                        }
                        Circle().strokeBorder(
                            isSkippedToday ? adaptiveRoutineSecondaryTextColor : routineTint.opacity(0.75),
                            lineWidth: 1.5
                        )
                        .bubblyIconMaterial(
                            tint: isSkippedToday ? adaptiveRoutineSecondaryTextColor : routineTint
                        )
                        if isCompletedToday {
                            routineButtonIcon("checkwavy", size: 10)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.black.opacity(0.42), radius: 5, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                
                if isPendingToday {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            RoutineTaskManager.shared.recordSkip(task: task, context: modelContext)
                        }
                    } label: {
                        Image("skipwavy").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .bubblyIconMaterial(tint: routineTint)
                            .shadow(color: Color.black.opacity(0.65), radius: 5, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                } else if isSkippedToday {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            RoutineTaskManager.shared.resetStatus(task: task, context: modelContext)
                        }
                    } label: {
                        Image("repeatfill").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .bubblyIconMaterial(tint: routineTint)
                            .shadow(color: Color.black.opacity(0.65), radius: 5, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editingTask = task
            } label: {
                Label { Text("Edit") } icon: {
                    Image("settings")
                        .renderingMode(.template)
                        .bubblyIconMaterial(tint: routineTint)
                }
            }

            if !availableMoveDestinations.isEmpty {
                Divider()

                Section("Move to Routine") {
                    ForEach(availableMoveDestinations) { destination in
                        Button {
                            moveTask(task, to: destination)
                        } label: {
                            Label {
                                Text(destination.name)
                            } icon: {
                                Image(destination.icon)
                                    .renderingMode(.template)
                                    .bubblyIconMaterial(tint: routineTint)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                deleteTask(task)
            } label: {
                Label {
                    Text("Delete")
                } icon: {
                    Image("trash")
                        .renderingMode(.template)
                        .bubblyIconMaterial(tint: routineTint)
                }
            }
            .tint(.white)
        }
    }

    private func deleteTask(_ task: LureliaRoutineTask) {
        modelContext.delete(task)
        routine.updatedAt = Date()
        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    private var availableMoveDestinations: [LureliaRoutine] {
        allRoutines
            .filter { $0.persistentID != routine.persistentID }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
    }

    private func moveTask(_ task: LureliaRoutineTask, to destination: LureliaRoutine) {
        guard destination.persistentID != routine.persistentID else { return }

        let destinationTasks = destination.sortedTasks
        let nextSortOrder = (destinationTasks.map(\.sortOrder).max() ?? -1) + 1

        task.attach(to: destination)
        task.phaseID = nil
        task.sortOrder = nextSortOrder
        task.updatedAt = Date()

        routine.updatedAt = Date()
        destination.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    // MARK: - Phases Flow Section
    
    private var phasesFlowSection: some View {
        VStack(spacing: 16) {
            ForEach(routine.sortedPhases) { phase in
                detailSectionCard(
                    title: phase.name.isEmpty ? "Phase" : phase.name,
                    icon: phase.icon
                ) {
                    VStack(spacing: 0) {
                        // Phase schedule if enabled
                        if phase.scheduleEnabled && !phase.scheduledDays.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    ForEach(phase.scheduledDays.sorted(), id: \.self) { weekday in
                                        ZStack {
                                            Circle()
                                                .fill(routineTint.opacity(0.18))
                                                .frame(width: 28, height: 28)
                                            Circle()
                                                .strokeBorder(routineTint.opacity(0.6), lineWidth: 1)
                                                .frame(width: 28, height: 28)
                                            Text(shortWeekdayLabel(for: weekday))
                                                .font(.system(size: 9, weight: .black, design: .rounded))
                                                .foregroundStyle(adaptiveRoutineTextColor)
                                        }
                                    }
                                    Spacer()

                                    HStack(spacing: 14) {
                                        Button {
                                            let run = RoutineManager.shared.startPhaseRun(
                                                for: routine,
                                                phase: phase,
                                                context: modelContext
                                            )

                                            try? modelContext.save()

                                            if run.isActive {
                                                activeRoutine = routine
                                                LureliaWidgetReloads.reloadAll()
                                            }
                                        } label: {
                                            Image("playwavy")
                                                .renderingMode(.template)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 18, height: 18)
                                                .foregroundStyle(routineTint)
                                                .bubblyIconMaterial(tint: routineTint)
                                                .shadow(color: Color.black.opacity(0.72), radius: 4, x: 0, y: 3)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            editingPhase = phase
                                        } label: {
                                            Image("pencil")
                                                .renderingMode(.template)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 17, height: 17)
                                                .foregroundStyle(routineTint)
                                                .bubblyIconMaterial(tint: routineTint)
                                                .shadow(color: Color.black.opacity(0.72), radius: 4, x: 0, y: 3)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                HStack(spacing: 8) {
                                    HStack(spacing: 5) {
                                        Image("clockfill").renderingMode(.template).resizable().scaledToFit()
                                            .frame(width: 11, height: 11).foregroundStyle(routineTint)
                                            .bubblyIconMaterial(tint: routineTint)
                                            .shadow(color: Color.black.opacity(0.72), radius: 3, x: 0, y: 2)
                                        Text(phase.formattedTimeRange)
                                            .font(.system(size: 11, weight: .black, design: .rounded))
                                            .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(routineTint.opacity(0.18), in: Capsule())
                                    .overlay(Capsule().strokeBorder(routineTint.opacity(0.45), lineWidth: 1))
                                    
                                    HStack(spacing: 5) {
                                        Image("hourglassfill").renderingMode(.template).resizable().scaledToFit()
                                            .frame(width: 11, height: 11).foregroundStyle(routineTint)
                                            .bubblyIconMaterial(tint: routineTint)
                                            .shadow(color: Color.black.opacity(0.72), radius: 3, x: 0, y: 2)
                                        Text(phaseDurationText(for: phase))
                                            .font(.system(size: 11, weight: .black, design: .rounded))
                                            .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(routineTint.opacity(0.18), in: Capsule())
                                    .overlay(Capsule().strokeBorder(routineTint.opacity(0.45), lineWidth: 1))
                                }
                            }
                            .padding(.bottom, 8)
                            Divider().overlay(theme.palette.textSecondary.opacity(0.18))
                                .padding(.bottom, 4)
                        }
                        
                        // Phase tasks
                        let phaseTasks = routine.tasksForPhase(phase)
                        if phaseTasks.isEmpty {
                            emptySectionText("No tasks in this phase.")
                        } else {
                            ForEach(Array(phaseTasks.enumerated()), id: \.element.id) { idx, task in
                                taskRow(task: task)
                                if idx < phaseTasks.count - 1 {
                                    Divider().overlay(theme.palette.textSecondary.opacity(0.18))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var historyCard: some View {
        detailSectionCard(title: "Run History", icon: "clock.arrow.circlepath") {
            if sortedRuns.isEmpty {
                emptySectionText("No completed routine runs yet. Start this routine to begin building history.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedRuns.prefix(10).enumerated()), id: \.element.id) { index, run in
                        runHistoryRow(run)
                            .contextMenu {
                                Button {
                                    deleteRunHistory(run)
                                } label: {
                                    Label {
                                        Text("Delete")
                                            .foregroundStyle(adaptiveRoutineTextColor)
                                    } icon: {
                                        Image("trash")
                                            .renderingMode(.template)
                                            .foregroundStyle(adaptiveRoutineTextColor)
                                            .bubblyIconMaterial(tint: routineTint)
                                    }
                                }
                            }
                        if index < min(sortedRuns.count, 10) - 1 { divider }
                    }
                }
            }
        }
    }

    // MARK: - Calendar Card

    private var routineCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    calendarExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image("ringstarcal")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(routineTint)
                        .frame(width: 20, height: 20)
                        .bubblyIconMaterial(tint: routineTint)

                    Text("Calendar")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    Image(calendarExpanded ? "chevup" : "chevdown")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(routineTint)
                        .frame(width: 15, height: 15)
                        .bubblyIconMaterial(tint: routineTint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if calendarExpanded {
                VStack(spacing: 14) {
                    HStack {
                        Button {
                            changeCalendarMonth(by: -1)
                        } label: {
                            Image("chevleft")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 15)
                                .foregroundStyle(routineTint)
                                .bubblyIconMaterial(tint: routineTint)
                                .shadow(color: Color.black.opacity(0.65), radius: 5, x: 0, y: 3)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(displayedCalendarMonth.formatted(.dateTime.month(.wide).year()))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(adaptiveRoutineTextColor)

                        Spacer()

                        Button {
                            changeCalendarMonth(by: 1)
                        } label: {
                            Image("chevright")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 15)
                                .foregroundStyle(routineTint)
                                .bubblyIconMaterial(tint: routineTint)
                                .shadow(color: Color.black.opacity(0.65), radius: 5, x: 0, y: 3)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                        spacing: 8
                    ) {
                        ForEach(
                            Array(Calendar.current.veryShortWeekdaySymbols.enumerated()),
                            id: \.offset
                        ) { _, symbol in
                            Text(symbol)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(routineTint)
                                .bubblyIconMaterial(tint: routineTint)
                                .shadow(color: Color.black.opacity(0.65), radius: 4, x: 0, y: 3)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(Array(calendarDaysForDisplayedMonth.enumerated()), id: \.offset) { _, date in
                            if let date {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        Calendar.current.isDateInToday(date)
                                        ? routineFillTextColor
                                        : adaptiveRoutineTextColor
                                    )
                                    .frame(width: 32, height: 32)
                                    .background {
                                        if Calendar.current.isDateInToday(date) {
                                            BubblyIconMaterial(tint: routineTint)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(theme.palette.raisedSurface)
                                        }
                                    }
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                Calendar.current.isDateInToday(date)
                                                ? routineTint.opacity(0.85)
                                                : routineTint.opacity(0.30),
                                                lineWidth: 1
                                            )
                                    }
                                    .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(height: 32)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background {
                    BubblyCardMaterial(
                        tint: routineTint,
                        cornerRadius: 18
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        calendarExpanded = true
                    }
                } label: {
                    HStack(spacing: 9) {
                        routineButtonIcon("ringstarcal", size: 15)

                        Text("View Calendar")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.black.opacity(0.68), radius: 2, x: 0, y: 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoutineDetailButtonSurface(
                            tint: routineTint,
                            cornerRadius: 16
                        )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background {
                    BubblyCardMaterial(
                        tint: routineTint,
                        cornerRadius: 18
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private var calendarDaysForDisplayedMonth: [Date?] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedCalendarMonth),
            let dayRange = calendar.range(of: .day, in: .month, for: displayedCalendarMonth)
        else {
            return []
        }

        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        var days = Array<Date?>(repeating: nil, count: max(0, firstWeekday - 1))

        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func changeCalendarMonth(by value: Int) {
        guard let newMonth = Calendar.current.date(
            byAdding: .month,
            value: value,
            to: displayedCalendarMonth
        ) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            displayedCalendarMonth = newMonth
        }
    }

    // MARK: - Principles Card

    private var principlesCard: some View {
        detailSectionCard(title: "Principles", icon: "sparkleprogress") {
            VStack(spacing: 12) {
                ForEach(routine.principles.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(routineTint.opacity(0.18))
                                .frame(width: 34, height: 34)
                            Circle()
                                .strokeBorder(routineTint.opacity(0.8), lineWidth: 1.5)
                                .frame(width: 34, height: 34)
                                .bubblyIconMaterial(tint: routineTint)
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(adaptiveRoutineTextColor)
                        }
                        Text(routine.principles[index])
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(adaptiveRoutineTextColor)
                        Spacer()
                    }
                    if index < routine.principles.count - 1 {
                        Divider().overlay(theme.palette.textSecondary.opacity(0.18))
                    }
                }
            }
        }
    }
}

// MARK: - Components
extension RoutineDetailView {
    
    private func routineMiniPill(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 5) {
            routineMaterialIcon(icon, size: 13)

            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveRoutineTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(subtitle)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.palette.raisedSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(routineTint.opacity(0.22))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(routineTint.opacity(0.50), lineWidth: 1.05)
        )
    }
    
    private var displayTaskCount: Int {
        if routine.phasesEnabled {
            return routine.sortedPhases.reduce(0) { total, phase in
                total + routine.tasksForPhase(phase).count
            }
        }

        return (routine.tasks ?? []).count
    }
    
    private var totalRoutineTaskCount: Int {
        if routine.phasesEnabled {
            return routine.sortedPhases.reduce(0) { total, phase in
                total + routine.tasksForPhase(phase).count
            }
        }

        return routine.sortedTasks.count
    }

    private var completedRoutineTaskCount: Int {
        if routine.phasesEnabled {
            return routine.sortedPhases.reduce(0) { total, phase in
                total + routine.tasksForPhase(phase).filter {
                    taskDayState($0) == .completed
                }.count
            }
        }

        return routine.sortedTasks.filter {
            taskDayState($0) == .completed
        }.count
    }

    private var routineTaskProgress: Double {
        guard totalRoutineTaskCount > 0 else { return 0 }
        return Double(completedRoutineTaskCount) / Double(totalRoutineTaskCount)
    }

    private var routineTaskProgressPercentText: String {
        "\(Int((routineTaskProgress * 100).rounded()))%"
    }

    private var displayDurationMinutes: Int {
        if routine.phasesEnabled {
            return routine.sortedPhases.reduce(0) { total, phase in
                total + phaseDurationMinutes(for: phase)
            }
        }

        return routine.durationMinutes
    }

    private var displayDurationText: String {
        let minutes = displayDurationMinutes
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 && remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(remainingMinutes)m"
    }

    private var displayScheduleIsOn: Bool {
        if routine.phasesEnabled {
            return routine.sortedPhases.contains { phase in
                phase.scheduleEnabled && !phase.scheduledDays.isEmpty
            }
        }

        return routine.scheduleEnabled
    }

    private var displayScheduleText: String {
        displayScheduleIsOn ? "On" : "Off"
    }

    private var displayScheduleIcon: String {
        displayScheduleIsOn ? "bellfill" : "bell.slash.fill"
    }

    private func phaseDurationMinutes(for phase: LureliaRoutinePhase) -> Int {
        let startMinutes = phase.startHour * 60 + phase.startMinute
        let endMinutes = phase.endHour * 60 + phase.endMinute
        let difference = endMinutes - startMinutes

        return max(
            1,
            difference > 0 ? difference : difference + 1440
        )
    }
    
    private func heroMetaLabel(
        icon: String,
        text: String,
        color: Color
    ) -> some View {
        HStack(spacing: 5) {
            routineMaterialIcon(icon, size: 12)

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
    }
    
    private func routineActionButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                routineButtonIcon(icon, size: 17)

                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.68), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoutineDetailButtonSurface(
                    tint: routineTint,
                    cornerRadius: 20,
                    dimmingOpacity: isPrimary ? 0 : 0.36
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isPrimary ? Color.white.opacity(0.14) : routineTint.opacity(0.45),
                        lineWidth: 1.05
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveRoutineTextColor)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background {
            BubblyCardMaterial(
                tint: routineTint,
                cornerRadius: 20
            )
        }
    }
    
    private func detailSectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                routineMaterialIcon(icon, size: 20)
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    BubblyCardMaterial(
                        tint: routineTint,
                        cornerRadius: 18
                    )
                }
        }
    }
    
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            routineMaterialIcon(icon, size: 14)
                .frame(width: 18)
                .shadow(color: Color.black.opacity(0.65), radius: 4, x: 0, y: 3)
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(adaptiveRoutineSecondaryTextColor)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(adaptiveRoutineTextColor)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func runHistoryRow(_ run: LureliaRoutineRun) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(run.wasCompleted ? routineTint.opacity(0.24) : theme.palette.raisedSurface)
                    .frame(width: 34, height: 34)
                Image(run.wasCompleted ? "checkwavy" : "xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(run.wasCompleted ? routineTint : adaptiveRoutineSecondaryTextColor)
                    .bubblyIconMaterial(tint: routineTint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(run.startedAt, style: .date)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(adaptiveRoutineTextColor)
                Text("\(run.completedCount)/\(run.totalCount) tasks completed · \(run.skippedCount) skipped")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(adaptiveRoutineSecondaryTextColor)
            }
            Spacer()
            if let endedAt = run.endedAt {
                let minutes = Int(endedAt.timeIntervalSince(run.startedAt) / 60)
                Text("\(minutes)m")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(adaptiveRoutineSecondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(routineTint.opacity(0.18), in: Capsule())
            }
        }
        .padding(.vertical, 10)
    }

    private func routineMaterialIcon(_ icon: String, size: CGFloat) -> some View {
        RoutineDetailMaterialIcon(
            icon: icon,
            size: size,
            tint: routineTint
        )
    }

    private func routineButtonIcon(
        _ icon: String,
        size: CGFloat,
        color: Color = .white,
        shadowColor: Color = Color.black.opacity(0.58)
    ) -> some View {
        RoutineDetailButtonIcon(
            icon: icon,
            size: size,
            color: color,
            shadowColor: shadowColor
        )
    }
    
    private func deleteRunHistory(_ run: LureliaRoutineRun) {
        modelContext.delete(run)
        routine.updatedAt = Date()
        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }

    private var offDayPickerRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 89, to: start) ?? start
        return start...end
    }

    private func normalizedOffDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func addPendingOffDay() {
        let result = routine.addOffDay(normalizedOffDay(pendingOffDayDate))

        switch result {
        case .valid:
            offDayValidationMessage = nil
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                offDayPickerExpanded = false
            }
            routine.refreshCurrentContractStatusIfNeeded()
            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()
        case .duplicate:
            offDayValidationMessage = "That off day is already selected."
        case .backToBack:
            offDayValidationMessage = "Off days cannot be back to back."
        case .limitReached:
            offDayValidationMessage = "Only 2 off days are allowed per 30 days."
        }
    }

    private func offDayTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        }

        return date.formatted(.dateTime.weekday(.wide))
    }
    
    private func emptySectionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, design: .rounded))
            .foregroundStyle(adaptiveRoutineSecondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
    
    private func shortWeekdayLabel(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "--" }
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }
    
    private func fullWeekdayLabel(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "Unknown Day" }
        return Calendar.current.weekdaySymbols[weekday - 1]
    }
    
    private var divider: some View {
        Divider()
            .overlay(theme.palette.textSecondary.opacity(0.18))
    }
}

private struct RoutineDetailMaterialIcon: View {
    let icon: String
    let size: CGFloat
    let tint: Color

    @ViewBuilder
    var body: some View {
        if UIImage(named: icon) != nil {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .bubblyIconMaterial(tint: tint)
        } else {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .bubblyIconMaterial(tint: tint)
        }
    }
}

private struct RoutineDetailButtonIcon: View {
    let icon: String
    let size: CGFloat
    let color: Color
    let shadowColor: Color

    @ViewBuilder
    var body: some View {
        if UIImage(named: icon) != nil {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(color)
                .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
        } else {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(color)
                .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
        }
    }
}

private struct RoutineDetailButtonSurface: View {
    let tint: Color
    let cornerRadius: CGFloat
    var dimmingOpacity: Double = 0

    var body: some View {
        ZStack {
            BubblyCardMaterial(
                tint: tint,
                cornerRadius: cornerRadius
            )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(dimmingOpacity))
        }
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.46), radius: 8, x: 0, y: 4)
        .allowsHitTesting(false)
    }
}

private func phaseDurationText(for phase: LureliaRoutinePhase) -> String {
    let startMinutes = phase.startHour * 60 + phase.startMinute
    let endMinutes = phase.endHour * 60 + phase.endMinute
    let difference = endMinutes - startMinutes

    let totalMinutes = max(
        1,
        difference > 0 ? difference : difference + 1440
    )

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 && minutes > 0 {
        return "\(hours)h \(minutes)m"
    }

    if hours > 0 {
        return "\(hours)h"
    }

    return "\(minutes)m"
}

private struct EditRoutinePhaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var routine: LureliaRoutine
    @Bindable var phase: LureliaRoutinePhase
    let routineTint: Color

    @State private var name: String
    @State private var selectedIcon: String
    @State private var scheduleEnabled: Bool
    @State private var selectedDays: Set<Int>
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var showIconPicker = false
    @State private var showAddTask = false
    @State private var editingTask: LureliaRoutineTask?
    @State private var taskPendingDeletion: LureliaRoutineTask?

    init(
        routine: LureliaRoutine,
        phase: LureliaRoutinePhase,
        routineTint: Color
    ) {
        self.routine = routine
        self.phase = phase
        self.routineTint = routineTint

        _name = State(initialValue: phase.name)
        _selectedIcon = State(initialValue: phase.icon)
        _scheduleEnabled = State(initialValue: phase.scheduleEnabled)
        _selectedDays = State(initialValue: Set(phase.scheduledDays))
        _startHour = State(initialValue: phase.startHour)
        _startMinute = State(initialValue: phase.startMinute)
        _endHour = State(initialValue: phase.endHour)
        _endMinute = State(initialValue: phase.endMinute)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var adaptiveTextColor: Color {
        routineTint.wcagContrastingTextColor
    }

    private var adaptiveSecondaryTextColor: Color {
        routineTint.wcagContrastingSecondaryTextColor
    }

    private var sheetTextColor: Color { .white.opacity(0.92) }
    private var sheetSecondaryTextColor: Color { .white.opacity(0.72) }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var phaseTasks: [LureliaRoutineTask] {
        routine.tasksForPhase(phase)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LureliaBackgroundAlt()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header
                        iconCard

                        fieldCard(title: "Phase Name") {
                            TextField("Phase name", text: $name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(sheetTextColor)
                        }

                        scheduleCard
                        timeCard
                        tasksCard
                        saveButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            .sheet(isPresented: Binding(
                get: { !isPad && showAddTask },
                set: { showAddTask = $0 }
            )) {
                addTaskSheet
            }
            .fullScreenCover(isPresented: Binding(
                get: { isPad && showAddTask },
                set: { showAddTask = $0 }
            )) {
                addTaskSheet
            }
            .routineTaskEditor(
                isPad: isPad,
                task: $editingTask,
                routineTint: routineTint
            )
            .confirmationDialog(
                "Remove Task?",
                isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Task", role: .destructive) {
                    if let taskPendingDeletion {
                        removeTask(taskPendingDeletion)
                    }
                    taskPendingDeletion = nil
                }

                Button("Cancel", role: .cancel) {
                    taskPendingDeletion = nil
                }
            } message: {
                Text("This removes the task from this phase and cancels its task notifications.")
            }
        }
    }

    private var addTaskSheet: some View {
        AddCustomRoutineTaskView(tint: routineTint) { draft in
            addTask(from: draft)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Edit Phase")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(sheetTextColor)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(adaptiveTextColor)
                    .bubblyIconMaterial(tint: adaptiveTextColor)
                    .wcagContrastLift(on: routineTint)
                    .frame(width: 40, height: 40)
                    .background(routineTint, in: Circle())
                    .overlay {
                        Circle().strokeBorder(routineTint, lineWidth: 2)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var iconCard: some View {
        Button {
            showIconPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)

                    Circle()
                        .strokeBorder(routineTint, lineWidth: 2)
                        .frame(width: 48, height: 48)

                    LureliaIconView(iconId: selectedIcon, size: 23)
                        .foregroundStyle(routineTint)
                        .bubblyIconMaterial(tint: routineTint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Phase Icon")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(sheetTextColor)

                    Text("Tap to change the icon")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(sheetSecondaryTextColor)
                }

                Spacer()

                Image("chevright")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(routineTint)
                    .bubblyIconMaterial(tint: routineTint)
            }
            .padding(14)
            .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(routineTint, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var scheduleCard: some View {
        fieldCard(title: "Schedule") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Scheduled Phase")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(sheetTextColor)

                    Spacer(minLength: 8)

                    LureliaSlidingIconToggle(
                        isOn: $scheduleEnabled,
                        iconName: "clockwavy",
                        accentColor: routineTint,
                        accessibilityLabel: "Scheduled Phase",
                        usesIconMaterial: true
                    )
                }

                if scheduleEnabled {
                    HStack(spacing: 7) {
                        ForEach(1...7, id: \.self) { weekday in
                            Button {
                                if selectedDays.contains(weekday) {
                                    selectedDays.remove(weekday)
                                } else {
                                    selectedDays.insert(weekday)
                                }
                            } label: {
                                Text(shortWeekdayLabel(for: weekday))
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(
                                        selectedDays.contains(weekday)
                                        ? Color.black
                                        : sheetSecondaryTextColor
                                    )
                                    .frame(width: 32, height: 32)
                                    .background {
                                        if selectedDays.contains(weekday) {
                                            BubblyIconMaterial(tint: routineTint)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(Color.white.opacity(0.06))
                                        }
                                    }
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                selectedDays.contains(weekday)
                                                ? routineTint
                                                : Color.white.opacity(0.22),
                                                lineWidth: selectedDays.contains(weekday) ? 2 : 1.5
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIME")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(sheetSecondaryTextColor)

            HStack(alignment: .top, spacing: 10) {
                compactTimePicker(
                    title: "Start time",
                    hour: $startHour,
                    minute: $startMinute
                )

                compactTimePicker(
                    title: "End time",
                    hour: $endHour,
                    minute: $endMinute
                )
            }
        }
    }

    private func compactTimePicker(
        title: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(sheetSecondaryTextColor)

            LureliaCompactTimeDrumPicker(
                hour: hour,
                minute: minute,
                tint: routineTint,
                usesDarkTypography: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tasksCard: some View {
        fieldCard(title: "Tasks") {
            VStack(spacing: 12) {
                Button {
                    showAddTask = true
                } label: {
                    HStack(spacing: 10) {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(.white)
                            .bubblyIconMaterial(tint: .white)
                            .shadow(color: .black.opacity(0.72), radius: 2, x: 0, y: 1)

                        Text("Add Task")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.black)

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background {
                        BubblyIconMaterial(tint: routineTint)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(routineTint, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)

                if phaseTasks.isEmpty {
                    Text("No tasks in this phase yet.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(sheetSecondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(phaseTasks.enumerated()), id: \.element.id) { index, task in
                            phaseTaskRow(task)

                            if index < phaseTasks.count - 1 {
                                Divider()
                                    .overlay(routineTint.opacity(0.55))
                                    .padding(.horizontal, 8)
                            }
                        }
                    }
                }
            }
        }
    }

    private func phaseTaskRow(_ task: LureliaRoutineTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                LureliaIconView(iconId: task.icon, size: 16)
                    .foregroundStyle(routineTint)
                    .bubblyIconMaterial(tint: routineTint)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle().strokeBorder(routineTint, lineWidth: 2)
                    }

                Spacer(minLength: 0)

                Button {
                    editingTask = task
                } label: {
                    Image("pencil")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(routineTint)
                        .bubblyIconMaterial(tint: routineTint)
                        .frame(width: 32, height: 32)
                        .background(LColors.glassSurface2, in: Circle())
                        .overlay {
                            Circle().strokeBorder(routineTint, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    taskPendingDeletion = task
                } label: {
                    Image("trash")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(routineTint)
                        .bubblyIconMaterial(tint: routineTint)
                        .frame(width: 32, height: 32)
                        .background(LColors.glassSurface2, in: Circle())
                        .overlay {
                            Circle().strokeBorder(routineTint, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(sheetTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(sheetSecondaryTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func fieldCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(sheetSecondaryTextColor)

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(routineTint, lineWidth: 2)
                }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save Phase")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    BubblyCardMaterial(tint: routineTint, cornerRadius: 24)
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
    }

    private func save() {
        phase.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        phase.icon = selectedIcon
        phase.scheduleEnabled = scheduleEnabled
        phase.scheduledDays = Array(selectedDays).sorted()
        phase.startHour = startHour
        phase.startMinute = startMinute
        phase.endHour = endHour
        phase.endMinute = endMinute
        phase.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
        dismiss()
    }

    private func addTask(from draft: LureliaRoutineTaskDraft) {
        let cleanTitle = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let task = LureliaRoutineTask(
            title: cleanTitle,
            icon: draft.icon,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: phaseTasks.count
        )
        task.phaseID = phase.id.uuidString
        task.attach(to: routine)

        modelContext.insert(task)

        if routine.tasks == nil {
            routine.tasks = []
        }
        if routine.tasks?.contains(where: { $0.id == task.id }) != true {
            routine.tasks?.append(task)
        }

        applyTaskDraft(draft, to: task)
        normalizePhaseTaskOrder()
        routine.updatedAt = Date()
        phase.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("🚨 [EditRoutinePhase] Add task save failed: \(error)")
        }

        RoutineTaskManager.shared.sync(task: task)
        LureliaWidgetReloads.reloadAll()
    }

    private func removeTask(_ task: LureliaRoutineTask) {
        RoutineTaskManager.shared.cancel(task: task)
        routine.tasks = (routine.tasks ?? []).filter { $0.id != task.id }
        modelContext.delete(task)
        normalizePhaseTaskOrder()
        routine.updatedAt = Date()
        phase.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("🚨 [EditRoutinePhase] Remove task save failed: \(error)")
        }

        LureliaWidgetReloads.reloadAll()
    }

    private func normalizePhaseTaskOrder() {
        for (index, task) in phaseTasks.enumerated() {
            task.sortOrder = index
            task.updatedAt = Date()
        }
    }

    private func applyTaskDraft(_ draft: LureliaRoutineTaskDraft, to task: LureliaRoutineTask) {
        task.title = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        task.icon = draft.icon
        task.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        task.context = draft.context.trimmingCharacters(in: .whitespacesAndNewlines)
        task.purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        task.motivation = draft.motivation.trimmingCharacters(in: .whitespacesAndNewlines)
        task.trigger = draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        task.triggerType = draft.triggerType
        task.triggerReason = draft.triggerReason.trimmingCharacters(in: .whitespacesAndNewlines)
        task.environment = draft.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        task.reward = draft.reward.trimmingCharacters(in: .whitespacesAndNewlines)
        task.rewardEnabled = draft.rewardEnabled
        task.consequence = draft.consequence.trimmingCharacters(in: .whitespacesAndNewlines)
        task.consequenceEnabled = draft.consequenceEnabled
        task.recoveryPlan = draft.recoveryPlan.trimmingCharacters(in: .whitespacesAndNewlines)

        task.hasDueTime = draft.hasDueTime
        task.dueHour = draft.dueHour
        task.dueMinute = draft.dueMinute
        task.estimatedDurationMinutes = max(0, draft.estimatedDurationMinutes)
        task.repeatsOnDays = draft.repeatsOnDays
        task.scheduledDays = draft.scheduledDays.sorted()

        task.notificationsEnabled = draft.notificationsEnabled && draft.hasDueTime
        task.notificationLeadMinutes = draft.notificationLeadMinutes.sorted()
        task.alarmEnabled = draft.alarmEnabled && draft.hasDueTime
        task.alarmSoundName = (draft.alarmEnabled && draft.hasDueTime) ? draft.alarmSoundName : nil

        for (index, stepDraft) in draft.steps.enumerated()
        where !stepDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let step = LureliaRoutineTaskStep(
                title: stepDraft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                isCompleted: stepDraft.isCompleted,
                sortOrder: index
            )
            step.id = stepDraft.id
            modelContext.insert(step)
            step.task = task
            if task.stepItems == nil { task.stepItems = [] }
            task.stepItems?.append(step)
        }

        for (index, supplyDraft) in draft.supplies.enumerated()
        where !supplyDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let supply = LureliaRoutineTaskSupply(
                name: supplyDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: index
            )
            supply.id = supplyDraft.id
            modelContext.insert(supply)
            supply.task = task
            if task.supplyItems == nil { task.supplyItems = [] }
            task.supplyItems?.append(supply)
        }

        for (index, obstacleDraft) in draft.obstacles.enumerated()
        where !obstacleDraft.obstacle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let obstacle = LureliaRoutineTaskObstacle(
                obstacle: obstacleDraft.obstacle.trimmingCharacters(in: .whitespacesAndNewlines),
                solution: obstacleDraft.solution.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: index
            )
            obstacle.id = obstacleDraft.id
            modelContext.insert(obstacle)
            obstacle.task = task
            if task.obstacleItems == nil { task.obstacleItems = [] }
            task.obstacleItems?.append(obstacle)
        }

        task.updatedAt = Date()
    }

    private func shortWeekdayLabel(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "--" }
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }
}

private struct EditRoutineTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var task: LureliaRoutineTask
    let routineTint: Color

    @State private var title: String
    @State private var notes: String
    @State private var selectedIcon: String
    @State private var showIconPicker = false

    init(
        task: LureliaRoutineTask,
        routineTint: Color
    ) {
        self.task = task
        self.routineTint = routineTint

        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _selectedIcon = State(initialValue: task.icon)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var adaptiveRoutineTextColor: Color {
        .white.opacity(0.92)
    }
    
    private var adaptiveRoutineSecondaryTextColor: Color {
        .white.opacity(0.72)
    }

    private var routineFillTextColor: Color {
        routineTint.wcagContrastingSolidTextColor
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LureliaBackgroundAlt()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header

                        iconCard

                        fieldCard(
                            title: "Task Name"
                        ) {
                            TextField("Task name", text: $title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(adaptiveRoutineTextColor)
                        }

                        fieldCard(
                            title: "Notes"
                        ) {
                            TextField("Notes", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(adaptiveRoutineTextColor)
                        }

                        saveButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Edit Task")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveRoutineTextColor)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(routineFillTextColor)
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
    }

    private var iconCard: some View {
        Button {
            showIconPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)

                    Circle()
                        .strokeBorder(routineTint.opacity(0.85), lineWidth: 1)

                    LureliaIconView(iconId: selectedIcon, size: 23)
                        .foregroundStyle(routineTint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Task Icon")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(adaptiveRoutineTextColor)

                    Text("Tap to change the icon")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Image("chevright")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(routineTint)
            }
            .padding(14)
            .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(routineTint.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func fieldCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(routineTint.opacity(0.35), lineWidth: 1)
                }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save Task")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(canSave ? routineFillTextColor : .white.opacity(0.45))
                .wcagContrastLift(on: routineTint, isActive: canSave)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    canSave ? routineTint : Color.white.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private func save() {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.icon = selectedIcon
        task.updatedAt = Date()

        try? modelContext.save()
        dismiss()
        LureliaWidgetReloads.reloadAll()
    }
}

private struct RoutineTaskDottedProgressRing<CenterContent: View>: View {
    let progress: Double
    let size: CGFloat
    let dotCount: Int
    let dotDiameter: CGFloat
    let trackColor: Color
    let progressColor: Color
    let centerContent: () -> CenterContent

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var filledDotCount: Int {
        Int((clampedProgress * Double(dotCount)).rounded())
    }

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { index in
                BubblyIconMaterial(
                    tint: index < filledDotCount ? progressColor : trackColor
                )
                    .clipShape(Circle())
                    .frame(width: dotDiameter, height: dotDiameter)
                    .offset(y: -(size / 2))
                    .rotationEffect(.degrees(Double(index) / Double(dotCount) * 360))
            }

            centerContent()
        }
        .frame(width: size, height: size)
    }
}
