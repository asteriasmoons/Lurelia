//
//  KanbanBoardView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import WidgetKit

enum KanbanCreateType { case reminder }
struct KanbanCreateRequest: Identifiable {
    let id = UUID()
    let type: KanbanCreateType
    let column: KanbanColumn
}

struct KanbanRoutineTaskCreateRequest: Identifiable {
    let id = UUID()
    let routine: LureliaRoutine
    let column: KanbanColumn
}

struct KanbanHabitCreateRequest: Identifiable {
    let id = UUID()
    let column: KanbanColumn
}

struct KanbanQuickTaskCreateRequest: Identifiable {
    let id = UUID()
    let column: KanbanColumn
    let suggestedDate: Date?

    init(column: KanbanColumn, suggestedDate: Date? = nil) {
        self.column = column
        self.suggestedDate = suggestedDate
    }
}

// MARK: - Kanban Column Add Menu

struct KanbanColumnAddCardMenu<LabelContent: View>: View {
    @Bindable var column: KanbanColumn

    let allReminders: [LureliaReminder]
    let allRoutines: [LureliaRoutine]
    let allHabits: [LureliaHabit]
    let onCreateReminder: () -> Void
    let onCreateHabit: () -> Void
    let onCreateQuickTask: () -> Void
    let onAddCard: (KanbanCardType, String) -> Void
    let onAddTask: (LureliaRoutine) -> Void
    @ViewBuilder var label: () -> LabelContent

    /// Observed so pinning excludes items pinned anywhere across every
    /// board — not just this column. Previously the same habit / routine
    /// task / reminder could be pinned to multiple boards at once.
    @Query private var allBoards: [KanbanBoard]

    private var allCards: [KanbanCard] {
        allBoards.flatMap { $0.columns ?? [] }.flatMap { $0.cards ?? [] }
    }

    private var pinnedReminderIDs: Set<String> {
        Set(allCards.filter { $0.cardType == .reminder }.map(\.itemID))
    }

    private var pinnedRoutineTaskIDs: Set<String> {
        let allTasks = allRoutines.flatMap { $0.sortedTasks }
        return Set(
            allCards
                .filter { $0.cardType == .routineTask }
                .map { card in
                    allTasks.first { $0.matchesKanbanItemID(card.itemID) }?.kanbanItemID ?? card.itemID
                }
        )
    }

    private var pinnedHabitIDs: Set<String> {
        Set(allCards.filter { $0.cardType == .habit }.map(\.itemID))
    }

    private var availableReminders: [LureliaReminder] {
        allReminders
            .filter { !pinnedReminderIDs.contains($0.id.uuidString) }
            .sorted { $0.title < $1.title }
    }

    private var availableRoutines: [LureliaRoutine] {
        allRoutines.sorted { $0.name < $1.name }
    }

    private var availableHabits: [LureliaHabit] {
        allHabits
            .filter { !$0.isArchived && !pinnedHabitIDs.contains($0.kanbanItemID) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        Menu {
            Button {
                onCreateQuickTask()
            } label: {
                Label {
                    Text("Add Quick Task")
                        .foregroundStyle(.white)
                } icon: {
                    Image("starnote")
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                }
                .foregroundStyle(.white)
            }

            Menu {
                Button {
                    onCreateReminder()
                } label: {
                    Label("New Reminder", systemImage: "plus.circle")
                }

                if availableReminders.isEmpty {
                    Text("No existing reminders")
                } else {
                    Menu {
                        ForEach(availableReminders) { reminder in
                            Button {
                                onAddCard(.reminder, reminder.id.uuidString)
                            } label: {
                                Label(reminder.title, systemImage: "bell")
                            }
                        }
                    } label: {
                        Label("Existing Reminders", systemImage: "tray")
                    }
                }
            } label: {
                Label("Reminder", systemImage: "bell")
            }

            Menu {
                if availableRoutines.isEmpty {
                    Text("No routines available")
                } else {
                    ForEach(availableRoutines) { routine in
                        routineMenu(for: routine)
                    }
                }
            } label: {
                Label("Routine", systemImage: "repeat")
            }

            Menu {
                Button {
                    onCreateHabit()
                } label: {
                    Label("New Habit", systemImage: "plus.circle")
                }

                if availableHabits.isEmpty {
                    Text("No habits available")
                } else {
                    ForEach(availableHabits) { habit in
                        Button {
                            onAddCard(.habit, habit.kanbanItemID)
                        } label: {
                            Label(habit.title, systemImage: "flame")
                        }
                    }
                }
            } label: {
                Label("Habit", systemImage: "flame")
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func routineMenu(for routine: LureliaRoutine) -> some View {
        Menu {
            if routine.sortedTasks.isEmpty {
                Text("No tasks yet")
            } else {
                Menu {
                    ForEach(routine.sortedTasks, id: \.kanbanItemID) { task in
                        Button {
                            onAddCard(.routineTask, task.kanbanItemID)
                        } label: {
                            Label(
                                task.title,
                                systemImage: pinnedRoutineTaskIDs.contains(task.kanbanItemID) ? "checkmark.circle" : "circle"
                            )
                        }
                        .disabled(pinnedRoutineTaskIDs.contains(task.kanbanItemID))
                    }
                } label: {
                    Label("Add Existing Task", systemImage: "checklist")
                }
            }

            Button {
                onAddTask(routine)
            } label: {
                Label("Add New Task", systemImage: "plus")
            }
        } label: {
            Label(routine.name, systemImage: "repeat")
        }
    }
}

// MARK: - Kanban Routine Task Creation Sheet

struct KanbanRoutineTaskCreationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var routine: LureliaRoutine
    let onCreated: (LureliaRoutineTask) -> Void

    var body: some View {
        AddCustomRoutineTaskView(tint: Color(lureliaHex: routine.colorHex)) { draft in
            addTask(from: draft)
        }
    }

    private func addTask(from draft: LureliaRoutineTaskDraft) {
        let title = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let task = LureliaRoutineTask(
            title: title,
            icon: draft.icon,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: routine.sortedTasks.count
        )
        task.routine = routine
        modelContext.insert(task)

        if routine.tasks == nil {
            routine.tasks = []
        }
        routine.tasks?.append(task)

        applyTaskDraft(draft, to: task)
        routine.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("🚨 [KanbanRoutineTaskCreation] save failed: \(error)")
        }

        RoutineTaskManager.shared.sync(task: task)
        LureliaWidgetReloads.reloadAll()
        onCreated(task)
    }

    private func applyTaskDraft(_ draft: LureliaRoutineTaskDraft, to task: LureliaRoutineTask) {
        task.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.context = draft.context.trimmingCharacters(in: .whitespacesAndNewlines)
        task.purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        task.motivation = draft.motivation.trimmingCharacters(in: .whitespacesAndNewlines)
        task.trigger = draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        task.triggerType = draft.triggerType
        task.triggerReason = draft.triggerReason.trimmingCharacters(in: .whitespacesAndNewlines)
        task.environment = draft.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        task.reward = draft.reward.trimmingCharacters(in: .whitespacesAndNewlines)
        task.consequence = draft.consequence.trimmingCharacters(in: .whitespacesAndNewlines)
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
            step.task = task
            modelContext.insert(step)
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
            supply.task = task
            modelContext.insert(supply)
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
            obstacle.task = task
            modelContext.insert(obstacle)
            if task.obstacleItems == nil { task.obstacleItems = [] }
            task.obstacleItems?.append(obstacle)
        }
    }
}

// MARK: - Kanban Quick Task Creation Sheet

struct AddKanbanQuickTaskSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Bindable var column: KanbanColumn
    private let editingTask: KanbanQuickTask?

