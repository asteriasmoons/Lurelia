//
//  HabitsView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import UIKit
import Combine
import WidgetKit

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(sort: \LureliaHabit.createdAt)
    private var habits: [LureliaHabit]

    @State private var habitColorSelection: HabitEditorLaunchRequest?
    @State private var queuedHabitEditor: HabitEditorLaunchRequest?
    @State private var habitEditor: HabitEditorLaunchRequest?
    @State private var editingHabit: LureliaHabit? = nil
    @State private var historyHabit: LureliaHabit? = nil

    private var activeHabits: [LureliaHabit] { habits.filter { !$0.isArchived } }
    private var archivedHabits: [LureliaHabit] { habits.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
        ZStack(alignment: .bottomTrailing) {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // MARK: - Header

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Habits")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Text("Build consistency, one day at a time.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        Spacer()

                        Button { beginNewHabit() } label: {
                            Image("addwavy")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundStyle(theme.palette.indicators)
                                .bubblyIconMaterial(tint: theme.palette.indicators)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // MARK: - Empty State

                    if habits.isEmpty {
                        LureliaHabitsEmptyState {
                            beginNewHabit()
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 32)
                    } else {

                        // MARK: - Active Habits

                        if !activeHabits.isEmpty {
                            VStack(spacing: 14) {
                                ForEach(activeHabits) { habit in
                                    NavigationLink(value: habit.id) {
                                    LureliaHabitCard(
                                        habit: habit,
                                        onEdit: { editingHabit = habit },
                                        onHistory: { historyHabit = habit }
                                    )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        // MARK: - Archived

                        if !archivedHabits.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ARCHIVED")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .tracking(0.8)
                                    .padding(.horizontal, 24)

                                VStack(spacing: 14) {
                                    ForEach(archivedHabits) { habit in
                                        NavigationLink(value: habit.id) {
                                        LureliaHabitCard(
                                            habit: habit,
                                            onEdit: { editingHabit = habit },
                                            onHistory: { historyHabit = habit }
                                        )
                                        .opacity(0.6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }

                    Spacer().frame(height: 110)
                }
            }
        }
        .sheet(item: $habitColorSelection, onDismiss: presentQueuedHabitEditor) { request in
            HabitColorSelectionSheet(initialColor: request.color) { color in
                queuedHabitEditor = HabitEditorLaunchRequest(
                    habit: nil,
                    color: color
                )
            }
        }
        .sheet(item: $habitEditor) { request in
            LureliaHabitFormSheet(
                habit: request.habit,
                initialColor: request.color
            ) {
                habitEditor = nil
            }
        }
        .fullScreenCover(item: $editingHabit) { habit in
            LureliaHabitFormSheet(habit: habit) { editingHabit = nil }
        }
        .overlay {
            if let habit = historyHabit {
                LureliaHabitHistoryOverlay(habit: habit) {
                    historyHabit = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(80)
            }
        }
        .navigationDestination(for: UUID.self) { habitID in
            if let habit = habits.first(where: { $0.id == habitID }) {
                HabitBlueprintDetailView(habit: habit)
            }
        }
        }
    }

    private func beginNewHabit() {
        queuedHabitEditor = nil
        habitColorSelection = HabitEditorLaunchRequest(
            habit: nil,
            color: theme.palette.primaryAction
        )
    }

    private func presentQueuedHabitEditor() {
        guard let queuedHabitEditor else { return }
        self.queuedHabitEditor = nil
        habitEditor = queuedHabitEditor
    }
}

// MARK: - Empty State

private struct LureliaHabitsEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image("flame")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .foregroundStyle(LGradients.header)

            VStack(spacing: 8) {
                Text("No Habits Yet")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Start tracking a daily habit to build streaks and stay consistent over time.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button {
                onCreate()
            } label: {
                Text("Create Habit")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LGradients.header)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

// MARK: - Schedule Form

struct LureliaHabitIconPreview: View {
    let iconName: String
    /// Optional single-color tint. When `nil`, uses the neutral glass sheet style.
    var tint: Color? = nil
    var usesDarkCardTreatment = false

    var body: some View {
        ZStack {
            Circle()
                .fill(fillStyle)
                .frame(width: 42, height: 42)

            Circle()
                .strokeBorder(strokeStyle, lineWidth: 2.5)
                .frame(width: 42, height: 42)
                .bubblyIconMaterial(
                    tint: tint ?? .white,
                    isEnabled: usesDarkCardTreatment
                )

            Group {
                if UIImage(named: iconName) != nil {
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: iconName)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(.white)
            .bubblyIconMaterial(tint: .white, isEnabled: usesDarkCardTreatment)
        }
    }

    private var fillStyle: AnyShapeStyle {
        if usesDarkCardTreatment {
            return AnyShapeStyle(Color.black.opacity(0.34))
        }

        if let tint {
            return AnyShapeStyle(tint.opacity(0.22))
        }
        return AnyShapeStyle(LColors.neutralGlassHighlight.opacity(0.08))
    }

    private var strokeStyle: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint)
        }
        return AnyShapeStyle(LColors.neutralGlassHighlight.opacity(0.28))
    }
}

struct LureliaHabitIconPickerButton: View {
    @Environment(\.appTheme) private var theme

    @Binding var iconName: String
    var tint: Color? = nil
    let action: () -> Void

    private var resolvedTint: Color {
        tint ?? theme.palette.primaryAction
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.34))

                    Circle()
                        .strokeBorder(resolvedTint, lineWidth: 1)
                        .bubblyIconMaterial(tint: resolvedTint)

                    Group {
                        if UIImage(named: iconName) != nil {
                            Image(iconName)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: iconName)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(width: 22, height: 22)
                    .foregroundStyle(resolvedTint)
                    .bubblyIconMaterial(tint: resolvedTint)
                }
                .frame(width: 46, height: 46)

                Text("Choose Icon")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Spacer()

                Image("chevright")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
                    .foregroundStyle(resolvedTint)
                    .bubblyIconMaterial(tint: resolvedTint)
            }
            .padding(14)
            .background(
                theme.palette.surface,
                in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                    .strokeBorder(resolvedTint, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HabitScheduleForm: View {
    @Environment(\.appTheme) private var theme

    @Binding var activeWeekdays: Set<Int>
    @Binding var daysPerWeek: Int
    @Binding var timesPerDay: Int
    var hideTimesPerDay: Bool
    var tint: Color? = nil
    var onTimesPerDayChange: (Int) -> Void

    private var resolvedTint: Color {
        tint ?? theme.palette.primaryAction
    }

    private let weekdays: [(value: Int, label: String)] = [
        (1, "Sun"),
        (2, "Mon"),
        (3, "Tue"),
        (4, "Wed"),
        (5, "Thu"),
        (6, "Fri"),
        (7, "Sat")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Active weekdays")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Spacer()

                Text("\(daysPerWeek) day\(daysPerWeek == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(resolvedTint)
            }

            HStack(spacing: 6) {
                ForEach(weekdays, id: \.value) { weekday in
                    weekdayButton(weekday)
                }
            }

            if !hideTimesPerDay {
                LureliaHabitTintedStepper(
                    title: "Times per day",
                    value: $timesPerDay,
                    range: 1...20,
                    tint: resolvedTint,
                    onChange: onTimesPerDayChange
                )
            }
        }
        .onAppear {
            syncDaysPerWeek()
        }
        .onChange(of: activeWeekdays) { _, _ in
            syncDaysPerWeek()
        }
    }

    private func weekdayButton(_ weekday: (value: Int, label: String)) -> some View {
        let selected = activeWeekdays.contains(weekday.value)

        return Button {
            toggleWeekday(weekday.value)
        } label: {
            Text(weekday.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.black : theme.palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    if selected {
                        BubblyIconMaterial(tint: resolvedTint)
                            .clipShape(Capsule())
                    } else {
                        Capsule()
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            selected ? resolvedTint : theme.palette.textPrimary.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func toggleWeekday(_ weekday: Int) {
        if activeWeekdays.contains(weekday) {
            guard activeWeekdays.count > 1 else { return }
            activeWeekdays.remove(weekday)
        } else {
            activeWeekdays.insert(weekday)
        }

        syncDaysPerWeek()
    }

    private func syncDaysPerWeek() {
        if activeWeekdays.isEmpty {
            activeWeekdays = [1, 2, 3, 4, 5, 6, 7]
        }
        daysPerWeek = activeWeekdays.count
    }
}

struct LureliaHabitTintedStepper: View {
    @Environment(\.appTheme) private var theme

    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    let tint: Color
    var onChange: (Int) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)

            Spacer(minLength: 10)

            counterButton(icon: "minuswavy", enabled: value > range.lowerBound) {
                updateValue(value - 1)
            }

            Text("\(value)")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 42)

            counterButton(icon: "addwavy", enabled: value < range.upperBound) {
                updateValue(value + 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            theme.palette.surface,
            in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                .strokeBorder(tint, lineWidth: 1)
        }
    }

    private func counterButton(
        icon: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 27)
                .foregroundStyle(tint)
                .bubblyIconMaterial(tint: tint)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.30)
    }

    private func updateValue(_ newValue: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, newValue))
        guard clamped != value else { return }
        value = clamped
        onChange(clamped)
    }
}

// MARK: - Habit Notification Kind

enum LureliaHabitNotificationKind: String, CaseIterable {
    case daily         = "Daily"
    case everyXHours   = "Every XH"
    case everyXMinutes = "Every XM"
}

// MARK: - Shared Notification Form

struct HabitNotificationForm: View {
    @Environment(\.appTheme) private var theme

    @Binding var notificationEnabled: Bool
    @Binding var notifKind: LureliaHabitNotificationKind
    @Binding var startDate: Date
    @Binding var reminderTimes: [Date]
    @Binding var intervalValue: Int
    @Binding var intervalValueText: String
    @Binding var intervalWindowStart: Date
    @Binding var intervalWindowEnd: Date
    var timesPerDay: Int
    var iconName: String = "flame"
    var daysPerWeek: Int
    var tint: Color? = nil

    private var resolvedTint: Color { tint ?? theme.palette.primaryAction }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notification")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Text("Send reminders for this habit")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                }

                Spacer(minLength: 8)

                LureliaSlidingIconToggle(
                    isOn: $notificationEnabled,
                    iconName: "bellfill",
                    accentColor: resolvedTint,
                    accessibilityLabel: "Notification",
                    usesIconMaterial: true
                )
            }
            .padding(14)
            .background(
                theme.palette.surface,
                in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                    .strokeBorder(resolvedTint, lineWidth: 1)
            }

            if notificationEnabled {
                VStack(alignment: .leading, spacing: 7) {
                    controlLabel("Start date")

                    LureliaGradientDateDrumPicker(
                        date: $startDate,
                        tint: resolvedTint,
                        usesCardMaterial: true,
                        usesDarkTypography: true
                    )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LureliaHabitNotificationKind.allCases, id: \.self) { k in
                            notificationKindButton(k)
                        }
                    }
                }

                switch notifKind {
                case .daily:
                    dailyControls
                case .everyXHours:
                    intervalControls(unit: "hours")
                case .everyXMinutes:
                    intervalControls(unit: "minutes")
                }
            }
        }
    }

    @ViewBuilder
    private var dailyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(reminderTimes.indices), id: \.self) { idx in
                VStack(alignment: .leading, spacing: 6) {
                    if reminderTimes.count > 1 {
                        controlLabel("Time \(idx + 1)")
                    }

                    LureliaTintedTimeDrumPicker(
                        hour: hourBinding(for: idx),
                        minute: minuteBinding(for: idx),
                        tint: resolvedTint,
                        usesCardMaterial: true,
                        usesDarkTypography: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func intervalControls(unit: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LureliaHabitTintedStepper(
                title: "Every \(unit)",
                value: intervalValueBinding,
                range: 1...999,
                tint: resolvedTint
            )

            VStack(alignment: .leading, spacing: 6) {
                controlLabel("From")
                LureliaTintedTimeDrumPicker(
                    hour: windowStartHourBinding,
                    minute: windowStartMinuteBinding,
                    tint: resolvedTint,
                    usesCardMaterial: true,
                    usesDarkTypography: true
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                controlLabel("Until")
                LureliaTintedTimeDrumPicker(
                    hour: windowEndHourBinding,
                    minute: windowEndMinuteBinding,
                    tint: resolvedTint,
                    usesCardMaterial: true,
                    usesDarkTypography: true
                )
            }
        }
    }

    private func notificationKindButton(_ kind: LureliaHabitNotificationKind) -> some View {
        let selected = notifKind == kind

        return Button {
            notifKind = kind
        } label: {
            Text(kind.rawValue.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.black : theme.palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background {
                    if selected {
                        BubblyIconMaterial(tint: resolvedTint)
                            .clipShape(Capsule())
                    } else {
                        Capsule()
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            selected ? resolvedTint : theme.palette.textPrimary.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func controlLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.palette.textSecondary)
            .tracking(0.6)
    }

    private var intervalValueBinding: Binding<Int> {
        Binding(
            get: { intervalValue },
            set: { newValue in
                intervalValue = newValue
                intervalValueText = "\(newValue)"
            }
        )
    }

    private func hourBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: reminderTimes.indices.contains(index) ? reminderTimes[index] : Date()) },
            set: { newHour in
                guard reminderTimes.indices.contains(index) else { return }
                var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderTimes[index])
                c.hour = newHour; c.second = 0
                if let d = Calendar.current.date(from: c) { reminderTimes[index] = d }
            }
        )
    }

    private func minuteBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: reminderTimes.indices.contains(index) ? reminderTimes[index] : Date()) },
            set: { newMinute in
                guard reminderTimes.indices.contains(index) else { return }
                var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderTimes[index])
                c.minute = newMinute; c.second = 0
                if let d = Calendar.current.date(from: c) { reminderTimes[index] = d }
            }
        )
    }

    private var windowStartHourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: intervalWindowStart) },
            set: { newHour in
                var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: intervalWindowStart)
                c.hour = newHour; c.second = 0
                if let d = Calendar.current.date(from: c) { intervalWindowStart = d }
            }
        )
    }

    private var windowStartMinuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: intervalWindowStart) },
            set: { newMinute in
                var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: intervalWindowStart)
                c.minute = newMinute; c.second = 0
                if let d = Calendar.current.date(from: c) { intervalWindowStart = d }
            }
        )
    }

    private var windowEndHourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: intervalWindowEnd) },
            set: { newHour in
                var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: intervalWindowEnd)
                c.hour = newHour; c.second = 0
                if let d = Calendar.current.date(from: c) { intervalWindowEnd = d }
            }
        )
    }

    private var windowEndMinuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: intervalWindowEnd) },
            set: { newMinute in
                var c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: intervalWindowEnd)
                c.minute = newMinute; c.second = 0
                if let d = Calendar.current.date(from: c) { intervalWindowEnd = d }
            }
        )
    }

}

