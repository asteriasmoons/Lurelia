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
    
    private var endDate: Date {
        guard let routine = run.routine else {
            return run.startedAt.addingTimeInterval(3600)
        }
        
        // Duration mode: count down from a fixed duration minus time already elapsed while active
        if routine.durationMode {
            let totalDuration = TimeInterval(routine.durationMinutesOverride * 60)
            return run.startedAt.addingTimeInterval(totalDuration).addingTimeInterval(run.totalPausedSeconds)
        }
        
        // Schedule mode: count down to fixed wall-clock end time
        if routine.scheduleEnabled {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = routine.endHour
            components.minute = routine.endMinute
            components.second = 0
            return calendar.date(from: components)
                ?? run.startedAt.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
        }
        
        return run.startedAt.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
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
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.routineName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(taskSummary)
                        
                        Text("•")
                        
                        if run.isPaused {
                            Text("Paused")
                        } else {
                            let end = endDate
                            TimelineView(.periodic(from: .now, by: 1)) { context in
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
                    .foregroundStyle(LColors.textSecondary)
                    .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LColors.bg)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(tint.opacity(0.28))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