    @State private var name = ""
    @State private var details = ""
    @State private var hasDate: Bool
    @State private var hasTime = false
    @State private var selectedDate: Date
    @State private var hour: Int
    @State private var minute: Int

    init(
        column: KanbanColumn,
        editingTask: KanbanQuickTask? = nil,
        suggestedDate: Date? = nil
    ) {
        self.column = column
        self.editingTask = editingTask

        let initialDate = editingTask?.taskDate ?? suggestedDate ?? Date()
        let initialTime = editingTask?.taskTime ?? initialDate
        let components = Calendar.current.dateComponents([.hour, .minute], from: initialTime)
        _name = State(initialValue: editingTask?.name ?? "")
        _details = State(initialValue: editingTask?.details ?? "")
        _hasDate = State(initialValue: editingTask?.taskDate != nil || suggestedDate != nil)
        _hasTime = State(initialValue: editingTask?.taskTime != nil)
        _selectedDate = State(initialValue: initialDate)
        _hour = State(initialValue: components.hour ?? 9)
        _minute = State(initialValue: components.minute ?? 0)
    }

    private var accent: Color {
        Color(lureliaHex: column.colorHex)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    taskFields
                    scheduleSection
                    saveButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.palette.background)
        .lureliaDismissKeyboardOnTap()
        .onChange(of: hasDate) { _, isEnabled in
            if !isEnabled {
                hasTime = false
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editingTask == nil ? "New Quick Task" : "Edit Quick Task")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text(column.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
                    .bubblyIconMaterial(tint: .white)
            }
            .buttonStyle(.plain)
        }
    }

    private var taskFields: some View {
        VStack(spacing: 14) {
            TextField("Quick task name", text: $name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background {
                    BubblyCardMaterial(tint: accent, cornerRadius: 18)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.76), lineWidth: 1.2)
                }
                .onSubmit { save() }

            TextEditor(text: $details)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 112)
                .background {
                    BubblyCardMaterial(tint: accent, cornerRadius: 18)
                }
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text("Description (optional)")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.76), lineWidth: 1.2)
                }
        }
    }

    private var scheduleSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Date")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Spacer()

                LureliaSlidingIconToggle(
                    isOn: $hasDate,
                    iconName: "ringstarcal",
                    accentColor: accent,
                    accessibilityLabel: "Quick Task Date",
                    usesIconMaterial: true
                )
            }

            if hasDate {
                HStack {
                    Text("Time")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Spacer()

                    LureliaSlidingIconToggle(
                        isOn: $hasTime,
                        iconName: "clockwavy",
                        accentColor: accent,
                        accessibilityLabel: "Quick Task Time",
                        usesIconMaterial: true
                    )
                }

                HStack(alignment: .top, spacing: 10) {
                    LureliaCompactDateDrumPicker(
                        date: $selectedDate,
                        tint: accent,
                        usesCardMaterial: true,
                        usesDarkTypography: true
                    )
                    .frame(maxWidth: .infinity)

                    if hasTime {
                        LureliaCompactTimeDrumPicker(
                            hour: $hour,
                            minute: $minute,
                            tint: accent,
                            usesDarkTypography: true
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background {
            BubblyCardMaterial(tint: accent, cornerRadius: 20)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.opacity(0.58), lineWidth: 1)
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Image(editingTask == nil ? "addwavy" : "checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.black.opacity(0.62))

                    Image(editingTask == nil ? "addwavy" : "checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.black)
                        .bubblyIconMaterial(tint: .black)
                }
                .frame(width: 15, height: 15)

                Text(editingTask == nil ? "Add Quick Task" : "Save Quick Task")
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                BubblyCardMaterial(tint: accent, cornerRadius: 20)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.42)
    }

    private func save() {
        guard canSave else { return }

        let calendar = Calendar.current
        let storedDate = hasDate ? calendar.startOfDay(for: selectedDate) : nil
        let storedTime: Date?
        if hasDate && hasTime {
            storedTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate)
        } else {
            storedTime = nil
        }

        if let editingTask {
            editingTask.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            editingTask.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            editingTask.taskDate = storedDate
            editingTask.taskTime = storedTime
            editingTask.updatedAt = Date()
            editingTask.column = column
            column.board?.updatedAt = Date()
            try? modelContext.save()
            dismiss()
            return
        }

        let task = KanbanQuickTask(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            taskDate: storedDate,
            taskTime: storedTime
        )
        task.column = column
        modelContext.insert(task)

        if !(column.quickTasks ?? []).contains(where: { $0.id == task.id }) {
            if column.quickTasks == nil {
                column.quickTasks = []
            }
            column.quickTasks?.append(task)
        }

        let card = KanbanCard(
            cardType: .quickTask,
            itemID: task.id,
            sortOrder: (column.cards ?? []).count
        )
        card.column = column
        modelContext.insert(card)
        if !(column.cards ?? []).contains(where: { $0.id == card.id }) {
            if column.cards == nil {
                column.cards = []
            }
            column.cards?.append(card)
        }
        column.board?.updatedAt = Date()

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - KanbanBoardView

struct KanbanBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Bindable var board: KanbanBoard

    @Query private var allReminders: [LureliaReminder]
    @Query private var allRoutines: [LureliaRoutine]
    @Query private var allHabits: [LureliaHabit]
    @Query private var allQuickTasks: [KanbanQuickTask]
    @Query private var allBoards: [KanbanBoard]

    @State private var showAddColumn = false
    @State private var editingColumn: KanbanColumn?
    @State private var createRequest: KanbanCreateRequest?
    @State private var taskCreateRequest: KanbanRoutineTaskCreateRequest?
    @State private var habitCreateRequest: KanbanHabitCreateRequest?
    @State private var quickTaskCreateRequest: KanbanQuickTaskCreateRequest?
    @State private var showCompletionBanner = false

    private func triggerBanner() {
        showCompletionBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCompletionBanner = false
        }
    }

    private var accentColor: Color { Color(lureliaHex: board.colorHex) }

    private var allRoutineTasks: [LureliaRoutineTask] {
        allRoutines.flatMap { $0.sortedTasks }
    }

    private var pinnedReminderIDs: Set<String> {
        let columns = allBoards.flatMap { $0.columns ?? [] }
        let cards = columns.flatMap { $0.cards ?? [] }
        let reminderCards = cards.filter { $0.cardType == .reminder }
        return Set(reminderCards.map { $0.itemID })
    }

    private var pinnedHabitIDsForBoard: Set<String> {
        // App-wide scope: a habit pinned on any board (not just this one)
        // should stop appearing in this board's habit inbox so the same
        // habit can't get pinned to multiple boards at once.
        let columns = allBoards.flatMap { $0.columns ?? [] }
        let cards = columns.flatMap { $0.cards ?? [] }
        return Set(cards.filter { $0.cardType == .habit }.map(\.itemID))
    }

    private var inboxReminders: [LureliaReminder] {
        allReminders
            .filter { $0.kind == .standalone && !pinnedReminderIDs.contains($0.id.uuidString) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var inboxHabits: [LureliaHabit] {
        allHabits
            .filter { !$0.isArchived && !pinnedHabitIDsForBoard.contains($0.kanbanItemID) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(board.name)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    HStack(spacing: 14) {
                        Button { showAddColumn = true } label: {
                            Image("addwavy").renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(accentColor)
                                .bubblyIconMaterial(tint: accentColor)
                        }
                        .buttonStyle(.plain)

                        Button { dismiss() } label: {
                            Image("xmarkwavy").renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.white)
                                .bubblyIconMaterial(tint: .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 59)
                .padding(.bottom, 4)

                if board.sortedColumns.isEmpty {
                    emptyState.padding(.top, 40)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 16) {
                            if !inboxReminders.isEmpty {
                                KanbanInboxColumnView(
                                    board: board,
                                    reminders: inboxReminders,
                                    boardAccent: accentColor,
                                    onMoveReminder: { reminder, col in
                                        pinCard(type: .reminder, itemID: reminder.id.uuidString, in: col)
                                    }
                                )
                            }

                            if !allRoutines.isEmpty {
                                KanbanRoutineTaskSourceColumnView(
                                    board: board,
                                    routines: allRoutines,
                                    boardAccent: accentColor,
                                    onAddRoutineTask: { task, column in
                                        pinCard(type: .routineTask, itemID: task.kanbanItemID, in: column)
                                    },
                                    onAddNewTask: { routine, column in
                                        taskCreateRequest = KanbanRoutineTaskCreateRequest(routine: routine, column: column)
                                    }
                                )
                            }

                            if !inboxHabits.isEmpty {
                                KanbanHabitSourceColumnView(
                                    board: board,
                                    habits: inboxHabits,
                                    boardAccent: accentColor,
                                    onAddHabit: { habit, column in
                                        pinCard(type: .habit, itemID: habit.kanbanItemID, in: column)
                                    }
                                )
                            }

                            ForEach(board.sortedColumns) { column in
                                KanbanColumnView(
                                    column: column,
                                    allReminders: allReminders,
                                    allRoutines: allRoutines,
                                    allRoutineTasks: allRoutineTasks,
                                    allHabits: allHabits,
                                    allQuickTasks: allQuickTasks,
                                    onCreateReminder: {
                                        createRequest = KanbanCreateRequest(type: .reminder, column: column)
                                    },
                                    onCreateHabit: {
                                        habitCreateRequest = KanbanHabitCreateRequest(column: column)
                                    },
                                    onCreateQuickTask: {
                                        quickTaskCreateRequest = KanbanQuickTaskCreateRequest(column: column)
                                    },
                                    onAddCard: { type, itemID in
                                        pinCard(type: type, itemID: itemID, in: column)
                                    },
                                    onAddTask: { routine in
                                        taskCreateRequest = KanbanRoutineTaskCreateRequest(routine: routine, column: column)
                                    },
                                    onEditColumn: {
                                        editingColumn = column
                                    },
                                    onComplete: { triggerBanner() }
                                )
                            }

                            Button { showAddColumn = true } label: {
                                HStack(spacing: 10) {
                                    Image("addwavy").renderingMode(.template).resizable().scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .foregroundStyle(accentColor)
                                        .bubblyIconMaterial(tint: accentColor)
                                        .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
                                    Text("Add Column")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(LColors.textSecondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16).padding(.vertical, 18)
                                .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LColors.glassBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 120)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(edges: .top)
        .completionBanner(isShowing: showCompletionBanner, message: "Reminder completed!")
        .sheet(isPresented: $showAddColumn) { AddColumnView(board: board) }
        .sheet(item: $editingColumn) { col in
            AddColumnView(board: board, column: col)
        }
        .sheet(item: $createRequest) { req in
            LureliaReminderCreationFlow(onCreated: { reminder in
                pinCard(type: .reminder, itemID: reminder.id.uuidString, in: req.column)
            })
        }
        .sheet(item: $taskCreateRequest) { request in
            KanbanRoutineTaskCreationSheet(routine: request.routine) { task in
                pinCard(type: .routineTask, itemID: task.kanbanItemID, in: request.column)
            }
        }
        .sheet(item: $habitCreateRequest) { request in
            LureliaHabitFormSheet(
                habit: nil,
                onSaved: { habit in
                    pinCard(type: .habit, itemID: habit.kanbanItemID, in: request.column)
                },
                onClose: {
                    habitCreateRequest = nil
                }
            )
        }
        .sheet(item: $quickTaskCreateRequest) { request in
            AddKanbanQuickTaskSheet(
                column: request.column,
                suggestedDate: request.suggestedDate
            )
        }
        .navigationDestination(for: UUID.self) { reminderID in
            if let reminder = allReminders.first(where: { $0.id == reminderID }) {
                ReminderDetailView(reminder: reminder)
            } else if let habit = allHabits.first(where: { $0.id == reminderID }) {
                HabitBlueprintDetailView(habit: habit)
            }
            }
        .navigationDestination(for: PersistentIdentifier.self) { id in
            if allRoutines.contains(where: { $0.id == id }) {
                RoutineDetailView(routineID: id)
            } else if let task = allRoutineTasks.first(where: { $0.id == id }) {
                RoutineTaskDetailView(
                    task: task,
                    routineTint: task.routine.map { Color(lureliaHex: $0.colorHex) } ?? LColors.gradientPurple
                )
            }
        }
        }
    }

    private func pinCard(type: KanbanCardType, itemID: String, in col: KanbanColumn) {
        let alreadyExists = (col.cards ?? []).contains {
            $0.cardType == type && $0.itemID == itemID
        }
        guard !alreadyExists else { return }

        let card = KanbanCard(cardType: type, itemID: UUID(), sortOrder: (col.cards ?? []).count)
        card.itemID = itemID
        card.cardType = type
        modelContext.insert(card)
        if col.cards == nil {
            col.cards = []
        }
        col.cards?.append(card)
        try? modelContext.save()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(board.icon).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(accentColor)
                .bubblyIconMaterial(tint: accentColor)
            Text("No Columns Yet")
                .font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(LColors.textPrimary)
            Text("Add columns to organize your board.")
                .font(.system(size: 14, design: .rounded)).foregroundStyle(LColors.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { showAddColumn = true } label: {
                HStack {
                    Spacer(minLength: 0)

                    Text("Add Column")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.black)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    BubblyCardMaterial(
                        tint: accentColor,
                        cornerRadius: 20
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 4)
        }
    }
}

// MARK: - KanbanColumnView

struct KanbanColumnView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var column: KanbanColumn

    let allReminders: [LureliaReminder]
    let allRoutines: [LureliaRoutine]
    let allRoutineTasks: [LureliaRoutineTask]
    let allHabits: [LureliaHabit]
    let allQuickTasks: [KanbanQuickTask]
    let onCreateReminder: () -> Void
    let onCreateHabit: () -> Void
    let onCreateQuickTask: () -> Void
    let onAddCard: (KanbanCardType, String) -> Void
    let onAddTask: (LureliaRoutine) -> Void
    let onEditColumn: () -> Void
    var onComplete: (() -> Void)? = nil

    private var accentColor: Color { Color(lureliaHex: column.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(column.name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                Spacer()
                Text("\(column.sortedCards.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kanbanChipMaterial(tint: accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.14), in: Capsule())
                KanbanColumnAddCardMenu(
                    column: column,
                    allReminders: allReminders,
                    allRoutines: allRoutines,
                    allHabits: allHabits,
                    onCreateReminder: onCreateReminder,
                    onCreateHabit: onCreateHabit,
                    onCreateQuickTask: onCreateQuickTask,
                    onAddCard: onAddCard,
                    onAddTask: onAddTask
                ) {
                    Image("addwavy").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(accentColor)
                        .bubblyIconMaterial(tint: accentColor)
                        .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14)

            Divider().overlay(LColors.glassBorder).padding(.horizontal, 10)

            VStack(spacing: 10) {
                ForEach(column.sortedCards) { card in
                    KanbanItemCard(
                        card: card,
                        column: column,
                        allReminders: allReminders,
                        allRoutines: allRoutines,
                        allRoutineTasks: allRoutineTasks,
                        allHabits: allHabits,
                        allQuickTasks: allQuickTasks,
                        columnAccent: accentColor,
                        onDelete: { deleteCard(card) },
                        onComplete: onComplete
                    )
                    .contextMenu {
                        ForEach(availableMoveColumns(for: card)) { targetColumn in
                            Button { moveCard(card, to: targetColumn) } label: {
                                Label("Move to \(targetColumn.name)", systemImage: "arrow.right.circle")
                            }
                        }
                        Divider()
                        Button(role: .destructive) { deleteCard(card) } label: {
                            Label("Delete Card", systemImage: "trash")
                        }
                    }
                }

                if column.sortedCards.isEmpty {
                    VStack(spacing: 8) {
                        Image("addwavy").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 20, height: 20).foregroundStyle(LColors.textSecondary.opacity(0.4))
                        Text("No cards yet")
                            .font(.system(size: 12, design: .rounded)).foregroundStyle(LColors.textSecondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(tint: accentColor, cornerRadius: 22)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu {
            Button { onEditColumn() } label: {
                Label("Edit Column", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                deleteColumn()
            } label: {
                Label("Delete Column", systemImage: "trash")
            }
        }
    }

    private func deleteCard(_ card: KanbanCard) {
        if card.cardType == .quickTask,
           let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }) {
            modelContext.delete(task)
        }

        modelContext.delete(card)
        try? modelContext.save()
    }

    private func deleteColumn() {
        if let cards = column.cards {
            for card in cards {
                modelContext.delete(card)
            }
        }

        modelContext.delete(column)
        try? modelContext.save()
    }

    private func availableMoveColumns(for card: KanbanCard) -> [KanbanColumn] {
        column.board?.sortedColumns.filter { $0.id != column.id } ?? []
    }

    private func moveCard(_ card: KanbanCard, to targetColumn: KanbanColumn) {
        guard targetColumn.id != column.id else { return }

        if card.cardType == .quickTask,
           let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }) {
            column.quickTasks = (column.quickTasks ?? []).filter { $0.id != task.id }
            if targetColumn.quickTasks == nil {
                targetColumn.quickTasks = []
            }
            targetColumn.quickTasks?.append(task)
            task.updatedAt = Date()
        }

        column.cards = (column.cards ?? []).filter { $0.id != card.id }
        card.sortOrder = (targetColumn.cards ?? []).count
        if targetColumn.cards == nil {
            targetColumn.cards = []
        }
        targetColumn.cards?.append(card)
        for (i, c) in (column.cards ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() { c.sortOrder = i }
        for (i, c) in (targetColumn.cards ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() { c.sortOrder = i }
        try? modelContext.save()
    }
}

// MARK: - KanbanItemCard

private let kanbanInnerCardSurface = Color.black.opacity(0.045)

private struct KanbanColumnCardIcon: View {
    let iconID: String
    let accent: Color
    var diameter: CGFloat = 36
    var iconSize: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.72))

            BubblyIconMaterial(tint: accent)
                .mask {
                    Circle()
                        .strokeBorder(lineWidth: 1.5)
                }

            LureliaIconView(iconId: iconID, size: iconSize)
                .foregroundStyle(accent)
                .bubblyIconMaterial(tint: accent)
        }
        .frame(width: diameter, height: diameter)
    }
}

private extension View {
    func kanbanChipMaterial(tint: Color) -> some View {
        foregroundStyle(tint)
            .bubblyIconMaterial(tint: tint)
            .shadow(color: .black.opacity(0.32), radius: 1.5, x: 0, y: 1)
    }

    func kanbanChipBorder(tint: Color) -> some View {
        overlay {
            BubblyIconMaterial(tint: tint)
                .mask {
                    Capsule()
                        .strokeBorder(lineWidth: 1)
                }
                .allowsHitTesting(false)
        }
    }

    func kanbanTaskTitle(isMuted: Bool = false) -> some View {
        foregroundStyle(isMuted ? Color.black.opacity(0.62) : LColors.textPrimary)
            .shadow(
                color: .black.opacity(isMuted ? 0.24 : 0.56),
                radius: isMuted ? 1 : 2,
                x: 0,
                y: 1
            )
    }

    func kanbanTrashMaterial() -> some View {
        foregroundStyle(Color.white)
            .bubblyIconMaterial(tint: .white)
            .shadow(color: .black.opacity(0.58), radius: 3, x: 0, y: 2)
    }
}

struct KanbanItemCard: View {
    let card: KanbanCard
    let column: KanbanColumn
    let allReminders: [LureliaReminder]
    let allRoutines: [LureliaRoutine]
    let allRoutineTasks: [LureliaRoutineTask]
    let allHabits: [LureliaHabit]
    let allQuickTasks: [KanbanQuickTask]
    let columnAccent: Color
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    var body: some View {
        if let reminder = reminder {
            NavigationLink(value: reminder.id) {
                KanbanReminderCard(
                    reminder: reminder,
                    accent: columnAccent,
                    onDelete: onDelete,
                    onComplete: onComplete
                )
            }
            .buttonStyle(.plain)
        } else if let routine = routine {
            NavigationLink(value: routine.id) {
                KanbanRoutineCard(
                    routine: routine,
                    accent: columnAccent,
                    onDelete: onDelete
                )
            }
            .buttonStyle(.plain)
        } else if let routineTask = routineTask {
            NavigationLink(value: routineTask.id) {
                KanbanRoutineTaskCard(
                    task: routineTask,
                    accent: columnAccent,
                    onDelete: onDelete
                )
            }
            .buttonStyle(.plain)
        } else if let habit = habit {
            NavigationLink(value: habit.id) {
                KanbanHabitCard(
                    habit: habit,
                    accent: columnAccent,
                    onDelete: onDelete,
                    onComplete: onComplete
                )
            }
            .buttonStyle(.plain)
        } else if let quickTask = quickTask {
            KanbanQuickTaskCard(
                task: quickTask,
                column: column,
                accent: columnAccent,
                onDelete: onDelete,
                onComplete: onComplete
            )
        } else {
            orphanCard
        }
    }

    private var reminder: LureliaReminder? {
        guard card.cardType == .reminder else { return nil }
        return allReminders.first { $0.id.uuidString == card.itemID }
    }

    private var routine: LureliaRoutine? {
        guard card.cardType == .routine else { return nil }
        return allRoutines.first { $0.persistentID == card.itemID }
    }

    private var routineTask: LureliaRoutineTask? {
        guard card.cardType == .routineTask else { return nil }
        return allRoutineTasks.first { $0.matchesKanbanItemID(card.itemID) }
    }

    private var habit: LureliaHabit? {
        guard card.cardType == .habit else { return nil }
        return allHabits.first { $0.matchesKanbanItemID(card.itemID) }
    }

    private var quickTask: KanbanQuickTask? {
        guard card.cardType == .quickTask else { return nil }
        return allQuickTasks.first { $0.matchesKanbanItemID(card.itemID) }
    }

    private var orphanCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(LColors.textSecondary)
            Text("Item deleted").font(.system(size: 12, design: .rounded)).foregroundStyle(LColors.textSecondary)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image("trash").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 14, height: 14)
                    .kanbanTrashMaterial()
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(kanbanInnerCardSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Kanban Quick Task Card

struct KanbanQuickTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: KanbanQuickTask
    let column: KanbanColumn
    let accent: Color
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    @State private var isEditing = false

    private var scheduleText: String? {
        guard let taskDate = task.taskDate else { return nil }

        if let taskTime = task.taskTime {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: taskDate)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: taskTime)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute

            if let combined = calendar.date(from: components) {
                return combined.formatted(date: .abbreviated, time: .shortened)
            }
        }

        return taskDate.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .kanbanTaskTitle(isMuted: task.isCompleted)
                        .strikethrough(task.isCompleted, color: Color.black.opacity(0.5))
                        .lineLimit(2)

                    if !task.details.isEmpty {
                        Text(task.details)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(task.isCompleted ? Color.black.opacity(0.56) : LColors.textSecondary)
                            .lineLimit(2)
                    }

                    if let scheduleText {
                        Text(scheduleText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .kanbanChipMaterial(tint: accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .kanbanChipBorder(tint: accent)
                    }
                }

                Spacer(minLength: 8)
                actionControls
            }

        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.32), lineWidth: 1)
                }
        }
        .sheet(isPresented: $isEditing) {
            AddKanbanQuickTaskSheet(
                column: column,
                editingTask: task
            )
        }
    }

    private var actionControls: some View {
        VStack(spacing: 6) {
            completionCircle

            HStack(spacing: 6) {
                Button { isEditing = true } label: {
                    quickTaskActionIcon("pencil", tint: accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit quick task")

                Button(role: .destructive, action: onDelete) {
                    quickTaskActionIcon("trash", tint: .white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete quick task")
            }
        }
    }

    private func quickTaskActionIcon(_ asset: String, tint: Color) -> some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 11, height: 11)
            .foregroundStyle(tint)
            .bubblyIconMaterial(tint: tint)
            .shadow(color: .black.opacity(0.52), radius: 2, x: 0, y: 1)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    private var completionCircle: some View {
        Button { complete() } label: {
            ZStack {
                Circle()
                    .fill(task.isCompleted ? accent.opacity(0.18) : Color.clear)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Circle()
                            .strokeBorder(accent.opacity(0.82), lineWidth: 2)
                    }

                if task.isCompleted {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(accent)
                        .bubblyIconMaterial(tint: accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(task.isCompleted)
        .accessibilityLabel(task.isCompleted ? "Quick task completed" : "Complete quick task")
    }

    private func complete() {
        guard !task.isCompleted else { return }
        task.isCompleted = true
        task.completedAt = Date()
        task.updatedAt = Date()
        try? modelContext.save()
        onComplete?()
    }
}

// MARK: - Kanban Routine Card

struct KanbanRoutineCard: View {
    @Bindable var routine: LureliaRoutine
    let accent: Color
    let onDelete: () -> Void

    private var progressText: String {
        let total = routine.sortedTasks.count
        guard total > 0 else { return "No tasks" }
        return "\(routine.completedTaskCount)/\(total) done"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KanbanColumnCardIcon(iconID: routine.icon, accent: accent)

            VStack(alignment: .leading, spacing: 7) {
                Text(routine.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .kanbanTaskTitle()
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badge(routine.scheduleEnabled ? routine.formattedTimeRange : "Ready")
                    badge(progressText)
                }
            }

            Spacer(minLength: 8)
            deleteButton
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(kanbanInnerCardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                }
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .kanbanChipMaterial(tint: accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .kanbanChipBorder(tint: accent)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image("trash")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .kanbanTrashMaterial()
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kanban Routine Task Card

struct KanbanRoutineTaskCard: View {
    @Bindable var task: LureliaRoutineTask
    let accent: Color
    let onDelete: () -> Void

    private var statusText: String {
        if task.isCompleted { return "Completed" }
        if task.isSkipped { return "Skipped" }
        return task.hasDueTime ? task.formattedDueTime : "Pending"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KanbanColumnCardIcon(iconID: task.icon, accent: accent)

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .kanbanTaskTitle(isMuted: !task.isPending)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let routineName = task.routine?.name, !routineName.isEmpty {
                        badge(routineName)
                    }
                    badge(statusText)
                }
            }

            Spacer(minLength: 8)
            deleteButton
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(kanbanInnerCardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                }
        }
        .opacity(task.isPending ? 1 : 0.90)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .kanbanChipMaterial(tint: accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .kanbanChipBorder(tint: accent)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image("trash")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .kanbanTrashMaterial()
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kanban Habit Card

struct KanbanHabitCard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var habit: LureliaHabit
    let accent: Color
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todaysLog: LureliaHabitLog? {
        habit.log(on: Date())
    }

    private var todaysSkip: LureliaHabitSkip? {
        habit.skip(on: Date())
    }

    private var statusText: String {
        if habit.isCompletedToday { return "Completed" }
        if todaysSkip != nil { return "Skipped" }
        if let next = nextFireToday {
            return next <= Date() ? "Due Now" : "Soon"
        }
        return "\(habit.todaysCount)/\(habit.target)"
    }

    private var nextFireToday: Date? {
        habit.fireDates(on: Date()).first { fireDate in
            fireDate >= Date() || !habit.isCompletedToday
        }
    }

    private var scheduleText: String {
        let dates = habit.fireDates(on: Date())
        guard let first = dates.first else { return "Flexible" }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        if dates.count == 1 {
            return formatter.string(from: first)
        }

        return "\(formatter.string(from: first)) +\(dates.count - 1)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KanbanColumnCardIcon(
                iconID: habit.iconName ?? "flame",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(habit.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .kanbanTaskTitle(
                        isMuted: habit.isArchived || habit.isCompletedToday || todaysSkip != nil
                    )
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badge(scheduleText)
                    badge(statusText)
                    badge("\(habit.todaysCount)/\(habit.target)")
                }
            }

            Spacer(minLength: 8)
            deleteButton
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(kanbanInnerCardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                }
        }
        .opacity((habit.isArchived || habit.isCompletedToday || todaysSkip != nil) ? 0.90 : 1)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .kanbanChipMaterial(tint: accent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .kanbanChipBorder(tint: accent)
    }

    private var completionButton: some View {
        Button {
            quickLog()
        } label: {
            ZStack {
                Circle()
                    .fill(habit.isCompletedToday ? AnyShapeStyle(accent) : AnyShapeStyle(Color.clear))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(accent.opacity(0.85), lineWidth: 2))

                if habit.isCompletedToday {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(habit.isCompletedToday || todaysSkip != nil)
        .opacity((habit.isCompletedToday || todaysSkip != nil) ? 0.55 : 1)
    }

    private var skipButton: some View {
        Button {
            toggleSkip()
        } label: {
            Image("skipwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(habit.isCompletedToday)
        .opacity(habit.isCompletedToday ? 0.55 : 1)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image("trash")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .kanbanTrashMaterial()
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func quickLog() {
        let cap = habit.target

        if let existingSkip = todaysSkip {
            modelContext.delete(existingSkip)
            habit.skips = (habit.skips ?? []).filter {
                $0.persistentModelID != existingSkip.persistentModelID
            }
        }

        if let existing = todaysLog {
            if existing.count < cap {
                existing.count = min(cap, existing.count + 1)
                existing.updatedAt = Date()
                habit.updatedAt = Date()
            }
        } else {
            let log = LureliaHabitLog(habit: habit, dayStart: todayStart, count: 1)
            modelContext.insert(log)
            habit.logs = (habit.logs ?? []) + [log]
            habit.updatedAt = Date()
        }

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()

        if habit.isCompletedToday {
            onComplete?()
        }
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

        guard todaysLog?.count ?? 0 == 0 else { return }

        let skip = LureliaHabitSkip(habit: habit, dayStart: todayStart)
        modelContext.insert(skip)
        habit.skips = (habit.skips ?? []) + [skip]
        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }
}

// MARK: - Kanban Routine Task Source Column

struct KanbanRoutineTaskSourceColumnView: View {
    let board: KanbanBoard
    let routines: [LureliaRoutine]
    let boardAccent: Color
    let onAddRoutineTask: (LureliaRoutineTask, KanbanColumn) -> Void
    let onAddNewTask: (LureliaRoutine, KanbanColumn) -> Void

    /// Observed so this "already pinned" filter reflects every board's
    /// cards, not just this board's. Prevents the same routine task from
    /// being pinnable on multiple boards.
    @Query private var allBoards: [KanbanBoard]

    private var pinnedRoutineTaskIDs: Set<String> {
        // Broken into explicit steps so the type-checker doesn't blow up
        // on the nested flatMap chain (Swift chokes on deep inference in
        // one expression).
        let allTasks: [LureliaRoutineTask] = routines.flatMap { $0.sortedTasks }
        let allColumns: [KanbanColumn] = allBoards.flatMap { $0.columns ?? [] }
        let allCards: [KanbanCard] = allColumns.flatMap { $0.cards ?? [] }
        let routineTaskCards: [KanbanCard] = allCards.filter { $0.cardType == .routineTask }

        var result: Set<String> = []
        for card in routineTaskCards {
            let match = allTasks.first { $0.matchesKanbanItemID(card.itemID) }
            result.insert(match?.kanbanItemID ?? card.itemID)
        }
        return result
    }

    private var availableRoutines: [LureliaRoutine] {
        routines
            .filter { !availableTasks(for: $0).isEmpty }
            .sorted { $0.name < $1.name }
    }

    private var availableTaskCount: Int {
        availableRoutines.reduce(0) { $0 + availableTasks(for: $1).count }
    }

    private func availableTasks(for routine: LureliaRoutine) -> [LureliaRoutineTask] {
        routine.sortedTasks.filter { !pinnedRoutineTaskIDs.contains($0.kanbanItemID) }
    }

    var body: some View {
        if availableTaskCount > 0 {
            VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image("repeatfill")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(boardAccent)

                    Text("Routine Tasks")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                }

                Spacer()

                Text("\(availableTaskCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kanbanChipMaterial(tint: boardAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(boardAccent.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()
                .overlay(LColors.glassBorder)
                .padding(.horizontal, 10)

            VStack(spacing: 12) {
                ForEach(availableRoutines) { routine in
                    routineSection(routine)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                BubblyCardMaterial(tint: boardAccent, cornerRadius: 22)
            }
        }
    }

    private func routineSection(_ routine: LureliaRoutine) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                KanbanColumnCardIcon(
                    iconID: routine.icon,
                    accent: boardAccent,
                    diameter: 34,
                    iconSize: 16
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .lineLimit(1)

                    Text(routine.scheduleEnabled ? routine.formattedTimeRange : "\(availableTasks(for: routine).count) task\(availableTasks(for: routine).count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                addNewTaskMenu(for: routine)
            }

            VStack(spacing: 7) {
                ForEach(availableTasks(for: routine), id: \.kanbanItemID) { task in
                    routineTaskSourceRow(task)
                }
            }
        }
        .padding(12)
        .background(LColors.glassSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(boardAccent.opacity(0.18), lineWidth: 1)
        }
    }

    private func routineTaskSourceRow(_ task: LureliaRoutineTask) -> some View {
        HStack(alignment: .center, spacing: 9) {
            KanbanColumnCardIcon(
                iconID: task.icon,
                accent: boardAccent,
                diameter: 28,
                iconSize: 13
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .kanbanTaskTitle()
                    .lineLimit(2)

                Text(task.hasDueTime ? task.formattedDueTime : "No due time")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            addTaskMenu(task)
        }
        .padding(9)
        .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(LColors.glassBorder.opacity(0.7), lineWidth: 1)
        }
        .contextMenu {
            taskColumnMenu(task)
        }
    }

    private func addTaskMenu(_ task: LureliaRoutineTask) -> some View {
        Menu {
            taskColumnMenu(task)
        } label: {
            Image("addwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(boardAccent)
                .bubblyIconMaterial(tint: boardAccent)
                .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
                .frame(width: 30, height: 30)
                .background(boardAccent.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(boardAccent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func addNewTaskMenu(for routine: LureliaRoutine) -> some View {
        Menu {
            if board.sortedColumns.isEmpty {
                Text("Add a column first")
            } else {
                ForEach(board.sortedColumns) { column in
                    Button {
                        onAddNewTask(routine, column)
                    } label: {
                        Label("Add to \(column.name)", systemImage: "plus")
                    }
                }
            }
        } label: {
            Image("addwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(boardAccent)
                .bubblyIconMaterial(tint: boardAccent)
                .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskColumnMenu(_ task: LureliaRoutineTask) -> some View {
        if board.sortedColumns.isEmpty {
            Text("Add a column first")
        } else {
            ForEach(board.sortedColumns) { column in
                Button {
                    onAddRoutineTask(task, column)
                } label: {
                    Label("Add to \(column.name)", systemImage: "arrow.right.circle")
                }
            }
        }
    }
}

// MARK: - Kanban Habit Source Column

struct KanbanHabitSourceColumnView: View {
    let board: KanbanBoard
    let habits: [LureliaHabit]
    let boardAccent: Color
    let onAddHabit: (LureliaHabit, KanbanColumn) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image("flame")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(boardAccent)

                    Text("Habits")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                }

                Spacer()

                Text("\(habits.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kanbanChipMaterial(tint: boardAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(boardAccent.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()
                .overlay(LColors.glassBorder)
                .padding(.horizontal, 10)

            VStack(spacing: 10) {
                ForEach(habits) { habit in
                    habitSourceRow(habit)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(tint: boardAccent, cornerRadius: 22)
        }
    }

    private func habitSourceRow(_ habit: LureliaHabit) -> some View {
        HStack(alignment: .center, spacing: 9) {
            KanbanColumnCardIcon(
                iconID: habit.iconName ?? "flame",
                accent: boardAccent,
                diameter: 28,
                iconSize: 13
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .kanbanTaskTitle()
                    .lineLimit(2)

                Text(habitScheduleSummary(habit))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary.opacity(0.75))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            addHabitMenu(habit)
        }
        .padding(9)
        .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(LColors.glassBorder.opacity(0.7), lineWidth: 1)
        }
        .contextMenu {
            habitColumnMenu(habit)
        }
    }

    private func addHabitMenu(_ habit: LureliaHabit) -> some View {
        Menu {
            habitColumnMenu(habit)
        } label: {
            Image("addwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(boardAccent)
                .bubblyIconMaterial(tint: boardAccent)
                .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
                .frame(width: 30, height: 30)
                .background(boardAccent.opacity(0.12), in: Circle())
                .overlay(Circle().strokeBorder(boardAccent.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func habitColumnMenu(_ habit: LureliaHabit) -> some View {
        if board.sortedColumns.isEmpty {
            Text("Add a column first")
        } else {
            ForEach(board.sortedColumns) { column in
                Button {
                    onAddHabit(habit, column)
                } label: {
                    Label("Add to \(column.name)", systemImage: "arrow.right.circle")
                }
            }
        }
    }

    private func habitScheduleSummary(_ habit: LureliaHabit) -> String {
        let targetText = "\(habit.target)x/day"
        let weekdayText = habit.activeWeekdays.count >= 7 ? "Every day" : "\(habit.activeWeekdays.count) days/week"
        return "\(targetText) • \(weekdayText)"
    }
}

// MARK: - KanbanInboxColumnView

struct KanbanInboxColumnView: View {
    let board: KanbanBoard
    let reminders: [LureliaReminder]
    let boardAccent: Color
    let onMoveReminder: (LureliaReminder, KanbanColumn) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image("inbox").renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(boardAccent)
                    Text("Inbox").font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(LColors.textPrimary)
                }
                Spacer()
                Text("\(reminders.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kanbanChipMaterial(tint: boardAccent)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(boardAccent.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 14).padding(.top, 14)

            Divider().overlay(LColors.glassBorder).padding(.horizontal, 10)

            VStack(spacing: 10) {
                ForEach(reminders) { reminder in
                    KanbanInboxReminderCard(reminder: reminder, accent: boardAccent)
                        .contextMenu {
                            if board.sortedColumns.isEmpty {
                                Label {
                                    Text("Add a column first")
                                } icon: {
                                    Image("inbox")
                                        .renderingMode(.template)
                                }
                            } else {
                                ForEach(board.sortedColumns) { col in
                                    Button { onMoveReminder(reminder, col) } label: {
                                        Label("Move to \(col.name)", systemImage: "arrow.right.circle")
                                    }
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(tint: boardAccent, cornerRadius: 22)
        }
    }
}

// MARK: - KanbanInboxReminderCard

struct KanbanInboxReminderCard: View {
    let reminder: LureliaReminder
    let accent: Color

    private var reminderIcon: String {
        reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bellfill" : reminder.icon
    }

    private func resolvedTimesOfDay() -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }
        if !stored.isEmpty { return stored }
        let cal = Calendar.current
        let anchor = reminder.nextFireAt ?? reminder.scheduledDate
        let ph = reminder.primaryHour != -1 ? reminder.primaryHour : cal.component(.hour, from: anchor)
        let pm = reminder.primaryMinute != -1 ? reminder.primaryMinute : cal.component(.minute, from: anchor)
        var times = [String(format: "%02d:%02d", ph, pm)]
        for ft in reminder.additionalFireTimes { times.append(String(format: "%02d:%02d", ft.hour, ft.minute)) }
        return times
    }

    private var allFireDates: [Date] {
        let cal = Calendar.current
        let anchor = reminder.nextFireAt ?? reminder.scheduledDate
        let dayComponents = cal.dateComponents([.year, .month, .day], from: anchor)
        return resolvedTimesOfDay().compactMap { timeStr -> Date? in
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var c = dayComponents; c.hour = h; c.minute = m; c.second = 0
            return cal.date(from: c)
        }.sorted()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            KanbanColumnCardIcon(iconID: reminderIcon, accent: accent)

            VStack(alignment: .leading, spacing: 7) {
                Text(reminder.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .kanbanTaskTitle(isMuted: !reminder.isEnabled)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(Array(allFireDates.prefix(2).enumerated()), id: \.offset) { _, d in
                        Text(d.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .kanbanChipMaterial(tint: accent)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .kanbanChipBorder(tint: accent)
                    }
                    if allFireDates.count > 2 {
                        Text("+\(allFireDates.count - 2)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .kanbanChipMaterial(tint: accent)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .kanbanChipBorder(tint: accent)
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(kanbanInnerCardSurface)
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1) }
        }
        .opacity(reminder.isEnabled ? 1 : 0.65)
    }
}

// MARK: - KanbanReminderCard

struct KanbanReminderCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: LureliaReminder
    let accent: Color
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    private var reminderIcon: String {
        reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bellfill" : reminder.icon
    }

    // All configured fire times displayed on the card — read from timesOfDay (source of truth)
    private var allFireDates: [Date] {
        let cal = Calendar.current
        let anchor = reminder.nextFireAt ?? reminder.scheduledDate
        let dayComponents = cal.dateComponents([.year, .month, .day], from: anchor)
        let times = resolvedTimesOfDay()

        return times.compactMap { timeStr -> Date? in
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            var c = dayComponents
            c.hour = h
            c.minute = m
            c.second = 0
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
        // Recurring reminders are never "done" — they always show status badges
        // This matches the main RemindersView behavior exactly.
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
        // Recurring reminders missed on a prior day should not stay stuck on Due Now
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                KanbanColumnCardIcon(iconID: reminderIcon, accent: accent)

                VStack(alignment: .leading, spacing: 7) {
                    Text(reminder.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .kanbanTaskTitle(isMuted: !reminder.isEnabled)
                        .lineLimit(2)
                    badgeRow(overdue: overdue, dueNow: dueNow, upcoming: upcoming)
                }

                Spacer(minLength: 8)
                completionCircle
            }

            HStack(alignment: .center, spacing: 8) {
                if let notes = reminder.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(notes)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(LColors.textSecondary.opacity(0.75))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
                deleteButton
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(kanbanInnerCardSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                }
        }
        .opacity(reminder.isEnabled ? 1 : 0.65)
    }

    private var completionCircle: some View {
        Button { completeReminderOccurrence() } label: {
            ZStack {
                Circle()
                    .fill(reminder.isCompleted && reminder.repeatUnit == .none ? accent.opacity(0.18) : Color.clear)
                    .frame(width: 30, height: 30)
                    .overlay { Circle().strokeBorder(accent.opacity(0.75), lineWidth: 2) }
                if reminder.isCompleted && reminder.repeatUnit == .none {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image("trash")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .kanbanTrashMaterial()
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func badgeRow(overdue: Bool, dueNow: Bool, upcoming: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(allFireDates.prefix(2).enumerated()), id: \.offset) { _, d in
                Text(d.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kanbanChipMaterial(tint: accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
                    .kanbanChipBorder(tint: accent)
            }

            if allFireDates.count > 2 {
                Text("+\(allFireDates.count - 2)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kanbanChipMaterial(tint: accent)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
                    .kanbanChipBorder(tint: accent)
            }

            if overdue || dueNow || upcoming {
                let label = overdue ? "OVERDUE" : dueNow ? "DUE NOW" : "UPCOMING"
                let color = overdue ? Color(lureliaHex: "#ff9be6") : dueNow ? Color(lureliaHex: "#b476ff") : Color(lureliaHex: "#7eedff")
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .kanbanChipMaterial(tint: color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12), in: Capsule())
                    .kanbanChipBorder(tint: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func completeReminderOccurrence() {
        Task {
            await ReminderActionManager.completeReminderOccurrence(
                reminder,
                in: modelContext
            )

            await MainActor.run {
                onComplete?()
            }
        }
    }

    private func skipReminderOccurrence() {
        Task {
            await ReminderActionManager.skipReminderOccurrence(
                reminder,
                in: modelContext
            )
        }
    }
}

// MARK: - AddColumnView

struct AddColumnView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Bindable var board: KanbanBoard
    var column: KanbanColumn?

    @State private var name: String
    @State private var selectedColor: Color

    init(board: KanbanBoard, column: KanbanColumn? = nil) {
        self.board = board
        self.column = column
        _name = State(initialValue: column?.name ?? "")
        _selectedColor = State(initialValue: Color(lureliaHex: column?.colorHex ?? "#03dbfc"))
    }

    private var isEditing: Bool { column != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.palette.textSecondary.opacity(0.45))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEditing ? "Edit Column" : "New Column")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text(isEditing ? "Update this column’s name and color." : "Add a column to \(board.name).")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.white)
                            .bubblyIconMaterial(tint: .white)
                    }
                }
                .padding(.horizontal, 24)

                LureliaFormSection(title: "Column Name") {
                    TextField("e.g. To Do, In Progress, Done", text: $name)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                        .padding(14)
                        .background(theme.palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(theme.palette.primaryAction, lineWidth: 1.2)
                        )
                        .onSubmit { save() }
                }

                LureliaFormSection(title: "Color") {
                    ColorPicker(selection: $selectedColor, supportsOpacity: false) {
                        Text("Column Color")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                    .padding(14)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.palette.secondaryAccent, lineWidth: 1.2)
                    )
                }

                Button { save() } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Image(isEditing ? "checkwavy" : "addwavy")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.black.opacity(0.58))

                            Image(isEditing ? "checkwavy" : "addwavy")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.black)
                                .bubblyIconMaterial(tint: .black)
                        }
                        .frame(width: 14, height: 14)

                        Text(isEditing ? "Save Changes" : "Add Column")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background {
                        BubblyCardMaterial(
                            tint: theme.palette.indicators,
                            cornerRadius: 22
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: theme.palette.indicators.opacity(0.14), radius: 18, y: 10)
                }
                .buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.45).padding(.horizontal, 24)

                Spacer()
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(theme.palette.background)
        .lureliaDismissKeyboardOnTap()
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = selectedColor.toHex() ?? column?.colorHex ?? "#03dbfc"

        if let column {
            column.name = trimmedName
            column.colorHex = hex
        } else {
            let col = KanbanColumn(name: trimmedName, colorHex: hex, sortOrder: (board.columns ?? []).count)
            modelContext.insert(col)
            if board.columns == nil {
                board.columns = []
            }
            board.columns?.append(col)
        }

        try? modelContext.save()
        dismiss()
    }
}
