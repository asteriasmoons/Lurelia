//
//  KanbanTimelineView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import WidgetKit
import Combine
import UIKit

private func kanbanReadableAccentText(_ tint: Color) -> Color {
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0

    guard UIColor(tint).getHue(
        &hue,
        saturation: &saturation,
        brightness: &brightness,
        alpha: &alpha
    ), saturation >= 0.10,
       (0.68...0.92).contains(hue) else {
        return tint
    }

    return Color(
        hue: Double(hue),
        saturation: Double(min(saturation * 0.78, 0.72)),
        brightness: Double(max(brightness, 0.90)),
        opacity: Double(alpha)
    )
}

// MARK: - Kanban Completion Banner

/// Kind of item that just fired the timeline's completion banner. Threaded
/// through each card's `onComplete` closure so the toast can say "Habit
/// completed!" vs "Reminder completed!" vs "Routine task completed!" — the
/// user shouldn't tap a habit and see a "Reminder completed!" banner.
enum KanbanCompletionKind {
    case habit, routineTask, reminder, quickTask

    var bannerMessage: String {
        switch self {
        case .habit:       return "Habit completed!"
        case .routineTask: return "Routine task completed!"
        case .reminder:    return "Reminder completed!"
        case .quickTask:   return "Quick task completed!"
        }
    }
}

// MARK: - Kanban Timeline View

