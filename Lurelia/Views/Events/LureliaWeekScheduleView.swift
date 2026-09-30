//
//  LureliaWeekScheduleView.swift
//  Lurelia
//

import SwiftUI

struct LureliaWeekScheduleView: View {
    @Environment(\.appTheme) private var theme

    @Binding var focusedDate: Date
    let localOccurrences: [LureliaEventOccurrence]
    let externalOccurrences: [LureliaExternalCalendarOccurrence]
    let events: [LureliaEvent]
    let onSelect: (LureliaEventUnifiedOccurrence) -> Void
    let onDelete: (LureliaEventUnifiedOccurrence) -> Void

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { moveWeek(-1) } label: {
                    ZStack {
                        Color.clear

                        Image("chevleft")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .bubblyIconMaterial(tint: theme.palette.indicators)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous week")

                Spacer()

                Text(weekTitle)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button { moveWeek(1) } label: {
                    ZStack {
                        Color.clear

                        Image("chevright")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .bubblyIconMaterial(tint: theme.palette.indicators)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next week")
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ForEach(weekDays, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(theme.palette.textPrimary)

                            Spacer()

                            Text("\(rows(on: day).count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.palette.textPrimary.opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(theme.palette.raisedSurface, in: Capsule())
                        }

                        let dayRows = rows(on: day)
                        if dayRows.isEmpty {
                            Text("No events")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 7)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(dayRows) { row in
                                    LureliaEventOccurrenceRow(
                                        row: row,
                                        onSelect: onSelect,
                                        onDelete: onDelete
                                    )
                                }
                            }
                        }
                    }
                    .padding(LSpacing.cardPadding)
                    .background(
                        theme.palette.surface,
                        in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                            .strokeBorder(LColors.glassBorder, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var weekDays: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: focusedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "This Week" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) - \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func rows(on day: Date) -> [LureliaEventUnifiedOccurrence] {
        let local = localOccurrences
            .map { LureliaEventUnifiedOccurrence.local($0) }
        let external = externalOccurrences
            .map { LureliaEventUnifiedOccurrence.apple($0) }
        return LureliaEventUnifiedOccurrence.deduplicated(local + external)
            .filter { $0.occurs(on: day, calendar: calendar) }
            .sorted { $0.start < $1.start }
    }

    private func moveWeek(_ value: Int) {
        focusedDate = calendar.date(byAdding: .weekOfYear, value: value, to: focusedDate) ?? focusedDate
    }
}
