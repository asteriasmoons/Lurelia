//
//  LureliaEventCalendarGateSheet.swift
//  Lurelia
//
//  Calendar-first entry gate for creating an event. A primary calendar
//  must be selected before the New Event editor can open.
//

import SwiftData
import SwiftUI

struct LureliaEventCalendarGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Query(sort: \LureliaCalendar.name) private var calendars: [LureliaCalendar]

    let onContinue: (LureliaCalendar) -> Void

    @State private var selectedCalendarID: UUID?

    private var selectedCalendar: LureliaCalendar? {
        calendars.first { $0.id == selectedCalendarID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Choose a calendar")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(theme.palette.textPrimary)

                            Text("The calendar color will tint the new event form.")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary)
                        }

                        calendarList
                        continueButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("New Event")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)

            Spacer()

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(theme.palette.primaryAction)
                    .bubblyIconMaterial(tint: theme.palette.primaryAction)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var calendarList: some View {
        if calendars.isEmpty {
            Text("Create a calendar before adding an event.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.palette.surface)
                }
        } else {
            VStack(spacing: 10) {
                ForEach(calendars) { calendar in
                    calendarRow(calendar)
                }
            }
        }
    }

    private func calendarRow(_ calendar: LureliaCalendar) -> some View {
        let tint = Color(lureliaHex: calendar.color)
        let isSelected = selectedCalendarID == calendar.id

        return Button {
            selectedCalendarID = calendar.id
        } label: {
            HStack(spacing: 12) {
                BubblyIconMaterial(tint: tint)
                    .clipShape(Circle())
                    .frame(width: 18, height: 18)

                Text(calendar.name.isEmpty ? "Untitled" : calendar.name)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(tint)
                        .bubblyIconMaterial(tint: tint)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            guard let selectedCalendar else { return }
            onContinue(selectedCalendar)
        } label: {
            Text("Continue")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(selectedCalendar == nil ? theme.palette.textSecondary : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    if let selectedCalendar {
                        BubblyCardMaterial(
                            tint: Color(lureliaHex: selectedCalendar.color),
                            cornerRadius: 20
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(theme.palette.surface)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(selectedCalendar == nil)
        .opacity(selectedCalendar == nil ? 0.58 : 1)
    }
}
