//
//  AddReminderView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit
import MapKit
import AVFoundation

struct LureliaReminderCreationFlow: View {
    private enum Stage {
        case color
        case editor
    }

    var onCreated: ((LureliaReminder) -> Void)? = nil

    @State private var stage: Stage = .color
    @State private var selectedColor = Color(lureliaHex: "#7d19f7")

    var body: some View {
        Group {
            switch stage {
            case .color:
                LureliaReminderColorGatekeeperView(color: $selectedColor) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        stage = .editor
                    }
                }
            case .editor:
                AddReminderView(
                    initialColor: selectedColor,
                    onCreated: onCreated
                )
            }
        }
        .presentationDetents(stage == .color ? [.height(330)] : [.large])
    }
}

private struct LureliaReminderColorGatekeeperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Binding var color: Color
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Text("Choose Reminder Color")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Spacer()

                    Button { dismiss() } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.white)
                            .bubblyIconMaterial(tint: .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                Text("Choose the color that will carry through this reminder and its editor.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)

                ColorPicker(selection: $color, supportsOpacity: false) {
                    Text("Reminder Color")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(height: 62)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(color, lineWidth: 1.4)
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background {
                            BubblyCardMaterial(tint: color, cornerRadius: 20)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }
}

struct AddReminderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    @Query private var settings: [UserSettings]
    
    var editingReminder: LureliaReminder? = nil
    var onCreated: ((LureliaReminder) -> Void)? = nil
    
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedCategory = ""
    @State private var selectedIcon = "bellfill"
    @State private var showIconPicker = false
    @FocusState private var notesFieldIsFocused: Bool
    @State private var checklistItems: [LureliaReminderChecklistItem] = [
        LureliaReminderChecklistItem(title: "", sortOrder: 0)
    ]
    @State private var emptyChecklistSubmitCount = 0
    @FocusState private var focusedChecklistItemID: UUID?
    
    
    @State private var reminderDate = Date()
    @State private var reminderHour = 9
    @State private var reminderMinute = 0
    @State private var additionalFireTimes: [LureliaAdditionalFireTime] = []
    @State private var alarmEnabled = false
    @State private var alarmDate = Date()
    @State private var alarmHour = 9
    @State private var alarmMinute = 0
    @State private var alarmSoundName = LureliaReminderAlarmSound.defaultSound.fileName
    @State private var alarmFireTimes: Set<String> = []
    @State private var showAlarmConfig = false
    
    @State private var repeatUnit: LureliaReminderRepeatUnit = .none
    @State private var repeatInterval = 1
    @State private var repeatIntervalAdjustmentTask: Task<Void, Never>? = nil
    @State private var repeatIntervalDidAutoAdjust = false
    @State private var repeatWeekdays: Set<Int> = []
    @State private var repeatEnds = false
    @State private var repeatEndsAt = Date()

    // Detail fields
    @State private var motivation = ""
    @State private var consequences = ""
    @State private var recoveryPlan = ""

    // Location fields
    @State private var locationLabel = ""
    @State private var locationAddress = ""
    @State private var locationLatitude: Double? = nil
    @State private var locationLongitude: Double? = nil
    @State private var locationSearchText = ""
    @State private var locationSearchResults: [MKMapItem] = []
    @State private var showLocationSearch = false

    /// User-selected reminder color. Creation receives this from the color
    /// gatekeeper; edit mode loads the reminder's saved `colorHex`.
    @State private var selectedColor: Color? = nil

    init(
        editingReminder: LureliaReminder? = nil,
        initialColor: Color? = nil,
        onCreated: ((LureliaReminder) -> Void)? = nil
    ) {
        self.editingReminder = editingReminder
        self.onCreated = onCreated
        _selectedColor = State(initialValue: initialColor)
    }

    /// The tint every in-sheet control accent uses.
    private var formTint: Color {
        selectedColor ?? LColors.neutralPearl.opacity(0.62)
    }

    private let weekdays: [(label: String, value: Int)] = [
        ("Su", 1), ("Mo", 2), ("Tu", 3), ("We", 4),
        ("Th", 5), ("Fr", 6), ("Sa", 7)
    ]
    
    private var isEditing: Bool {
        editingReminder != nil
    }
    
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var scheduledDate: Date {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: reminderDate
        )
        
        components.hour = reminderHour
        components.minute = reminderMinute
        components.second = 0
        
        return Calendar.current.date(from: components) ?? Date()
    }

    private var allPreviewFireDates: [Date] {
        let calendar = Calendar.current
        let extraDates = additionalFireTimes.compactMap { fireTime -> Date? in
            var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
            components.hour = fireTime.hour
            components.minute = fireTime.minute
            components.second = 0
            return calendar.date(from: components)
        }

        return ([scheduledDate] + extraDates).sorted()
    }

    private var alarmScheduledDate: Date {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: alarmDate
        )

        components.hour = alarmHour
        components.minute = alarmMinute
        components.second = 0

        return Calendar.current.date(from: components) ?? scheduledDate
    }

    private var currentAlarmFireTimes: [String] {
        allCurrentFireTimes().map { String(format: "%02d:%02d", $0.hour, $0.minute) }
    }

    private var useFullScreenCover: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private func repeatUnitText(for unit: LureliaReminderRepeatUnit) -> String {
        switch unit {
        case .none:
            return "None"
        case .minutes:
            return "Minutes"
        case .hours:
            return "Hours"
        case .days:
            return "Days"
        case .weeks:
            return "Weeks"
        case .months:
            return "Months"
        case .years:
            return "Years"
        }
    }

    private func adjustRepeatInterval(by amount: Int) {
        repeatInterval = min(999, max(1, repeatInterval + amount))
    }

    private func handleRepeatIntervalTap(by amount: Int) {
        if repeatIntervalDidAutoAdjust {
            repeatIntervalDidAutoAdjust = false
            return
        }

        adjustRepeatInterval(by: amount)
    }

    private func beginAutoAdjustingRepeatInterval(by amount: Int) {
        repeatIntervalAdjustmentTask?.cancel()
        repeatIntervalDidAutoAdjust = false

        repeatIntervalAdjustmentTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            while !Task.isCancelled {
                let previousValue = repeatInterval
                adjustRepeatInterval(by: amount)
                guard repeatInterval != previousValue else { break }

                repeatIntervalDidAutoAdjust = true
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopAutoAdjustingRepeatInterval() {
        repeatIntervalAdjustmentTask?.cancel()
        repeatIntervalAdjustmentTask = nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboardEverywhere()
                    }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        previewCard
                        
                        field("Reminder Title") {
                            TextField("What should Lurelia remind you about?", text: $title)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(LColors.textPrimary)
                        }
                        
                        field("Notes") {
                            TextField("Optional details", text: $notes, axis: .vertical)
                                .focused($notesFieldIsFocused)
                                .lineLimit(3, reservesSpace: true)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(LColors.textPrimary)
                        }

                        checklistField

                        field("Icon") {
                            Button {
                                showIconPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.42))
                                            .frame(width: 44, height: 44)

                                        Circle()
                                            .strokeBorder(formTint, lineWidth: 1.4)
                                            .bubblyIconMaterial(tint: formTint)
                                            .frame(width: 44, height: 44)

                                        LureliaIconView(iconId: selectedIcon, size: 22)
                                            .foregroundStyle(formTint)
                                            .bubblyIconMaterial(tint: formTint)
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Reminder Icon")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(LColors.textPrimary)

                                        Text("Tap to choose a custom icon.")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(LColors.textSecondary.opacity(0.75))
                                    }

                                    Spacer()

                                    Image("settings")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(formTint)
                                        .bubblyIconMaterial(tint: formTint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        colorPickerField

                        HStack(alignment: .top, spacing: 12) {
                            compactPickerField("Date") {
                                LureliaCompactDateDrumPicker(
                                    date: $reminderDate,
                                    tint: formTint,
                                    usesCardMaterial: true,
                                    usesDarkTypography: true
                                )
                            }

                            compactPickerField("Time") {
                                LureliaCompactTimeDrumPicker(
                                    hour: $reminderHour,
                                    minute: $reminderMinute,
                                    tint: formTint,
                                    usesDarkTypography: true
                                )
                            }
                        }

                        field("Additional Times") {
                            additionalFireTimesSection
                        }

                        field("Alarm") {
                            alarmSection
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Repeat")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary)

                            repeatSection
                        }

                        // Motivation / Consequences / Recovery Plan hidden
                        // from the UI. The underlying model fields
                        // (`motivation`, `consequences`, `recoveryPlan`) are
                        // still saved/loaded via `populate()` and `save()` so
                        // any existing data survives round-trips.

                        // Location

                        locationField

                        Button {
                            save()
                        } label: {
                            Text(isEditing ? "Save Reminder" : "Create Reminder")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .background {
                                    BubblyCardMaterial(tint: formTint, cornerRadius: 22)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(formTint.opacity(0.82), lineWidth: 1.4)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.45)
                        
                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                // Swipe/drag down inside the scroll dismisses the keyboard
                // interactively; supplements the tap-outside dismiss below.
                .scrollDismissesKeyboard(.interactively)
            }
            // Tap anywhere outside a focused text field dismisses the
            // keyboard. Attached to the whole NavigationStack so it also
            // covers taps on non-focusable text/labels above/below inputs.
            .simultaneousGesture(
                TapGesture().onEnded { dismissKeyboardEverywhere() }
            )
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(.white)
                            .bubblyIconMaterial(tint: .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
        }
        .onAppear {
            populate()
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .sheet(isPresented: Binding(
            get: { !useFullScreenCover && showAlarmConfig },
            set: { showAlarmConfig = $0 }
        )) {
            alarmConfigSheet
        }
        .fullScreenCover(isPresented: Binding(
            get: { useFullScreenCover && showAlarmConfig },
            set: { showAlarmConfig = $0 }
        )) {
            alarmConfigSheet
        }
    }

    private var alarmConfigSheet: some View {
            LureliaReminderAlarmConfigSheet(
                alarmEnabled: $alarmEnabled,
                availableFireTimes: currentAlarmFireTimes,
                selectedFireTimes: $alarmFireTimes,
                alarmSoundName: $alarmSoundName,
                tint: formTint
            )
    }
    
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 58, height: 58)

                    Circle()
                        .strokeBorder(formTint, lineWidth: 1.6)
                        .bubblyIconMaterial(tint: formTint)
                        .frame(width: 58, height: 58)

                    LureliaIconView(iconId: selectedIcon, size: 28)
                        .foregroundStyle(formTint)
                        .bubblyIconMaterial(tint: formTint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Reminder Preview" : title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .lineLimit(2)

                    Text(scheduledDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Description / notes — wraps freely to as many lines as needed.
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNotes.isEmpty {
                Text(trimmedNotes)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(LColors.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 70), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(allPreviewFireDates.enumerated()), id: \.offset) { _, fireDate in
                    Text(fireDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            BubblyIconMaterial(tint: formTint)
                                .clipShape(Capsule())
                        }
                }
            }
            
            if repeatUnit != .none {
                Text(repeatPreviewText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        BubblyIconMaterial(tint: formTint)
                            .clipShape(Capsule())
                    }
            }

            if alarmEnabled {
                Text("Alarm \(alarmScheduledDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        BubblyIconMaterial(tint: formTint)
                            .clipShape(Capsule())
                    }
            }
        }
        .padding(18)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(formTint, lineWidth: 1.5)
        )
    }
    private var checklistField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Completion Steps")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(nonEmptyChecklistItems.count) items")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(LColors.textPrimary)

                        Text("Add small steps to complete this reminder.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(LColors.textSecondary.opacity(0.75))
                    }

                    Spacer()

                    Button {
                        addChecklistItemAndFocus()
                    } label: {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(formTint)
                            .bubblyIconMaterial(tint: formTint)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 10) {
                    ForEach(checklistItems) { item in
                        checklistRow(item)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(formTint, lineWidth: 1.4)
            )
        }
    }

    private func checklistRow(_ item: LureliaReminderChecklistItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(formTint, lineWidth: 1.4)
                .frame(width: 20, height: 20)

            TextField("Step", text: checklistTitleBinding(for: item.id))
                .focused($focusedChecklistItemID, equals: item.id)
                .submitLabel(.return)
                .onSubmit {
                    handleChecklistSubmit(for: item.id)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(LColors.textPrimary)

            if checklistItems.count > 1 {
                Button {
                    removeChecklistItem(item.id)
                } label: {
                    Image("xmarkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(LColors.textSecondary.opacity(0.75))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(formTint, lineWidth: 1.2)
        )
    }

    private var nonEmptyChecklistItems: [LureliaReminderChecklistItem] {
        checklistItems.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func checklistTitleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                checklistItems.first(where: { $0.id == id })?.title ?? ""
            },
            set: { newValue in
                guard let index = checklistItems.firstIndex(where: { $0.id == id }) else { return }
                checklistItems[index].title = newValue
                checklistItems[index].updatedAt = Date()
                emptyChecklistSubmitCount = 0
            }
        )
    }
    
    private func addChecklistItemAndFocus() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            let newItem = LureliaReminderChecklistItem(
                title: "",
                sortOrder: checklistItems.count
            )
            checklistItems.append(newItem)
            focusedChecklistItemID = newItem.id
            emptyChecklistSubmitCount = 0
        }
    }

    private func handleChecklistSubmit(for id: UUID) {
        let trimmed = checklistItems.first(where: { $0.id == id })?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmed.isEmpty {
            emptyChecklistSubmitCount += 1

            if emptyChecklistSubmitCount >= 2 {
                focusedChecklistItemID = nil
                emptyChecklistSubmitCount = 0
            }

            return
        }

        emptyChecklistSubmitCount = 0
        addChecklistItemAndFocus()
    }

    private func removeChecklistItem(_ id: UUID) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            checklistItems.removeAll { $0.id == id }

            if checklistItems.isEmpty {
                checklistItems = [LureliaReminderChecklistItem(title: "", sortOrder: 0)]
            }

            normalizeChecklistSortOrder()
        }
    }

    private func normalizeChecklistSortOrder() {
        for index in checklistItems.indices {
            checklistItems[index].sortOrder = index
            checklistItems[index].updatedAt = Date()
        }
    }

    private var additionalFireTimesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if additionalFireTimes.isEmpty {
                Text("Add another time when this reminder needs to fire more than once on the same day.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(LColors.textSecondary.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 12) {
                    ForEach(additionalFireTimes) { fireTime in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text("Extra Fire Time")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(LColors.textSecondary)

                                Spacer()

                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        additionalFireTimes.removeAll { $0.id == fireTime.id }
                                    }
                                } label: {
                                    Image("xmarkwavy")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(formTint)
                                        .bubblyIconMaterial(tint: formTint)
                                }
                                .buttonStyle(.plain)
                            }

                            LureliaGradientTimeDrumPicker(
                                hour: bindingForAdditionalFireHour(fireTime.id),
                                minute: bindingForAdditionalFireMinute(fireTime.id),
                                tint: formTint,
                                usesDarkTypography: true
                            )
                        }
                        .padding(12)
                        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(formTint, lineWidth: 1.3)
                        )
                    }
                }
            }

            Button {
                addAdditionalFireTime()
            } label: {
                HStack(spacing: 8) {
                    Image("addwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text("Add Another Time")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    BubblyCardMaterial(tint: formTint, cornerRadius: 16)
                }
            }
            .buttonStyle(.plain)
        }
    }
    private func addAdditionalFireTime() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            additionalFireTimes.append(
                LureliaAdditionalFireTime(
                    hour: reminderHour,
                    minute: reminderMinute
                )
            )
        }
    }

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(alarmEnabled ? "Alarm On" : "Alarm Off")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)

                    Text(alarmEnabled ? alarmSummaryText : "Use a system alarm for this reminder.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(LColors.textSecondary.opacity(0.78))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                LureliaSlidingIconToggle(
                    isOn: alarmEnabledBinding,
                    iconName: "petalarm",
                    accentColor: formTint,
                    accessibilityLabel: "Reminder alarm",
                    usesIconMaterial: true
                )
            }

            if alarmEnabled {
                Button {
                    showAlarmConfig = true
                } label: {
                    HStack(spacing: 12) {
                        Image("petalarm")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(formTint)
                            .bubblyIconMaterial(tint: formTint)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Alarm Settings")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(LColors.textPrimary)

                            Text(alarmSummaryText)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(LColors.textSecondary.opacity(0.78))
                                .lineLimit(2)
                        }

                        Spacer()

                        Image("chevright")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(formTint)
                            .bubblyIconMaterial(tint: formTint)
                    }
                    .padding(12)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(formTint, lineWidth: 1.2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var alarmEnabledBinding: Binding<Bool> {
        Binding(
            get: { alarmEnabled },
            set: { newValue in
                alarmEnabled = newValue
                if newValue {
                    if alarmScheduledDate < Date() {
                        syncAlarmDateToReminder()
                    }
                    showAlarmConfig = true
                }
            }
        )
    }

    private var alarmSummaryText: String {
        let sound = LureliaReminderAlarmSound.sound(named: alarmSoundName).displayName
        let selectedCount = alarmFireTimes.intersection(Set(currentAlarmFireTimes)).count
        let countText = selectedCount == 1 ? "1 time" : "\(selectedCount) times"
        return "\(countText) • \(sound)"
    }

    private func syncAlarmDateToReminder() {
        alarmDate = reminderDate
        alarmHour = reminderHour
        alarmMinute = reminderMinute
        if alarmFireTimes.isEmpty {
            alarmFireTimes = Set([String(format: "%02d:%02d", reminderHour, reminderMinute)])
        }
    }

    private func bindingForAdditionalFireHour(_ id: UUID) -> Binding<Int> {
        Binding(
            get: {
                additionalFireTimes.first(where: { $0.id == id })?.hour ?? reminderHour
            },
            set: { newValue in
                guard let index = additionalFireTimes.firstIndex(where: { $0.id == id }) else { return }
                additionalFireTimes[index].hour = newValue
            }
        )
    }

    private func bindingForAdditionalFireMinute(_ id: UUID) -> Binding<Int> {
        Binding(
            get: {
                additionalFireTimes.first(where: { $0.id == id })?.minute ?? reminderMinute
            },
            set: { newValue in
                guard let index = additionalFireTimes.firstIndex(where: { $0.id == id }) else { return }
                additionalFireTimes[index].minute = newValue
            }
        )
    }
    
    
    
    private var locationField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(LColors.textSecondary)

            VStack(alignment: .leading, spacing: 14) {
                TextField("Label (e.g. Home, Walmart, Work)", text: $locationLabel)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)

                if locationLatitude != nil {
                    HStack(spacing: 8) {
                        Image("lovelocation")
                            .renderingMode(.template)
                            .resizable().scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(formTint)
                            .bubblyIconMaterial(tint: formTint)

                        Text(locationAddress.isEmpty ? "Location selected" : locationAddress)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(LColors.textSecondary)
                            .lineLimit(2)

                        Spacer()

                        Button {
                            locationLatitude = nil
                            locationLongitude = nil
                            locationAddress = ""
                        } label: {
                            Image("xmarkwavy")
                                .renderingMode(.template)
                                .resizable().scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(formTint)
                                .bubblyIconMaterial(tint: formTint)
                        }
                        .buttonStyle(.plain)
                    }

                }

                // Search
                TextField("Search for a location", text: $locationSearchText)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                    .onChange(of: locationSearchText) { _, newValue in
                        searchLocation(query: newValue)
                    }

                if !locationSearchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(locationSearchResults.prefix(5), id: \.self) { item in
                            Button {
                                selectMapItem(item)
                            } label: {
                                HStack(spacing: 10) {
                                    Image("lovelocation")
                                        .renderingMode(.template)
                                        .resizable().scaledToFit()
                                        .frame(width: 14, height: 14)
                                        .foregroundStyle(formTint)
                                        .bubblyIconMaterial(tint: formTint)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(LColors.textPrimary)
                                            .lineLimit(1)
                                        if let address = item.placemark.formattedAddress {
                                            Text(address)
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundStyle(LColors.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if item != locationSearchResults.prefix(5).last {
                                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(formTint, lineWidth: 1)
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(formTint, lineWidth: 1.4)
            )
        }
    }

    private func searchLocation(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            locationSearchResults = []
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            locationSearchResults = response?.mapItems ?? []
        }
    }

    private func selectMapItem(_ item: MKMapItem) {
        locationLatitude = item.placemark.coordinate.latitude
        locationLongitude = item.placemark.coordinate.longitude
        locationAddress = item.placemark.formattedAddress ?? ""
        if locationLabel.isEmpty {
            locationLabel = item.name ?? ""
        }
        locationSearchText = ""
        locationSearchResults = []
    }

    private var repeatSection: some View {
        VStack(spacing: 14) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(LureliaReminderRepeatUnit.allCases, id: \.self) { unit in
                    Button {
                        repeatUnit = unit
                    } label: {
                        Text(repeatUnitText(for: unit))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(repeatUnit == unit ? Color.black : theme.palette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                if repeatUnit == unit {
                                    BubblyIconMaterial(tint: formTint)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(theme.palette.surface)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(formTint, lineWidth: 1.2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if repeatUnit != .none {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Every \(repeatInterval) \(repeatUnit.rawValue.lowercased())")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.textPrimary)
                        
                        Text("Controls how often this reminder repeats.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(LColors.textSecondary.opacity(0.75))
                    }

                    Spacer()

                    Button {
                        handleRepeatIntervalTap(by: -1)
                    } label: {
                        Image("minuswavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 23, height: 23)
                            .foregroundStyle(formTint)
                            .bubblyIconMaterial(tint: formTint)
                    }
                    .buttonStyle(.plain)
                    .disabled(repeatInterval <= 1)
                    .opacity(repeatInterval <= 1 ? 0.35 : 1)
                    .accessibilityLabel("Decrease repeat interval")
                    .onLongPressGesture(
                        minimumDuration: 0.35,
                        maximumDistance: 30,
                        perform: {},
                        onPressingChanged: { isPressing in
                            if isPressing {
                                beginAutoAdjustingRepeatInterval(by: -1)
                            } else {
                                stopAutoAdjustingRepeatInterval()
                            }
                        }
                    )

                    Button {
                        handleRepeatIntervalTap(by: 1)
                    } label: {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 23, height: 23)
                            .foregroundStyle(formTint)
                            .bubblyIconMaterial(tint: formTint)
                    }
                    .buttonStyle(.plain)
                    .disabled(repeatInterval >= 999)
                    .opacity(repeatInterval >= 999 ? 0.35 : 1)
                    .accessibilityLabel("Increase repeat interval")
                    .onLongPressGesture(
                        minimumDuration: 0.35,
                        maximumDistance: 30,
                        perform: {},
                        onPressingChanged: { isPressing in
                            if isPressing {
                                beginAutoAdjustingRepeatInterval(by: 1)
                            } else {
                                stopAutoAdjustingRepeatInterval()
                            }
                        }
                    )
                }
                
                if repeatUnit == .weeks {
                    HStack(spacing: 6) {
                        ForEach(weekdays, id: \.value) { day in
                            Button {
                                if repeatWeekdays.contains(day.value) {
                                    repeatWeekdays.remove(day.value)
                                } else {
                                    repeatWeekdays.insert(day.value)
                                }
                            } label: {
                                Text(day.label)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(repeatWeekdays.contains(day.value) ? Color.black : theme.palette.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background {
                                        if repeatWeekdays.contains(day.value) {
                                            BubblyIconMaterial(tint: formTint)
                                                .clipShape(Circle())
                                        } else {
                                            Circle().fill(theme.palette.surface)
                                        }
                                    }
                                    .overlay {
                                        Circle().strokeBorder(formTint, lineWidth: 1.2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    Text("Repeat ends")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)

                    Spacer()

                    LureliaSlidingIconToggle(
                        isOn: $repeatEnds,
                        iconName: "repeatfill",
                        accentColor: formTint,
                        accessibilityLabel: "Repeat ends",
                        usesIconMaterial: true
                    )
                }
                
                if repeatEnds {
                    LureliaCompactDateDrumPicker(
                        date: $repeatEndsAt,
                        tint: formTint,
                        usesCardMaterial: true,
                        usesDarkTypography: true
                    )
                }
            }
        }
    }
    
    private var repeatPreviewText: String {
        guard repeatUnit != .none else { return "Does not repeat" }
        return "Repeats every \(repeatInterval) \(repeatUnit.rawValue.lowercased())"
    }
    
    /// Clear every focus binding in this sheet AND ask UIKit to resign the
    /// first responder — the belt-and-suspenders way to hide the keyboard
    /// from any typeable field (title, notes, checklist steps, location
    /// label/search, repeat interval, etc.) without knowing which one is
    /// active.
    private func dismissKeyboardEverywhere() {
        notesFieldIsFocused = false
        focusedChecklistItemID = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// User picks any reminder color via a native ColorPicker. Changes are
    /// bound directly to every tinted surface in the editor.
    private var colorPickerField: some View {
        field("Reminder Color") {
            HStack(spacing: 12) {
                Text("Choose a color")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)

                Spacer(minLength: 8)

                ColorPicker(
                    "Reminder Color",
                    selection: colorPickerBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 32, height: 32)
            }
        }
    }

    private var colorPickerBinding: Binding<Color> {
        Binding(
            get: { selectedColor ?? Color(lureliaHex: "#7d19f7") },
            set: { selectedColor = $0 }
        )
    }

    private func field<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(LColors.textSecondary)
            
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(formTint, lineWidth: 1.4)
                )
        }
    }

    private func compactPickerField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private func populate() {
        guard let reminder = editingReminder else { return }

        title = reminder.title
        selectedIcon = reminder.icon
        notes = reminder.notes ?? ""
        selectedCategory = ""
        reminderDate = reminder.scheduledDate

        // Load the reminder's saved user-selected color so the Edit sheet
        // inherits that reminder's visual identity.
        let trimmedColorHex = reminder.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedColor = Color(lureliaHex: trimmedColorHex.isEmpty ? "#7d19f7" : trimmedColorHex)

        // Use the originally configured primary hour/minute, not the advanced scheduledDate
        if reminder.primaryHour != -1 {
            reminderHour = reminder.primaryHour
            reminderMinute = reminder.primaryMinute
        } else {
            let components = Calendar.current.dateComponents([.hour, .minute], from: reminder.scheduledDate)
            reminderHour = components.hour ?? 9
            reminderMinute = components.minute ?? 0
        }
        additionalFireTimes = reminder.additionalFireTimes
        alarmEnabled = reminder.alarmEnabled
        alarmDate = reminder.alarmDate ?? reminder.scheduledDate
        let alarmComponents = Calendar.current.dateComponents([.hour, .minute], from: reminder.alarmDate ?? reminder.scheduledDate)
        alarmHour = alarmComponents.hour ?? reminderHour
        alarmMinute = alarmComponents.minute ?? reminderMinute
        alarmSoundName = reminder.alarmSoundName ?? LureliaReminderAlarmSound.defaultSound.fileName
        alarmFireTimes = Set(reminder.alarmFireTimes)
        if alarmEnabled && alarmFireTimes.isEmpty {
            alarmFireTimes = Set([String(format: "%02d:%02d", alarmHour, alarmMinute)])
        }
        let existingChecklist = reminder.checklistItems.sorted { $0.sortOrder < $1.sortOrder }
        checklistItems = existingChecklist.isEmpty
            ? [LureliaReminderChecklistItem(title: "", sortOrder: 0)]
            : existingChecklist
        
        repeatUnit = reminder.repeatUnit
        repeatInterval = reminder.repeatInterval
        repeatWeekdays = Set(reminder.repeatWeekdays)

        if let repeatEndsAt = reminder.repeatEndsAt {
            repeatEnds = true
            self.repeatEndsAt = repeatEndsAt
        }

        // Detail fields
        motivation = reminder.motivation ?? ""
        consequences = reminder.consequences ?? ""
        recoveryPlan = reminder.recoveryPlan ?? ""

        // Location
        locationLabel = reminder.locationLabel ?? ""
        locationAddress = reminder.locationAddress ?? ""
        locationLatitude = reminder.locationLatitude
        locationLongitude = reminder.locationLongitude
    }
    
    private func save() {
        guard canSave else { return }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let reminder: LureliaReminder
        let isCreatingNewReminder = editingReminder == nil
        let existingScheduleKey = editingReminder.map { scheduleKey(for: $0) }
        let newScheduleKey = currentScheduleKey()
        let scheduleDidChange = isCreatingNewReminder || existingScheduleKey != newScheduleKey

        if let editingReminder {
            reminder = editingReminder
        } else {
            reminder = LureliaReminder(
                title: cleanTitle,
                icon: selectedIcon,
                notes: cleanNotes.isEmpty ? nil : cleanNotes,
                category: "",
                kind: .standalone,
                scheduledDate: scheduledDate,
                repeatUnit: repeatUnit,
                repeatInterval: repeatInterval
            )
        }

        reminder.title = cleanTitle
        reminder.icon = selectedIcon
        reminder.notes = cleanNotes.isEmpty ? nil : cleanNotes
        reminder.category = ""
        reminder.kind = .standalone
        // Persist the user-selected color. Only write if the user actually
        // picked one, so we never clobber an existing reminder's color with
        // a blank in edit mode when the picker wasn't touched.
        if let picked = selectedColor, let hex = picked.toHex() {
            reminder.colorHex = hex
        }
        reminder.scheduledDate = scheduledDate
        reminder.repeatUnit = repeatUnit
        reminder.repeatInterval = max(1, repeatInterval)
        reminder.repeatWeekdays = Array(repeatWeekdays).sorted()
        reminder.repeatEndsAt = repeatEnds ? repeatEndsAt : nil
        reminder.additionalFireTimes = additionalFireTimes

        let selectedAlarmTimes = normalizedSelectedAlarmTimes()
        reminder.alarmEnabled = alarmEnabled
        reminder.alarmDate = alarmEnabled ? alarmDateForSelectedTimes(selectedAlarmTimes) : nil
        reminder.alarmSoundName = alarmEnabled ? alarmSoundName : nil
        reminder.alarmFireTimes = alarmEnabled ? selectedAlarmTimes : []
        reminder.keepAlarmIdentifiers(for: alarmEnabled ? selectedAlarmTimes : [])
        if alarmEnabled && reminder.alarmID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            reminder.alarmID = UUID().uuidString
        }

        // Detail fields
        reminder.purpose = nil
        reminder.importance = nil
        reminder.reminderOutcome = nil
        reminder.motivation = motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : motivation.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.consequences = consequences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : consequences.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.recoveryPlan = recoveryPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : recoveryPlan.trimmingCharacters(in: .whitespacesAndNewlines)

        // Location
        reminder.locationLabel = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.locationAddress = locationAddress.isEmpty ? nil : locationAddress
        reminder.locationLatitude = locationLatitude
        reminder.locationLongitude = locationLongitude

        reminder.checklistItems = nonEmptyChecklistItems.enumerated().map { index, item in
            LureliaReminderChecklistItem(
                id: item.id,
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                isCompleted: item.isCompleted,
                sortOrder: index,
                createdAt: item.createdAt,
                updatedAt: Date()
            )
        }
        reminder.levels = []
        if scheduleDidChange {
            reminder.nextFireAt = nextUnfiredDateFromCurrentForm()
            if alarmEnabled && !isEditing {
                reminder.alarmDate = alarmDateForSelectedTimes(selectedAlarmTimes)
            }
        }
        reminder.isEnabled = true
        reminder.updatedAt = Date()

        // Only rewrite the configured primary fire time when creating or changing the schedule.
        if isCreatingNewReminder || scheduleDidChange || reminder.primaryHour == -1 {
            reminder.primaryHour = reminderHour
            reminder.primaryMinute = reminderMinute
        }

        // Store all fire times as HH:mm strings — single source of truth
        var allTimes: [String] = [String(format: "%02d:%02d", reminderHour, reminderMinute)]
        for ft in additionalFireTimes {
            allTimes.append(String(format: "%02d:%02d", ft.hour, ft.minute))
        }
        reminder.timesOfDay = Array(Set(allTimes)).sorted()

        let descriptor = FetchDescriptor<LureliaReminder>()
        let existingReminders = (try? modelContext.fetch(descriptor)) ?? []
        let duplicateMatches = existingReminders.filter { existing in
            existing.persistentModelID != reminder.persistentModelID &&
            existing.isDuplicateConfiguration(of: reminder)
        }

        for duplicate in duplicateMatches {
            LureliaNotificationManager.shared.cancelReminder(duplicate)
            modelContext.delete(duplicate)
        }

        if isCreatingNewReminder {
            modelContext.insert(reminder)
        }

        try? modelContext.save()
        if isCreatingNewReminder { onCreated?(reminder) }

        LureliaWidgetReloads.reloadAll()

        Task {
            await LureliaNotificationManager.shared.scheduleReminder(reminder)
            LureliaWidgetReloads.reloadAll()
        }

        dismiss()
    }

    private func currentScheduleKey() -> String {
        let normalizedAdditionalTimes = additionalFireTimes
            .map { String(format: "%02d:%02d", $0.hour, $0.minute) }
            .sorted()
            .joined(separator: ",")

        let normalizedWeekdays = repeatWeekdays
            .sorted()
            .map(String.init)
            .joined(separator: ",")

        let endDateKey = repeatEnds
            ? String(Int(repeatEndsAt.timeIntervalSince1970))
            : "none"

        return [
            String(Int(scheduledDate.timeIntervalSince1970)),
            String(format: "%02d:%02d", reminderHour, reminderMinute),
            normalizedAdditionalTimes,
            repeatUnit.rawValue,
            String(max(1, repeatInterval)),
            normalizedWeekdays,
            endDateKey
        ].joined(separator: "|")
    }

    private func nextUnfiredDateFromCurrentForm(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let sortedFireTimes = allCurrentFireTimes()

        for fireTime in sortedFireTimes {
            var components = calendar.dateComponents([.year, .month, .day], from: reminderDate)
            components.hour = fireTime.hour
            components.minute = fireTime.minute
            components.second = 0

            guard let candidate = calendar.date(from: components) else { continue }

            if candidate > now {
                return candidate
            }
        }

        if repeatUnit != .none,
           let nextRepeatDate = nextRepeatDateAfterCurrentReminderDate() {
            let firstFireTime = sortedFireTimes.first ?? (hour: reminderHour, minute: reminderMinute)
            var components = calendar.dateComponents([.year, .month, .day], from: nextRepeatDate)
            components.hour = firstFireTime.hour
            components.minute = firstFireTime.minute
            components.second = 0

            return calendar.date(from: components) ?? scheduledDate
        }

        return scheduledDate
    }

    private func allCurrentFireTimes() -> [(hour: Int, minute: Int)] {
        var fireTimes: [(hour: Int, minute: Int)] = [
            (hour: reminderHour, minute: reminderMinute)
        ]

        fireTimes.append(contentsOf: additionalFireTimes.map { additionalTime in
            (hour: additionalTime.hour, minute: additionalTime.minute)
        })

        return fireTimes
            .reduce(into: [(hour: Int, minute: Int)]()) { uniqueTimes, fireTime in
                guard !uniqueTimes.contains(where: { $0.hour == fireTime.hour && $0.minute == fireTime.minute }) else { return }
                uniqueTimes.append(fireTime)
            }
            .sorted { lhs, rhs in
                if lhs.hour == rhs.hour {
                    return lhs.minute < rhs.minute
                }
                return lhs.hour < rhs.hour
            }
    }

    private func normalizedSelectedAlarmTimes() -> [String] {
        let availableTimes = currentAlarmFireTimes
        let selectedTimes = availableTimes.filter { alarmFireTimes.contains($0) }

        if !selectedTimes.isEmpty {
            return selectedTimes
        }

        return alarmEnabled ? Array(availableTimes.prefix(1)) : []
    }

    private func alarmDateForSelectedTimes(_ selectedTimes: [String]) -> Date? {
        guard let firstTime = selectedTimes.first else { return nil }
        let parts = firstTime.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return alarmScheduledDate
        }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: reminderDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)
    }

    private func nextRepeatDateAfterCurrentReminderDate() -> Date? {
        let calendar = Calendar.current
        let interval = max(1, repeatInterval)

        switch repeatUnit {
        case .none:
            return nil
        case .minutes, .hours:
            return calendar.date(byAdding: .day, value: 1, to: reminderDate)
        case .days:
            return calendar.date(byAdding: .day, value: interval, to: reminderDate)
        case .weeks:
            if !repeatWeekdays.isEmpty {
                let todayStart = calendar.startOfDay(for: reminderDate)

                for dayOffset in 1...14 {
                    guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else { continue }
                    let weekday = calendar.component(.weekday, from: candidate)

                    if repeatWeekdays.contains(weekday) {
                        return candidate
                    }
                }
            }

            return calendar.date(byAdding: .weekOfYear, value: interval, to: reminderDate)
        case .months:
            return calendar.date(byAdding: .month, value: interval, to: reminderDate)
        case .years:
            return calendar.date(byAdding: .year, value: interval, to: reminderDate)
        }
    }

    private func scheduleKey(for reminder: LureliaReminder) -> String {
        let primaryHour = reminder.primaryHour != -1
            ? reminder.primaryHour
            : Calendar.current.component(.hour, from: reminder.scheduledDate)

        let primaryMinute = reminder.primaryHour != -1
            ? reminder.primaryMinute
            : Calendar.current.component(.minute, from: reminder.scheduledDate)

        let normalizedAdditionalTimes = reminder.additionalFireTimes
            .map { String(format: "%02d:%02d", $0.hour, $0.minute) }
            .sorted()
            .joined(separator: ",")

        let normalizedWeekdays = reminder.repeatWeekdays
            .sorted()
            .map(String.init)
            .joined(separator: ",")

        let endDateKey = reminder.repeatEndsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"

        return [
            String(Int(reminder.scheduledDate.timeIntervalSince1970)),
            String(format: "%02d:%02d", primaryHour, primaryMinute),
            normalizedAdditionalTimes,
            reminder.repeatUnit.rawValue,
            String(max(1, reminder.repeatInterval)),
            normalizedWeekdays,
            endDateKey
        ].joined(separator: "|")
    }
}

struct LureliaReminderAlarmSound: Identifiable, Hashable {
    let fileName: String

    var id: String { fileName }

    var displayName: String {
        if let mappedName = Self.displayNames[fileName] {
            return mappedName
        }

        return URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    static let displayNames: [String: String] = [
        "bythesea.m4a": "By The Sea",
        "circuit.m4a": "Circuit",
        "constellation.m4a": "Constellation",
        "crystals.m4a": "Crystals",
        "nightowl.m4a": "Night Owl",
        "radiate.m4a": "Radiate",
        "silk.m4a": "Silk",
        "summit.m4a": "Summit",
        "uplift.m4a": "Uplift",
        "waves.m4a": "Waves"
    ]

    static let fallbackSounds: [LureliaReminderAlarmSound] = [
        "bythesea.m4a",
        "circuit.m4a",
        "constellation.m4a",
        "crystals.m4a",
        "nightowl.m4a",
        "radiate.m4a",
        "silk.m4a",
        "summit.m4a",
        "uplift.m4a",
        "waves.m4a"
    ].map { LureliaReminderAlarmSound(fileName: $0) }

    static var availableSounds: [LureliaReminderAlarmSound] {
        let nestedSounds = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Sounds") ?? []
        let rootSounds = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil) ?? []
        let bundleSounds = (nestedSounds + rootSounds)
            .filter { ["m4a", "mp3", "wav", "caf", "aiff"].contains($0.pathExtension.lowercased()) }
            .map { LureliaReminderAlarmSound(fileName: $0.lastPathComponent) }
            .reduce(into: [String: LureliaReminderAlarmSound]()) { soundsByName, sound in
                soundsByName[sound.fileName] = sound
            }
            .values
            .sorted { $0.displayName < $1.displayName }

        return bundleSounds.isEmpty ? fallbackSounds : bundleSounds
    }

    static var defaultSound: LureliaReminderAlarmSound {
        sound(named: "radiate.m4a")
    }

    static func sound(named fileName: String) -> LureliaReminderAlarmSound {
        availableSounds.first { $0.fileName == fileName }
            ?? fallbackSounds.first { $0.fileName == fileName }
            ?? fallbackSounds[0]
    }

    var bundleURL: URL? {
        let resourceName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let resourceExtension = URL(fileURLWithPath: fileName).pathExtension

        return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
            ?? Bundle.main.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Sounds")
    }
}

struct LureliaReminderAlarmConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Binding var alarmEnabled: Bool
    let availableFireTimes: [String]
    @Binding var selectedFireTimes: Set<String>
    @Binding var alarmSoundName: String
    var fireTimesTitle: String = "Reminder Times"
    var fireTimeSubtitle: String = "Alarm at this reminder time."
    /// Optional accent tint. Reminder editors pass their selected reminder
    /// color; other callers fall back to the themed primary action color.
    var tint: Color? = nil

    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewingSoundName: String?

    private var reminderTint: Color {
        tint ?? theme.palette.primaryAction
    }

    private var sounds: [LureliaReminderAlarmSound] {
        LureliaReminderAlarmSound.availableSounds
    }

    private var selectedCountText: String {
        let count = selectedFireTimes.intersection(Set(availableFireTimes)).count
        return count == 1 ? "1 alarm time" : "\(count) alarm times"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        sheetHeader
                        alarmHeader

                        alarmCard(fireTimesTitle) {
                            VStack(spacing: 10) {
                                ForEach(availableFireTimes, id: \.self) { fireTime in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(displayTime(fireTime))
                                                .font(.system(size: 14, weight: .black, design: .rounded))
                                                .foregroundStyle(theme.palette.textPrimary)

                                            Text(fireTimeSubtitle)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(theme.palette.textSecondary)
                                        }

                                        Spacer(minLength: 8)

                                        LureliaSlidingIconToggle(
                                            isOn: selectedBinding(for: fireTime),
                                            iconName: "clockfill",
                                            accentColor: reminderTint,
                                            accessibilityLabel: "Alarm at \(displayTime(fireTime))",
                                            usesIconMaterial: true
                                        )
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 11)
                                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(reminderTint, lineWidth: 1.3)
                                    }
                                }
                            }
                        }

                        alarmCard("Sound") {
                            VStack(spacing: 10) {
                                ForEach(sounds) { sound in
                                    HStack(spacing: 12) {
                                        Button {
                                            alarmSoundName = sound.fileName
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image("lovemusicnote")
                                                    .renderingMode(.template)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 21, height: 21)
                                                    .foregroundStyle(reminderTint)
                                                    .bubblyIconMaterial(tint: reminderTint)

                                                Text(sound.displayName)
                                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                                    .foregroundStyle(theme.palette.textPrimary)

                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .buttonStyle(.plain)

                                        Button {
                                            toggleSoundPreview(sound)
                                        } label: {
                                            Image(previewingSoundName == sound.fileName ? "stopwavy" : "playwavy")
                                                .renderingMode(.template)
                                                .resizable()
                                                .scaledToFit()
                                                .foregroundStyle(reminderTint)
                                                .bubblyIconMaterial(tint: reminderTint)
                                                .frame(width: 30, height: 30)
                                                .frame(width: 38, height: 38)
                                                .contentShape(Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(previewingSoundName == sound.fileName ? "Stop preview" : "Preview \(sound.displayName)")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 11)
                                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(reminderTint, lineWidth: alarmSoundName == sound.fileName ? 1.7 : 1.2)
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .onDisappear {
                stopSoundPreview()
            }
            .onAppear {
                if alarmEnabled && selectedFireTimes.intersection(Set(availableFireTimes)).isEmpty,
                   let firstFireTime = availableFireTimes.first {
                    selectedFireTimes = [firstFireTime]
                }
            }
        }
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            alarmHeaderButton("Off") {
                alarmEnabled = false
                dismiss()
            }

            Text("Alarm")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .frame(maxWidth: .infinity)

            alarmHeaderButton("Done") {
                dismiss()
            }
        }
    }

    private func alarmHeaderButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    BubblyIconMaterial(tint: reminderTint)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var alarmHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.42))

                Circle()
                    .strokeBorder(reminderTint, lineWidth: 1.4)
                    .bubblyIconMaterial(tint: reminderTint)

                Image("petalarm")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(reminderTint)
                    .bubblyIconMaterial(tint: reminderTint)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                Text(selectedCountText)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text(LureliaReminderAlarmSound.sound(named: alarmSoundName).displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer()
        }
        .padding(18)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(reminderTint, lineWidth: 1.4)
        )
    }

    private func selectedBinding(for fireTime: String) -> Binding<Bool> {
        Binding(
            get: { selectedFireTimes.contains(fireTime) },
            set: { isSelected in
                if isSelected {
                    selectedFireTimes.insert(fireTime)
                } else {
                    selectedFireTimes.remove(fireTime)
                }
            }
        )
    }

    private func displayTime(_ fireTime: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let outputFormatter = DateFormatter()
        outputFormatter.timeStyle = .short

        guard let date = formatter.date(from: fireTime) else { return fireTime }
        return outputFormatter.string(from: date)
    }

    private func toggleSoundPreview(_ sound: LureliaReminderAlarmSound) {
        if previewingSoundName == sound.fileName {
            stopSoundPreview()
            return
        }

        stopSoundPreview()

        guard let soundURL = sound.bundleURL else {
            print("⚠️ [Lurelia] Missing alarm preview sound: \(sound.fileName)")
            return
        }

        do {
            previewPlayer = try AVAudioPlayer(contentsOf: soundURL)
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()
            previewingSoundName = sound.fileName
        } catch {
            print("⚠️ [Lurelia] Could not preview alarm sound \(sound.fileName): \(error)")
        }
    }

    private func stopSoundPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingSoundName = nil
    }

    private func alarmCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

// MARK: - CLPlacemark Address Helper

extension CLPlacemark {
    var formattedAddress: String? {
        let parts = [
            subThoroughfare,
            thoroughfare,
            locality,
            administrativeArea,
            postalCode
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
