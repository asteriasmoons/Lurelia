//
//  ActiveRoutineBanner.swift
//  Lurelia
//

import SwiftUI

struct ActiveRoutineBanner: View {
    let run: LureliaRoutineRun
    var onTap: (() -> Void)? = nil
    
    private var tint: Color {
        Color(lureliaHex: run.routineColorHex)
    }
    
    private var taskSummary: String {
        "\(run.completedCount)/\(run.totalCount) tasks"
    }
    
    private func endDate(at date: Date) -> Date {
        guard let routine = run.routine else {
            return run.startedAt
                .addingTimeInterval(3600)
                .addingTimeInterval(run.pausedDuration(at: date))
        }

        let pausedSeconds = run.pausedDuration(at: date)
        
        // Duration mode: count down from a fixed duration minus time already elapsed while active
        if routine.durationMode {
            let totalDuration = TimeInterval(routine.durationMinutesOverride * 60)
            return run.startedAt
                .addingTimeInterval(totalDuration)
                .addingTimeInterval(pausedSeconds)
        }
        
        // Schedule mode: count down to fixed wall-clock end time
        if routine.scheduleEnabled {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = routine.endHour
            components.minute = routine.endMinute
            components.second = 0
            let scheduledEnd = calendar.date(from: components)
                ?? run.startedAt.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
            return scheduledEnd.addingTimeInterval(pausedSeconds)
        }
        
        return run.startedAt
            .addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
            .addingTimeInterval(pausedSeconds)
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                        )
                    
                    LureliaIconView(iconId: run.routineIcon, size: 22)
                        .foregroundStyle(tint)
                        .bubblyIconMaterial(tint: tint)
                        .shadow(
                            color: Color.black.opacity(0.74),
                            radius: 5,
                            x: 0,
                            y: 3
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.routineName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .shadow(color: Color.black.opacity(0.72), radius: 2, x: 0, y: 1)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(taskSummary)
                        
                        Text("•")
                        
                        if run.isPaused {
                            Text("Paused")
                        } else {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let end = endDate(at: context.date)
                                let remaining = max(0, end.timeIntervalSince(context.date))
                                let hours = Int(remaining) / 3600
                                let minutes = (Int(remaining) % 3600) / 60
                                let seconds = Int(remaining) % 60
                                Text(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .shadow(color: Color.black.opacity(0.64), radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                BubblyCardMaterial(
                    tint: tint,
                    cornerRadius: 22
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: tint.opacity(0.16), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
