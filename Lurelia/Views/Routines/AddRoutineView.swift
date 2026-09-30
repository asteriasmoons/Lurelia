//
//  AddRoutineView.swift
//  Lurelia
//

import SwiftUI
import SwiftData

private let lureliaWeekdays: [(label: String, value: Int)] = [
    ("Su", 1), ("Mo", 2), ("Tu", 3), ("We", 4),
    ("Th", 5), ("Fr", 6), ("Sa", 7)
]

// MARK: - Phase Draft

struct LureliaRoutinePhaseDraft: Identifiable {
    let id = UUID()
    var name: String
    var icon: String = "sparkle"
    var tasks: [LureliaRoutineTaskDraft] = []
    var scheduleEnabled: Bool = false
    var scheduledDays: Set<Int> = []
    var startHour: Int = 8
    var startMinute: Int = 0
    var endHour: Int = 8
    var endMinute: Int = 30
    var durationMode: Bool = false
    var durationMinutesOverride: Int = 30
}

private struct PhaseTaskSheetTarget: Identifiable {
    enum Mode {
        case add
        case edit(taskIndex: Int)
    }

    let id = UUID()
    let phaseIndex: Int
    let mode: Mode
}

struct RoutineEditorLaunchRequest: Identifiable {
    let id = UUID()
    let routine: LureliaRoutine?
    let color: Color
}

private struct RoutineDarkIconMaterialModifier: ViewModifier {
    let tint: Color
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .foregroundStyle(tint)
                .bubblyIconMaterial(tint: tint)
                .overlay {
                    content
                        .foregroundStyle(Color.black.opacity(0.78))
                }
        } else {
            content
        }
    }
}

private extension View {
    func routineDarkIconMaterial(
        tint: Color,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            RoutineDarkIconMaterialModifier(
                tint: tint,
                isEnabled: isEnabled
            )
        )
    }
}