struct KanbanTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(sort: \KanbanBoard.sortOrder)
    private var boards: [KanbanBoard]

    @Query private var allReminders: [LureliaReminder]
    @Query private var allRoutines: [LureliaRoutine]
    @Query private var allRoutineTasks: [LureliaRoutineTask]
    @Query private var allHabits: [LureliaHabit]
    @Query private var allQuickTasks: [KanbanQuickTask]
    @Query private var allHabitLogs: [LureliaHabitLog]
    @Query private var settings: [UserSettings]

    @State private var selectedBoardIDs: Set<UUID> = []
    @State private var didInitializeBoardSelection = false
    @State private var selectedDay: Date = Date()
    @State private var isBoardDropdownExpanded = false
    @State private var showCreateBoard = false
    @State private var showAddColumn = false
    @State private var editingColumn: KanbanColumn?
    @State private var createRequest: KanbanCreateRequest?
    @State private var taskCreateRequest: KanbanRoutineTaskCreateRequest?
    @State private var habitCreateRequest: KanbanHabitCreateRequest?
    @State private var quickTaskCreateRequest: KanbanQuickTaskCreateRequest?
    @State private var showCompletionBanner = false
    @State private var completionBannerMessage: String = "Completed!"
    /// Flips true after the timeline has auto-scrolled to the current time
    /// on first appear. Prevents that scroll from re-firing every time the
    /// view re-renders (which would fight the user if they've scrolled
    /// somewhere else).
    @State private var didInitialScrollToNow = false

    /// Shared "current time" for every time-sensitive card in the timeline
    /// (habit / routine-task / reminder). Previously each card owned its
    /// own `TimelineView(.periodic(from: .now, by: 30))`, which meant one
    /// timer + one full-body invalidation per card twice a minute. This
    /// single publisher pushes `now` down as a plain `Date` parameter, so
    /// the cards can re-render their status labels without any TimelineView
    /// re-entering the body pipeline.
    @State private var timelineNow: Date = Date()

    // MARK: - Cached derived data
    //
    // These two computed properties used to be re-derived every body render
    // — each one is O(cards × items × fireDates) with linear scans and per-
    // day walks. Every SwiftData save (habit log, reminder complete, sheet
    // dismissal) invalidates body, which meant tapping "complete" on one
    // item paid the cost of rebuilding EVERY row. They're now cached in
    // @State and rebuilt only when their real inputs change (see
    // `rebuildTimelineCache` and the `.onChange` triggers on `body`).
    @State private var cachedTimelineOccurrences: [KanbanTimelineColumnOccurrence] = []
    @State private var cachedTimelineOccurrenceRows: [String: [KanbanTimelineOccurrence]] = [:]
    @State private var cachedSelectedDayItemCount: Int = 0
    /// Bumped by completion / edit callbacks so a rebuild can be forced
    /// even when the raw arrays haven't changed shape (e.g., just a
    /// completion timestamp was appended).
    @State private var timelineRebuildTick: Int = 0

    private var displayedTimelineOccurrenceRows: [String: [KanbanTimelineOccurrence]] {
        var rows = cachedTimelineOccurrenceRows

        for board in selectedBoards {
            for occurrence in explicitQuickTaskOccurrences(for: board) {
                guard let column = occurrence.column else { continue }
                let key = timelineOccurrenceRowKey(
                    columnID: column.id,
                    fireDate: occurrence.fireDate
                )

                if !(rows[key] ?? []).contains(where: { $0.id == occurrence.id }) {
                    rows[key, default: []].append(occurrence)
                }
            }
        }

        for key in rows.keys {
            rows[key]?.sort { left, right in
                if left.fireDate != right.fireDate {
                    return left.fireDate < right.fireDate
                }

                return left.card.sortOrder < right.card.sortOrder
            }
        }

        return rows
    }

    private var displayedTimelineOccurrences: [KanbanTimelineColumnOccurrence] {
        computeTimelineColumnOccurrences(from: displayedTimelineOccurrenceRows)
    }

    private var calendar: Calendar { .current }

    private var selectedBoards: [KanbanBoard] {
        boards.filter { selectedBoardIDs.contains($0.id) }
    }

    private var selectedBoard: KanbanBoard? {
        selectedBoards.first
    }

    private var boardIDs: [UUID] {
        boards.map(\.id)
    }

    private var defaultTimelineBoardIDs: Set<UUID> {
        Set(settings.first?.defaultTimelineBoardIDs ?? [])
    }

    private var defaultTimelineBoardIDsStorage: Data? {
        settings.first?.defaultTimelineBoardIDsStorage
    }

    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start
        ?? calendar.startOfDay(for: selectedDay)
    }

    private var weekDays: [Date] {
        (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    private var selectedDayTitle: String {
        selectedDay.formatted(date: .complete, time: .omitted)
    }

    private var selectedBoardAccent: Color {
        guard selectedBoards.count == 1, let selectedBoard else {
            return theme.palette.primaryAction
        }

        return Color(lureliaHex: selectedBoard.colorHex)
    }

    private var selectedBoardPickerTitle: String {
        guard !boards.isEmpty else { return "No Boards" }
        return "Showing \(selectedBoards.count) of \(boards.count) Boards"
    }

    private var pinnedReminderIDs: Set<String> {
        let cards = boards
            .flatMap { $0.columns ?? [] }
            .flatMap { $0.cards ?? [] }
            .filter { $0.cardType == .reminder }

        return Set(cards.map { $0.itemID })
    }

    private var selectedDayStandaloneReminders: [LureliaReminder] {
        allReminders
            .filter { reminder in
                reminder.kind == .standalone &&
                reminder.isDue(on: selectedDay, calendar: calendar)
            }
            .sorted {
                let left = fireDates(for: $0, on: selectedDay).first ?? $0.nextFireAt ?? $0.scheduledDate
                let right = fireDates(for: $1, on: selectedDay).first ?? $1.nextFireAt ?? $1.scheduledDate
                return left < right
            }
    }

    private var inboxReminders: [LureliaReminder] {
        selectedDayStandaloneReminders
            .filter { !pinnedReminderIDs.contains($0.id.uuidString) }
    }

    private var useFullScreenCover: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {

                    // MARK: - Header

                    HStack {
                        Text("Kanban Timeline")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 59)
                    .padding(.bottom, 12)

                    // MARK: - Board Picker

                    boardPicker
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    // MARK: - Week Row

                    weekRow
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)

                    if let board = selectedBoard {
                        GeometryReader { proxy in
                            ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 16) {

                                selectedDayHeader

                                ZStack(alignment: .topLeading) {

                                    Rectangle()
                                        .fill(.white.opacity(0.16))
                                        .frame(width: 2)
                                        .padding(.leading, 18)
                                        .padding(.top, 8)
                                        .padding(.bottom, 8)

                                    LazyVStack(alignment: .leading, spacing: 16) {

                                        timelineMarker(title: "Inbox", accentIndex: 0)

                                        if !inboxReminders.isEmpty {
                                            HStack(spacing: 0) {
                                                Color.clear
                                                    .frame(width: 48)

                                                KanbanTimelineInboxColumnView(
                                                    board: board,
                                                    reminders: inboxReminders,
                                                    selectedDay: selectedDay,
                                                    boardAccent: selectedBoardAccent,
                                                    onMoveReminder: { reminder, column in
                                                        pinCard(type: .reminder, itemID: reminder.id.uuidString, in: column)
                                                    }
                                                )
                                            }
                                        }

                                        if selectedBoards.allSatisfy({ $0.sortedColumns.isEmpty }) {
                                            emptyColumnsState(board: board)
                                                .padding(.leading, 48)
                                        } else if displayedTimelineOccurrences.isEmpty {
                                            Text("No cards left for this day.")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                             .foregroundStyle(.white.opacity(0.45))
                                                .padding(.leading, 48)
                                                .padding(.vertical, 20)
                                        } else {
                                            ForEach(Array(displayedTimelineOccurrences.enumerated()), id: \.element.id) { index, occurrence in
                                                VStack(alignment: .leading, spacing: 16) {
                                                    timelineMarker(
                                                        title: timelineMarkerLabel(for: occurrence),
                                                        accentIndex: index + 1
                                                    )

                                                    HStack(spacing: 0) {
                                                        Color.clear
                                                            .frame(width: 48)

                                                        KanbanTimelineColumnView(
                                                            column: occurrence.column,
                                                            selectedDay: selectedDay,
                                                            now: timelineNow,
                                                            forcedFireDate: occurrence.fireDate,
                                                            precomputedOccurrences: displayedTimelineOccurrenceRows[
                                                                timelineOccurrenceRowKey(
                                                                    columnID: occurrence.column.id,
                                                                    fireDate: occurrence.fireDate
                                                                )
                                                            ],
                                                            allReminders: allReminders,
                                                            allRoutines: allRoutines,
                                                            allRoutineTasks: allRoutineTasks,
                                                            allHabits: allHabits,
                                                            allQuickTasks: allQuickTasks,
                                                            onCreateReminder: {
                                                                createRequest = KanbanCreateRequest(type: .reminder, column: occurrence.column)
                                                            },
                                                            onCreateHabit: {
                                                                habitCreateRequest = KanbanHabitCreateRequest(column: occurrence.column)
                                                            },
                                                            onCreateQuickTask: {
                                                                quickTaskCreateRequest = KanbanQuickTaskCreateRequest(
                                                                    column: occurrence.column,
                                                                    suggestedDate: selectedDay
                                                                )
                                                            },
                                                            onAddCard: { type, itemID in
                                                                pinCard(type: type, itemID: itemID, in: occurrence.column)
                                                            },
                                                            onAddTask: { routine in
                                                                taskCreateRequest = KanbanRoutineTaskCreateRequest(routine: routine, column: occurrence.column)
                                                            },
                                                            onEditColumn: {
                                                                editingColumn = occurrence.column
                                                            },
                                                            onComplete: triggerBanner
                                                        )
                                                    }
                                                }
                                                // ForEach already keys rows by
                                                // KanbanTimelineColumnOccurrence.id
                                                // (column + fire date). The
                                                // previous override collided
                                                // for two columns firing at
                                                // the same minute and forced
                                                // needless row recreation.
                                            }
                                        }

                                        Button {
                                            showAddColumn = true
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image("addwavy")
                                                    .renderingMode(.template)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 20, height: 20)
                                                 .foregroundStyle(LGradients.header)

                                                Text("Add Column")
                                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                                 .foregroundStyle(LColors.textSecondary)

                                                Spacer()
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 18)
                                            .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                    .strokeBorder(LColors.glassBorder, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(selectedBoards.count != 1)
                                        .opacity(selectedBoards.count == 1 ? 1 : 0.35)
                                        .padding(.leading, 48)
                                    }
                                }
                            }
                            .frame(width: proxy.size.width - 40, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 140)
                        }
                        .scrollClipDisabled(false)
                        .clipped()
                        .onAppear {
                            scrollToNowIfNeeded(using: scrollProxy)
                        }
                        .onChange(of: selectedDay) { _, _ in
                            // Reset when the user changes days so the next
                            // day's view lands on "now" again if it's today.
                            didInitialScrollToNow = false
                            scrollToNowIfNeeded(using: scrollProxy)
                        }
                        }
                    }
                } else {
                        if boards.isEmpty {
                            noBoardsState
                                .padding(.horizontal, 24)
                                .padding(.top, 30)
                        } else {
                            noBoardSelectionState
                                .padding(.horizontal, 24)
                                .padding(.top, 30)
                        }

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .modifier(
                KanbanTimelinePresentationModifier(
                    showCreateBoard: $showCreateBoard,
                    showAddColumn: $showAddColumn,
                    editingColumn: $editingColumn,
                    createRequest: $createRequest,
                    taskCreateRequest: $taskCreateRequest,
                    habitCreateRequest: $habitCreateRequest,
                    quickTaskCreateRequest: $quickTaskCreateRequest,
                    showCompletionBanner: $showCompletionBanner,
                    completionBannerMessage: completionBannerMessage,
                    selectedBoard: selectedBoard,
                    selectedBoardAccent: selectedBoardAccent,
                    boardIDs: boardIDs,
                    allReminders: allReminders,
                    allRoutines: allRoutines,
                    allRoutineTasks: allRoutineTasks,
                    allHabits: allHabits,
                    selectedDay: selectedDay,
                    defaultTimelineBoardIDsStorage: defaultTimelineBoardIDsStorage,
                    useFullScreenCover: useFullScreenCover,
                    onSyncSelectedBoard: syncSelectedBoard,
                    onPinCard: pinCard
                )
            )
            // Rebuild the two heavy caches on relevant input changes only —
            // NOT on every SwiftUI body invalidation.
            .task {
                rebuildTimelineCache()
                didInitialScrollToNow = false
            }
            .onChange(of: timelineRebuildKey) { _, _ in
                rebuildTimelineCache()
                didInitialScrollToNow = false
            }
            // One shared clock instead of one TimelineView per visible card.
            // Once-per-minute is enough for OVERDUE / DUE NOW / UPCOMING
            // labels to flip within a reasonable window.
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { newNow in
                timelineNow = newNow
            }
        }
    }

    // MARK: - Board Picker

    private func syncSelectedBoard(with ids: [UUID], preferDefault: Bool) {
        let availableIDs = Set(ids)
        let savedDefaultIDs = defaultTimelineBoardIDs.intersection(availableIDs)

        selectedBoardIDs.formIntersection(availableIDs)

        if preferDefault {
            if defaultTimelineBoardIDsStorage != nil {
                selectedBoardIDs = savedDefaultIDs
            } else if !savedDefaultIDs.isEmpty {
                selectedBoardIDs = savedDefaultIDs
            } else if !didInitializeBoardSelection, let firstID = ids.first {
                selectedBoardIDs = [firstID]
            }
        } else if !didInitializeBoardSelection, let firstID = ids.first {
            selectedBoardIDs = savedDefaultIDs.isEmpty ? [firstID] : savedDefaultIDs
        }

        if !ids.isEmpty {
            didInitializeBoardSelection = true
        }
    }

    private var boardPicker: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                    isBoardDropdownExpanded.toggle()
                }
            } label: {
                timelinePickerSurface(cornerRadius: 22, padding: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(selectedBoardAccent.opacity(0.14))
                                .frame(width: 38, height: 38)

                            if selectedBoards.count == 1, let selectedBoard {
                                Image(selectedBoard.icon)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 19, height: 19)
                                    .bubblyIconMaterial(tint: selectedBoardAccent)
                            } else {
                                Image("starcal")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 19, height: 19)
                                    .bubblyIconMaterial(tint: theme.palette.indicators)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("BOARD")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.35))
                                .tracking(0.6)

                            Text(selectedBoardPickerTitle)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(isBoardDropdownExpanded ? "chevup" : "chevdown")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .bubblyIconMaterial(tint: theme.palette.indicators)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isBoardDropdownExpanded {
                timelinePickerSurface(cornerRadius: 18, padding: 6) {
                    VStack(spacing: 5) {
                        ForEach(boards) { board in
                            boardDropdownOption(board)
                        }

                        if !boards.isEmpty {
                            Rectangle()
                                .fill(LColors.glassBorder)
                                .frame(height: 1)
                                .padding(.horizontal, 8)
                        }

                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                                isBoardDropdownExpanded = false
                            }
                            showCreateBoard = true
                        } label: {
                            HStack(spacing: 10) {
                                Image("addwavy")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .bubblyIconMaterial(tint: theme.palette.primaryAction)

                                Text("Create New Board")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func boardDropdownOption(_ board: KanbanBoard) -> some View {
        let isSelected = selectedBoardIDs.contains(board.id)
        let boardAccent = Color(lureliaHex: board.colorHex)

        return Button {
            if isSelected {
                selectedBoardIDs.remove(board.id)
            } else {
                selectedBoardIDs.insert(board.id)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(boardAccent.opacity(0.14))
                        .frame(width: 34, height: 34)

                    Image(board.icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .bubblyIconMaterial(tint: boardAccent)
                }

                Text(board.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .bubblyIconMaterial(tint: theme.palette.indicators)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? theme.palette.raisedSurface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Week Row

    private var weekRow: some View {
        timelinePickerSurface(cornerRadius: 24, padding: 12) {
            VStack(spacing: 10) {
                HStack {
                    Button {
                        moveWeek(by: -1)
                    } label: {
                        Image("chevleft")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .bubblyIconMaterial(tint: theme.palette.secondaryAccent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(weekRangeText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                       .foregroundStyle(.white.opacity(0.82))

                    Spacer()

                    Button {
                        moveWeek(by: 1)
                    } label: {
                        Image("chevright")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .bubblyIconMaterial(tint: theme.palette.secondaryAccent)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 7) {
                    ForEach(weekDays, id: \.self) { day in
                        dayButton(day)
                    }
                }
            }
        }
    }

    private func timelineMarker(title: String, accentIndex: Int) -> some View {
        let accent = rotatingThemeAccent(at: accentIndex)

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .frame(width: 14, height: 14)
                    .bubblyIconMaterial(tint: accent)

                Circle()
                    .strokeBorder(accent.opacity(0.52), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            .frame(width: 38)

            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .tracking(0.4)

            Spacer()
        }
    }

    private func timelineMarkerLabel(for occurrence: KanbanTimelineColumnOccurrence) -> String {
        let fireDate = occurrence.fireDate
        let rowKey = timelineOccurrenceRowKey(
            columnID: occurrence.column.id,
            fireDate: fireDate
        )
        let row = displayedTimelineOccurrenceRows[rowKey] ?? []
        let containsOnlyDateOnlyQuickTasks = !row.isEmpty && row.allSatisfy { item in
            guard case .quickTask(let id) = item.kind,
                  let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(id) })
            else {
                return false
            }

            return task.taskTime == nil
        }

        if containsOnlyDateOnlyQuickTasks {
            return calendar.isDate(fireDate, inSameDayAs: selectedDay)
                ? "Any Time"
                : "Any Time · \(fireDate.formatted(.dateTime.month(.abbreviated).day()))"
        }

        let time = fireDate.formatted(date: .omitted, time: .shortened)

        if calendar.isDate(fireDate, inSameDayAs: selectedDay) {
            return time
        }

        if calendar.isDateInYesterday(fireDate) {
            return "\(time) · Yesterday"
        }

        let day = fireDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(time) · \(day)"
    }

    private func timelineMarkerTitle(for column: KanbanColumn) -> String {
        guard let date = earliestVisibleFireDate(in: column) else {
            return column.name
        }

        return date.formatted(date: .omitted, time: .shortened)
    }

    private var timelineStartForSelectedDay: Date {
        calendar.startOfDay(for: selectedDay)
    }

    private var timelineEndForSelectedDay: Date {
        let start = calendar.startOfDay(for: selectedDay)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? selectedDay
    }

    private func hasVisibleFireDate(_ reminder: LureliaReminder) -> Bool {
        fireDates(for: reminder, on: selectedDay).contains { fireDate in
            fireDate >= timelineStartForSelectedDay &&
            fireDate < timelineEndForSelectedDay
        }
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func routineFireDate(_ routine: LureliaRoutine, on day: Date) -> Date? {
        guard routine.scheduleEnabled else { return nil }
        let weekday = calendar.component(.weekday, from: day)

        if !routine.scheduledDays.isEmpty,
           !routine.scheduledDays.contains(weekday) {
            return nil
        }

        return date(on: day, hour: routine.startHour, minute: routine.startMinute)
    }

    private func routineTaskFireDate(_ task: LureliaRoutineTask, on day: Date) -> Date? {
        guard task.hasDueTime else { return nil }
        let weekday = calendar.component(.weekday, from: day)

        if task.repeatsOnDays {
            if !task.scheduledDays.isEmpty,
               !task.scheduledDays.contains(weekday) {
                return nil
            }
        } else if let routine = task.routine,
                  routine.scheduleEnabled,
                  !routine.scheduledDays.isEmpty,
                  !routine.scheduledDays.contains(weekday) {
            return nil
        }

        return date(on: day, hour: task.dueHour, minute: task.dueMinute)
    }

    private func earliestVisibleFireDate(in column: KanbanColumn) -> Date? {
        var dates: [Date] = []

        for card in column.sortedCards {
            switch card.cardType {
            case .reminder:
                guard let reminder = selectedDayStandaloneReminders.first(where: { $0.id.uuidString == card.itemID }) else {
                    continue
                }

                let validDates = fireDates(for: reminder, on: selectedDay).filter { fireDate in
                    fireDate >= timelineStartForSelectedDay
                }
                dates.append(contentsOf: validDates)

            case .routine:
                if let routine = allRoutines.first(where: { $0.persistentID == card.itemID }),
                   let fireDate = routineFireDate(routine, on: selectedDay),
                   fireDate >= timelineStartForSelectedDay,
                   fireDate < timelineEndForSelectedDay {
                    dates.append(fireDate)
                }

            case .routineTask:
                if let task = allRoutineTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }),
                   let fireDate = routineTaskFireDate(task, on: selectedDay),
                   fireDate >= timelineStartForSelectedDay,
                   fireDate < timelineEndForSelectedDay {
                    dates.append(fireDate)
                }

            case .habit:
                if let habit = allHabits.first(where: { $0.matchesKanbanItemID(card.itemID) }) {
                    let habitDates = habit.fireDates(on: selectedDay, calendar: calendar).filter { fireDate in
                        fireDate >= timelineStartForSelectedDay &&
                        fireDate < timelineEndForSelectedDay
                    }
                    dates.append(contentsOf: habitDates)
                }

            case .quickTask:
                if let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }),
                   let fireDate = task.timelineDate(calendar: calendar),
                   calendar.isDate(fireDate, inSameDayAs: selectedDay) {
                    dates.append(fireDate)
                }
            }
        }

        return dates.min()
    }

    private var timelineColumns: [KanbanColumn] {
        let remainingColumns = selectedBoards.flatMap(\.sortedColumns).filter { column in
            earliestVisibleFireDate(in: column) != nil
        }

        return remainingColumns.sorted { left, right in
            let leftDate = earliestVisibleFireDate(in: left) ?? .distantFuture
            let rightDate = earliestVisibleFireDate(in: right) ?? .distantFuture

            if leftDate != rightDate {
                return leftDate < rightDate
            }

            return left.sortOrder < right.sortOrder
        }
    }

    private var weekRangeText: String {
        guard let end = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return selectedDay.formatted(date: .abbreviated, time: .omitted)
        }

        let startText = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let endText = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText) - \(endText)"
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let accent = dayAccent(for: day)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedDay = day
            }
        } label: {
            VStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.45))

                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.82))

                Circle()
                    .fill(isToday ? AnyShapeStyle(LColors.neutralPearl.opacity(0.82)) : AnyShapeStyle(Color.clear))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                if isSelected {
                    BubblyIconMaterial(tint: accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LColors.glassSurface)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accent : LColors.glassBorder.opacity(0.70), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func timelinePickerSurface<Content: View>(
        cornerRadius: CGFloat,
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content()
            .padding(padding)
            .background(
                shape
                    .fill(theme.palette.surface)
                    .overlay {
                        shape.strokeBorder(LColors.glassBorder, lineWidth: 1)
                    }
            )
    }

    private func dayAccent(for day: Date) -> Color {
        let sundayBasedIndex = max(0, calendar.component(.weekday, from: day) - 1)
        return rotatingThemeAccent(at: sundayBasedIndex)
    }

    private func rotatingThemeAccent(at index: Int) -> Color {
        let rotation = theme.palette.rotation
        guard !rotation.isEmpty else { return theme.palette.primaryAction }
        let normalizedIndex = ((index % rotation.count) + rotation.count) % rotation.count
        return rotation[normalizedIndex]
    }

    private func moveWeek(by value: Int) {
        guard let newDay = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDay) else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedDay = newDay
        }
    }

    // MARK: - Cached timeline rebuild
    //
    // Rebuild trigger: any time the raw shape of the data or the day/board
    // selection changes. Edits (title, time) that don't change array count
    // are picked up because the completion/edit callbacks bump
    // `timelineRebuildTick`, which is included in the change key.
    //
    // We deliberately don't observe every item's `updatedAt` here because
    // building that key would itself be O(all items) per body render — the
    // very thing we're trying to avoid. Explicit callback-based bumping
    // covers the common in-timeline edit cases; other views' edits will
    // reflect on the next `.onAppear`.
    private var timelineRebuildKey: String {
        let boardKey = selectedBoardIDs
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",")
        let dayKey = "\(Int(selectedDay.timeIntervalSince1970))"
        let cardCount = boards.reduce(0) { acc, board in
            acc + (board.columns?.reduce(0) { $0 + ($1.cards?.count ?? 0) } ?? 0)
        }

        // Item-level state signature. Purely count-based signatures miss
        // CloudKit-driven state changes (e.g. iPad receives a
        // completion recorded on iPhone — array size stays the same but
        // `updatedAt` on the completed task moves forward). Hashing the
        // updatedAt values is O(n) per body render but still trivial
        // compared to the O(cards × items) rebuild, and it guarantees
        // the cache never lies about post-sync state.
        var stateHasher = Hasher()
        for reminder in allReminders {
            stateHasher.combine(reminder.updatedAt)
            stateHasher.combine(reminder.completedAt)
        }
        for routine in allRoutines {
            stateHasher.combine(routine.updatedAt)
        }
        for task in allRoutineTasks {
            stateHasher.combine(task.updatedAt)
            stateHasher.combine(task.completedAt)
            stateHasher.combine(task.skippedAt)
        }
        for habit in allHabits {
            stateHasher.combine(habit.updatedAt)
        }
        for task in allQuickTasks {
            stateHasher.combine(task.updatedAt)
            stateHasher.combine(task.taskDate)
            stateHasher.combine(task.taskTime)
            stateHasher.combine(task.isCompleted)
        }
        for log in allHabitLogs {
            stateHasher.combine(log.updatedAt)
            stateHasher.combine(log.count)
            stateHasher.combine(log.completedFireTimesStorage)
        }
        let stateSig = stateHasher.finalize()

        return "\(boardKey)|\(dayKey)|\(allReminders.count)|\(allRoutines.count)|\(allHabits.count)|\(allQuickTasks.count)|\(cardCount)|\(stateSig)|\(timelineRebuildTick)"
    }

    private func rebuildTimelineCache() {
        let rows = computeTimelineOccurrenceRows()
        cachedTimelineOccurrenceRows = rows
        cachedTimelineOccurrences = computeTimelineColumnOccurrences(from: rows)
        cachedSelectedDayItemCount = computeSelectedDayScheduledItemCount()
    }

    private func timelineOccurrenceRowKey(columnID: UUID, fireDate: Date) -> String {
        "\(columnID.uuidString)::\(fireDate.timeIntervalSince1970)"
    }

    // MARK: - Auto-scroll to "now"

    /// Stable string id used for both `.id()` on each timeline row and
    /// `scrollProxy.scrollTo(...)`. Two rows at the same clock minute map
    /// to the same key, which is fine — we always resolve to a single
    /// target below.
    private func timelineScrollID(for date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "timeline-%04d-%02d-%02d-%02d-%02d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0,
            comps.hour ?? 0,
            comps.minute ?? 0
        )
    }

    /// On first appear (and whenever the selected day changes), scroll the
    /// timeline to the row whose fire time is at or just before the
    /// current moment — so it lands on "now" without preventing the user
    /// from scrolling anywhere else afterwards.
    ///
    /// Rules:
    ///   • If the selected day isn't today, do nothing (the user picked a
    ///     specific day and probably wants to see the start of it).
    ///   • If a row's fire time is ≤ now, prefer the latest such row.
    ///   • If every row is in the future, land on the earliest one.
    ///   • If there are no timed rows, do nothing.
    private func scrollToNowIfNeeded(using scrollProxy: ScrollViewProxy) {
        guard calendar.isDateInToday(selectedDay) else { return }

        let now = Date()
        let occurrences = displayedTimelineOccurrences
        guard !occurrences.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                scrollToNowIfNeeded(using: scrollProxy)
            }
            return
        }

        let target: KanbanTimelineColumnOccurrence
        if let latestPast = occurrences.filter({ $0.fireDate <= now }).max(by: { $0.fireDate < $1.fireDate }) {
            target = latestPast
        } else if let earliestFuture = occurrences.min(by: { $0.fireDate < $1.fireDate }) {
            target = earliestFuture
        } else {
            return
        }

        let id = target.id

        // Force the jump after layout settles. A second pass makes sure
        // SwiftUI lands on the correct row even if the first scroll fires
        // while the timeline is still sizing itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scrollProxy.scrollTo(id, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                scrollProxy.scrollTo(id, anchor: .top)
            }
            didInitialScrollToNow = true
        }
    }

    // MARK: - Selected Day Header

    /// **DO NOT** call this from `body`. Use `cachedSelectedDayItemCount`
    /// instead — this is the expensive counter that `rebuildTimelineCache`
    /// invokes on relevant input changes.
    private func computeSelectedDayScheduledItemCount() -> Int {
        guard !selectedBoards.isEmpty else {
            return 0
        }

        let selectedCards = selectedBoards
            .flatMap(\.sortedColumns)
            .flatMap { $0.sortedCards }

        let pinnedTaskCount = selectedCards
            .filter { card in
                guard card.cardType == .routineTask,
                      let task = allRoutineTasks.first(where: { $0.matchesKanbanItemID(card.itemID) })
                else {
                    return false
                }

                return routineTaskFireDate(task, on: selectedDay) != nil
            }
            .count

        let quickTaskIDs = Set(
            selectedCards
                .filter { $0.cardType == .quickTask }
                .map(\.itemID)
        )
        let quickTaskCount = allQuickTasks.filter { task in
            guard quickTaskIDs.contains(task.kanbanItemID),
                  let timelineDate = task.timelineDate(calendar: calendar)
            else {
                return false
            }

            return calendar.isDate(timelineDate, inSameDayAs: selectedDay)
        }.count

        return selectedDayStandaloneReminders.count + pinnedTaskCount + quickTaskCount
    }

    private var selectedDayHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDayTitle)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(cachedSelectedDayItemCount) item\(cachedSelectedDayItemCount == 1 ? "" : "s") scheduled")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Button {
                selectedDay = Date()
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background {
                        BubblyIconMaterial(tint: theme.palette.primaryAction)
                            .clipShape(Capsule())
                    }
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.palette.primaryAction, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Empty States

    private var noBoardsState: some View {
        VStack(spacing: 18) {
            Image("starcal")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .foregroundStyle(LGradients.header)

            VStack(spacing: 8) {
                Text("No Boards Yet")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Create a board to start organizing cards by timeline.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button {
                showCreateBoard = true
            } label: {
                Text("Create Board")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background { LureliaNeutralGlassSurface(cornerRadius: 20) }
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private var noBoardSelectionState: some View {
        VStack(spacing: 14) {
            Image("starcal")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .bubblyIconMaterial(tint: theme.palette.indicators)

            Text("No Boards Selected")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Choose one or more boards above to display their timeline cards.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func emptyColumnsState(board: KanbanBoard) -> some View {
        VStack(spacing: 14) {
            Image(board.icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(Color(lureliaHex: board.colorHex))

            Text("No Columns Yet")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Add columns to organize cards for this day.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)

            Button {
                showAddColumn = true
            } label: {
                Text("Add Column")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background { LureliaNeutralGlassSurface(cornerRadius: 18) }
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(LColors.glassSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LColors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func triggerBanner(_ kind: KanbanCompletionKind) {
        completionBannerMessage = kind.bannerMessage
        showCompletionBanner = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCompletionBanner = false
        }

        // NO cache rebuild here. Completed items stay visible on the
        // timeline and each card renders its own "COMPLETED" status via
        // `@Bindable`, so the row updates instantly on tap. Rebuilding
        // the whole cache used to make the tap feel laggy — the
        // O(cards × items) recompute ran on the main thread before the
        // button-press animation could commit.
    }

    private func pinCard(type: KanbanCardType, itemID: String, in column: KanbanColumn) {
        let alreadyExists = (column.cards ?? []).contains {
            $0.cardType == type && $0.itemID == itemID
        }

        guard !alreadyExists else { return }

        let card = KanbanCard(cardType: type, itemID: UUID(), sortOrder: (column.cards ?? []).count)
        card.itemID = itemID
        card.cardType = type

        modelContext.insert(card)

        if column.cards == nil {
            column.cards = []
        }

        column.cards?.append(card)
        column.board?.updatedAt = Date()

        try? modelContext.save()
    }

    private func fireDates(for reminder: LureliaReminder, on day: Date) -> [Date] {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let times = resolvedTimesOfDay(for: reminder)

        return times.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else {
                return nil
            }

            var components = dayComponents
            components.hour = hour
            components.minute = minute
            components.second = 0

            return calendar.date(from: components)
        }
        .sorted()
    }

    private func isOccurrenceCompleted(
        _ reminder: LureliaReminder,
        fireDate: Date,
        allFireDates: [Date]
    ) -> Bool {
        let completions = ([reminder.completedAt].compactMap { $0 } + reminder.completionTimestamps)
            .filter { calendar.isDate($0, inSameDayAs: selectedDay) }

        guard !completions.isEmpty else {
            return false
        }

        let sortedFireDates = allFireDates.sorted()

        guard let index = sortedFireDates.firstIndex(of: fireDate) else {
            return reminder.wasCompleted(on: selectedDay, calendar: calendar)
        }

        let nextFireDate: Date? = {
            let nextIndex = index + 1
            guard sortedFireDates.indices.contains(nextIndex) else { return nil }
            return sortedFireDates[nextIndex]
        }()

        return completions.contains { completedAt in
            completedAt >= fireDate &&
            (nextFireDate == nil || completedAt < nextFireDate!)
        }
    }

    private func resolvedTimesOfDay(for reminder: LureliaReminder) -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }

        if !stored.isEmpty {
            return stored
        }

        let hour = reminder.primaryHour != -1
            ? reminder.primaryHour
            : calendar.component(.hour, from: reminder.scheduledDate)

        let minute = reminder.primaryMinute != -1
            ? reminder.primaryMinute
            : calendar.component(.minute, from: reminder.scheduledDate)

        var times = [String(format: "%02d:%02d", hour, minute)]

        for fireTime in reminder.additionalFireTimes {
            times.append(String(format: "%02d:%02d", fireTime.hour, fireTime.minute))
        }

        return times
    }

    /// **DO NOT** call this from `body`. Use `cachedTimelineOccurrences`
    /// instead — this is the expensive builder that `rebuildTimelineCache`
    /// invokes on relevant input changes.
    ///
    /// Delegates to `KanbanTimelineEngine` so the widget target can share
    /// the exact same computation via that engine.
    private func computeTimelineColumnOccurrences() -> [KanbanTimelineColumnOccurrence] {
        var occurrences: [KanbanTimelineColumnOccurrence] = []

        for board in selectedBoards {
            occurrences.append(contentsOf: KanbanTimelineEngine.columnOccurrences(
                for: board,
                on: selectedDay,
                allReminders: allReminders,
                allRoutines: allRoutines,
                allRoutineTasks: allRoutineTasks,
                allHabits: allHabits,
                allQuickTasks: allQuickTasks,
                calendar: calendar
            ))
        }

        return occurrences.sorted { left, right in
            if left.fireDate != right.fireDate {
                return left.fireDate < right.fireDate
            }

            return left.column.sortOrder < right.column.sortOrder
        }
    }

    private func computeTimelineOccurrenceRows() -> [String: [KanbanTimelineOccurrence]] {
        guard !selectedBoards.isEmpty else { return [:] }

        var rows: [String: [KanbanTimelineOccurrence]] = [:]
        var engineOccurrences: [KanbanTimelineOccurrence] = []
        var quickTaskOccurrences: [KanbanTimelineOccurrence] = []

        for board in selectedBoards {
            engineOccurrences.append(contentsOf: KanbanTimelineEngine.occurrences(
                for: board,
                on: selectedDay,
                allReminders: allReminders,
                allRoutines: allRoutines,
                allRoutineTasks: allRoutineTasks,
                allHabits: allHabits,
                allQuickTasks: allQuickTasks,
                calendar: calendar
            ))
            quickTaskOccurrences.append(contentsOf: explicitQuickTaskOccurrences(for: board))
        }

        var insertedOccurrenceIDs: Set<String> = []

        for occurrence in engineOccurrences + quickTaskOccurrences {
            guard insertedOccurrenceIDs.insert(occurrence.id).inserted else {
                continue
            }

            guard let column = occurrence.column else { continue }
            let key = timelineOccurrenceRowKey(
                columnID: column.id,
                fireDate: occurrence.fireDate
            )
            rows[key, default: []].append(occurrence)
        }

        for key in rows.keys {
            rows[key]?.sort { left, right in
                if left.fireDate != right.fireDate {
                    return left.fireDate < right.fireDate
                }

                return left.card.sortOrder < right.card.sortOrder
            }
        }

        return rows
    }

    private func explicitQuickTaskOccurrences(
        for board: KanbanBoard
    ) -> [KanbanTimelineOccurrence] {
        let quickTasksByID = Dictionary(
            allQuickTasks.map { ($0.kanbanItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var occurrences: [KanbanTimelineOccurrence] = []

        for column in board.sortedColumns {
            for card in column.sortedCards where card.cardType == .quickTask {
                guard let task = quickTasksByID[card.itemID],
                      let fireDate = task.timelineDate(calendar: calendar),
                      calendar.isDate(fireDate, inSameDayAs: selectedDay)
                else {
                    continue
                }

                occurrences.append(
                    KanbanTimelineOccurrence(
                        card: card,
                        kind: .quickTask(task.kanbanItemID),
                        fireDate: fireDate,
                        column: column
                    )
                )
            }
        }

        return occurrences
    }

    private func computeTimelineColumnOccurrences(
        from rows: [String: [KanbanTimelineOccurrence]]
    ) -> [KanbanTimelineColumnOccurrence] {
        rows.compactMap { _, occurrences in
            guard let first = occurrences.first,
                  let column = first.column
            else {
                return nil
            }

            return KanbanTimelineColumnOccurrence(
                column: column,
                fireDate: first.fireDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate {
                return lhs.fireDate < rhs.fireDate
            }

            return lhs.column.sortOrder < rhs.column.sortOrder
        }
    }

    /// Original in-view expansion — kept here (renamed) because a handful
    /// of the private helpers it declared are still referenced by other
    /// scopes in this file. Its result is no longer consumed.
    private func computeTimelineColumnOccurrences_legacyUnused() -> [KanbanTimelineColumnOccurrence] {
        guard let board = selectedBoard else { return [] }

        // O(1) lookups per card. Without these dictionaries we scanned the
        // full arrays per card × per column × (potentially) per fire date.
        let remindersByID: [String: LureliaReminder] = Dictionary(
            uniqueKeysWithValues: allReminders.map { ($0.id.uuidString, $0) }
        )
        let routinesByID: [String: LureliaRoutine] = Dictionary(
            uniqueKeysWithValues: allRoutines.map { ($0.persistentID, $0) }
        )
        let habitsByKanbanID: [String: LureliaHabit] = Dictionary(
            allHabits.map { ($0.kanbanItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Routine tasks: only key by `kanbanItemID` (composite of routine
        // ID + stableTaskID — actually unique). Do NOT index by
        // `stableTaskID` alone: two tasks with the same title and
        // sortOrder in different routines produce the same
        // `stableTaskID`, so indexing on it would collide and drop tasks
        // silently. Legacy cards that stored the bare `stableTaskID`
        // fall back to a linear `matchesKanbanItemID` scan below.
        let routineTasksByKanbanID: [String: LureliaRoutineTask] = Dictionary(
            allRoutineTasks.map { ($0.kanbanItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let routineTaskLookup: (String) -> LureliaRoutineTask? = { itemID in
            if let hit = routineTasksByKanbanID[itemID] { return hit }
            // Legacy fallback: card's itemID is a bare `stableTaskID`.
            // If exactly ONE task matches, use it. If MULTIPLE match
            // (same title + sortOrder across different routines both
            // generate the same stableTaskID), we can't disambiguate
            // and returning the "first" one causes wrong fire times to
            // render — the exact bug the user just hit where an
            // Energy-column task showed the Nighttime task's PM time.
            // Return nil in that case so the row orphans instead of
            // silently binding to the wrong task.
            let matches = allRoutineTasks.filter { $0.matchesKanbanItemID(itemID) }
            return matches.count == 1 ? matches.first : nil
        }

        var occurrences: [KanbanTimelineColumnOccurrence] = []
        let showOverdue = calendar.isDateInToday(selectedDay)
        let startOfSelectedDay = calendar.startOfDay(for: selectedDay)

        for column in board.sortedColumns {
            var fireDatesForColumn: [Date] = []

            for card in column.sortedCards {
                switch card.cardType {
                case .reminder:
                    guard let reminder = remindersByID[card.itemID] else {
                        continue
                    }

                    // Today's occurrences. Completed items stay visible on
                    // the current-day timeline — the reminder card renders
                    // its own "COMPLETED" status so the user can see what
                    // they knocked out today rather than having rows vanish
                    // out from under them.
                    if reminder.isDue(on: selectedDay, calendar: calendar) {
                        let dayFireDates = fireDates(for: reminder, on: selectedDay)
                        let dates = dayFireDates.filter { fireDate in
                            fireDate >= timelineStartForSelectedDay &&
                            fireDate < timelineEndForSelectedDay
                        }
                        fireDatesForColumn.append(contentsOf: dates)
                    }

                    // Prior-day missed occurrences (only when viewing today).
                    if showOverdue {
                        let missedDays = overdueDays(for: reminder, before: startOfSelectedDay)
                        for missedDay in missedDays {
                            let dayFireDates = fireDates(for: reminder, on: missedDay)
                            let missedFires = dayFireDates.filter { fireDate in
                                !isOccurrenceCompleted(reminder, fireDate: fireDate, allFireDates: dayFireDates, on: missedDay)
                            }
                            fireDatesForColumn.append(contentsOf: missedFires)
                        }
                    }

                case .routine:
                    guard let routine = routinesByID[card.itemID],
                          let fireDate = routineFireDate(routine, on: selectedDay),
                          fireDate >= timelineStartForSelectedDay,
                          fireDate < timelineEndForSelectedDay
                    else {
                        continue
                    }

                    fireDatesForColumn.append(fireDate)

                case .routineTask:
                    guard let task = routineTaskLookup(card.itemID),
                          let fireDate = routineTaskFireDate(task, on: selectedDay),
                          fireDate >= timelineStartForSelectedDay,
                          fireDate < timelineEndForSelectedDay
                    else {
                        continue
                    }

                    fireDatesForColumn.append(fireDate)

                case .habit:
                    guard let habit = habitsByKanbanID[card.itemID] else {
                        continue
                    }

                    let dates = habit.fireDates(on: selectedDay, calendar: calendar)
                        .filter { fireDate in
                            fireDate >= timelineStartForSelectedDay &&
                            fireDate < timelineEndForSelectedDay
                        }

                    fireDatesForColumn.append(contentsOf: dates)

                case .quickTask:
                    guard let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }),
                          let fireDate = task.timelineDate(calendar: calendar),
                          calendar.isDate(fireDate, inSameDayAs: selectedDay)
                    else {
                        continue
                    }

                    fireDatesForColumn.append(fireDate)
                }
            }

            let uniqueDates = Array(Set(fireDatesForColumn)).sorted()

            for fireDate in uniqueDates {
                occurrences.append(
                    KanbanTimelineColumnOccurrence(
                        column: column,
                        fireDate: fireDate
                    )
                )
            }
        }

        return occurrences.sorted { left, right in
            if left.fireDate != right.fireDate {
                return left.fireDate < right.fireDate
            }

            return left.column.sortOrder < right.column.sortOrder
        }
    }

    private func overdueDays(for reminder: LureliaReminder, before startOfDay: Date) -> [Date] {
        guard reminder.kind == .standalone, reminder.isEnabled else { return [] }

        let scheduledDay = calendar.startOfDay(for: reminder.scheduledDate)
        guard scheduledDay < startOfDay else { return [] }

        if reminder.repeatUnit == .none {
            return reminder.isCompleted ? [] : [scheduledDay]
        }

        // Repeating: return only the MOST RECENT missed occurrence day.
        // Walking further back would flood the timeline with old occurrences
        // from any pinned reminder that's been sitting around. Bounded to
        // 30 days so a repeating reminder whose most-recent miss doesn't
        // match a recent weekday can't burn a per-iteration `isDue` call
        // across hundreds of days every render (a big scroll-jank source).
        let daysBetween = calendar.dateComponents([.day], from: scheduledDay, to: startOfDay).day ?? 0
        let lookback = min(max(daysBetween, 0), 30)
        guard lookback > 0 else { return [] }

        for daysBack in 1...lookback {
            guard let pastDay = calendar.date(byAdding: .day, value: -daysBack, to: startOfDay) else { continue }

            if reminder.isDue(on: pastDay, calendar: calendar) {
                if reminder.wasCompleted(on: pastDay, calendar: calendar) {
                    return []
                }
                return [pastDay]
            }
        }
        return []
    }

    private func isOccurrenceCompleted(
        _ reminder: LureliaReminder,
        fireDate: Date,
        allFireDates: [Date],
        on day: Date
    ) -> Bool {
        let completions = ([reminder.completedAt].compactMap { $0 } + reminder.completionTimestamps)
            .filter { calendar.isDate($0, inSameDayAs: day) }

        guard !completions.isEmpty else { return false }

        let sortedFireDates = allFireDates.sorted()

        guard let index = sortedFireDates.firstIndex(of: fireDate) else {
            return reminder.wasCompleted(on: day, calendar: calendar)
        }

        let nextFireDate: Date? = {
            let nextIndex = index + 1
            guard sortedFireDates.indices.contains(nextIndex) else { return nil }
            return sortedFireDates[nextIndex]
        }()

        return completions.contains { completedAt in
            completedAt >= fireDate &&
            (nextFireDate == nil || completedAt < nextFireDate!)
        }
    }
}

// MARK: - Kanban Timeline Presentation

private struct KanbanTimelinePresentationModifier: ViewModifier {
    @Binding var showCreateBoard: Bool
    @Binding var showAddColumn: Bool
    @Binding var editingColumn: KanbanColumn?
    @Binding var createRequest: KanbanCreateRequest?
    @Binding var taskCreateRequest: KanbanRoutineTaskCreateRequest?
    @Binding var habitCreateRequest: KanbanHabitCreateRequest?
    @Binding var quickTaskCreateRequest: KanbanQuickTaskCreateRequest?
    @Binding var showCompletionBanner: Bool
    let completionBannerMessage: String

    let selectedBoard: KanbanBoard?
    let selectedBoardAccent: Color
    let boardIDs: [UUID]
    let allReminders: [LureliaReminder]
    let allRoutines: [LureliaRoutine]
    let allRoutineTasks: [LureliaRoutineTask]
    let allHabits: [LureliaHabit]
    let selectedDay: Date
    let defaultTimelineBoardIDsStorage: Data?
    let useFullScreenCover: Bool
    let onSyncSelectedBoard: ([UUID], Bool) -> Void
    let onPinCard: (KanbanCardType, String, KanbanColumn) -> Void

    func body(content: Content) -> some View {
        let baseContent = content
            .ignoresSafeArea(edges: .top)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .completionBanner(isShowing: showCompletionBanner, message: completionBannerMessage)
            .onAppear {
                onSyncSelectedBoard(boardIDs, true)
            }
            .onChange(of: boardIDs) { _, ids in
                onSyncSelectedBoard(ids, false)
            }
            .onChange(of: defaultTimelineBoardIDsStorage) { _, _ in
                onSyncSelectedBoard(boardIDs, true)
            }

        let boardPresentation = baseContent
            .sheet(isPresented: $showCreateBoard) {
                KanbanTimelineCreateBoardSheet()
            }

        let columnPresentation = boardPresentation
            .sheet(isPresented: Binding(
                get: { !useFullScreenCover && showAddColumn },
                set: { showAddColumn = $0 }
            )) {
                if let selectedBoard {
                    KanbanTimelineColumnSheet(board: selectedBoard)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { useFullScreenCover && showAddColumn },
                set: { showAddColumn = $0 }
            )) {
                if let selectedBoard {
                    KanbanTimelineColumnSheet(board: selectedBoard)
                }
            }
            .sheet(item: Binding(
                get: { useFullScreenCover ? nil : editingColumn },
                set: { editingColumn = $0 }
            )) { column in
                if let selectedBoard {
                    KanbanTimelineColumnSheet(board: selectedBoard, column: column)
                }
            }
            .fullScreenCover(item: Binding(
                get: { useFullScreenCover ? editingColumn : nil },
                set: { editingColumn = $0 }
            )) { column in
                if let selectedBoard {
                    KanbanTimelineColumnSheet(board: selectedBoard, column: column)
                }
            }

        let reminderPresentation = columnPresentation
            .sheet(item: Binding(
                get: { useFullScreenCover ? nil : createRequest },
                set: { createRequest = $0 }
            )) { request in
                LureliaReminderCreationFlow(onCreated: { reminder in
                    reminder.kind = .standalone
                    onPinCard(.reminder, reminder.id.uuidString, request.column)
                })
            }
            .fullScreenCover(item: Binding(
                get: { useFullScreenCover ? createRequest : nil },
                set: { createRequest = $0 }
            )) { request in
                LureliaReminderCreationFlow(onCreated: { reminder in
                    reminder.kind = .standalone
                    onPinCard(.reminder, reminder.id.uuidString, request.column)
                })
            }

        let routineTaskPresentation = reminderPresentation
            .sheet(item: Binding(
                get: { useFullScreenCover ? nil : taskCreateRequest },
                set: { taskCreateRequest = $0 }
            )) { request in
                KanbanRoutineTaskCreationSheet(routine: request.routine) { task in
                    onPinCard(.routineTask, task.kanbanItemID, request.column)
                }
            }
            .fullScreenCover(item: Binding(
                get: { useFullScreenCover ? taskCreateRequest : nil },
                set: { taskCreateRequest = $0 }
            )) { request in
                KanbanRoutineTaskCreationSheet(routine: request.routine) { task in
                    onPinCard(.routineTask, task.kanbanItemID, request.column)
                }
            }

        let habitPresentation = routineTaskPresentation
            .sheet(item: Binding(
                get: { useFullScreenCover ? nil : habitCreateRequest },
                set: { habitCreateRequest = $0 }
            )) { request in
                LureliaHabitFormSheet(
                    habit: nil,
                    onSaved: { habit in
                        onPinCard(.habit, habit.kanbanItemID, request.column)
                    },
                    onClose: {
                        habitCreateRequest = nil
                    }
                )
            }
            .fullScreenCover(item: Binding(
                get: { useFullScreenCover ? habitCreateRequest : nil },
                set: { habitCreateRequest = $0 }
            )) { request in
                LureliaHabitFormSheet(
                    habit: nil,
                    onSaved: { habit in
                        onPinCard(.habit, habit.kanbanItemID, request.column)
                    },
                    onClose: {
                        habitCreateRequest = nil
                    }
                )
            }

        let quickTaskPresentation = habitPresentation
            .sheet(item: Binding(
                get: { useFullScreenCover ? nil : quickTaskCreateRequest },
                set: { quickTaskCreateRequest = $0 }
            )) { request in
                AddKanbanQuickTaskSheet(
                    column: request.column,
                    suggestedDate: request.suggestedDate ?? selectedDay
                )
            }
            .fullScreenCover(item: Binding(
                get: { useFullScreenCover ? quickTaskCreateRequest : nil },
                set: { quickTaskCreateRequest = $0 }
            )) { request in
                AddKanbanQuickTaskSheet(
                    column: request.column,
                    suggestedDate: request.suggestedDate ?? selectedDay
                )
            }

        return quickTaskPresentation
            .navigationDestination(for: UUID.self) { reminderID in
                if let reminder = allReminders.first(where: { $0.id == reminderID }) {
                    ReminderDetailView(reminder: reminder)
                } else if let habit = allHabits.first(where: { $0.id == reminderID }) {
                    HabitBlueprintDetailView(habit: habit)
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if allRoutines.contains(where: { $0.id == id }) {
                    RoutineDetailView(routineID: id)
                } else if let task = allRoutineTasks.first(where: { $0.id == id }) {
                    RoutineTaskDetailView(
                        task: task,
                        routineTint: task.routineTaskTint
                    )
                }
            }
    }
}

// MARK: - Kanban Timeline Occurrence
//
// `KanbanTimelineOccurrenceKind`, `KanbanTimelineOccurrence`, and
// `KanbanTimelineColumnOccurrence` used to be defined here. They now live
// in `Utilities/KanbanTimelineEngine.swift` so widgets and other consumers
// can reference the exact same types the app timeline uses.

private extension LureliaRoutineTask {
    var routineTaskTint: Color {
        Color(lureliaHex: routine?.colorHex ?? "#7d19f7")
    }
}

enum KanbanTimelineDisplayRow: Identifiable {
    case occurrence(KanbanTimelineOccurrence)

    var id: String {
        switch self {
        case .occurrence(let occurrence):
            return "occurrence-\(occurrence.id)"
        }
    }

    var fireDate: Date {
        switch self {
        case .occurrence(let occurrence):
            return occurrence.fireDate
        }
    }

    var sortOrder: Int {
        switch self {
        case .occurrence(let occurrence):
            return occurrence.card.sortOrder
        }
    }
}

// MARK: - Kanban Timeline Column View

struct KanbanTimelineColumnView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var column: KanbanColumn
    @State private var editingReminder: LureliaReminder?
    @State private var editingRoutineTask: LureliaRoutineTask?
    @State private var editingHabit: LureliaHabit?
    @Query private var allBoards: [KanbanBoard]

    let selectedDay: Date
    /// Shared clock pushed down from the root timeline. Cards use this in
    /// place of their own per-card `TimelineView(.periodic)` so status
    /// labels (OVERDUE / DUE NOW / UPCOMING) update without every card
    /// re-entering SwiftUI's body pipeline twice a minute.
    let now: Date
    var forcedFireDate: Date? = nil
    var precomputedOccurrences: [KanbanTimelineOccurrence]? = nil
    let allReminders: [LureliaReminder]
    let allRoutines: [LureliaRoutine]
    let allRoutineTasks: [LureliaRoutineTask]
    let allHabits: [LureliaHabit]
    let allQuickTasks: [KanbanQuickTask]
    let onCreateReminder: () -> Void
    let onCreateHabit: () -> Void
    let onCreateQuickTask: () -> Void
    let onAddCard: (KanbanCardType, String) -> Void
    let onAddTask: (LureliaRoutine) -> Void
    let onEditColumn: () -> Void
    /// Fires when the user taps a card's complete/skip control. The kind
    /// tells the parent what got completed so the banner can pick the
    /// right message.
    var onComplete: ((KanbanCompletionKind) -> Void)? = nil

    private var accentColor: Color {
        Color(lureliaHex: column.colorHex)
    }

    private var visibleOccurrences: [KanbanTimelineOccurrence] {
        if let precomputedOccurrences {
            return precomputedOccurrences
        }

        // O(1) lookups per card instead of O(n) linear scans.
        let remindersByID: [String: LureliaReminder] = Dictionary(
            uniqueKeysWithValues: allReminders.map { ($0.id.uuidString, $0) }
        )
        let routinesByID: [String: LureliaRoutine] = Dictionary(
            uniqueKeysWithValues: allRoutines.map { ($0.persistentID, $0) }
        )
        let habitsByKanbanID: [String: LureliaHabit] = Dictionary(
            allHabits.map { ($0.kanbanItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let quickTasksByKanbanID: [String: KanbanQuickTask] = Dictionary(
            allQuickTasks.map { ($0.kanbanItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Routine tasks: key by composite `kanbanItemID` (routine ID +
        // stableTaskID). Never index by bare `stableTaskID` — two tasks
        // with the same title and sortOrder produce the same
        // `stableTaskID` and would collide in the dict, silently
        // collapsing distinct tasks. Legacy cards that stored the bare
        // stableTaskID fall back to a linear `matchesKanbanItemID` scan.
        let routineTasksByKanbanID: [String: LureliaRoutineTask] = Dictionary(
            allRoutineTasks.map { ($0.kanbanItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let routineTaskLookup: (String) -> LureliaRoutineTask? = { itemID in
            if let hit = routineTasksByKanbanID[itemID] { return hit }
            return allRoutineTasks.first { $0.matchesKanbanItemID(itemID) }
        }

        var occurrences: [KanbanTimelineOccurrence] = []

        for card in column.sortedCards {
            switch card.cardType {
            case .reminder:
                guard let reminder = remindersByID[card.itemID] else {
                    continue
                }

                if let forcedFireDate {
                    guard reminder.isDue(on: forcedFireDate, calendar: .current) else {
                        continue
                    }

                    // Verify the reminder actually fires at this moment on that day
                    // (handles both today and prior-day overdue occurrences).
                    let dayFireDates = fireDatesForDay(reminder, day: forcedFireDate)
                    if dayFireDates.contains(where: { abs($0.timeIntervalSince(forcedFireDate)) < 60 }) {
                        occurrences.append(
                            KanbanTimelineOccurrence(
                                card: card,
                                kind: .reminder(reminder.id.uuidString),
                                fireDate: forcedFireDate
                            )
                        )
                    }
                } else {
                    guard reminder.isDue(on: selectedDay, calendar: .current) else {
                        continue
                    }

                    for fireDate in fireDatesForDay(reminder, day: selectedDay) {
                        occurrences.append(
                            KanbanTimelineOccurrence(
                                card: card,
                                kind: .reminder(reminder.id.uuidString),
                                fireDate: fireDate
                            )
                        )
                    }
                }

            case .routine:
                guard let routine = routinesByID[card.itemID] else {
                    continue
                }

                let day = forcedFireDate ?? selectedDay
                guard let fireDate = fireDate(for: routine, on: day),
                      forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60
                else {
                    continue
                }

                occurrences.append(
                    KanbanTimelineOccurrence(
                        card: card,
                        kind: .routine(routine.persistentID),
                        fireDate: fireDate
                    )
                )

            case .routineTask:
                guard let task = routineTaskLookup(card.itemID) else {
                    continue
                }

                let day = forcedFireDate ?? selectedDay
                guard let fireDate = fireDate(for: task, on: day),
                      forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60
                else {
                    continue
                }

                occurrences.append(
                    KanbanTimelineOccurrence(
                        card: card,
                        kind: .routineTask(task.kanbanItemID),
                        fireDate: fireDate
                    )
                )

            case .habit:
                guard let habit = habitsByKanbanID[card.itemID] else {
                    continue
                }

                let day = forcedFireDate ?? selectedDay
                for fireDate in habit.fireDates(on: day) {
                    guard forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60 else {
                        continue
                    }

                    occurrences.append(
                        KanbanTimelineOccurrence(
                            card: card,
                            kind: .habit(habit.kanbanItemID),
                            fireDate: fireDate
                        )
                    )
                }

            case .quickTask:
                guard let task = quickTasksByKanbanID[card.itemID],
                      let fireDate = task.timelineDate(),
                      Calendar.current.isDate(fireDate, inSameDayAs: forcedFireDate ?? selectedDay),
                      forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60
                else {
                    continue
                }

                occurrences.append(
                    KanbanTimelineOccurrence(
                        card: card,
                        kind: .quickTask(task.kanbanItemID),
                        fireDate: fireDate
                    )
                )
            }
        }

        return occurrences.sorted { left, right in
            if left.fireDate != right.fireDate {
                return left.fireDate < right.fireDate
            }

            return left.card.sortOrder < right.card.sortOrder
        }
    }

    private var visibleDisplayRows: [KanbanTimelineDisplayRow] {
        visibleOccurrences.map { .occurrence($0) }.sorted { left, right in
            if left.fireDate != right.fireDate {
                return left.fireDate < right.fireDate
            }

            return left.sortOrder < right.sortOrder
        }
    }

    private func fireDate(for routine: LureliaRoutine, on day: Date) -> Date? {
        guard routine.scheduleEnabled else { return nil }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: day)

        if !routine.scheduledDays.isEmpty,
           !routine.scheduledDays.contains(weekday) {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = routine.startHour
        components.minute = routine.startMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func fireDate(for task: LureliaRoutineTask, on day: Date) -> Date? {
        guard task.hasDueTime else { return nil }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: day)

        if task.repeatsOnDays {
            if !task.scheduledDays.isEmpty,
               !task.scheduledDays.contains(weekday) {
                return nil
            }
        } else if let routine = task.routine,
                  routine.scheduleEnabled,
                  !routine.scheduledDays.isEmpty,
                  !routine.scheduledDays.contains(weekday) {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = task.dueHour
        components.minute = task.dueMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private func occurrence(for card: KanbanCard, forcedFireDate: Date? = nil) -> [KanbanTimelineOccurrence] {
        switch card.cardType {
        case .reminder:
            guard let reminder = allReminders.first(where: { $0.id.uuidString == card.itemID }) else {
                return []
            }

            if let forcedFireDate {
                guard reminder.isDue(on: forcedFireDate, calendar: .current) else { return [] }
                let dayFireDates = fireDatesForDay(reminder, day: forcedFireDate)
                guard dayFireDates.contains(where: { abs($0.timeIntervalSince(forcedFireDate)) < 60 }) else { return [] }
                return [
                    KanbanTimelineOccurrence(
                        card: card,
                        kind: .reminder(reminder.id.uuidString),
                        fireDate: forcedFireDate
                    )
                ]
            }

            guard reminder.isDue(on: selectedDay, calendar: .current) else { return [] }
            return fireDatesForDay(reminder, day: selectedDay).map { fireDate in
                KanbanTimelineOccurrence(
                    card: card,
                    kind: .reminder(reminder.id.uuidString),
                    fireDate: fireDate
                )
            }

        case .routine:
            guard let routine = allRoutines.first(where: { $0.persistentID == card.itemID }) else {
                return []
            }

            let day = forcedFireDate ?? selectedDay
            guard let fireDate = fireDate(for: routine, on: day),
                  forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60
            else {
                return []
            }

            return [
                KanbanTimelineOccurrence(
                    card: card,
                    kind: .routine(routine.persistentID),
                    fireDate: fireDate
                )
            ]

        case .routineTask:
            guard let task = allRoutineTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }) else {
                return []
            }

            let day = forcedFireDate ?? selectedDay
            guard let fireDate = fireDate(for: task, on: day),
                  forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60
            else {
                return []
            }

            return [
                KanbanTimelineOccurrence(
                    card: card,
                    kind: .routineTask(task.kanbanItemID),
                    fireDate: fireDate
                )
            ]

        case .habit:
            guard let habit = allHabits.first(where: { $0.matchesKanbanItemID(card.itemID) }) else {
                return []
            }

            let day = forcedFireDate ?? selectedDay
            return habit.fireDates(on: day).compactMap { fireDate in
                guard forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60 else {
                    return nil
                }

                return KanbanTimelineOccurrence(
                    card: card,
                    kind: .habit(habit.kanbanItemID),
                    fireDate: fireDate
                )
            }

        case .quickTask:
            guard let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }),
                  let fireDate = task.timelineDate(),
                  Calendar.current.isDate(fireDate, inSameDayAs: forcedFireDate ?? selectedDay),
                  forcedFireDate == nil || abs(fireDate.timeIntervalSince(forcedFireDate!)) < 60
            else {
                return []
            }

            return [
                KanbanTimelineOccurrence(
                    card: card,
                    kind: .quickTask(task.kanbanItemID),
                    fireDate: fireDate
                )
            ]
        }
    }

    private func fireDatesForDay(_ reminder: LureliaReminder, day: Date) -> [Date] {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let times = resolvedTimesOfDay(for: reminder)

        return times.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else {
                return nil
            }

            var components = dayComponents
            components.hour = hour
            components.minute = minute
            components.second = 0

            return calendar.date(from: components)
        }
        .sorted()
    }

    private func resolvedTimesOfDay(for reminder: LureliaReminder) -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }

        if !stored.isEmpty {
            return stored
        }

        let calendar = Calendar.current

        let hour = reminder.primaryHour != -1
            ? reminder.primaryHour
            : calendar.component(.hour, from: reminder.scheduledDate)

        let minute = reminder.primaryMinute != -1
            ? reminder.primaryMinute
            : calendar.component(.minute, from: reminder.scheduledDate)

        var times = [String(format: "%02d:%02d", hour, minute)]

        for fireTime in reminder.additionalFireTimes {
            times.append(String(format: "%02d:%02d", fireTime.hour, fireTime.minute))
        }

        return times
    }

    var body: some View {
        let displayRows = visibleDisplayRows

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(column.name)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(displayRows.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(kanbanReadableAccentText(accentColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.14), in: Capsule())

                KanbanColumnAddCardMenu(
                    column: column,
                    allReminders: allReminders,
                    allRoutines: allRoutines,
                    allHabits: allHabits,
                    onCreateReminder: onCreateReminder,
                    onCreateHabit: onCreateHabit,
                    onCreateQuickTask: onCreateQuickTask,
                    onAddCard: onAddCard,
                    onAddTask: onAddTask
                ) {
                    Image("addwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(accentColor)
                        .bubblyIconMaterial(tint: accentColor)
                        .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            VStack(spacing: 10) {
                ForEach(displayRows) { row in
                    displayRow(row)
                }

                if displayRows.isEmpty {
                    VStack(spacing: 8) {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                          .foregroundStyle(LColors.textSecondary.opacity(0.4))

                        Text("No cards for this day")
                            .font(.system(size: 12, design: .rounded))
                          .foregroundStyle(LColors.textSecondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(
                tint: accentColor,
                cornerRadius: 22
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(item: Binding(
            get: {
                UIDevice.current.userInterfaceIdiom == .pad ? nil : editingReminder
            },
            set: {
                editingReminder = $0
            }
        )) { reminder in
            AddReminderView(editingReminder: reminder)
        }
        .fullScreenCover(item: Binding(
            get: {
                UIDevice.current.userInterfaceIdiom == .pad ? editingReminder : nil
            },
            set: {
                editingReminder = $0
            }
        )) { reminder in
            AddReminderView(editingReminder: reminder)
        }
        .routineTaskEditor(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            task: $editingRoutineTask,
            routineTint: editingRoutineTask?.routineTaskTint ?? LColors.gradientPurple
        )
        .sheet(item: Binding(
            get: {
                UIDevice.current.userInterfaceIdiom == .pad ? nil : editingHabit
            },
            set: { editingHabit = $0 }
        )) { habit in
            LureliaHabitFormSheet(habit: habit, onClose: { editingHabit = nil })
        }
        .fullScreenCover(item: Binding(
            get: {
                UIDevice.current.userInterfaceIdiom == .pad ? editingHabit : nil
            },
            set: { editingHabit = $0 }
        )) { habit in
            LureliaHabitFormSheet(habit: habit, onClose: { editingHabit = nil })
        }
        .contextMenu {
            Button {
                onEditColumn()
            } label: {
                HStack {
                    Image("pencil")
                        .renderingMode(.template)

                    Text("Edit Column")
                }
            }

            Divider()

            Button(role: .destructive) {
                deleteColumn()
            } label: {
                HStack {
                    Image("trash")
                        .renderingMode(.template)

                    Text("Delete Column")
                }
            }
        }
    }

    private var timelineAllCards: [KanbanCard] {
        allBoards.flatMap { $0.columns ?? [] }.flatMap { $0.cards ?? [] }
    }

    private var timelinePinnedReminderIDs: Set<String> {
        Set(timelineAllCards.filter { $0.cardType == .reminder }.map(\.itemID))
    }

    private var timelinePinnedRoutineTaskIDs: Set<String> {
        Set(
            timelineAllCards
                .filter { $0.cardType == .routineTask }
                .compactMap { card in
                    allRoutineTasks.first { $0.matchesKanbanItemID(card.itemID) }?.kanbanItemID
                }
        )
    }

    private var timelinePinnedHabitIDs: Set<String> {
        Set(timelineAllCards.filter { $0.cardType == .habit }.map(\.itemID))
    }

    @ViewBuilder
    private func displayRow(_ row: KanbanTimelineDisplayRow) -> some View {
        switch row {
        case .occurrence(let occurrence):
            KanbanTimelineOccurrenceCard(
                occurrence: occurrence,
                selectedDay: selectedDay,
                now: now,
                allReminders: allReminders,
                allRoutines: allRoutines,
                allRoutineTasks: allRoutineTasks,
                allHabits: allHabits,
                allQuickTasks: allQuickTasks,
                accent: accentColor,
                onDelete: { deleteCard(occurrence.card) },
                onEditReminder: { reminder in
                    editingReminder = reminder
                },
                onEditTask: { task in
                    editingRoutineTask = task
                },
                onEditHabit: { habit in
                    editingHabit = habit
                },
                onComplete: onComplete
            )
            .contextMenu {
                cardContextMenu(for: occurrence.card)
            }

        }
    }

    @ViewBuilder
    private func cardContextMenu(for card: KanbanCard) -> some View {
        ForEach(availableMoveColumns(for: card)) { targetColumn in
            Button {
                moveCard(card, to: targetColumn)
            } label: {
                HStack {
                    Image("rightwavy")
                        .renderingMode(.template)

                    Text("Move to \(targetColumn.name)")
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            deleteCard(card)
        } label: {
            HStack {
                Image("trash")
                    .renderingMode(.template)

                Text("Delete Card")
            }
        }
    }

    private func deleteCard(_ card: KanbanCard) {
        if card.cardType == .quickTask,
           let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }) {
            modelContext.delete(task)
        }

        modelContext.delete(card)
        try? modelContext.save()
    }

    private func deleteColumn() {
        if let cards = column.cards {
            for card in cards {
                modelContext.delete(card)
            }
        }

        modelContext.delete(column)
        try? modelContext.save()
    }

    private func availableMoveColumns(for card: KanbanCard) -> [KanbanColumn] {
        column.board?.sortedColumns.filter { $0.id != column.id } ?? []
    }

    private func moveCard(_ card: KanbanCard, to targetColumn: KanbanColumn) {
        guard targetColumn.id != column.id else { return }

        if card.cardType == .quickTask,
           let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(card.itemID) }) {
            column.quickTasks = (column.quickTasks ?? []).filter { $0.id != task.id }
            if targetColumn.quickTasks == nil {
                targetColumn.quickTasks = []
            }
            targetColumn.quickTasks?.append(task)
            task.updatedAt = Date()
        }

        column.cards = (column.cards ?? []).filter { $0.id != card.id }

        card.sortOrder = (targetColumn.cards ?? []).count

        if targetColumn.cards == nil {
            targetColumn.cards = []
        }

        targetColumn.cards?.append(card)

        for (index, card) in (column.cards ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            card.sortOrder = index
        }

        for (index, card) in (targetColumn.cards ?? []).sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            card.sortOrder = index
        }

        try? modelContext.save()
    }
}

// MARK: - Kanban Timeline Item Card

struct KanbanTimelineItemCard: View {
    let card: KanbanCard
    let selectedDay: Date
    let now: Date
    let allReminders: [LureliaReminder]
    let accent: Color
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    var body: some View {
        if card.cardType == .reminder,
           let reminder = allReminders.first(where: { $0.id.uuidString == card.itemID }) {
            NavigationLink(value: reminder.id) {
                KanbanTimelineReminderCard(
                    reminder: reminder,
                    selectedDay: selectedDay,
                    now: now,
                    accent: accent,
                    onDelete: onDelete,
                    onEdit: { },
                    onComplete: onComplete
                )
            }
            .buttonStyle(.plain)
        } else {
            orphanCard
        }
    }

    private var orphanCard: some View {
        HStack(spacing: 10) {
            Image("warnwavy")
                .renderingMode(.template)
                .foregroundStyle(LColors.textSecondary)

            Text("Item deleted")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(LColors.textSecondary)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image("trash")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color(lureliaHex: "#0db7d9"))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(LColors.glassSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Kanban Timeline Occurrence Card

struct KanbanTimelineOccurrenceCard: View {
    let occurrence: KanbanTimelineOccurrence
    let selectedDay: Date
    /// Shared clock from the root timeline. Threaded into each time-
    /// sensitive card so they can compute their status labels without
    /// installing their own `TimelineView(.periodic)`.
    let now: Date
    let allReminders: [LureliaReminder]
    let allRoutines: [LureliaRoutine]
    let allRoutineTasks: [LureliaRoutineTask]
    let allHabits: [LureliaHabit]
    let allQuickTasks: [KanbanQuickTask]
    let accent: Color
    let onDelete: () -> Void
    let onEditReminder: (LureliaReminder) -> Void
    let onEditTask: (LureliaRoutineTask) -> Void
    let onEditHabit: (LureliaHabit) -> Void
    /// Kind-aware completion callback. This dispatcher wraps it into a
    /// plain `() -> Void` per card-kind, so the leaf cards don't need to
    /// know about `KanbanCompletionKind`.
    var onComplete: ((KanbanCompletionKind) -> Void)? = nil

    var body: some View {
        switch occurrence.kind {
        case .reminder(let id):
            if let reminder = allReminders.first(where: { $0.id.uuidString == id }) {
                NavigationLink(value: reminder.id) {
                    KanbanTimelineReminderCard(
                        reminder: reminder,
                        selectedDay: selectedDay,
                        now: now,
                        forcedFireDate: occurrence.fireDate,
                        accent: accent,
                        onDelete: onDelete,
                        onEdit: { onEditReminder(reminder) },
                        onComplete: { onComplete?(.reminder) }
                    )
                }
                .buttonStyle(.plain)
            } else {
                orphanCard
            }

        case .routine(let id):
            if let routine = allRoutines.first(where: { $0.persistentID == id }) {
                KanbanTimelineRoutineOccurrenceCard(
                    routine: routine,
                    fireDate: occurrence.fireDate,
                    accent: accent,
                    onDelete: onDelete
                )
            } else {
                orphanCard
            }

        case .routineTask(let id):
            if let task = allRoutineTasks.first(where: { $0.matchesKanbanItemID(id) }) {
                NavigationLink(value: task.id) {
                    KanbanTimelineRoutineTaskOccurrenceCard(
                        task: task,
                        fireDate: occurrence.fireDate,
                        now: now,
                        accent: accent,
                        onDelete: onDelete,
                        onEdit: { onEditTask(task) },
                        onComplete: { onComplete?(.routineTask) }
                    )
                }
                .buttonStyle(.plain)
            } else {
                orphanCard
            }

        case .habit(let id):
            if let habit = allHabits.first(where: { $0.matchesKanbanItemID(id) }) {
                NavigationLink(value: habit.id) {
                    KanbanTimelineHabitOccurrenceCard(
                        habit: habit,
                        fireDate: occurrence.fireDate,
                        now: now,
                        accent: accent,
                        onDelete: onDelete,
                        onEdit: { onEditHabit(habit) },
                        onComplete: { onComplete?(.habit) }
                    )
                }
                .buttonStyle(.plain)
            } else {
                orphanCard
            }

        case .quickTask(let id):
            if let task = allQuickTasks.first(where: { $0.matchesKanbanItemID(id) }),
               let column = occurrence.column ?? task.column {
                KanbanTimelineQuickTaskCard(
                    task: task,
                    column: column,
                    accent: accent,
                    onDelete: onDelete,
                    onComplete: { onComplete?(.quickTask) }
                )
            } else {
                orphanCard
            }
        }
    }

    private var orphanCard: some View {
        HStack(spacing: 10) {
            Image("warnwavy")
                .renderingMode(.template)
                .foregroundStyle(LColors.textSecondary)

            Text("Item deleted")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(LColors.textSecondary)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image("trash")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color(lureliaHex: "#0db7d9"))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(LColors.glassSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Timeline Quick Task Card

struct KanbanTimelineQuickTaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: KanbanQuickTask
    let column: KanbanColumn
    let accent: Color
    let onDelete: () -> Void
    var onComplete: (() -> Void)? = nil

    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            quickTaskIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(task.isCompleted ? Color.black.opacity(0.62) : .white)
                    .shadow(color: .black.opacity(0.52), radius: 2, x: 0, y: 1)
                    .strikethrough(task.isCompleted, color: Color.black.opacity(0.48))
                    .lineLimit(1)

                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(task.isCompleted ? Color.black.opacity(0.52) : .white.opacity(0.78))
                        .shadow(color: .black.opacity(0.34), radius: 1.5, x: 0, y: 1)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 6)
            actionControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background {
            ZStack {
                BubblyCardMaterial(tint: accent, cornerRadius: 14)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.10))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 5)
        .sheet(isPresented: $isEditing) {
            AddKanbanQuickTaskSheet(
                column: column,
                editingTask: task
            )
        }
    }

    private var actionControls: some View {
        VStack(alignment: .trailing, spacing: 5) {
            completionCircle
                .frame(width: 28, alignment: .center)

            HStack(spacing: 7) {
                Button { isEditing = true } label: {
                    quickTaskActionIcon("pencil", tint: accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit quick task")

                Button(role: .destructive, action: onDelete) {
                    quickTaskActionIcon("trash", tint: .white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete quick task")
            }
        }
    }

    private func quickTaskActionIcon(_ asset: String, tint: Color) -> some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 15, height: 15)
            .foregroundStyle(tint)
            .bubblyIconMaterial(tint: tint)
            .shadow(color: .black.opacity(0.52), radius: 2, x: 0, y: 1)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    private var quickTaskIcon: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.72))

            BubblyIconMaterial(tint: accent)
                .mask {
                    Circle()
                        .strokeBorder(lineWidth: 1.4)
                }

            Image(column.board?.icon ?? "starcal")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(accent)
                .bubblyIconMaterial(tint: accent)
        }
        .frame(width: 34, height: 34)
        .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
    }

    private var completionCircle: some View {
        Button { complete() } label: {
            ZStack {
                Circle()
                    .fill(task.isCompleted ? accent.opacity(0.20) : Color.clear)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle()
                            .strokeBorder(accent.opacity(0.88), lineWidth: 2)
                    }

                if task.isCompleted {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 9, height: 9)
                        .foregroundStyle(accent)
                        .bubblyIconMaterial(tint: accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(task.isCompleted)
        .accessibilityLabel(task.isCompleted ? "Quick task completed" : "Complete quick task")
    }

    private func complete() {
        guard !task.isCompleted else { return }
        task.isCompleted = true
        task.completedAt = Date()
        task.updatedAt = Date()
        try? modelContext.save()
        onComplete?()
    }
}

// MARK: - Timeline Habit Card

private func kanbanTimelineItemIcon(_ iconID: String, accent: Color) -> some View {
    ZStack {
        Circle()
            .fill(Color.black.opacity(0.72))

        BubblyIconMaterial(tint: accent)
            .mask {
                Circle()
                    .strokeBorder(lineWidth: 1.4)
            }

        LureliaIconView(iconId: iconID, size: 19)
            .foregroundStyle(accent)
            .bubblyIconMaterial(tint: accent)
    }
    .frame(width: 36, height: 36)
    .shadow(color: .black.opacity(0.42), radius: 3, x: 0, y: 2)
}

private func kanbanTimelineActionIcon(_ assetName: String) -> some View {
    Image(assetName)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 13, height: 13)
        .foregroundStyle(.white)
        .shadow(color: Color.black.opacity(0.48), radius: 2, x: 0, y: 1)
        .frame(width: 30, height: 30)
        .background(LColors.glassSurface, in: Circle())
        .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
        .contentShape(Circle())
}

struct KanbanTimelineHabitOccurrenceCard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var habit: LureliaHabit
    let fireDate: Date
    /// Shared clock from the root timeline. Replaces this card's old
    /// per-instance `TimelineView(.periodic)`.
    let now: Date
    let accent: Color
    let onDelete: () -> Void
    let onEdit: () -> Void
    var onComplete: (() -> Void)? = nil

    private var calendar: Calendar { .current }

    private var dayLog: LureliaHabitLog? {
        habit.log(on: fireDate, calendar: calendar)
    }

    private var daySkip: LureliaHabitSkip? {
        habit.skip(on: fireDate, calendar: calendar)
    }

    private var dayCount: Int {
        habit.count(on: fireDate, calendar: calendar)
    }

    /// True only when *this specific fire time* has been checked off. The
    /// old day-level `isCompleted(on:)` counted the whole habit as done
    /// once `count >= target`, which meant checking the 10am card would
    /// leave every other card looking pending even though the count went
    /// up. This one is per-occurrence.
    private var isCompletedForOccurrence: Bool {
        dayLog?.isCompleted(atFireDate: fireDate, calendar: calendar) ?? false
    }

    private var isSkippedForDay: Bool {
        daySkip != nil
    }

    private var actionDay: Date {
        calendar.isDateInToday(fireDate) ? Date() : fireDate
    }

    var body: some View {
        cardContent(now: now)
    }

    private func cardContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                kanbanTimelineItemIcon(habit.iconName ?? "flame", accent: accent)

                VStack(alignment: .leading, spacing: 7) {
                    Text(habit.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isCompletedForOccurrence || isSkippedForDay ? Color.white.opacity(0.55) : .white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        badge(fireDate.formatted(date: .omitted, time: .shortened))
                        statusBadge(now: now)
                        badge("\(dayCount)/\(habit.target)")
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    completionCircle
                    skipButton
                }
            }

            HStack(alignment: .center, spacing: 8) {
                if let details = habit.details?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !details.isEmpty {
                    Text(details)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    editButton
                    deleteButton
                }
            }
        }
        .padding(12)
        .background {
            LureliaUserChoiceSurface(
                tint: accent,
                role: .supporting,
                cornerRadius: 16
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .opacity(isCompletedForOccurrence || isSkippedForDay ? 0.72 : 1)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(kanbanReadableAccentText(accent))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
    }

    private func statusBadge(now: Date) -> some View {
        let text: String
        let color: Color

        if isCompletedForOccurrence {
            text = "COMPLETED"
            color = LColors.success
        } else if isSkippedForDay {
            text = "SKIPPED"
            color = LColors.textSecondary
        } else {
            // Split explicitly by past / today / future so "DUE NOW" can
            // only ever appear for a habit that's actually due today and
            // whose scheduled time has passed. Past days that weren't
            // completed read as OVERDUE; future days read as UPCOMING.
            let todayStart = calendar.startOfDay(for: now)
            let fireDayStart = calendar.startOfDay(for: fireDate)

            if fireDayStart < todayStart {
                text = "OVERDUE"
                color = Color(lureliaHex: "#ff9be6")
            } else if fireDayStart > todayStart {
                text = "UPCOMING"
                color = LColors.gradientBlue
            } else if fireDate <= now {
                text = "DUE NOW"
                color = LColors.gradientPurple
            } else {
                text = "SOON"
                color = LColors.gradientBlue
            }
        }

        let usesCardColorMaterial = text == "SOON" || text == "DUE NOW"
        let badgeTint = usesCardColorMaterial ? accent : color
        let textTint = usesCardColorMaterial ? badgeTint.wcagContrastingSolidTextColor : color

        return Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(textTint)
            .bubblyIconMaterial(tint: textTint, isEnabled: usesCardColorMaterial)
            .shadow(
                color: usesCardColorMaterial ? Color.black.opacity(0.68) : .clear,
                radius: 2,
                x: 0,
                y: 1
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if usesCardColorMaterial {
                    Capsule()
                        .fill(badgeTint)
                        .bubblyIconMaterial(tint: badgeTint)
                } else {
                    Capsule()
                        .fill(color.opacity(0.12))
                }
            }
            .overlay {
                if usesCardColorMaterial {
                    Capsule()
                        .strokeBorder(badgeTint, lineWidth: 1)
                        .bubblyIconMaterial(tint: badgeTint)
                } else {
                    Capsule()
                        .strokeBorder(color.opacity(0.28), lineWidth: 1)
                }
            }
    }

    private var completionCircle: some View {
        Button {
            quickLog()
        } label: {
            ZStack {
                Circle()
                    .fill(isCompletedForOccurrence ? accent.opacity(0.18) : Color.clear)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .strokeBorder(accent.opacity(0.75), lineWidth: 2)
                    }

                if isCompletedForOccurrence {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isCompletedForOccurrence || isSkippedForDay)
        .opacity((isCompletedForOccurrence || isSkippedForDay) ? 0.55 : 1)
    }

    private var skipButton: some View {
        Button {
            toggleSkip()
        } label: {
            Image("skipwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCompletedForOccurrence)
        .opacity(isCompletedForOccurrence ? 0.55 : 1)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            kanbanTimelineActionIcon("pencil")
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            kanbanTimelineActionIcon("trash")
        }
        .buttonStyle(.plain)
    }

    private func quickLog() {
        // Tapping the check on a completed occurrence un-checks it.
        if let existing = dayLog,
           existing.isCompleted(atFireDate: fireDate, calendar: calendar) {
            existing.unmarkCompleted(atFireDate: fireDate, calendar: calendar)
            habit.updatedAt = Date()
            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()
            return
        }

        // Completing an occurrence clears any day-level skip so the two
        // states can't disagree.
        if let existingSkip = daySkip {
            modelContext.delete(existingSkip)
            habit.skips = (habit.skips ?? []).filter {
                $0.persistentModelID != existingSkip.persistentModelID
            }
        }

        let log: LureliaHabitLog
        if let existing = dayLog {
            log = existing
        } else {
            log = LureliaHabitLog(habit: habit, dayStart: actionDay, count: 0)
            modelContext.insert(log)
            habit.logs = (habit.logs ?? []) + [log]
        }

        log.markCompleted(atFireDate: fireDate, calendar: calendar)
        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()

        if isCompletedForOccurrence {
            onComplete?()
        }
    }

    private func toggleSkip() {
        if let existing = daySkip {
            modelContext.delete(existing)
            habit.skips = (habit.skips ?? []).filter {
                $0.persistentModelID != existing.persistentModelID
            }
            habit.updatedAt = Date()
            try? modelContext.save()
            LureliaWidgetReloads.reloadAll()
            return
        }

        guard dayCount == 0 else { return }

        let skip = LureliaHabitSkip(habit: habit, dayStart: actionDay)
        modelContext.insert(skip)
        habit.skips = (habit.skips ?? []) + [skip]
        habit.updatedAt = Date()

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }
}

// MARK: - Timeline Routine Card

struct KanbanTimelineRoutineOccurrenceCard: View {
    @Bindable var routine: LureliaRoutine
    let fireDate: Date
    let accent: Color
    let onDelete: () -> Void

    @State private var isExpanded = false

    private var calendar: Calendar {
        .current
    }

    private var progressText: String {
        let total = routine.sortedTasks.count
        guard total > 0 else { return "No tasks" }

        let completed = routine.sortedTasks.filter {
            $0.kanbanTimelineOccurrenceStatus(on: fireDate, calendar: calendar) == .completed
        }.count

        return "\(completed)/\(total) done"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 36, height: 36)

                            LureliaIconView(iconId: routine.icon, size: 19)
                              .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text(routine.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                               .foregroundStyle(.white)
                                .lineLimit(2)

                            HStack(spacing: 6) {
                                badge(fireDate.formatted(date: .omitted, time: .shortened))
                                badge(progressText)
                            }
                        }

                        Spacer(minLength: 8)

                        Image(isExpanded ? "chevdown" : "chevright")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                          .foregroundStyle(accent)
                            .padding(.top, 11)
                    }
                }
                .buttonStyle(.plain)

                deleteButton
            }

            if isExpanded {
                if routine.sortedTasks.isEmpty {
                    Text("No tasks in this routine yet")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(routine.sortedTasks, id: \.kanbanItemID) { task in
                            NavigationLink(value: task.id) {
                                KanbanTimelineRoutineDetailTaskCard(
                                    task: task,
                                    fireDate: fireDate,
                                    accent: accent
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background {
            LureliaUserChoiceSurface(
                tint: accent,
                role: .supporting,
                cornerRadius: 16
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(kanbanReadableAccentText(accent))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image("trash")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(Color(lureliaHex: "#0db7d9"))
                .frame(width: 30, height: 30)
                .background(LColors.glassSurface, in: Circle())
                .overlay(Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline Routine Task Cards

private enum KanbanTimelineRoutineTaskOccurrenceStatus {
    case pending
    case completed
    case skipped
}

private extension LureliaRoutineTask {
    func kanbanTimelineOccurrenceStatus(
        on fireDate: Date,
        calendar: Calendar = .current
    ) -> KanbanTimelineRoutineTaskOccurrenceStatus {
        if let entry = sortedHistory.first(where: { calendar.isDate($0.date, inSameDayAs: fireDate) }) {
            return entry.wasCompleted ? .completed : .skipped
        }

        let completionDate = completedAt.flatMap { date in
            calendar.isDate(date, inSameDayAs: fireDate) ? date : nil
        }
        let skipDate = skippedAt.flatMap { date in
            calendar.isDate(date, inSameDayAs: fireDate) ? date : nil
        }

        switch (completionDate, skipDate) {
        case let (completed?, skipped?):
            return completed >= skipped ? .completed : .skipped
        case (.some, .none):
            return .completed
        case (.none, .some):
            return .skipped
        case (.none, .none):
            return .pending
        }
    }
}

struct KanbanTimelineRoutineTaskOccurrenceCard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var task: LureliaRoutineTask
    let fireDate: Date
    /// Shared clock from the root timeline. Replaces this card's old
    /// per-instance `TimelineView(.periodic)`.
    let now: Date
    let accent: Color
    let onDelete: () -> Void
    let onEdit: () -> Void
    var onComplete: (() -> Void)? = nil

    private var calendar: Calendar {
        .current
    }

    private var occurrenceStatus: KanbanTimelineRoutineTaskOccurrenceStatus {
        task.kanbanTimelineOccurrenceStatus(on: fireDate, calendar: calendar)
    }

    private var isCompletedForOccurrence: Bool {
        occurrenceStatus == .completed
    }

    private var isSkippedForOccurrence: Bool {
        occurrenceStatus == .skipped
    }

    private var isPendingForOccurrence: Bool {
        occurrenceStatus == .pending
    }

    private var actionOccurrenceDate: Date {
        calendar.isDateInToday(fireDate) ? Date() : fireDate
    }

    var body: some View {
        cardContent(now: now)
    }

    private func cardContent(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                routineTaskIcon

                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isPendingForOccurrence ? .white : Color.white.opacity(0.55))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        badge(fireDate.formatted(date: .omitted, time: .shortened))
                        statusBadge(now: now)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    completionCircle
                    skipButton
                }
            }

            HStack(alignment: .center, spacing: 8) {
                if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.notes)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    editButton
                    deleteButton
                }
            }
        }
        .padding(12)
        .background {
            LureliaUserChoiceSurface(
                tint: accent,
                role: .supporting,
                cornerRadius: 16
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .opacity(isPendingForOccurrence ? 1 : 0.72)
    }

    private func statusText(now: Date) -> String {
        if isCompletedForOccurrence { return "COMPLETED" }
        if isSkippedForOccurrence { return "SKIPPED" }

        let calendar = Calendar.current

        if fireDate < calendar.startOfDay(for: now) {
            return "OVERDUE"
        }

        if calendar.isDateInToday(fireDate), fireDate <= now {
            return "DUE NOW"
        }

        return "SOON"
    }

    private func statusColor(now: Date) -> Color {
        if isCompletedForOccurrence { return LColors.success }
        if isSkippedForOccurrence { return Color(lureliaHex: "#ff9be6") }

        let calendar = Calendar.current

        if fireDate < calendar.startOfDay(for: now) {
            return Color(lureliaHex: "#ff9be6")
        }

        if calendar.isDateInToday(fireDate), fireDate <= now {
            return Color(lureliaHex: "#b476ff")
        }

        return accent
    }

    private var routineTaskIcon: some View {
        kanbanTimelineItemIcon(task.icon, accent: accent)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(kanbanReadableAccentText(accent))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
    }

    private func statusBadge(now: Date) -> some View {
        let color = statusColor(now: now)

        return Text(statusText(now: now))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }

    private var completionCircle: some View {
        Button {
            toggleCompletion()
        } label: {
            ZStack {
                Circle()
                    .fill(isCompletedForOccurrence ? accent.opacity(0.18) : Color.clear)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .strokeBorder(accent.opacity(0.75), lineWidth: 2)
                    }

                if isCompletedForOccurrence {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button {
            RoutineTaskManager.shared.recordSkip(
                task: task,
                occurredAt: actionOccurrenceDate,
                context: modelContext
            )
        } label: {
            Image("skipwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPendingForOccurrence)
        .opacity(isPendingForOccurrence ? 1 : 0.4)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            kanbanTimelineActionIcon("pencil")
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            kanbanTimelineActionIcon("trash")
        }
        .buttonStyle(.plain)
    }

    private func toggleCompletion() {
        if isCompletedForOccurrence {
            resetOccurrenceState()
        } else {
            RoutineTaskManager.shared.recordCompletion(
                task: task,
                occurredAt: actionOccurrenceDate,
                context: modelContext
            )
            onComplete?()
        }
    }

    private func resetOccurrenceState() {
        let remainingHistory = (task.historyItems ?? []).filter {
            !calendar.isDate($0.date, inSameDayAs: fireDate)
        }

        for entry in task.historyItems ?? [] where calendar.isDate(entry.date, inSameDayAs: fireDate) {
            modelContext.delete(entry)
        }

        task.historyItems = remainingHistory

        if let completedAt = task.completedAt,
           calendar.isDate(completedAt, inSameDayAs: fireDate) {
            task.completedAt = nil
        }

        if let skippedAt = task.skippedAt,
           calendar.isDate(skippedAt, inSameDayAs: fireDate) {
            task.skippedAt = nil
        }

        if let latest = remainingHistory.sorted(by: { $0.date > $1.date }).first {
            task.state = latest.wasCompleted ? "completed" : "skipped"
            task.completedAt = latest.wasCompleted ? latest.date : nil
            task.skippedAt = latest.wasCompleted ? nil : latest.date
            task.updatedAt = Date()
        } else {
            task.resetState()
        }

        LureliaRoutineTaskOccurrenceNotifications.restorePendingOccurrence(
            for: task,
            on: fireDate
        )
        LureliaRoutineTaskOccurrenceAlarms.restorePendingOccurrence(
            for: task,
            on: fireDate
        )

        try? modelContext.save()
        LureliaWidgetReloads.reloadAll()
    }
}

struct KanbanTimelineRoutineDetailTaskCard: View {
    @Bindable var task: LureliaRoutineTask
    let fireDate: Date
    let accent: Color

    private var occurrenceStatus: KanbanTimelineRoutineTaskOccurrenceStatus {
        task.kanbanTimelineOccurrenceStatus(on: fireDate)
    }

    private var isPendingForOccurrence: Bool {
        occurrenceStatus == .pending
    }

    private var completedSteps: Int {
        task.sortedSteps.filter(\.isCompleted).count
    }

    private var stepText: String {
        let total = task.sortedSteps.count
        guard total > 0 else { return "No steps" }
        return "\(completedSteps)/\(total) steps"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(accent.opacity(0.35), lineWidth: 1))

                LureliaIconView(iconId: task.icon, size: 14)
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isPendingForOccurrence ? .white : Color.white.opacity(0.55))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    badge(stepText)
                    if task.hasDueTime {
                        badge(task.formattedDueTime)
                    }
                    switch occurrenceStatus {
                    case .pending:
                        EmptyView()
                    case .completed:
                        badge("Completed")
                    case .skipped:
                        badge("Skipped")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            LureliaUserChoiceSurface(
                tint: accent,
                role: .supporting,
                cornerRadius: 14
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(kanbanReadableAccentText(accent))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(accent.opacity(0.10), in: Capsule())
    }
}

// MARK: - Kanban Timeline Inbox Column

struct KanbanTimelineInboxColumnView: View {
    let board: KanbanBoard
    let reminders: [LureliaReminder]
    let selectedDay: Date
    let boardAccent: Color
    let onMoveReminder: (LureliaReminder, KanbanColumn) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image("inbox")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                       .foregroundStyle(boardAccent)

                    Text("Inbox")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(reminders.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(boardAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(boardAccent.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()
                .overlay(LColors.glassBorder)
                .padding(.horizontal, 10)

            VStack(spacing: 10) {
                ForEach(reminders) { reminder in
                    KanbanTimelineInboxReminderCard(
                        reminder: reminder,
                        selectedDay: selectedDay,
                        accent: boardAccent
                    )
                    .contextMenu {
                        if board.sortedColumns.isEmpty {
                            Label {
                                Text("Add a column first")
                            } icon: {
                                Image("inbox")
                                    .renderingMode(.template)
                            }
                        } else {
                            ForEach(board.sortedColumns) { column in
                                Button {
                                    onMoveReminder(reminder, column)
                                } label: {
                                    HStack {
                                        Image("rightwavy")
                                            .renderingMode(.template)

                                        Text("Move to \(column.name)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubblyCardMaterial(
                tint: boardAccent,
                cornerRadius: 22
            )
        }
    }
}

// MARK: - Timeline Reminder Card

struct KanbanTimelineReminderCard: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var reminder: LureliaReminder
    let selectedDay: Date
    /// Shared clock from the root timeline. Replaces this card's old
    /// per-instance `TimelineView(.periodic)`.
    let now: Date
    var forcedFireDate: Date? = nil
    let accent: Color
    let onDelete: () -> Void
    let onEdit: () -> Void
    var onComplete: (() -> Void)? = nil

    private var calendar: Calendar { .current }

    private var reminderIcon: String {
        reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bellfill" : reminder.icon
    }

    private var fireDates: [Date] {
        if let forcedFireDate {
            return [forcedFireDate]
        }

        let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDay)

        return resolvedTimesOfDay().compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else {
                return nil
            }

            var components = dayComponents
            components.hour = hour
            components.minute = minute
            components.second = 0

            return calendar.date(from: components)
        }
        .sorted()
    }

    private var isDoneOnSelectedDay: Bool {
        if let completedAt = reminder.completedAt,
           calendar.isDate(completedAt, inSameDayAs: selectedDay) {
            return true
        }

        return reminder.completionTimestamps.contains {
            calendar.isDate($0, inSameDayAs: selectedDay)
        }
    }

    private var statusFireDate: Date? {
        forcedFireDate ?? fireDates.first
    }

    private var isDoneForThisOccurrence: Bool {
        guard let forcedFireDate else {
            return isDoneOnSelectedDay
        }

        // Completions are checked against the fire date's own day (which may
        // be a prior day for overdue occurrences), not selectedDay.
        let occurrenceDay = forcedFireDate
        let completions = ([reminder.completedAt].compactMap { $0 } + reminder.completionTimestamps)
            .filter { calendar.isDate($0, inSameDayAs: occurrenceDay) }

        guard !completions.isEmpty else {
            return false
        }

        let sortedFireDates = fireDates.sorted()

        guard let index = sortedFireDates.firstIndex(of: forcedFireDate) else {
            return false
        }

        let nextFireDate: Date? = {
            let nextIndex = index + 1
            guard sortedFireDates.indices.contains(nextIndex) else { return nil }
            return sortedFireDates[nextIndex]
        }()

        return completions.contains { completedAt in
            completedAt >= forcedFireDate &&
            (nextFireDate == nil || completedAt < nextFireDate!)
        }
    }

    private func isOverdue(now: Date) -> Bool {
        guard !isDoneForThisOccurrence && reminder.isEnabled else { return false }
        guard let fireDate = statusFireDate else { return false }

        // This specific occurrence is OVERDUE if its fire date is before
        // the start of today.
        return fireDate < calendar.startOfDay(for: now)
    }

    private func isDueNow(now: Date) -> Bool {
        guard !isDoneForThisOccurrence && reminder.isEnabled else { return false }
        guard let fireDate = statusFireDate else { return false }

        // DUE NOW only for today's fire dates that have passed.
        return calendar.isDateInToday(fireDate) && fireDate <= now
    }

    private func isUpcoming(now: Date) -> Bool {
        guard !isDoneForThisOccurrence && reminder.isEnabled else { return false }
        guard let fireDate = statusFireDate else { return false }

        return fireDate > now
    }

    var body: some View {
        cardContent(
            overdue: isOverdue(now: now),
            dueNow: isDueNow(now: now),
            upcoming: isUpcoming(now: now)
        )
    }

    @ViewBuilder
    private func cardContent(overdue: Bool, dueNow: Bool, upcoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                kanbanTimelineItemIcon(reminderIcon, accent: accent)

                VStack(alignment: .leading, spacing: 7) {
                    Text(reminder.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(reminder.isEnabled ? .white : Color.white.opacity(0.55))
                        .lineLimit(2)

                    badgeRow(overdue: overdue, dueNow: dueNow, upcoming: upcoming)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    completionCircle
                    skipButton
                }
            }

            HStack(alignment: .center, spacing: 8) {
                if let notes = reminder.notes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(notes)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    editButton
                    deleteButton
                }
            }
        }
        .padding(12)
        .background {
            LureliaUserChoiceSurface(
                tint: accent,
                role: .supporting,
                cornerRadius: 16
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .opacity(reminder.isEnabled ? 1 : 0.65)
    }

    private var completionCircle: some View {
        Button {
            completeReminderOccurrence()
        } label: {
            ZStack {
                Circle()
                    .fill(isDoneOnSelectedDay && reminder.repeatUnit == .none ? accent.opacity(0.18) : Color.clear)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .strokeBorder(accent.opacity(0.75), lineWidth: 2)
                    }

                if isDoneOnSelectedDay && reminder.repeatUnit == .none {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accent)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button {
            skipReminderOccurrence()
        } label: {
            Image("skipwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!reminder.isEnabled || (reminder.repeatUnit == .none && reminder.isCompleted))
        .opacity((!reminder.isEnabled || (reminder.repeatUnit == .none && reminder.isCompleted)) ? 0.4 : 1)
    }

    private var editButton: some View {
        Button(action: onEdit) {
            kanbanTimelineActionIcon("pencil")
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            kanbanTimelineActionIcon("trash")
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }

    private func badgeRow(overdue: Bool, dueNow: Bool, upcoming: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(fireDates.prefix(2).enumerated()), id: \.offset) { _, date in
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(kanbanReadableAccentText(accent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
            }

            if fireDates.count > 2 {
                Text("+\(fireDates.count - 2)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(kanbanReadableAccentText(accent))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
            }

            if overdue {
                statusBadge(label: "OVERDUE", color: Color(lureliaHex: "#ff9be6"))
            }

            if dueNow {
                statusBadge(label: "DUE NOW", color: Color(lureliaHex: "#b476ff"))
            }

            if upcoming {
                statusBadge(label: "UPCOMING", color: Color(lureliaHex: "#7eedff"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reminder Scheduling Helpers

    private func resolvedTimesOfDay() -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }

        if !stored.isEmpty {
            return stored
        }

        let hour = reminder.primaryHour != -1
            ? reminder.primaryHour
            : calendar.component(.hour, from: reminder.scheduledDate)

        let minute = reminder.primaryMinute != -1
            ? reminder.primaryMinute
            : calendar.component(.minute, from: reminder.scheduledDate)

        var times = [String(format: "%02d:%02d", hour, minute)]

        for fireTime in reminder.additionalFireTimes {
            times.append(String(format: "%02d:%02d", fireTime.hour, fireTime.minute))
        }

        return times
    }

    // MARK: - Actions

    private func completeReminderOccurrence() {
        Task {
            await ReminderActionManager.completeReminderOccurrence(
                reminder,
                in: modelContext
            )

            await MainActor.run {
                onComplete?()
            }
        }
    }

    private func skipReminderOccurrence() {
        Task {
            await ReminderActionManager.skipReminderOccurrence(
                reminder,
                in: modelContext
            )
        }
    }
}

// MARK: - Timeline Inbox Reminder Card

struct KanbanTimelineInboxReminderCard: View {
    let reminder: LureliaReminder
    let selectedDay: Date
    let accent: Color

    private var calendar: Calendar { .current }

    private var reminderIcon: String {
        reminder.icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bellfill" : reminder.icon
    }

    private var fireDates: [Date] {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDay)
        let times = resolvedTimesOfDay()

        return times.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1])
            else {
                return nil
            }

            var components = dayComponents
            components.hour = hour
            components.minute = minute
            components.second = 0

            return calendar.date(from: components)
        }
        .sorted()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            kanbanTimelineItemIcon(reminderIcon, accent: accent)

            VStack(alignment: .leading, spacing: 7) {
                Text(reminder.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(reminder.isEnabled ? .white : Color.white.opacity(0.55))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    ForEach(Array(fireDates.prefix(2).enumerated()), id: \.offset) { _, date in
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(kanbanReadableAccentText(accent))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
                    }

                    if fireDates.count > 2 {
                        Text("+\(fireDates.count - 2)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(kanbanReadableAccentText(accent))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(0.28), lineWidth: 1))
                    }
                }
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background {
            LureliaUserChoiceSurface(
                tint: accent,
                role: .supporting,
                cornerRadius: 16
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .allowsHitTesting(false)
            }
        }
        .opacity(reminder.isEnabled ? 1 : 0.65)
    }

    private func resolvedTimesOfDay() -> [String] {
        let stored = reminder.timesOfDay.filter { !$0.isEmpty }

        if !stored.isEmpty {
            return stored
        }

        let hour = reminder.primaryHour != -1
            ? reminder.primaryHour
            : calendar.component(.hour, from: reminder.scheduledDate)

        let minute = reminder.primaryMinute != -1
            ? reminder.primaryMinute
            : calendar.component(.minute, from: reminder.scheduledDate)

        var times = [String(format: "%02d:%02d", hour, minute)]

        for fireTime in reminder.additionalFireTimes {
            times.append(String(format: "%02d:%02d", fireTime.hour, fireTime.minute))
        }

        return times
    }
}

// MARK: - Timeline Column Sheet

struct KanbanTimelineColumnSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var board: KanbanBoard
    var column: KanbanColumn?

    @State private var name: String
    @State private var selectedColor: Color

    init(board: KanbanBoard, column: KanbanColumn? = nil) {
        self.board = board
        self.column = column
        _name = State(initialValue: column?.name ?? "")
        _selectedColor = State(initialValue: Color(lureliaHex: column?.colorHex ?? "#03dbfc"))
    }

    private var isEditing: Bool { column != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack {
            LureliaBackgroundAlt()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isEditing ? "Edit Column" : "New Column")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                          .foregroundStyle(.white)

                        Text(isEditing ? "Update this column." : "Add a column to \(board.name).")
                            .font(.system(size: 13, design: .rounded))
                          .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Button { dismiss() } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                          .foregroundStyle(LGradients.header)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                LureliaFormSection(title: "Column Name") {
                    TextField("e.g. Morning, Afternoon, Evening", text: $name)
                        .font(.system(size: 15, design: .rounded))
                       .foregroundStyle(.white)
                        .padding(14)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                LureliaFormSection(title: "Color") {
                    ColorPicker(selection: $selectedColor, supportsOpacity: false) {
                        Text("Column Color")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                           .foregroundStyle(.white)
                    }
                    .padding(14)
                    .background(LColors.glassSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button { save() } label: {
                    Text(isEditing ? "Save Changes" : "Add Column")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background { LureliaNeutralGlassSurface(cornerRadius: 22) }
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard canSave else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = selectedColor.toHex() ?? column?.colorHex ?? "#03dbfc"

        if let column {
            column.name = trimmedName
            column.colorHex = hex
        } else {
            let newColumn = KanbanColumn(
                name: trimmedName,
                colorHex: hex,
                sortOrder: (board.columns ?? []).count
            )

            modelContext.insert(newColumn)

            if board.columns == nil {
                board.columns = []
            }

            board.columns?.append(newColumn)
        }

        board.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Create Board Sheet

struct KanbanTimelineCreateBoardSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \KanbanBoard.sortOrder)
    private var boards: [KanbanBoard]

    @State private var name = ""
    @State private var icon = "starcal"
    @State private var selectedColor = Color(lureliaHex: "#03dbfc")

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            LureliaBackgroundAlt()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New Board")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                          .foregroundStyle(.white)

                        Text("Create a board for your timeline.")
                            .font(.system(size: 13, design: .rounded))
                          .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                          .foregroundStyle(LGradients.header)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                LureliaFormSection(title: "Board Name") {
                    TextField("e.g. Weekly Flow", text: $name)
                        .font(.system(size: 15, design: .rounded))
                       .foregroundStyle(.white)
                        .padding(14)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            LColors.gradientBlue.opacity(0.95),
                                            LColors.gradientPurple.opacity(0.95),
                                            Color.white.opacity(0.55)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.1
                                )
                        )
                        .onSubmit { save() }
                }

                LureliaFormSection(title: "Color") {
                    ColorPicker(selection: $selectedColor, supportsOpacity: false) {
                        Text("Board Color")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                           .foregroundStyle(.white)
                    }
                    .padding(14)
                    .background(LColors.glassSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        LColors.gradientBlue.opacity(0.95),
                                        LColors.gradientPurple.opacity(0.95),
                                        Color.white.opacity(0.55)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                    )
                }

                Button {
                    save()
                } label: {
                    HStack(spacing: 10) {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                          .foregroundStyle(.white)

                        Text("Create Board")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background { LureliaNeutralGlassSurface(cornerRadius: 22) }
                    .shadow(color: LColors.neutralPearl.opacity(0.10), radius: 18, y: 10)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard canSave else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = selectedColor.toHex() ?? "#03dbfc"

        let board = KanbanBoard(
            name: trimmedName,
            icon: icon,
            colorHex: hex,
            sortOrder: boards.count
        )

        modelContext.insert(board)
        try? modelContext.save()
        dismiss()
    }
}
