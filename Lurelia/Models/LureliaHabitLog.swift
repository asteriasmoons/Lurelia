//
//  LureliaHabitLog.swift
//  Lurelia
//

import Foundation
import SwiftData

@Model
final class LureliaHabitLog {

    // MARK: - Identity

    var id: UUID = UUID()

    // MARK: - Core

    var dayStart: Date = Date()
    var count: Int = 1
    var habitIDString: String = ""

    /// JSON-encoded `[String]` of "HH:mm" fire times the user has checked
    /// off for this day. Enables per-fire-time completion tracking on the
    /// Kanban Timeline — checking the 10:00 card marks only that specific
    /// occurrence, not the whole day. `count` is kept in sync as the
    /// backwards-compatible per-day total (widgets, statistics).
    var completedFireTimesStorage: String?

    // MARK: - Metadata

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // MARK: - Relationship

    var habit: LureliaHabit?

    // MARK: - Init

    init(habit: LureliaHabit, dayStart: Date, count: Int = 1) {
        self.id = UUID()
        self.habit = habit
        self.habitIDString = habit.id.uuidString
        self.dayStart = Calendar.current.startOfDay(for: dayStart)
        self.count = max(1, count)
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Fire-time storage

extension LureliaHabitLog {

    /// The set of "HH:mm" fire times the user has completed for this day.
    var completedFireTimes: Set<String> {
        get {
            guard let data = completedFireTimesStorage?.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(decoded)
        }
        set {
            let sorted = newValue.sorted()
            if let data = try? JSONEncoder().encode(sorted),
               let string = String(data: data, encoding: .utf8) {
                completedFireTimesStorage = string
            } else {
                completedFireTimesStorage = nil
            }
        }
    }

    /// True if the user has explicitly checked off the fire time that
    /// corresponds to `date` (compared at hour+minute granularity).
    func isCompleted(atFireDate date: Date, calendar: Calendar = .current) -> Bool {
        completedFireTimes.contains(Self.fireTimeKey(for: date, calendar: calendar))
    }

    /// Adds `date`'s HH:mm key to `completedFireTimes` and keeps `count`
    /// in sync (widgets and statistics still read the per-day count).
    /// No-op if the fire time is already recorded.
    func markCompleted(atFireDate date: Date, calendar: Calendar = .current) {
        var current = completedFireTimes
        let key = Self.fireTimeKey(for: date, calendar: calendar)
        guard !current.contains(key) else { return }
        current.insert(key)
        completedFireTimes = current
        count = max(count, current.count)
        updatedAt = Date()
    }

    /// Restores per-occurrence keys for legacy logs that only stored `count`.
    /// Existing keys and the historical count are preserved exactly.
    @discardableResult
    func backfillCompletedFireTimes(
        from fireDates: [Date],
        calendar: Calendar = .current
    ) -> Bool {
        guard count > 0, !fireDates.isEmpty else { return false }

        var current = completedFireTimes
        let desiredKeyCount = min(count, fireDates.count)
        guard current.count < desiredKeyCount else { return false }

        for fireDate in fireDates.sorted() where current.count < desiredKeyCount {
            current.insert(Self.fireTimeKey(for: fireDate, calendar: calendar))
        }

        guard current != completedFireTimes else { return false }
        completedFireTimes = current
        updatedAt = Date()
        return true
    }

    /// Removes `date`'s HH:mm key from `completedFireTimes` and decrements
    /// `count`. Used when the user unchecks a specific occurrence.
    func unmarkCompleted(atFireDate date: Date, calendar: Calendar = .current) {
        var current = completedFireTimes
        let key = Self.fireTimeKey(for: date, calendar: calendar)
        guard current.contains(key) else { return }
        current.remove(key)
        completedFireTimes = current
        count = max(0, count - 1)
        updatedAt = Date()
    }

    /// Removes one completion from this day, preferring the latest completed
    /// scheduled fire time when per-time tracking exists.
    @discardableResult
    func undoLatestCompletion(fireDates: [Date], calendar: Calendar = .current) -> Bool {
        let completedKeys = completedFireTimes

        if !completedKeys.isEmpty {
            let latestCompletedFireDate = fireDates
                .filter { completedKeys.contains(Self.fireTimeKey(for: $0, calendar: calendar)) }
                .sorted()
                .last

            if let latestCompletedFireDate {
                unmarkCompleted(atFireDate: latestCompletedFireDate, calendar: calendar)
                return true
            }

            if let latestKey = completedKeys.sorted().last {
                var updatedKeys = completedKeys
                updatedKeys.remove(latestKey)
                completedFireTimes = updatedKeys
                count = max(0, count - 1)
                updatedAt = Date()
                return true
            }
        }

        guard count > 0 else { return false }

        count = max(0, count - 1)
        updatedAt = Date()
        return true
    }

    /// Normalizes a fire date into an "HH:mm" key. Two dates that share
    /// the same hour and minute map to the same key regardless of day.
    static func fireTimeKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
