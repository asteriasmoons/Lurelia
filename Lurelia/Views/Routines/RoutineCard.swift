//
//  RoutineCard.swift
//  Lurelia
//

import SwiftUI

struct RoutineCard: View {
    let routine: LureliaRoutine
    let onRun: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onEdit: () -> Void
    var fixedWidth: CGFloat? = nil

    static let cardHeight: CGFloat = 164

    private var isActive: Bool {
        routine.activeRun != nil
    }

    private var isPaused: Bool {
        routine.activeRun?.isPaused == true
    }

    private var routineTint: Color {
        Color(lureliaHex: routine.colorHex)
    }

    private var scheduleLabel: String {
        guard routine.scheduleEnabled && !routine.scheduledDays.isEmpty else {
            return "Unscheduled"
        }

        let symbols = Calendar.current.shortWeekdaySymbols

        let days = routine.scheduledDays
            .sorted()
            .compactMap { $0 >= 1 && $0 <= 7 ? symbols[$0 - 1] : nil }
            .joined(separator: ", ")

        return "\(days)  \(routine.formattedTimeRange)"
    }

    private var taskCount: Int {
        (routine.tasks ?? []).count
    }

    private var phaseCount: Int {
        routine.phasesEnabled ? routine.sortedPhases.count : 0
    }

    private var scheduleStatusText: String {
        routine.scheduleEnabled && !routine.scheduledDays.isEmpty ? "Scheduled" : "Unscheduled"
    }

    private var weekdayPillText: String {
        guard routine.scheduleEnabled && !routine.scheduledDays.isEmpty else {
            return "None"
        }

        let symbols = Calendar.current.shortWeekdaySymbols

        return routine.scheduledDays
            .sorted()
            .compactMap { weekday in
                guard weekday >= 1 && weekday <= 7 else { return nil }
                return String(symbols[weekday - 1].prefix(3))
            }
            .joined(separator: " ")
    }

    private var taskPhaseText: String {
        let taskWord = taskCount == 1 ? "Task" : "Tasks"
        let phaseWord = phaseCount == 1 ? "Phase" : "Phases"

        return "\(taskCount) \(taskWord) • \(phaseCount) \(phaseWord)"
    }

    private var weekdayValuesForDisplay: [Int] {
        let days: [Int]

        if routine.phasesEnabled {
            days = Array(
                Set(
                    routine.sortedPhases
                        .filter { $0.scheduleEnabled }
                        .flatMap { $0.scheduledDays }
                )
            )
            .sorted()
        } else {
            days = routine.scheduleEnabled ? routine.scheduledDays.sorted() : []
        }

        return days
            .filter { (1...7).contains($0) }
            .sorted()
    }

    private var timeDisplayText: String {
        "\(routine.formattedStartTime) – \(routine.formattedEndTime)"
    }

    private var centeredTaskPhaseText: String {
        if isActive {
            return "\(taskPhaseText) • \(isPaused ? "Paused" : "In progress")"
        }

        return taskPhaseText
    }

    var body: some View {
        VStack(spacing: 1) {
            routineIconBadge

            Text(routine.name)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(centeredTaskPhaseText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LColors.textSecondary.opacity(0.9))
                .lineLimit(1)
                .multilineTextAlignment(.center)

            scheduledDaysRow

            Text(timeDisplayText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LColors.textSecondary.opacity(0.85))
                .lineLimit(1)
                .multilineTextAlignment(.center)

            Color.clear
                .frame(height: 2)
                .allowsHitTesting(false)

            bottomControlRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: fixedWidth, height: Self.cardHeight, alignment: .center)
        .background {
            BubblyCardMaterial(
                tint: routineTint,
                cornerRadius: 22
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: routineTint.opacity(0.13), radius: 14, x: 0, y: 7)
    }

    private var routineIconBadge: some View {
        LureliaIconView(iconId: routine.icon, size: 30)
            .foregroundStyle(routineTint)
            .bubblyIconMaterial(tint: routineTint)
            .shadow(color: Color.black.opacity(0.50), radius: 3.5, x: 0, y: 2)
            .frame(width: 36.5, height: 36.5)
    }

    private var bottomControlRow: some View {
        HStack(spacing: 4) {
            if isActive {
                activeRunButton
            } else {
                inactiveRunButton
            }

            settingsButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var activeRunButton: some View {
        if isPaused {
            Button {
                onRun()
            } label: {
                routineControlIcon(
                    named: "playwavy",
                    iconSize: 17,
                    buttonSize: 26,
                    foreground: LColors.textPrimary,
                    background: routineTint.opacity(0.32),
                    border: routineTint.opacity(0.38)
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                onPause()
            } label: {
                routineControlIcon(
                    named: "pausewavy",
                    iconSize: 17,
                    buttonSize: 26,
                    foreground: LColors.textPrimary,
                    background: routineTint.opacity(0.28),
                    border: routineTint.opacity(0.36)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var inactiveRunButton: some View {
        Button {
            onRun()
        } label: {
            routineControlIcon(
                named: "playwavy",
                iconSize: 17,
                buttonSize: 26,
                foreground: LColors.textPrimary,
                background: routineTint.opacity(0.32),
                border: routineTint.opacity(0.38)
            )
        }
        .buttonStyle(.plain)
    }

    private var settingsButton: some View {
        Button {
            onEdit()
        } label: {
            routineControlIcon(
                named: "settings",
                iconSize: 14,
                buttonSize: 26,
                foreground: LColors.textSecondary,
                background: LColors.glassSurface,
                border: LColors.glassBorder
            )
        }
        .buttonStyle(.plain)
    }

    private func routineControlIcon(
        named imageName: String,
        iconSize: CGFloat,
        buttonSize: CGFloat,
        foreground: Color,
        background: Color,
        border: Color
    ) -> some View {
        Image(imageName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(foreground)
            .frame(width: buttonSize, height: buttonSize)
            .background(background, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(border, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var scheduledDaysRow: some View {
        let days = weekdayValuesForDisplay

        if days.isEmpty {
            Text("No Schedule")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LColors.textSecondary.opacity(0.85))
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { weekday in
                    Text(shortWeekdayLabel(for: weekday))
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(routineTint)
                        .frame(width: 16, height: 16)
                        .background(routineTint.opacity(0.14), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(routineTint.opacity(0.65), lineWidth: 1)
                        }
                }
            }
        }
    }

    private func shortWeekdayLabel(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "--" }
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }

    private func routineInfoPill(title: String, subtitle: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(subtitle.uppercased())
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textSecondary.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            routineTint.opacity(0.18),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(routineTint.opacity(0.45), lineWidth: 1)
        }
    }
}