struct AddRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    @Query(sort: \LureliaRoutine.sortOrder)
    private var routines: [LureliaRoutine]
    
    @Query private var reminders: [LureliaReminder]
    
    let editingRoutine: LureliaRoutine?
    let onCreated: ((LureliaRoutine) -> Void)?
    
    @State private var name = ""
    @State private var timeOfDay: LureliaRoutineTimeOfDay = .morning
    @State private var selectedColor: Color
    @State private var selectedIcon = "sparkle"
    @State private var showIconPicker = false
    
    // Enhanced fields
    @State private var purpose = ""
    @State private var descriptionText = ""
    @State private var principles: [String] = []
    @State private var newPrinciple = ""
    
    // Phases
    @State private var phasesEnabled = false
    @State private var phaseDrafts: [LureliaRoutinePhaseDraft] = []
    @State private var showAddPhase = false
    @State private var editingPhaseScheduleIndex: Int? = nil
    @State private var editingPhaseIconIndex: Int? = nil
    
    // Schedule (routine-level, hidden when phases enabled)
    @State private var reminderEnabled = false
    @State private var scheduleEnabled = false
    @State private var selectedDays: Set<Int> = []
    @State private var startHour = 8
    @State private var startMinute = 0
    @State private var endHour = 8
    @State private var endMinute = 30
    @State private var durationMode = false
    @State private var durationMinutesOverride = 30
    
    // Tasks (routine-level, hidden when phases enabled)
    @State private var routineTasks: [LureliaRoutineTaskDraft] = []
    @State private var showAddCustomTask = false
    @State private var editingRoutineTaskIndex: Int? = nil
    
    // Phase-level task add
    @State private var addingTaskForPhaseIndex: Int? = nil
    @State private var editingPhaseTaskIndices: (phase: Int, task: Int)? = nil
    @State private var phaseTaskSheetTarget: PhaseTaskSheetTarget? = nil
    
    private var isEditing: Bool { editingRoutine != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    init(
        editingRoutine: LureliaRoutine? = nil,
        initialColor: Color,
        onCreated: ((LureliaRoutine) -> Void)? = nil
    ) {
        self.editingRoutine = editingRoutine
        _selectedColor = State(initialValue: initialColor)
        self.onCreated = onCreated
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        
                        field("Routine Name") {
                            TextField("e.g. Morning Reset", text: $name)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(LColors.textPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Time of Day")

                            HStack(spacing: 8) {
                                ForEach(LureliaRoutineTimeOfDay.allCases, id: \.self) { tod in
                                    let isSelected = timeOfDay == tod
                                    Button {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { timeOfDay = tod }
                                    } label: {
                                        Text(tod.rawValue)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                                            .routineDarkIconMaterial(
                                                tint: selectedColor,
                                                isEnabled: isSelected
                                            )
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 11)
                                            .background {
                                                if isSelected {
                                                    BubblyIconMaterial(tint: selectedColor)
                                                        .clipShape(RoundedRectangle(cornerRadius: LSpacing.inputRadius, style: .continuous))
                                                } else {
                                                    RoundedRectangle(cornerRadius: LSpacing.inputRadius, style: .continuous)
                                                        .fill(theme.palette.surface)
                                                }
                                            }
                                            .overlay {
                                                RoundedRectangle(cornerRadius: LSpacing.inputRadius, style: .continuous)
                                                    .strokeBorder(
                                                        isSelected ? selectedColor : theme.palette.textPrimary.opacity(0.12),
                                                        lineWidth: 1
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        field("Color") {
                            HStack(spacing: 14) {
                                ColorPicker(
                                    "Routine Color",
                                    selection: $selectedColor,
                                    supportsOpacity: false
                                )
                                .labelsHidden()
                                .frame(width: 44, height: 44)

                                Text("Tap to change the routine color")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(LColors.textSecondary)

                                Spacer()

                                Circle()
                                    .fill(selectedColor)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(selectedColor, lineWidth: 1)
                                    }
                            }
                        }
                        
                        field("Icon") {
                            Button { showIconPicker = true } label: {
                                HStack(spacing: 14) {
                                    LureliaIconView(iconId: selectedIcon, size: 26)
                                        .foregroundStyle(selectedColor)
                                        .bubblyIconMaterial(tint: selectedColor)
                                        .frame(width: 44, height: 44)
                                        .background(theme.palette.raisedSurface, in: RoundedRectangle(cornerRadius: LSpacing.inputRadius))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: LSpacing.inputRadius, style: .continuous)
                                                .strokeBorder(selectedColor, lineWidth: 1)
                                        }
                                    Text("Choose icon")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(theme.palette.textSecondary)
                                    Spacer()
                                    Image("chevright")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 19, height: 19)
                                        .foregroundStyle(selectedColor)
                                        .bubblyIconMaterial(tint: selectedColor)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // MARK: - Purpose
                        
                        field("Purpose") {
                            TextField("Why this routine exists...", text: $purpose, axis: .vertical)
                                .lineLimit(2, reservesSpace: true)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(LColors.textPrimary)
                        }
                        
                        // MARK: - Description
                        
                        field("Description") {
                            TextField("What this routine covers...", text: $descriptionText, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(LColors.textPrimary)
                        }
                        
                        // MARK: - Principles
                        
                        principlesSection
                        
                        // MARK: - Phases Toggle
                        
                        field("Phases") {
                            routineToggleRow(
                                title: "Enable phases",
                                subtitle: "Split this routine into named phases with their own tasks and schedules",
                                isOn: $phasesEnabled,
                                icon: "listcircle"
                            )
                            .onChange(of: phasesEnabled) { oldValue, newValue in
                                guard oldValue, !newValue else { return }
                                // Populate the non-phase task editor immediately so tasks
                                // remain visible when the toggle is turned off. The save path
                                // still preserves the original SwiftData task objects in-place.
                                routineTasks = phaseDrafts.flatMap(\.tasks)
                            }
                        }
                        
                        // MARK: - Reminders
                        
                        field("Reminders") {
                            VStack(alignment: .leading, spacing: 12) {
                                routineToggleRow(
                                    title: "Enable reminders",
                                    subtitle: "Send reminders at the start, halfway point, and end of this routine",
                                    isOn: $reminderEnabled,
                                    icon: "bellfill"
                                )
                                
                                if reminderEnabled {
                                    VStack(alignment: .leading, spacing: 8) {
                                        reminderPreviewRow(title: "Start", time: formattedTime(hour: startHour, minute: startMinute))
                                        reminderPreviewRow(title: "Halfway", time: formattedTime(hour: halfwayReminderHour, minute: halfwayReminderMinute))
                                        reminderPreviewRow(title: "End", time: formattedTime(hour: endReminderHour, minute: endReminderMinute))
                                    }
                                }
                            }
                        }
                        
                        // MARK: - Schedule (hidden when phases enabled)
                        
                        if !phasesEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Schedule")

                                routineToggleCard(
                                    title: "Enable schedule",
                                    subtitle: "Choose when this routine is scheduled",
                                    isOn: $scheduleEnabled,
                                    icon: "ringstarcal"
                                )

                                if scheduleEnabled {
                                    scheduleContent(
                                        selectedDays: $selectedDays,
                                        startHour: $startHour,
                                        startMinute: $startMinute,
                                        endHour: $endHour,
                                        endMinute: $endMinute,
                                        durationMode: $durationMode,
                                        durationMinutesOverride: $durationMinutesOverride
                                    )
                                }
                            }
                        }
                        
                        // MARK: - Tasks (hidden when phases enabled)
                        
                        if !phasesEnabled {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionLabel("Tasks")
                                taskListContent(
                                    tasks: $routineTasks,
                                    onAdd: {
                                        addingTaskForPhaseIndex = nil
                                        editingRoutineTaskIndex = nil
                                        showAddCustomTask = true
                                    },
                                    onEdit: { index in
                                        addingTaskForPhaseIndex = nil
                                        editingRoutineTaskIndex = index
                                        showAddCustomTask = true
                                    }
                                )
                            }
                        }
                        
                        // MARK: - Phases (shown when phases enabled)
                        
                        if phasesEnabled {
                            ForEach(phaseDrafts.indices, id: \.self) { phaseIndex in
                                // Use the phase name or fallback placeholder for the section header label
                                field(phaseDrafts[phaseIndex].name.isEmpty ? "Phase \(phaseIndex + 1)" : phaseDrafts[phaseIndex].name) {
                                    VStack(spacing: 16) {
                                        
                                        // 1. PHASE NAME & ICON ROW
                                        HStack(spacing: 12) {
                                            Button {
                                                editingPhaseIconIndex = phaseIndex
                                            } label: {
                                                LureliaIconView(iconId: phaseDrafts[phaseIndex].icon, size: 18)
                                                    .foregroundStyle(selectedColor)
                                                    .bubblyIconMaterial(tint: selectedColor)
                                                    .frame(width: 38, height: 38)
                                                    .background(theme.palette.raisedSurface, in: RoundedRectangle(cornerRadius: 10))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .strokeBorder(selectedColor, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                            
                                            TextField("Phase name", text: $phaseDrafts[phaseIndex].name)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundStyle(LColors.textPrimary)
                                            
                                            Spacer()
                                            
                                            Button { phaseDrafts.remove(at: phaseIndex) } label: {
                                                Image("trash").renderingMode(.template).resizable().scaledToFit()
                                                    .frame(width: 14, height: 14)
                                                    .foregroundStyle(selectedColor)
                                                    .bubblyIconMaterial(tint: selectedColor)
                                            }.buttonStyle(.plain)
                                        }
                                        
                                        Divider().overlay(LColors.glassBorder)
                                        
                                        // 2. PHASE TASKS LIST & ADD TASK BUTTON
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Tasks for this Phase")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(LColors.textSecondary)
                                                
                                            phaseTaskListContent(phaseIndex: phaseIndex)
                                        }
                                        
                                        Divider().overlay(LColors.glassBorder)
                                        
                                        // 3. PER-PHASE SCHEDULE CARD
                                        Button {
                                            editingPhaseScheduleIndex = phaseIndex
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image("starcal").renderingMode(.template).resizable().scaledToFit()
                                                    .frame(width: 18, height: 18)
                                                    .foregroundStyle(selectedColor)
                                                    .bubblyIconMaterial(tint: selectedColor)
                                                
                                                if phaseDrafts[phaseIndex].scheduleEnabled {
                                                    let days = phaseDrafts[phaseIndex].scheduledDays.sorted()
                                                        .compactMap { d in d >= 1 && d <= 7 ? Calendar.current.shortWeekdaySymbols[d - 1] : nil }
                                                        .joined(separator: ", ")
                                                    Text(days.isEmpty ? "Schedule" : days)
                                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(LColors.textPrimary)
                                                } else {
                                                    Text("Add Schedule")
                                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(LColors.textSecondary)
                                                }
                                                
                                                Spacer()
                                                
                                                Image("chevright").renderingMode(.template).resizable().scaledToFit()
                                                    .frame(width: 11, height: 11).foregroundStyle(LColors.textSecondary.opacity(0.55))
                                            }
                                            .padding(12)
                                            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .strokeBorder(selectedColor, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            
                            // Add Phase Button
                            Button {
                                phaseDrafts.append(LureliaRoutinePhaseDraft(name: ""))
                            } label: {
                                HStack(spacing: 6) {
                                    Image("addwavy").renderingMode(.template).resizable().scaledToFit()
                                        .frame(width: 13, height: 13)
                                        .routineDarkIconMaterial(tint: selectedColor)
                                    Text("Add Phase")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .routineDarkIconMaterial(tint: selectedColor)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background {
                                    BubblyCardMaterial(
                                        tint: selectedColor,
                                        cornerRadius: LSpacing.inputRadius
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Routine" : "New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LColors.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .fontWeight(.semibold).foregroundStyle(LColors.textPrimary).disabled(!canSave)
                }
            }
            .sheet(isPresented: $showAddCustomTask, onDismiss: {
                editingRoutineTaskIndex = nil
            }) {
                addTaskSheet
            }
            .sheet(item: $phaseTaskSheetTarget) { target in
                phaseTaskSheet(target: target)
            }
            .sheet(isPresented: $showIconPicker) {
                LureliaIconPickerView(selectedIcon: $selectedIcon)
            }
            .sheet(isPresented: Binding(
                get: { editingPhaseScheduleIndex != nil },
                set: { if !$0 { editingPhaseScheduleIndex = nil } }
            )) {
                if let phaseIndex = editingPhaseScheduleIndex, phaseIndex < phaseDrafts.count {
                    PhaseScheduleSheet(draft: $phaseDrafts[phaseIndex], tintColor: selectedColor)
                }
            }
            .sheet(isPresented: Binding(
                get: { editingPhaseIconIndex != nil },
                set: { if !$0 { editingPhaseIconIndex = nil } }
            )) {
                if let phaseIndex = editingPhaseIconIndex, phaseIndex < phaseDrafts.count {
                    LureliaIconPickerView(selectedIcon: $phaseDrafts[phaseIndex].icon)
                }
            }
        }
        .onAppear { populate() }
    }
    
    // MARK: - Add Task Sheet
    
    @ViewBuilder
    private var addTaskSheet: some View {
        if let editIndex = editingRoutineTaskIndex {
            AddCustomRoutineTaskView(
                initialDraft: routineTasks[editIndex],
                tint: selectedColor
            ) { draft in
                routineTasks[editIndex] = draft
            }
        } else {
            AddCustomRoutineTaskView(tint: selectedColor) { draft in
                routineTasks.append(draft)
            }
        }
    }
    
    @ViewBuilder
    private func phaseTaskSheet(target: PhaseTaskSheetTarget) -> some View {
        if target.phaseIndex < phaseDrafts.count {
            switch target.mode {

            case .add:
                AddCustomRoutineTaskView(tint: selectedColor) { draft in
                    phaseDrafts[target.phaseIndex].tasks.append(draft)

                    print("Added phase task")
                    print("Phase:", target.phaseIndex + 1)
                    print("Task Count:", phaseDrafts[target.phaseIndex].tasks.count)
                    print(phaseDrafts[target.phaseIndex].tasks.map(\.name))
                }

            case .edit(let taskIndex):
                if taskIndex < phaseDrafts[target.phaseIndex].tasks.count {
                    AddCustomRoutineTaskView(
                        initialDraft: phaseDrafts[target.phaseIndex].tasks[taskIndex],
                        tint: selectedColor
                    ) { draft in
                        phaseDrafts[target.phaseIndex].tasks[taskIndex] = draft

                        print("Edited phase task")
                        print("Phase:", target.phaseIndex + 1)
                        print("Task Count:", phaseDrafts[target.phaseIndex].tasks.count)
                    }
                } else {
                    Text("Task not found")
                }
            }
        } else {
            Text("Phase not found")
        }
    }
    
    // MARK: - Field

    private var principlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Principles")

            HStack(spacing: 12) {
                TextField("e.g. Progress over perfection", text: $newPrinciple)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .submitLabel(.done)
                    .onSubmit(addPrinciple)

                Button(action: addPrinciple) {
                    Image("addwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(selectedColor)
                        .bubblyIconMaterial(tint: selectedColor)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                    .strokeBorder(selectedColor, lineWidth: 1)
            }

            ForEach(principles.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text("\(index + 1).")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .routineDarkIconMaterial(tint: selectedColor)

                    Text(principles[index])
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .routineDarkIconMaterial(tint: selectedColor)

                    Spacer(minLength: 8)

                    Button {
                        principles.remove(at: index)
                    } label: {
                        Image("trash")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .routineDarkIconMaterial(tint: selectedColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    BubblyCardMaterial(
                        tint: selectedColor,
                        cornerRadius: LSpacing.inputRadius
                    )
                }
            }
        }
    }

    private func addPrinciple() {
        let trimmed = newPrinciple.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        principles.append(trimmed)
        newPrinciple = ""
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.palette.textSecondary)
    }

    private func routineToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer(minLength: 8)

            LureliaSlidingIconToggle(
                isOn: isOn,
                iconName: icon,
                accentColor: selectedColor,
                accessibilityLabel: title,
                usesIconMaterial: true
            )
        }
    }

    private func routineToggleCard(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        icon: String
    ) -> some View {
        routineToggleRow(
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            icon: icon
        )
        .padding(14)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                .strokeBorder(selectedColor, lineWidth: 1)
        }
    }
    
    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(label)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                        .strokeBorder(selectedColor, lineWidth: 1)
                }
        }
    }
    
    // MARK: - Schedule Content (reusable)
    
    private func scheduleContent(
        selectedDays: Binding<Set<Int>>,
        startHour: Binding<Int>,
        startMinute: Binding<Int>,
        endHour: Binding<Int>,
        endMinute: Binding<Int>,
        durationMode: Binding<Bool>,
        durationMinutesOverride: Binding<Int>
    ) -> some View {
        RoutineScheduleEditor(
            selectedDays: selectedDays,
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            durationMode: durationMode,
            durationMinutesOverride: durationMinutesOverride,
            tintColor: selectedColor
        )
    }
        
    // MARK: - Task List Content (reusable for routine-level and phase-level)

    private func taskListContent(
        tasks: Binding<[LureliaRoutineTaskDraft]>,
        onAdd: @escaping () -> Void,
        onEdit: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 10) {

            Button {
                onAdd()
            } label: {
                HStack(spacing: 6) {
                    Image("addwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .routineDarkIconMaterial(tint: selectedColor)

                    Text("Add Task")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .routineDarkIconMaterial(tint: selectedColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    BubblyCardMaterial(
                        tint: selectedColor,
                        cornerRadius: LSpacing.inputRadius
                    )
                }
            }
            .buttonStyle(.plain)

            if !tasks.wrappedValue.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(tasks.wrappedValue.enumerated()), id: \.element.id) { index, taskDraft in
                        routineTaskMaterialRow(
                            taskDraft: taskDraft,
                            onEdit: { onEdit(index) },
                            onDelete: {
                                tasks.wrappedValue.remove(at: index)
                            }
                        )
                    }
                }
            }
        }
    }
    
    private func phaseTaskListContent(phaseIndex: Int) -> some View {
        VStack(spacing: 10) {

            Button {
                phaseTaskSheetTarget = PhaseTaskSheetTarget(
                    phaseIndex: phaseIndex,
                    mode: .add
                )
            } label: {
                HStack(spacing: 6) {
                    Image("addwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .routineDarkIconMaterial(tint: selectedColor)

                    Text("Add Task")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .routineDarkIconMaterial(tint: selectedColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    BubblyCardMaterial(
                        tint: selectedColor,
                        cornerRadius: LSpacing.inputRadius
                    )
                }
            }
            .buttonStyle(.plain)

            if phaseIndex < phaseDrafts.count,
               !phaseDrafts[phaseIndex].tasks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(phaseDrafts[phaseIndex].tasks.indices, id: \.self) { taskIndex in
                        let taskDraft = phaseDrafts[phaseIndex].tasks[taskIndex]

                        routineTaskMaterialRow(
                            taskDraft: taskDraft,
                            onEdit: {
                                phaseTaskSheetTarget = PhaseTaskSheetTarget(
                                    phaseIndex: phaseIndex,
                                    mode: .edit(taskIndex: taskIndex)
                                )
                            },
                            onDelete: {
                                phaseDrafts[phaseIndex].tasks.remove(at: taskIndex)
                            }
                        )
                    }
                }
            }
        }
    }

    private func routineTaskMaterialRow(
        taskDraft: LureliaRoutineTaskDraft,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 7) {
            Button(action: onEdit) {
                Image("settings")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .routineDarkIconMaterial(tint: selectedColor)
            }
            .buttonStyle(.plain)

            LureliaIconView(iconId: taskDraft.icon, size: 18)
                .routineDarkIconMaterial(tint: selectedColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(taskDraft.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .routineDarkIconMaterial(tint: selectedColor)

                if !taskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(taskDraft.notes)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .routineDarkIconMaterial(tint: selectedColor)
                        .opacity(0.76)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Button(action: onDelete) {
                Image("trash")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .routineDarkIconMaterial(tint: selectedColor)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            BubblyCardMaterial(
                tint: selectedColor,
                cornerRadius: LSpacing.inputRadius
            )
        }
    }
    
    // MARK: - Reminder Helpers
    
    private var calculatedDurationMinutes: Int {
        if durationMode { return max(1, durationMinutesOverride) }
        let diff = (endHour * 60 + endMinute) - (startHour * 60 + startMinute)
        return max(1, diff > 0 ? diff : diff + 1440)
    }
    
    private var halfwayReminderTotalMinutes: Int { ((startHour * 60 + startMinute) + (calculatedDurationMinutes / 2)) % 1440 }
    private var halfwayReminderHour: Int { halfwayReminderTotalMinutes / 60 }
    private var halfwayReminderMinute: Int { halfwayReminderTotalMinutes % 60 }
    private var endReminderTotalMinutes: Int { durationMode ? ((startHour * 60 + startMinute) + calculatedDurationMinutes) % 1440 : endHour * 60 + endMinute }
    private var endReminderHour: Int { endReminderTotalMinutes / 60 }
    private var endReminderMinute: Int { endReminderTotalMinutes % 60 }
    
    private func formattedTime(hour: Int, minute: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        guard let d = Calendar.current.date(from: c) else { return "\(hour):\(String(format: "%02d", minute))" }
        return d.formatted(date: .omitted, time: .shortened)
    }
    
    private func reminderPreviewRow(title: String, time: String) -> some View {
        HStack(spacing: 8) {
            Image("bellfill").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(selectedColor)
                .bubblyIconMaterial(tint: selectedColor)
            Text(title).font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(theme.palette.textPrimary)
            Spacer()
            Text(time).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(theme.palette.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selectedColor, lineWidth: 1)
        }
    }
    
    // MARK: - Populate
    
    private func populate() {
        guard let routine = editingRoutine else { return }
        
        name = routine.name
        selectedIcon = routine.icon
        timeOfDay = routine.timeOfDay
        purpose = routine.purpose
        descriptionText = routine.descriptionText
        principles = routine.principles
        phasesEnabled = routine.phasesEnabled
        reminderEnabled = routine.remindersEnabled
        scheduleEnabled = routine.scheduleEnabled
        selectedDays = Set(routine.scheduledDays)
        startHour = routine.startHour
        startMinute = routine.startMinute
        endHour = routine.endHour
        endMinute = routine.endMinute
        durationMode = routine.durationMode
        durationMinutesOverride = routine.durationMinutesOverride
        
        if routine.phasesEnabled {
            phaseDrafts = routine.sortedPhases.map { phase in
                var draft = LureliaRoutinePhaseDraft(name: phase.name)
                draft.icon = phase.icon
                draft.scheduleEnabled = phase.scheduleEnabled
                draft.scheduledDays = Set(phase.scheduledDays)
                draft.startHour = phase.startHour
                draft.startMinute = phase.startMinute
                draft.endHour = phase.endHour
                draft.endMinute = phase.endMinute
                draft.durationMode = phase.durationMode
                draft.durationMinutesOverride = phase.durationMinutesOverride
                
                let phaseIDString = phase.id.uuidString
                draft.tasks = routine.sortedTasks
                    .filter { $0.phaseID == phaseIDString }
                    .map { makeTaskDraft(from: $0) }
                return draft
            }
        } else {
            routineTasks = routine.sortedTasks.map { makeTaskDraft(from: $0) }
        }
    }

    /// Builds a full task draft from an existing task so that EDITING a routine
    /// preserves every field (blueprint, schedule, notifications, alarm, and the
    /// step / supply / obstacle children) instead of wiping them on save.
    private func makeTaskDraft(from task: LureliaRoutineTask) -> LureliaRoutineTaskDraft {
        var d = LureliaRoutineTaskDraft(name: task.title, icon: task.icon, notes: task.notes)

        d.context = task.context
        d.purpose = task.purpose
        d.motivation = task.motivation
        d.trigger = task.trigger
        d.triggerType = task.triggerType
        d.triggerReason = task.triggerReason
        d.environment = task.environment
        d.reward = task.reward
        d.rewardEnabled = task.rewardEnabled ?? !task.reward.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        d.consequence = task.consequence
        d.consequenceEnabled = task.consequenceEnabled ?? !task.consequence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        d.recoveryPlan = task.recoveryPlan

        d.hasDueTime = task.hasDueTime
        d.dueHour = task.dueHour
        d.dueMinute = task.dueMinute
        d.estimatedDurationMinutes = task.estimatedDurationMinutes
        d.repeatsOnDays = task.repeatsOnDays
        d.scheduledDays = task.scheduledDays

        d.notificationsEnabled = task.notificationsEnabled
        d.notificationLeadMinutes = task.notificationLeadMinutes
        d.alarmEnabled = task.alarmEnabled
        d.alarmSoundName = task.alarmSoundName ?? LureliaReminderAlarmSound.defaultSound.fileName

        d.steps = task.sortedSteps.map { StepDraft(id: $0.id, title: $0.title, isCompleted: $0.isCompleted) }
        d.supplies = task.sortedSupplies.map { SupplyDraft(id: $0.id, name: $0.name) }
        d.obstacles = task.sortedObstacles.map { ObstacleDraft(id: $0.id, obstacle: $0.obstacle, solution: $0.solution) }

        return d
    }
    
    // MARK: - Save
    
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let routine: LureliaRoutine
        
        let isDisablingPhases = editingRoutine?.phasesEnabled == true && !phasesEnabled

        if let existing = editingRoutine {
            existing.name = trimmed
            existing.icon = selectedIcon
            existing.timeOfDay = timeOfDay
            existing.colorHex = selectedColor.toLureliaHex() ?? "#7d19f7"
            existing.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.descriptionText = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.principles = principles
            existing.phasesEnabled = phasesEnabled
            existing.remindersEnabled = reminderEnabled
            existing.scheduleEnabled = phasesEnabled ? false : scheduleEnabled
            existing.scheduledDays = Array(selectedDays).sorted()
            existing.startHour = startHour
            existing.startMinute = startMinute
            existing.endHour = endHour
            existing.endMinute = endMinute
            existing.durationMode = durationMode
            existing.durationMinutesOverride = durationMinutesOverride
            existing.updatedAt = Date()
            
            if isDisablingPhases {
                // Keep the existing task model objects so their identity, history,
                // completion state, Kanban references, notification IDs, etc. survive.
                let flattenedTasks = existing.sortedPhases.flatMap { phase in
                    let phaseIDString = phase.id.uuidString
                    return existing.sortedTasks.filter { $0.phaseID == phaseIDString }
                }

                for (index, task) in flattenedTasks.enumerated() {
                    task.phaseID = nil
                    task.sortOrder = index
                    task.updatedAt = Date()
                }

                // The phase containers can now be removed; tasks themselves stay intact.
                (existing.phases ?? []).forEach { modelContext.delete($0) }
            } else {
                // Normal edit path: rebuild tasks/phases from the current drafts.
                (existing.tasks ?? []).forEach { modelContext.delete($0) }
                (existing.phases ?? []).forEach { modelContext.delete($0) }
            }
            
            routine = existing
        } else {
            routine = LureliaRoutine(
                name: trimmed, icon: selectedIcon, timeOfDay: timeOfDay,
                colorHex: selectedColor.toLureliaHex() ?? "#7d19f7",
                scheduledDays: Array(selectedDays).sorted(),
                startHour: startHour, startMinute: startMinute,
                endHour: endHour, endMinute: endMinute,
                scheduleEnabled: phasesEnabled ? false : scheduleEnabled,
                sortOrder: routines.count,
                durationMode: durationMode,
                durationMinutesOverride: durationMinutesOverride
            )
            modelContext.insert(routine)
            routine.remindersEnabled = reminderEnabled
            routine.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            routine.descriptionText = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            routine.principles = principles
            routine.phasesEnabled = phasesEnabled
        }
        
        if isDisablingPhases {
            // Existing task objects were flattened in-place above; do not recreate them.
        } else if phasesEnabled {
            // Create phases and their tasks
            for (phaseIndex, draft) in phaseDrafts.enumerated() {
                let phase = LureliaRoutinePhase(
                    name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    icon: draft.icon,
                    sortOrder: phaseIndex
                )
                phase.scheduleEnabled = draft.scheduleEnabled
                phase.scheduledDays = Array(draft.scheduledDays).sorted()
                phase.startHour = draft.startHour
                phase.startMinute = draft.startMinute
                phase.endHour = draft.endHour
                phase.endMinute = draft.endMinute
                phase.durationMode = draft.durationMode
                phase.durationMinutesOverride = draft.durationMinutesOverride
                phase.routine = routine
                modelContext.insert(phase)
                
                let phaseIDString = phase.id.uuidString
                for (taskIndex, taskDraft) in draft.tasks.enumerated() {
                    let task = LureliaRoutineTask(
                        title: taskDraft.name, icon: taskDraft.icon,
                        notes: taskDraft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        sortOrder: taskIndex
                    )
                    task.phaseID = phaseIDString
                    task.attach(to: routine)
                    modelContext.insert(task)
                    applyTaskDraft(taskDraft, to: task)
                }
            }
        } else {
            // Create routine-level tasks
            for (index, draft) in routineTasks.enumerated() {
                let task = LureliaRoutineTask(
                    title: draft.name, icon: draft.icon,
                    notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    sortOrder: index
                )
                task.attach(to: routine)
                modelContext.insert(task)
                applyTaskDraft(draft, to: task)
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("🚨 [AddRoutine] SAVE FAILED (routine + tasks): \(error)")
        }
        let reminderSyncResults = syncRoutineReminders(for: routine)
        do {
            try modelContext.save()
        } catch {
            print("🚨 [AddRoutine] SAVE FAILED (reminder sync): \(error)")
        }
        scheduleRoutineTaskNotifications(for: routine)
        LureliaWidgetReloads.reloadDueRoutines()
        if editingRoutine == nil { onCreated?(routine) }
        
        Task {
            for result in reminderSyncResults {
                switch result {
                case .schedule(let reminder):
                    await LureliaNotificationManager.shared.cancelReminder(reminder)
                    await LureliaNotificationManager.shared.scheduleReminder(reminder)
                case .cancel(let reminder):
                    await LureliaNotificationManager.shared.cancelReminder(reminder)
                case .none: break
                }
            }
        }
        dismiss()
    }
    
    // MARK: - Task Draft Mapping

    /// Copies every blueprint / schedule / notification field from a task draft
    /// onto a freshly-created LureliaRoutineTask and materializes its child
    /// step / supply / obstacle models.
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

        for (i, s) in draft.steps.enumerated()
        where !s.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let step = LureliaRoutineTaskStep(
                title: s.title.trimmingCharacters(in: .whitespacesAndNewlines),
                isCompleted: s.isCompleted,
                sortOrder: i
            )
            step.id = s.id
            modelContext.insert(step)
            step.task = task
            if task.stepItems == nil { task.stepItems = [] }
            task.stepItems?.append(step)
        }

        for (i, s) in draft.supplies.enumerated()
        where !s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let supply = LureliaRoutineTaskSupply(
                name: s.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: i
            )
            supply.id = s.id
            modelContext.insert(supply)
            supply.task = task
            if task.supplyItems == nil { task.supplyItems = [] }
            task.supplyItems?.append(supply)
        }

        for (i, o) in draft.obstacles.enumerated()
        where !o.obstacle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let obstacle = LureliaRoutineTaskObstacle(
                obstacle: o.obstacle.trimmingCharacters(in: .whitespacesAndNewlines),
                solution: o.solution.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: i
            )
            obstacle.id = o.id
            modelContext.insert(obstacle)
            obstacle.task = task
            if task.obstacleItems == nil { task.obstacleItems = [] }
            task.obstacleItems?.append(obstacle)
        }
    }

    /// After the routine is saved, schedule per-task notifications / alarms for
    /// any task that has its own due time configured.
    private func scheduleRoutineTaskNotifications(for routine: LureliaRoutine) {
        let tasks = (routine.tasks ?? []).filter { $0.hasDueTime }
        guard !tasks.isEmpty else { return }
        Task { @MainActor in
            for task in tasks {
                RoutineTaskManager.shared.sync(task: task)
            }
        }
    }

    // MARK: - Reminder Sync

    private func syncRoutineReminders(for routine: LureliaRoutine) -> [RoutineReminderSyncResult] {
        let routineID = routine.persistentModelID.hashValue.description
        let reminderConfigs: [(key: String, title: String, note: String, hour: Int, minute: Int)] = [
            ("start", "\(routine.name) Start", "Routine start reminder", startHour, startMinute),
            ("halfway", "\(routine.name) Halfway", "Routine halfway reminder", halfwayReminderHour, halfwayReminderMinute),
            ("end", "\(routine.name) End", "Routine end reminder", endReminderHour, endReminderMinute)
        ]
        let validKeys = reminderConfigs.map { "\(routineID)::\($0.key)" }
        
        if !reminderEnabled {
            return reminders
                .filter { $0.kind == .routine && (validKeys.contains($0.routinePersistentID ?? "") || $0.routinePersistentID == routineID) }
                .map { r in r.isEnabled = false; r.updatedAt = Date(); return .cancel(r) }
        }
        
        return reminderConfigs.map { config in
            let reminderKey = "\(routineID)::\(config.key)"
            let scheduledDate = reminderDate(hour: config.hour, minute: config.minute)
            let reminder: LureliaReminder
            if let existing = reminders.first(where: { $0.kind == .routine && $0.routinePersistentID == reminderKey }) {
                reminder = existing
            } else {
                reminder = LureliaReminder(title: config.title, notes: config.note, category: "Routines", kind: .routine, scheduledDate: scheduledDate, repeatUnit: selectedDays.isEmpty ? .none : .weeks, repeatInterval: 1)
                reminder.routinePersistentID = reminderKey
                modelContext.insert(reminder)
            }
            reminder.title = config.title; reminder.notes = config.note; reminder.category = "Routines"
            reminder.kind = .routine; reminder.routinePersistentID = reminderKey; reminder.isEnabled = true
            reminder.scheduledDate = scheduledDate; reminder.repeatUnit = selectedDays.isEmpty ? .none : .weeks
            reminder.repeatInterval = 1; reminder.repeatWeekdays = Array(selectedDays).sorted()
            reminder.nextFireAt = scheduledDate; reminder.updatedAt = Date()
            return .schedule(reminder)
        }
    }
    
    private func reminderDate(hour: Int, minute: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}

struct RoutineColorSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var selectedColor: Color

    let onContinue: (Color) -> Void

    init(
        initialColor: Color,
        onContinue: @escaping (Color) -> Void
    ) {
        _selectedColor = State(initialValue: initialColor)
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose Routine Color")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Text("Pick the color that will carry through this routine.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                }

                ColorPicker(
                    selection: $selectedColor,
                    supportsOpacity: false
                ) {
                    Text("Routine Color")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(
                    theme.palette.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selectedColor, lineWidth: 1)
                }

                Button {
                    onContinue(selectedColor)
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            BubblyCardMaterial(
                                tint: selectedColor,
                                cornerRadius: 16
                            )
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .presentationDetents([.height(270)])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.palette.background)
    }
}

