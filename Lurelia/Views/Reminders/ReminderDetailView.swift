//
//  ReminderDetailView.swift
//  Lurelia
//

import SwiftUI
import UIKit
import SwiftData
import MapKit
import WidgetKit

struct ReminderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    let reminder: LureliaReminder

    @State private var historyExpanded = false
    @State private var showEditor = false
    @State private var isCompleting = false
    @State private var frictionEditing = false
    @State private var frictionDraft = ""
    @State private var isGeneratingTinyNudge = false
    @State private var tinyNudgeResponse: TinyNudgeResponse?
    @State private var tinyNudgeError: String?

    @Query(sort: \LureliaReminderHistory.occurrenceDate, order: .reverse)
    private var allHistory: [LureliaReminderHistory]

    private var reminderHistory: [LureliaReminderHistory] {
        allHistory.filter { $0.reminderID == reminder.id }
    }

    private var reminderIcon: String {
        let icon = reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "bellfill" : icon
    }

    private var useFullScreenCover: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // MARK: - Header

                    HStack(spacing: 12) {
                        Text("Reminder")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Button { showEditor = true } label: {
                            Image("settings")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background {
                                    BubblyIconMaterial(tint: reminder.color)
                                        .clipShape(Circle())
                                }
                        }
                        .buttonStyle(.plain)

                        Button { dismiss() } label: {
                            Image("xmarkwavy")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(.black)
                                .frame(width: 40, height: 40)
                                .background {
                                    BubblyIconMaterial(tint: reminder.color)
                                        .clipShape(Circle())
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // MARK: - Icon + Title + Description

                    VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.42))
                                    .frame(width: 64, height: 64)

                                Circle()
                                    .strokeBorder(reminder.color, lineWidth: 1.4)
                                    .bubblyIconMaterial(tint: reminder.color)
                                    .frame(width: 64, height: 64)

                                LureliaIconView(iconId: reminderIcon, size: 38)
                                    .foregroundStyle(reminder.color)
                                    .bubblyIconMaterial(tint: reminder.color)
                            }

                            Text(reminder.title)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            if let notes = reminder.notes,
                               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(notes)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .multilineTextAlignment(.center)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background {
                        BubblyCardMaterial(tint: reminder.color, cornerRadius: 22)
                    }
                    .padding(.horizontal, 24)

                    // Motivation / Consequences hidden from the detail view.
                    // The underlying model fields are still populated so this
                    // is a visual-only removal.

                    // MARK: - Schedule

                    sectionCard(title: "Schedule", icon: "timebook") {
                        VStack(alignment: .leading, spacing: 10) {
                            scheduleInfoTile(label: "Time", value: timeSummary)

                            scheduleInfoTile(label: "Frequency", value: repeatSummary)

                            scheduleInfoTile(label: "Next Occurrence", value: nextOccurrenceText)

                            scheduleInfoTile(label: "Alarm", value: alarmSummary)
                        }
                    }
                    
                    // MARK: - Streaks

                    if reminder.repeatUnit != .none {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image("boltprogress")
                                    .renderingMode(.template)
                                    .resizable().scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(reminder.color)
                                    .bubblyIconMaterial(tint: reminder.color)
                                Text("Streaks")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }

                            HStack(spacing: 12) {
                                streakCard(label: "Current Streak", value: "\(reminder.currentStreak)", unit: reminder.currentStreak == 1 ? "day" : "days")
                                streakCard(label: "Longest Streak", value: "\(reminder.longestStreak)", unit: reminder.longestStreak == 1 ? "day" : "days")
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    // MARK: - Status + Time Remaining

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let now = context.date
                        let status = resolvedStatus(now: now)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image("dotlovering")
                                    .renderingMode(.template)
                                    .resizable().scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(reminder.color)
                                    .bubblyIconMaterial(tint: reminder.color)
                                Text("Status & Time")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }

                            HStack(spacing: 12) {
                                statusCard(status)
                                timeRemainingCard(now: now)
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    // Recovery Plan and Tiny Nudge hidden from the detail
                    // view. The model fields and TinyNudge state remain so
                    // this is a visual-only removal.


                    // MARK: - Completion Steps (Checklist)

                    if reminder.hasChecklist {
                        sectionCard(title: "Completion Steps", icon: "checkwavy") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(reminder.checklistCompletedCount) / \(reminder.checklistTotalCount) completed")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.45))
                                    Spacer()
                                    Text("\(Int(reminder.checklistProgress * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.white.adaptivePrimaryText)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)).frame(height: 6)
                                        RoundedRectangle(cornerRadius: 4).fill(reminder.color)
                                            .frame(width: geo.size.width * reminder.checklistProgress, height: 6)
                                    }
                                }
                                .frame(height: 6)

                                ForEach(sortedChecklistItems, id: \.id) { item in
                                    Button {
                                        toggleChecklistItem(item)
                                    } label: {
                                        HStack(spacing: 10) {
                                            ZStack {
                                                Circle()
                                                    .fill(item.isCompleted ? AnyShapeStyle(reminder.color) : AnyShapeStyle(Color.clear))
                                                    .frame(width: 18, height: 18)

                                                Circle()
                                                    .strokeBorder(
                                                        item.isCompleted ? AnyShapeStyle(Color.clear) : AnyShapeStyle(reminder.color),
                                                        lineWidth: 1.3
                                                    )
                                                    .bubblyIconMaterial(
                                                        tint: reminder.color,
                                                        isEnabled: !item.isCompleted
                                                    )
                                                    .frame(width: 18, height: 18)

                                                if item.isCompleted {
                                                    Image("checkwavy")
                                                        .renderingMode(.template)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: 10, height: 10)
                                                        .foregroundStyle(.white)
                                                }
                                            }

                                            Text(item.title)
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundStyle(item.isCompleted ? .white.opacity(0.45) : .white.opacity(0.85))
                                                .strikethrough(item.isCompleted, color: .white.opacity(0.3))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // MARK: - Location

                    if reminder.hasLocation || (reminder.locationLabel?.isEmpty == false) {
                        locationSection
                    }

                    // MARK: - Completion History

                    if !reminderHistory.isEmpty {
                        completionHistorySection
                    }

                    Spacer().frame(height: 140)
                }
            }
            .onTapGesture {
                if frictionEditing {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        frictionEditing = false
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            resetChecklistIfNeededForCurrentOccurrence()
        }
        .sheet(isPresented: Binding(
            get: { !useFullScreenCover && showEditor },
            set: { showEditor = $0 }
        )) {
            AddReminderView(editingReminder: reminder)
        }
        .fullScreenCover(isPresented: Binding(
            get: { useFullScreenCover && showEditor },
            set: { showEditor = $0 }
        )) {
            AddReminderView(editingReminder: reminder)
        }
    }

    // MARK: - Schedule Helpers

    private var repeatSummary: String {
        guard reminder.repeatUnit != .none else { return "One-time" }
        let interval = max(1, reminder.repeatInterval)
        if interval == 1 {
            switch reminder.repeatUnit {
            case .minutes: return "Every minute"
            case .hours: return "Hourly"
            case .days: return "Daily"
            case .weeks: return "Weekly"
            case .months: return "Monthly"
            case .years: return "Yearly"
            case .none: return "One-time"
            }
        }
        return "Every \(interval) \(reminder.repeatUnit.rawValue.lowercased())"
    }

    private var timeSummary: String {
        let times = reminder.timesOfDay.filter { !$0.isEmpty }
        guard !times.isEmpty else {
            return reminder.scheduledDate.formatted(date: .omitted, time: .shortened)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let outFormatter = DateFormatter()
        outFormatter.timeStyle = .short
        return times.compactMap { str -> String? in
            guard let d = formatter.date(from: str) else { return str }
            return outFormatter.string(from: d)
        }.joined(separator: ", ")
    }

    private var repeatPatternText: String {
        let interval = max(1, reminder.repeatInterval)
        var text = "Every \(interval) \(reminder.repeatUnit.rawValue.lowercased())"
        if reminder.repeatUnit == .weeks, !reminder.repeatWeekdays.isEmpty {
            let dayNames = reminder.repeatWeekdays.sorted().compactMap { weekdayShort($0) }
            text += " on \(dayNames.joined(separator: ", "))"
        }
        if let ends = reminder.repeatEndsAt {
            text += " until \(ends.formatted(date: .abbreviated, time: .omitted))"
        }
        return text
    }

    private var nextOccurrenceText: String {
        let next = reminder.nextFireAt ?? reminder.scheduledDate
        return next.formatted(date: .abbreviated, time: .shortened)
    }

    private var alarmSummary: String {
        guard reminder.alarmEnabled else { return "Disabled" }
        let count = reminder.alarmFireTimes.filter { !$0.isEmpty }.count
        if count <= 1 { return "1 time" }
        return "\(count) times"
    }

    private func schedulePill(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.06))
                .clipShape(Capsule())

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(reminder.color.opacity(0.22))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(reminder.color.opacity(0.55), lineWidth: 1))
        }
    }
    
    private func scheduleInfoTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .tracking(0.6)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
    }

    // MARK: - Status

    private enum ReminderStatus {
        case upcoming, dueNow, overdue, completed, skipped

        var label: String {
            switch self {
            case .upcoming: return "UPCOMING"
            case .dueNow: return "DUE NOW"
            case .overdue: return "OVERDUE"
            case .completed: return "COMPLETED"
            case .skipped: return "SKIPPED"
            }
        }

        var color: Color {
            switch self {
            case .upcoming: return Color(lureliaHex: "#7eedff")
            case .dueNow: return Color(lureliaHex: "#b476ff")
            case .overdue: return Color(lureliaHex: "#ff9be6")
            case .completed: return LColors.success
            case .skipped: return .white.opacity(0.4)
            }
        }
    }

    private func resolvedStatus(now: Date) -> ReminderStatus {
        let cal = Calendar.current

        // Non-recurring completed/skipped
        if reminder.repeatUnit == .none {
            if reminder.isCompleted { return .completed }
        }

        let nextFire = reminder.nextFireAt ?? reminder.scheduledDate
        let startOfToday = cal.startOfDay(for: now)

        if nextFire < startOfToday { return .overdue }
        if nextFire <= now { return .dueNow }
        return .upcoming
    }

    private func statusCard(_ status: ReminderStatus) -> some View {
        tintedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("STATUS")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.6)

                Text(status.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(status.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeRemainingCard(now: Date) -> some View {
        let next = reminder.nextFireAt ?? reminder.scheduledDate
        let diff = next.timeIntervalSince(now)

        return tintedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("TIME")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.6)

                Text(timeRemainingLabel(diff))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(diff < 0 ? Color(lureliaHex: "#ff9be6") : .white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeRemainingLabel(_ interval: TimeInterval) -> String {
        let abs = abs(interval)
        let suffix = interval < 0 ? " Overdue" : ""

        if abs < 60 { return "Now" }
        if abs < 3600 { return "\(Int(abs / 60)) Min\(suffix)" }
        if abs < 86400 {
            let hours = Int(abs / 3600)
            return "\(hours) Hr\(hours == 1 ? "" : "s")\(suffix)"
        }
        let days = Int(abs / 86400)
        if days == 1 { return interval > 0 ? "Tomorrow" : "1 Day\(suffix)" }
        return "\(days) Day\(days == 1 ? "" : "s")\(suffix)"
    }

    // MARK: - Location

    @ViewBuilder
    private var locationSection: some View {
        sectionCard(title: "Location", icon: "starpinlocation") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reminder.locationLabel?.isEmpty == false ? reminder.locationLabel! : "Location Saved")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        
                        if let address = reminder.locationAddress,
                           !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(address)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if reminder.hasLocation,
                   let lat = reminder.locationLatitude,
                   let lon = reminder.locationLongitude {
                    Button {
                        openInMaps(lat: lat, lon: lon)
                    } label: {
                        HStack(spacing: 8) {
                            Image("linkcircle")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)

                            Text("Open in Maps")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background {
                            BubblyCardMaterial(tint: reminder.color, cornerRadius: 14)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func openInMaps(lat: Double, lon: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = reminder.locationLabel ?? reminder.title
        item.openInMaps(launchOptions: nil)
    }

    // MARK: - Streak Card

    private func streakCard(label: String, value: String, unit: String) -> some View {
        tintedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.6)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Completion History

    @ViewBuilder
    private var completionHistorySection: some View {
        let allCompleted = reminderHistory.filter { $0.action == .completed }
        let allSkipped = reminderHistory.filter { $0.action == .skipped }
        let combined = (allCompleted + allSkipped).sorted { $0.occurrenceDate > $1.occurrenceDate }
        let limit = historyExpanded ? combined.count : min(6, combined.count)
        let visible = Array(combined.prefix(limit))

        if !combined.isEmpty {
            sectionCard(title: "Completion History", icon: "timebook") {
                VStack(alignment: .leading, spacing: 12) {
                    if let last = reminder.lastCompletedDate {
                        HStack {
                            Text("Last Completed")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                            Spacer()
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(LColors.success)
                        }

                        Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    }

                    ForEach(visible, id: \.id) { entry in
                        let isSkip = entry.action == .skipped
                        historyRow(entry, color: isSkip ? .white.opacity(0.4) : LColors.success)
                    }

                    if combined.count > 6 && !historyExpanded {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                historyExpanded = true
                            }
                        } label: {
                            Text("Load More")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(reminder.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: LureliaReminderHistory, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 8, height: 8)

            Text(entry.occurrenceDate.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text(entry.action.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Reusable

    private func sectionCard<Content: View>(
        title: String, icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(icon).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(reminder.color)
                    .bubblyIconMaterial(tint: reminder.color)
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            tintedCard {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    private func tintedCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(18)
            .background {
                BubblyCardMaterial(tint: reminder.color, cornerRadius: 22)
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.6)
    }

    private func sectionBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func nudgeLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.6)
    }

    private func nudgeBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var frictionBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            if frictionEditing {
                TextField("What is making this harder?", text: $frictionDraft, axis: .vertical)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onTapGesture { }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()

                            Button("Done") {
                                dismissKeyboard()
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                    }

                Button {
                    saveFriction()

                    Task {
                        isGeneratingTinyNudge = true
                        tinyNudgeError = nil

                        do {
                            tinyNudgeResponse = try await TinyNudgeService.shared.convinceMe(
                                taskType: .reminder,
                                taskName: reminder.title,
                                friction: reminder.friction ?? ""
                            )
                        } catch {
                            tinyNudgeError = error.localizedDescription
                        }

                        isGeneratingTinyNudge = false
                    }
                } label: {
                    Text("Convince Me")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white.adaptivePrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(reminder.color)
                        )
                }
                .buttonStyle(.plain)

            } else {
                Button {
                    frictionDraft = ""

                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        frictionEditing = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(reminder.color)

                        Text("Add Friction")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if isGeneratingTinyNudge {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)

                    Text("Writing your nudge...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let tinyNudgeResponse {
                VStack(alignment: .leading, spacing: 12) {
                    nudgeLabel("Convince Me")
                    nudgeBody(tinyNudgeResponse.encouragement)

                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(height: 1)

                    nudgeLabel("Reduce Friction")
                    nudgeBody(tinyNudgeResponse.frictionSuggestion)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let tinyNudgeError {
                Text(tinyNudgeError)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(lureliaHex: "#ff9be6"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(lureliaHex: "#ff9be6").opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func saveFriction() {
        reminder.friction = frictionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.updatedAt = Date()
        try? modelContext.save()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            frictionEditing = false
        }
    }

    // MARK: - Checklist Completion Actions

    private func toggleChecklistItem(_ item: LureliaReminderChecklistItem) {
        var items = reminder.checklistItems
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].isCompleted.toggle()
        items[index].updatedAt = Date()

        reminder.checklistItems = items
        reminder.updatedAt = Date()

        try? modelContext.save()

        let allCompleted = !reminder.checklistItems.isEmpty &&
            reminder.checklistItems.allSatisfy { $0.isCompleted }

        if allCompleted {
            completeReminderOccurrenceFromChecklist()
        }
    }

    private func resetChecklistIfNeededForCurrentOccurrence() {
        ReminderActionManager.resetChecklistIfNeededForCurrentOccurrence(
            reminder,
            in: modelContext
        )
    }

    private func completeReminderOccurrenceFromChecklist() {
        guard !isCompleting else { return }

        isCompleting = true

        Task {
            await ReminderActionManager.completeReminderOccurrence(
                reminder,
                in: modelContext
            )

            await MainActor.run {
                isCompleting = false
            }
        }
    }

    private var sortedChecklistItems: [LureliaReminderChecklistItem] {
        reminder.checklistItems
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private var sortedLevels: [LureliaReminderLevel] {
        reminder.levels
            .filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted {
                $0.sortOrder < $1.sortOrder
            }
    }
    
    private func levelRow(_ level: LureliaReminderLevel) -> some View {
        let iconNumber = (level.sortOrder + 1) % 10

        return HStack(spacing: 10) {

            Image("\(iconNumber)wavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(reminder.color)

            Text(level.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.055))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(
                .white.opacity(0.09),
                lineWidth: 1
            )
        )
    }

    private func weekdayShort(_ value: Int) -> String? {
        guard value >= 1 && value <= 7 else { return nil }
        return Calendar.current.shortWeekdaySymbols[value - 1]
    }
}
