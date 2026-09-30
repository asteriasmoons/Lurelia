//
//  RoutineTaskEditorView.swift
//  Lurelia
//
//  Edit an existing routine task's full blueprint. Shares its entire field UI
//  with the create-routine add-task sheet via RoutineTaskFieldsForm, and
//  commits the drafts into the task's @Model child entities on save.
//

import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct RoutineTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Bindable var task: LureliaRoutineTask
    var routineTint: Color = LColors.gradientPurple

    @State private var showTemplatePreview = false

    // Core
    @State private var title: String
    @State private var notes: String
    @State private var taskContext: String
    @State private var selectedIcon: String

    // Blueprint
    @State private var purpose: String
    @State private var motivation: String
    @State private var trigger: String
    @State private var triggerType: LureliaCueType?
    @State private var triggerReason: String
    @State private var environment: String
    @State private var reward: String
    @State private var rewardEnabled: Bool
    @State private var consequence: String
    @State private var consequenceEnabled: Bool
    @State private var recoveryPlan: String

    // Schedule
    @State private var hasDueTime: Bool
    @State private var dueHour: Int
    @State private var dueMinute: Int
    @State private var estimatedDuration: Int
    @State private var repeatsOnDays: Bool
    @State private var scheduledDays: Set<Int>

    // Notifications & Alarm
    @State private var notificationsEnabled: Bool
    @State private var leadMinutes: Set<Int>
    @State private var alarmEnabled: Bool
    @State private var alarmSoundName: String

    // Structured content (value-type drafts reconciled against child models on save)
    @State private var steps: [StepDraft]
    @State private var supplies: [SupplyDraft]
    @State private var obstacles: [ObstacleDraft]

    init(task: LureliaRoutineTask, routineTint: Color = LColors.gradientPurple) {
        self.task = task
        self.routineTint = routineTint

        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _taskContext = State(initialValue: task.context)
        _selectedIcon = State(initialValue: task.icon)

        _purpose = State(initialValue: task.purpose)
        _motivation = State(initialValue: task.motivation)
        _trigger = State(initialValue: task.trigger)
        _triggerType = State(initialValue: task.triggerType)
        _triggerReason = State(initialValue: task.triggerReason)
        _environment = State(initialValue: task.environment)
        _reward = State(initialValue: task.reward)
        _rewardEnabled = State(initialValue: task.rewardEnabled ?? !task.reward.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        _consequence = State(initialValue: task.consequence)
        _consequenceEnabled = State(initialValue: task.consequenceEnabled ?? !task.consequence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        _recoveryPlan = State(initialValue: task.recoveryPlan)

        _hasDueTime = State(initialValue: task.hasDueTime)
        _dueHour = State(initialValue: task.dueHour)
        _dueMinute = State(initialValue: task.dueMinute)
        _estimatedDuration = State(initialValue: max(0, task.estimatedDurationMinutes))
        _repeatsOnDays = State(initialValue: task.repeatsOnDays)
        _scheduledDays = State(initialValue: Set(task.scheduledDays))

        _notificationsEnabled = State(initialValue: task.notificationsEnabled)
        _leadMinutes = State(initialValue: Set(task.notificationLeadMinutes))
        _alarmEnabled = State(initialValue: task.alarmEnabled)
        _alarmSoundName = State(initialValue: task.alarmSoundName ?? LureliaReminderAlarmSound.defaultSound.fileName)

        _steps = State(initialValue: task.sortedSteps.map {
            StepDraft(id: $0.id, title: $0.title, isCompleted: $0.isCompleted)
        })
        _supplies = State(initialValue: task.sortedSupplies.map {
            SupplyDraft(id: $0.id, name: $0.name)
        })
        _obstacles = State(initialValue: task.sortedObstacles.map {
            ObstacleDraft(id: $0.id, obstacle: $0.obstacle, solution: $0.solution)
        })
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var textColor: Color {
        theme.palette.textPrimary
    }

    private var routineFillTextColor: Color {
        routineTint.wcagContrastingSolidTextColor
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()
                    .routineDismissKeyboardOnTap()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        header

                        RoutineTaskFieldsForm(
                            accent: AnyShapeStyle(routineTint),
                            accentColor: routineTint,
                            title: $title,
                            notes: $notes,
                            taskContext: $taskContext,
                            selectedIcon: $selectedIcon,
                            purpose: $purpose,
                            motivation: $motivation,
                            trigger: $trigger,
                            triggerType: $triggerType,
                            triggerReason: $triggerReason,
                            environment: $environment,
                            reward: $reward,
                            rewardEnabled: $rewardEnabled,
                            consequence: $consequence,
                            consequenceEnabled: $consequenceEnabled,
                            recoveryPlan: $recoveryPlan,
                            hasDueTime: $hasDueTime,
                            dueHour: $dueHour,
                            dueMinute: $dueMinute,
                            estimatedDuration: $estimatedDuration,
                            repeatsOnDays: $repeatsOnDays,
                            scheduledDays: $scheduledDays,
                            notificationsEnabled: $notificationsEnabled,
                            leadMinutes: $leadMinutes,
                            alarmEnabled: $alarmEnabled,
                            alarmSoundName: $alarmSoundName,
                            steps: $steps,
                            supplies: $supplies,
                            obstacles: $obstacles
                        )

                        saveButton
                        saveAsTemplateButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 60)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showTemplatePreview) {
                // "Save as Template" — opens the template editor directly
                // with a fresh copy of this task's fields. The task itself
                // is never touched by this flow; the user can freely change
                // things and only the template is written on save.
                RoutineTaskTemplateEditorView(
                    template: RoutineTaskTemplate.fromTask(task),
                    isNew: true
                )
            }
            .tint(routineTint)
        }
    }

    private var saveAsTemplateButton: some View {
        Button { showTemplatePreview = true } label: {
            HStack(spacing: 8) {
                Image("cardlines")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(routineTint)

                Text("Save as Template")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(theme.palette.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(routineTint, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .padding(.top, 2)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Edit Task")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(textColor)

            Spacer()

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(routineFillTextColor)
                    .wcagContrastLift(on: routineTint)
                    .frame(width: 40, height: 40)
                    .background(routineTint, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button { save() } label: {
            Text("Save Task")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(canSave ? routineFillTextColor : theme.palette.textSecondary.opacity(0.45))
                .wcagContrastLift(on: routineTint, isActive: canSave)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background {
                    if canSave {
                        BubblyCardMaterial(tint: routineTint, cornerRadius: 28)
                    } else {
                        Capsule()
                            .fill(theme.palette.raisedSurface)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.top, 6)
    }

    private func save() {
        task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.context = taskContext.trimmingCharacters(in: .whitespacesAndNewlines)
        task.icon = selectedIcon

        task.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        task.motivation = motivation.trimmingCharacters(in: .whitespacesAndNewlines)
        task.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        task.triggerType = triggerType
        task.triggerReason = triggerReason.trimmingCharacters(in: .whitespacesAndNewlines)
        task.environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        task.reward = reward.trimmingCharacters(in: .whitespacesAndNewlines)
        task.rewardEnabled = rewardEnabled
        task.consequence = consequence.trimmingCharacters(in: .whitespacesAndNewlines)
        task.consequenceEnabled = consequenceEnabled
        task.recoveryPlan = recoveryPlan.trimmingCharacters(in: .whitespacesAndNewlines)

        task.hasDueTime = hasDueTime
        task.dueHour = dueHour
        task.dueMinute = dueMinute
        task.estimatedDurationMinutes = max(0, estimatedDuration)
        task.repeatsOnDays = repeatsOnDays
        task.scheduledDays = scheduledDays.sorted()

        task.notificationsEnabled = notificationsEnabled && hasDueTime
        task.notificationLeadMinutes = leadMinutes.sorted()
        task.alarmEnabled = alarmEnabled && hasDueTime
        task.alarmSoundName = (alarmEnabled && hasDueTime) ? alarmSoundName : nil

        reconcileSteps()
        reconcileSupplies()
        reconcileObstacles()

        task.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            print("🚨 [RoutineTaskEditor] SAVE FAILED: \(error)")
        }

        // Reschedule this task's notifications and alarm from its new config.
        RoutineTaskManager.shared.sync(task: task)

        LureliaWidgetReloads.reloadAll()
        dismiss()
    }

    // MARK: - Child Model Reconciliation

    private func reconcileSteps() {
        let drafts = steps.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let keptIDs = Set(drafts.map { $0.id })

        for existing in (task.stepItems ?? []) where !keptIDs.contains(existing.id) {
            modelContext.delete(existing)
        }

        for (index, draft) in drafts.enumerated() {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = (task.stepItems ?? []).first(where: { $0.id == draft.id }) {
                existing.title = title
                existing.isCompleted = draft.isCompleted
                existing.sortOrder = index
                existing.updatedAt = Date()
            } else {
                let step = LureliaRoutineTaskStep(title: title, isCompleted: draft.isCompleted, sortOrder: index)
                step.id = draft.id
                modelContext.insert(step)
                step.task = task
                if task.stepItems == nil { task.stepItems = [] }
                task.stepItems?.append(step)
            }
        }
    }

    private func reconcileSupplies() {
        let drafts = supplies.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let keptIDs = Set(drafts.map { $0.id })

        for existing in (task.supplyItems ?? []) where !keptIDs.contains(existing.id) {
            modelContext.delete(existing)
        }

        for (index, draft) in drafts.enumerated() {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = (task.supplyItems ?? []).first(where: { $0.id == draft.id }) {
                existing.name = name
                existing.sortOrder = index
                existing.updatedAt = Date()
            } else {
                let supply = LureliaRoutineTaskSupply(name: name, sortOrder: index)
                supply.id = draft.id
                modelContext.insert(supply)
                supply.task = task
                if task.supplyItems == nil { task.supplyItems = [] }
                task.supplyItems?.append(supply)
            }
        }
    }

    private func reconcileObstacles() {
        let drafts = obstacles.filter { !$0.obstacle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let keptIDs = Set(drafts.map { $0.id })

        for existing in (task.obstacleItems ?? []) where !keptIDs.contains(existing.id) {
            modelContext.delete(existing)
        }

        for (index, draft) in drafts.enumerated() {
            let obstacle = draft.obstacle.trimmingCharacters(in: .whitespacesAndNewlines)
            let solution = draft.solution.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = (task.obstacleItems ?? []).first(where: { $0.id == draft.id }) {
                existing.obstacle = obstacle
                existing.solution = solution
                existing.sortOrder = index
                existing.updatedAt = Date()
            } else {
                let item = LureliaRoutineTaskObstacle(obstacle: obstacle, solution: solution, sortOrder: index)
                item.id = draft.id
                modelContext.insert(item)
                item.task = task
                if task.obstacleItems == nil { task.obstacleItems = [] }
                task.obstacleItems?.append(item)
            }
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
}

// MARK: - Adaptive Item Presenter

/// Presents the routine-task editor as a sheet on iPhone and a full-screen
/// cover on iPad, matching the project's established adaptive presentation.
struct RoutineTaskEditorPresenter: ViewModifier {
    let isPad: Bool
    @Binding var task: LureliaRoutineTask?
    var routineTint: Color = LColors.gradientPurple

    func body(content: Content) -> some View {
        if isPad {
            content.fullScreenCover(item: $task) { task in
                RoutineTaskEditorView(task: task, routineTint: routineTint)
            }
        } else {
            content.sheet(item: $task) { task in
                RoutineTaskEditorView(task: task, routineTint: routineTint)
            }
        }
    }
}

extension View {
    func routineTaskEditor(
        isPad: Bool,
        task: Binding<LureliaRoutineTask?>,
        routineTint: Color
    ) -> some View {
        modifier(RoutineTaskEditorPresenter(isPad: isPad, task: task, routineTint: routineTint))
    }
}