private enum RoutineReminderSyncResult {
    case schedule(LureliaReminder)
    case cancel(LureliaReminder)
    case none
}

private struct RoutineScheduleEditor: View {
    @Environment(\.appTheme) private var theme

    @Binding var selectedDays: Set<Int>
    @Binding var startHour: Int
    @Binding var startMinute: Int
    @Binding var endHour: Int
    @Binding var endMinute: Int
    @Binding var durationMode: Bool
    @Binding var durationMinutesOverride: Int

    let tintColor: Color

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(lureliaWeekdays, id: \.value) { day in
                    weekdayButton(day)
                }
            }

            timePicker(
                title: "Start time",
                hour: $startHour,
                minute: $startMinute
            )

            timePicker(
                title: "End time",
                hour: $endHour,
                minute: $endMinute
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Duration countdown")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)

                        Text("Count down from a set duration instead of end time")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                    }

                    Spacer(minLength: 8)

                    LureliaSlidingIconToggle(
                        isOn: $durationMode,
                        iconName: "clockwavy",
                        accentColor: tintColor,
                        accessibilityLabel: "Duration countdown",
                        usesIconMaterial: true
                    )
                }

                if durationMode {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Duration (minutes)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)

                        TextField("e.g. 45", value: $durationMinutesOverride, format: .number)
                            .keyboardType(.numberPad)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                            .padding(12)
                            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(tintColor, lineWidth: 1)
                            }
                    }
                }
            }
            .padding(14)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                    .strokeBorder(tintColor, lineWidth: 1)
            }
        }
    }

    private func weekdayButton(_ day: (label: String, value: Int)) -> some View {
        let isSelected = selectedDays.contains(day.value)

        return Button {
            if isSelected {
                selectedDays.remove(day.value)
            } else {
                selectedDays.insert(day.value)
            }
        } label: {
            Text(day.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                .routineDarkIconMaterial(
                    tint: tintColor,
                    isEnabled: isSelected
                )
                .frame(width: 38, height: 38)
                .background {
                    if isSelected {
                        BubblyIconMaterial(tint: tintColor)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? tintColor : theme.palette.textPrimary.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func timePicker(
        title: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            LureliaGradientTimeDrumPicker(
                hour: hour,
                minute: minute,
                tint: tintColor
            )
        }
    }
}

// MARK: - Phase Schedule Sheet

struct PhaseScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Binding var draft: LureliaRoutinePhaseDraft
    let tintColor: Color
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Schedule for \(draft.name.isEmpty ? "Phase" : draft.name)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LColors.textSecondary)
                            
                            enableScheduleCard

                            if draft.scheduleEnabled {
                                RoutineScheduleEditor(
                                    selectedDays: $draft.scheduledDays,
                                    startHour: $draft.startHour,
                                    startMinute: $draft.startMinute,
                                    endHour: $draft.endHour,
                                    endMinute: $draft.endMinute,
                                    durationMode: $draft.durationMode,
                                    durationMinutesOverride: $draft.durationMinutesOverride,
                                    tintColor: tintColor
                                )
                            }
                        }
                    }
                    .padding(.horizontal).padding(.top, 16).padding(.bottom, 40)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
            }
            .navigationTitle("Phase Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(theme.palette.textPrimary)
                }
            }
        }
    }

    private var enableScheduleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Enable schedule")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text("Choose when this phase is scheduled")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer(minLength: 8)

            LureliaSlidingIconToggle(
                isOn: $draft.scheduleEnabled,
                iconName: "ringstarcal",
                accentColor: tintColor,
                accessibilityLabel: "Enable schedule",
                usesIconMaterial: true
            )
        }
        .padding(14)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                .strokeBorder(tintColor, lineWidth: 1)
        }
    }
}

