//
//  RoutineRunView.swift
//  Lurelia
//

import SwiftUI
import SwiftData

private extension View {
    func routineRunTextShadow() -> some View {
        shadow(
            color: Color.black.opacity(0.72),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

struct RoutineRunView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let routine: LureliaRoutine
    
    @State private var run: LureliaRoutineRun? = nil
    @State private var isPausedState: Bool = false
    
    private var routineTint: Color {
        Color(lureliaHex: routine.colorHex)
    }
    
    private var sortedTasks: [LureliaRoutineRunTask] {
        (run?.tasks ?? []).sorted {
            $0.sortOrder < $1.sortOrder
        }
    }
    
    private var progress: Double {
        run?.progress ?? 0
    }
    
    private var completedCount: Int {
        run?.completedCount ?? 0
    }
    
    private var totalCount: Int {
        run?.totalCount ?? 0
    }
    
    private var skippedCount: Int {
        run?.skippedCount ?? 0
    }
    
    private var allDone: Bool {
        run?.allDone ?? false
    }
    
    private var isPaused: Bool { isPausedState }
    
    var body: some View {
        ZStack {
            BubblyTileBackground(tint: routineTint)
            
            VStack(spacing: 0) {
                topHero
                
                progressSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedTasks) { runTask in
                            LureliaRoutineRunTaskRow(
                                runTask: runTask,
                                routineTint: routineTint,
                                onComplete: {
                                    guard let run else { return }
                                    
                                    RoutineManager.shared.completeTask(
                                        runTask,
                                        run: run,
                                        routine: routine
                                    )
                                    
                                    checkAllDone()
                                },
                                onSkip: {
                                    guard let run else { return }
                                    
                                    RoutineManager.shared.skipTask(
                                        runTask,
                                        run: run,
                                        routine: routine
                                    )
                                    
                                    checkAllDone()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped()
                
                if allDone {
                    completionCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .transition(
                            .move(edge: .bottom)
                            .combined(with: .opacity)
                        )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startRun()
        }
    }
}

// MARK: - Hero

extension RoutineRunView {
    
    private var topHero: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(routineTint.opacity(0.18))
                                .frame(width: 68, height: 68)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            LColors.glassBorderStrong,
                                            lineWidth: 1
                                        )
                                )
                            
                            Circle()
                                .fill(routineTint.opacity(0.24))
                                .frame(width: 44, height: 44)
                                .blur(radius: 12)
                            
                            LureliaIconView(
                                iconId: routine.icon,
                                size: 30
                            )
                            .foregroundStyle(routineTint)
                            .bubblyIconMaterial(tint: routineTint)
                            .shadow(
                                color: Color.black.opacity(0.78),
                                radius: 8,
                                x: 0,
                                y: 5
                            )
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(routine.name)
                                .font(
                                    .system(
                                        size: 25,
                                        weight: .black,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(LColors.textPrimary)
                                .routineRunTextShadow()
                                .lineLimit(2)
                            
                            HStack(spacing: 8) {
                                Label(
                                    routine.timeOfDay.rawValue,
                                    systemImage: routine.timeOfDay.icon
                                )
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(routineTint)
                                .routineRunTextShadow()
                                
                                Text("·")
                                    .foregroundStyle(Color.black)
                                    .routineRunTextShadow()
                                
                                Label(
                                    isPaused ? "Paused" : "In Progress",
                                    systemImage: isPaused
                                    ? "pause.fill"
                                    : "play.fill"
                                )
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .semibold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(Color.black)
                                .routineRunTextShadow()
                            }
                        }
                    }
                    
                    HStack(spacing: 10) {
                        statPill(
                            title: "\(completedCount)",
                            subtitle: "Done"
                        )
                        
                        statPill(
                            title: "\(skippedCount)",
                            subtitle: "Skipped"
                        )
                        
                        statPill(
                            title: "\(totalCount)",
                            subtitle: "Total"
                        )
                    }
                }
                
                Spacer()
                
                Button {
                    if allDone {
                        endAndDismiss()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image("chevdown")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.white)
                        .bubblyIconMaterial(tint: .white)
                        .shadow(
                            color: Color.black.opacity(0.78),
                            radius: 5,
                            x: 0,
                            y: 3
                        )
                        .frame(width: 40, height: 40)
                        .background(
                            LColors.glassSurface,
                            in: Circle()
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LColors.glassBorder,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            
            actionBar
        }
        .padding(18)
        .background {
            BubblyCardMaterial(
                tint: routineTint,
                cornerRadius: 28
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: routineTint.opacity(0.16), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }
    
    private var actionBar: some View {
        HStack(spacing: 12) {
            if isPaused {
                Button {
                    guard let run else { return }
                    
                    RoutineManager.shared.resumeRun(
                        run: run,
                        routine: routine
                    )
                    
                    try? modelContext.save()
                    isPausedState = run.isPaused
                } label: {
                    actionButton(
                        title: "Resume",
                        icon: "play.fill",
                        filled: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    guard let run else { return }
                    
                    RoutineManager.shared.pauseRun(
                        run: run,
                        routine: routine
                    )
                    
                    try? modelContext.save()
                    isPausedState = run.isPaused
                } label: {
                    actionButton(
                        title: "Pause",
                        icon: "pause.fill",
                        filled: false
                    )
                }
                .buttonStyle(.plain)
            }
            
            Button {
                endAndDismiss()
            } label: {
                actionButton(
                    title: "End",
                    icon: "stop.fill",
                    filled: false
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func actionButton(
        title: String,
        icon: String,
        filled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            
            Text(title)
                .font(
                    .system(
                        size: 13,
                        weight: .black,
                        design: .rounded
                    )
                )
                .routineRunTextShadow()
        }
        .foregroundStyle(
            filled
            ? routineTint.wcagContrastingSolidTextColor
            : LColors.textPrimary
        )
        .wcagContrastLift(on: routineTint, isActive: filled)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            Group {
                if filled {
                    BubblyCardMaterial(
                        tint: routineTint,
                        cornerRadius: 18
                    )
                } else {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LColors.glassSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(routineTint.opacity(0.22))
                        }
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    filled
                    ? Color.white.opacity(0.15)
                    : LColors.glassBorder,
                    lineWidth: 1
                )
        )
    }
    
    private func statPill(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(
                    .system(
                        size: 15,
                        weight: .black,
                        design: .rounded
                    )
                )
                .foregroundStyle(LColors.textPrimary)
                .routineRunTextShadow()
            
            Text(subtitle)
                .font(
                    .system(
                        size: 10,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(Color.black)
                .routineRunTextShadow()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LColors.glassSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(routineTint.opacity(0.22))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(LColors.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - Progress

extension RoutineRunView {
    
    private var progressSection: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LColors.glassSurface2)
                    
                    Capsule()
                        .fill(routineTint)
                        .frame(
                            width: geo.size.width * progress
                        )
                        .animation(
                            .spring(
                                response: 0.35,
                                dampingFraction: 0.82
                            ),
                            value: progress
                        )
                }
            }
            .frame(height: 10)
            
            HStack {
                Text("\(Int(progress * 100))% complete")
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(Color.black)
                    .routineRunTextShadow()
                
                Spacer()
                
                if !allDone {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let end = countdownEndDate(at: context.date)
                        let remaining = max(0, end.timeIntervalSince(context.date))
                        let hours = Int(remaining) / 3600
                        let minutes = (Int(remaining) % 3600) / 60
                        let seconds = Int(remaining) % 60
                        Text(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(routineTint)
                            .routineRunTextShadow()
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Completion

extension RoutineRunView {
    
    private var completionCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(routineTint.opacity(0.18))
                    .frame(width: 66, height: 66)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(routineTint)
            }
            
            Text("Routine Complete")
                .font(
                    .system(
                        size: 21,
                        weight: .black,
                        design: .rounded
                    )
                )
                .foregroundStyle(LColors.textPrimary)
                .routineRunTextShadow()
            
            Text("You finished your routine flow for this session.")
                .font(
                    .system(
                        size: 13,
                        design: .rounded
                    )
                )
                .foregroundStyle(Color.black)
                .routineRunTextShadow()
                .multilineTextAlignment(.center)
            
            Button {
                endAndDismiss()
            } label: {
                Text("Done")
                    .font(
                        .system(
                            size: 14,
                            weight: .black,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(routineTint.wcagContrastingSolidTextColor)
                    .routineRunTextShadow()
                    .wcagContrastLift(on: routineTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(routineTint)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LColors.glassSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(routineTint.opacity(0.24))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(
                    LColors.glassBorder,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Logic

extension RoutineRunView {
    
    private func startRun() {
        guard run == nil else { return }

        run = RoutineManager.shared.startRun(
            for: routine,
            context: modelContext
        )
        
        isPausedState = run?.isPaused == true
    }
    
    private func checkAllDone() {
        let _ = run?.allDone
    }
    
    private func endAndDismiss() {
        if let run {
            RoutineManager.shared.finishRun(
                run: run,
                routine: routine,
                wasCompleted: run.allDone
            )
        }
        
        dismiss()
    }
    
    private func countdownEndDate(at date: Date) -> Date {
        let startDate = run?.startedAt ?? date
        let pausedSeconds = run?.pausedDuration(at: date) ?? 0
        
        if routine.scheduleEnabled {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: startDate)
            components.hour = routine.endHour
            components.minute = routine.endMinute
            components.second = 0
            var wallClockEnd = calendar.date(from: components)
                ?? startDate.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))

            if wallClockEnd <= startDate {
                wallClockEnd = calendar.date(byAdding: .day, value: 1, to: wallClockEnd)
                    ?? wallClockEnd.addingTimeInterval(86_400)
            }
            
            // If durationMode is on and we started outside the scheduled window, use duration instead
            if routine.durationMode {
                var startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
                startComponents.hour = routine.startHour
                startComponents.minute = routine.startMinute
                startComponents.second = 0
                let windowStart = calendar.date(from: startComponents) ?? startDate
                
                if startDate < windowStart || startDate > wallClockEnd {
                    // Started outside the window — use duration countdown
                    return startDate
                        .addingTimeInterval(TimeInterval(routine.durationMinutesOverride * 60))
                        .addingTimeInterval(pausedSeconds)
                }
            }
            
            return wallClockEnd.addingTimeInterval(pausedSeconds)
        }
        
        let durationSeconds = TimeInterval(routine.durationMinutes * 60)
        return startDate.addingTimeInterval(durationSeconds).addingTimeInterval(pausedSeconds)
    }
}

// MARK: - Task Row

struct LureliaRoutineRunTaskRow: View {
    let runTask: LureliaRoutineRunTask
    let routineTint: Color
    
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            
            Button {
                onComplete()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(
                            circleColor.opacity(0.45),
                            lineWidth: 1.5
                        )
                        .frame(width: 28, height: 28)
                    
                    if runTask.isCompleted {
                        Circle()
                            .fill(circleColor)
                            .frame(width: 17, height: 17)
                    } else if runTask.isSkipped {
                        Image(systemName: "forward.fill")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(circleColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!runTask.isPending)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(runTask.taskName)
                    .font(
                        .system(
                            size: 15,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(runTask.isPending ? LColors.textPrimary : Color.black)
                    .routineRunTextShadow()
                    .strikethrough(!runTask.isPending)
                
                if runTask.isCompleted {
                    Text("Completed")
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(routineTint.opacity(0.9))
                        .routineRunTextShadow()
                } else if runTask.isSkipped {
                    Text("Skipped")
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(Color.black)
                        .routineRunTextShadow()
                }
            }
            
            Spacer()
            
            if runTask.isPending {
                Button {
                    onSkip()
                } label: {
                    Image("skipwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(routineTint)
                        .bubblyIconMaterial(tint: routineTint)
                        .shadow(
                            color: Color.black.opacity(0.74),
                            radius: 5,
                            x: 0,
                            y: 3
                        )
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(runTask.run?.isPaused == true)
                .opacity(
                    runTask.run?.isPaused == true
                    ? 0.4
                    : 1
                )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .fill(
                runTask.isPending
                ? LColors.glassSurface2
                : LColors.glassSurface
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(routineTint.opacity(runTask.isPending ? 0.22 : 0.14))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .strokeBorder(
                    circleColor.opacity(
                        runTask.isPending
                        ? 0.22
                        : 0.1
                    ),
                    lineWidth: 1
                )
            }
        }
    }
    
    private var circleColor: Color {
        if runTask.isCompleted {
            return routineTint
        }
        
        if runTask.isSkipped {
            return LColors.textSecondary
        }
        
        return LColors.textSecondary.opacity(0.7)
    }
}
