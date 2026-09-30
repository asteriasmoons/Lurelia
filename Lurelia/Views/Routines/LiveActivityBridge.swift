//
//  LureliaLiveActivityBridge.swift
//  Lurelia
//
//
//  Wraps ActivityKit calls so the main app target compiles even before
//  the Widget Extension target is configured. Once you add LureliaWidgets
//  and include LureliaRoutineLiveActivity.swift there, everything lights up.
//

import Foundation
import SwiftData

#if canImport(ActivityKit)
import ActivityKit
#endif

final class LureliaLiveActivityBridge {
    static let shared = LureliaLiveActivityBridge()
    
    private init() {}
    
    #if canImport(ActivityKit)
    private var currentActivity: Activity<LureliaRoutineActivityAttributes>?
    #endif
    
    // MARK: - Start
    
    func start(
        routine: LureliaRoutine,
        run: LureliaRoutineRun
    ) {
        
        #if canImport(ActivityKit)
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }
        
        let stateDate = Date()
        let endDate = endDateFor(routine: routine, run: run, at: stateDate)
        
        let state = LureliaRoutineActivityAttributes.ContentState(
            routineName: routine.name,
            completedCount: run.completedCount,
            totalCount: run.totalCount,
            endDate: endDate,
            isFinished: run.allDone,
            colorHex: routine.colorHex,
            isPaused: run.isPaused,
            pausedRemainingSeconds: run.isPaused
                ? max(0, endDate.timeIntervalSince(stateDate))
                : nil
        )
        
        let attributes = LureliaRoutineActivityAttributes(
            routineID: activityID(for: routine)
        )
        
        let content = ActivityContent(
            state: state,
            staleDate: run.isPaused ? nil : endDate.addingTimeInterval(300)
        )

        if let existingActivity = existingActivity(for: routine) {
            currentActivity = existingActivity
            Task {
                await existingActivity.update(content)
            }
            return
        }
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            #if !targetEnvironment(simulator)
            print("[LureliaLiveActivityBridge] start failed: \(error)")
            #endif
        }
        
        #endif
    }
    
    // MARK: - Update
    
    func update(
        routine: LureliaRoutine,
        run: LureliaRoutineRun
    ) {
        
        #if canImport(ActivityKit)
        
        guard let activity = matchingCurrentActivity(for: routine) ?? existingActivity(for: routine) else {
            if run.isActive {
                start(routine: routine, run: run)
            }
            return
        }

        currentActivity = activity
        
        let stateDate = Date()
        let endDate = endDateFor(routine: routine, run: run, at: stateDate)
        
        let state = LureliaRoutineActivityAttributes.ContentState(
            routineName: routine.name,
            completedCount: run.completedCount,
            totalCount: run.totalCount,
            endDate: endDate,
            isFinished: run.allDone,
            colorHex: routine.colorHex,
            isPaused: run.isPaused,
            pausedRemainingSeconds: run.isPaused
                ? max(0, endDate.timeIntervalSince(stateDate))
                : nil
        )
        
        let content = ActivityContent(
            state: state,
            staleDate: run.isPaused ? nil : endDate.addingTimeInterval(300)
        )
        
        Task {
            await activity.update(content)
        }
        
        #endif
    }
    
    // MARK: - End
    
    func end() {
        
        #if canImport(ActivityKit)
        
        guard let activity = currentActivity else {
            return
        }
        
        Task {
            await activity.end(
                nil,
                dismissalPolicy: .after(
                    Date().addingTimeInterval(5)
                )
            )
        }
        
        currentActivity = nil
        
        #endif
    }
    
    // MARK: - Helpers
    
    private func endDateFor(
        routine: LureliaRoutine,
        run: LureliaRoutineRun,
        at date: Date
    ) -> Date {
        let startedAt = run.startedAt
        let pausedSeconds = run.pausedDuration(at: date)

        let calendar = Calendar.current

        if routine.scheduleEnabled {
            var startComponents = calendar.dateComponents([.year, .month, .day], from: startedAt)
            startComponents.hour = routine.startHour
            startComponents.minute = routine.startMinute
            startComponents.second = 0
            let scheduledStart = calendar.date(from: startComponents) ?? startedAt

            var endComponents = calendar.dateComponents([.year, .month, .day], from: scheduledStart)
            endComponents.hour = routine.endHour
            endComponents.minute = routine.endMinute
            endComponents.second = 0

            var scheduledEnd = calendar.date(from: endComponents)
                ?? startedAt.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))

            if scheduledEnd <= scheduledStart {
                scheduledEnd = calendar.date(byAdding: .day, value: 1, to: scheduledEnd)
                    ?? scheduledEnd.addingTimeInterval(86_400)
            }

            if routine.durationMode,
               startedAt < scheduledStart || startedAt > scheduledEnd {
                return startedAt
                    .addingTimeInterval(TimeInterval(max(1, routine.durationMinutesOverride) * 60))
                    .addingTimeInterval(pausedSeconds)
            }

            return scheduledEnd.addingTimeInterval(pausedSeconds)
        }

        if routine.durationMode {
            return startedAt
                .addingTimeInterval(TimeInterval(max(1, routine.durationMinutesOverride) * 60))
                .addingTimeInterval(pausedSeconds)
        }

        return startedAt
            .addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
            .addingTimeInterval(pausedSeconds)
    }

    private func activityID(for routine: LureliaRoutine) -> String {
        routine.persistentID.isEmpty
            ? routine.persistentModelID.hashValue.description
            : routine.persistentID
    }

    private func legacyActivityID(for routine: LureliaRoutine) -> String {
        routine.persistentModelID.hashValue.description
    }

    #if canImport(ActivityKit)
    private func existingActivity(
        for routine: LureliaRoutine
    ) -> Activity<LureliaRoutineActivityAttributes>? {
        let ids = Set([activityID(for: routine), legacyActivityID(for: routine)])
        return Activity<LureliaRoutineActivityAttributes>.activities.first {
            ids.contains($0.attributes.routineID)
        }
    }

    private func matchingCurrentActivity(
        for routine: LureliaRoutine
    ) -> Activity<LureliaRoutineActivityAttributes>? {
        guard let currentActivity else { return nil }
        let ids = Set([activityID(for: routine), legacyActivityID(for: routine)])
        return ids.contains(currentActivity.attributes.routineID)
            ? currentActivity
            : nil
    }
    #endif
}