// MARK: - Add Custom Routine Task Sheet

struct AddCustomRoutineTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let onSave: (LureliaRoutineTaskDraft) -> Void
    let tint: Color

    private let isEditing: Bool
    private let baseDraft: LureliaRoutineTaskDraft

    // Core
    @State private var taskName: String
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

    // Structured content
    @State private var steps: [StepDraft]
    @State private var supplies: [SupplyDraft]
    @State private var obstacles: [ObstacleDraft]

    init(
        initialDraft: LureliaRoutineTaskDraft = LureliaRoutineTaskDraft(name: ""),
        tint: Color,
        onSave: @escaping (LureliaRoutineTaskDraft) -> Void
    ) {
        self.onSave = onSave
        self.tint = tint
        self.baseDraft = initialDraft
        self.isEditing = !initialDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        _taskName = State(initialValue: initialDraft.name)
        _notes = State(initialValue: initialDraft.notes)
        _taskContext = State(initialValue: initialDraft.context)
        _selectedIcon = State(initialValue: initialDraft.icon)

        _purpose = State(initialValue: initialDraft.purpose)
        _motivation = State(initialValue: initialDraft.motivation)
        _trigger = State(initialValue: initialDraft.trigger)
        _triggerType = State(initialValue: initialDraft.triggerType)
        _triggerReason = State(initialValue: initialDraft.triggerReason)
        _environment = State(initialValue: initialDraft.environment)
        _reward = State(initialValue: initialDraft.reward)
        _rewardEnabled = State(initialValue: initialDraft.rewardEnabled)
        _consequence = State(initialValue: initialDraft.consequence)
        _consequenceEnabled = State(initialValue: initialDraft.consequenceEnabled)
        _recoveryPlan = State(initialValue: initialDraft.recoveryPlan)

        _hasDueTime = State(initialValue: initialDraft.hasDueTime)
        _dueHour = State(initialValue: initialDraft.dueHour)
        _dueMinute = State(initialValue: initialDraft.dueMinute)
        _estimatedDuration = State(initialValue: max(0, initialDraft.estimatedDurationMinutes))
        _repeatsOnDays = State(initialValue: initialDraft.repeatsOnDays)
        _scheduledDays = State(initialValue: Set(initialDraft.scheduledDays))

        _notificationsEnabled = State(initialValue: initialDraft.notificationsEnabled)
        _leadMinutes = State(initialValue: Set(initialDraft.notificationLeadMinutes))
        _alarmEnabled = State(initialValue: initialDraft.alarmEnabled)
        _alarmSoundName = State(initialValue: initialDraft.alarmSoundName)

        _steps = State(initialValue: initialDraft.steps)
        _supplies = State(initialValue: initialDraft.supplies)
        _obstacles = State(initialValue: initialDraft.obstacles)
    }

    private var canAdd: Bool { !taskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()
                    .routineDismissKeyboardOnTap()

                ScrollView(showsIndicators: false) {
                    RoutineTaskFieldsForm(
                        accent: AnyShapeStyle(tint),
                        accentColor: tint,
                        title: $taskName,
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Task" : "Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(theme.palette.textPrimary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { commit() }
                        .fontWeight(.semibold).foregroundStyle(theme.palette.textPrimary).disabled(!canAdd)
                }
            }
            .tint(tint)
        }
    }

    private func commit() {
        let trimmedName = taskName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var draft = baseDraft
        draft.name = trimmedName
        draft.icon = selectedIcon
        draft.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.context = taskContext.trimmingCharacters(in: .whitespacesAndNewlines)

        draft.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.motivation = motivation.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.triggerType = triggerType
        draft.triggerReason = triggerReason.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.reward = reward.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.rewardEnabled = rewardEnabled
        draft.consequence = consequence.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.consequenceEnabled = consequenceEnabled
        draft.recoveryPlan = recoveryPlan.trimmingCharacters(in: .whitespacesAndNewlines)

        draft.hasDueTime = hasDueTime
        draft.dueHour = dueHour
        draft.dueMinute = dueMinute
        draft.estimatedDurationMinutes = max(0, estimatedDuration)
        draft.repeatsOnDays = repeatsOnDays
        draft.scheduledDays = scheduledDays.sorted()

        draft.notificationsEnabled = notificationsEnabled && hasDueTime
        draft.notificationLeadMinutes = leadMinutes.sorted()
        draft.alarmEnabled = alarmEnabled && hasDueTime
        draft.alarmSoundName = alarmSoundName

        draft.steps = steps.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        draft.supplies = supplies.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        draft.obstacles = obstacles.filter { !$0.obstacle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        onSave(draft)
        dismiss()
    }
}