// MARK: - Habit Pill Row (wrapping)

private struct HabitPillRow: View {
    let pills: [HabitPillItem]

    var body: some View {
        FlexibleView(data: pills, spacing: 4, alignment: .leading) { pill in
            pill.view
        }
    }
}

private struct HabitPillItem: Identifiable, Hashable {
    let id: String
    let label: String
    let isGradient: Bool
    let r: Double
    let g: Double
    let b: Double
    let alpha: Double

    init(label: String, isGradient: Bool, r: Double = 1, g: Double = 1, b: Double = 1, alpha: Double = 1) {
        self.id = label
        self.label = label
        self.isGradient = isGradient
        self.r = r; self.g = g; self.b = b; self.alpha = alpha
    }

    var color: Color { Color(red: r, green: g, blue: b).opacity(alpha) }

    @ViewBuilder var view: some View {
        if isGradient {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .fixedSize(horizontal: true, vertical: false)
                .background(Capsule().fill(LGradients.header))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        } else {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .fixedSize(horizontal: true, vertical: false)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
        }
    }
}

// MARK: - Flexible Wrapping View

private struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content

    @State private var totalHeight: CGFloat = .zero

    init(
        data: Data,
        spacing: CGFloat = 8,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.spacing = spacing
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            generateContent(in: geometry)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        let items = Array(data)
        let lastItem = items.last

        return ZStack(alignment: Alignment(horizontal: alignment, vertical: .top)) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, spacing)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width - spacing) > geometry.size.width {
                            width = 0
                            height -= dimension.height + spacing
                        }

                        let result = width

                        if item == lastItem {
                            width = 0
                        } else {
                            width -= dimension.width + spacing
                        }

                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height

                        if item == lastItem {
                            height = 0
                        }

                        return result
                    }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        totalHeight = geometry.size.height
                    }
                    .onChange(of: geometry.size.height) { _, newHeight in
                        totalHeight = newHeight
                    }
            }
        )
    }
}