// MARK: - Routine Task Draft

struct LureliaRoutineTaskDraft: Identifiable {
    let id = UUID()
    var name: String
    var icon: String = "sparkle"
    var notes: String = ""
    var context: String = ""
    var isFromBank: Bool = false
    var bankTaskID: String? = nil

    // MARK: - Blueprint
    var purpose: String = ""
    var motivation: String = ""
    var trigger: String = ""
    var triggerType: LureliaCueType? = nil
    var triggerReason: String = ""
    var environment: String = ""
    var reward: String = ""
    var rewardEnabled: Bool = false
    var consequence: String = ""
    var consequenceEnabled: Bool = false
    var recoveryPlan: String = ""

    // MARK: - Schedule
    var hasDueTime: Bool = false
    var dueHour: Int = 8
    var dueMinute: Int = 0
    var estimatedDurationMinutes: Int = 0
    var repeatsOnDays: Bool = false
    var scheduledDays: [Int] = []

    // MARK: - Notifications & Alarm
    var notificationsEnabled: Bool = false
    var notificationLeadMinutes: [Int] = []
    var alarmEnabled: Bool = false
    var alarmSoundName: String = LureliaReminderAlarmSound.defaultSound.fileName

    // MARK: - Structured content
    var steps: [StepDraft] = []
    var supplies: [SupplyDraft] = []
    var obstacles: [ObstacleDraft] = []
}

// MARK: - Time Picker

struct LureliaTimeDrumPicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var body: some View {
        HStack(spacing: 10) {
            Picker("Hour", selection: $hour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                .pickerStyle(.wheel).frame(maxWidth: .infinity).frame(height: 110).clipped()
            Text(":").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(LColors.textPrimary)
            Picker("Minute", selection: $minute) { ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                .pickerStyle(.wheel).frame(maxWidth: .infinity).frame(height: 110).clipped()
        }
    }
}

// MARK: - Color Hex Helper

extension Color {
    func toLureliaHex() -> String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
