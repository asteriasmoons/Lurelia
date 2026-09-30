//
//  LureliaEventCalendarSettingsView.swift
//  Lurelia
//
//  Sheet layout matches every other add/edit sheet: title top-left,
//  xmarkwavy top-right, labeled settings sections, and a Done control
//  at the bottom.
//
//  Sections (top to bottom):
//    1. Default View — LureliaGradientDropdown (Agenda / Month / Week)
//    2. My Calendars — filter user-created LureliaCalendar rows with
//       hollow/filled gradient circles for visibility, tap row to edit
//    3. Apple Calendar — Show + Two-Way Sync toggles
//    4. Visible Calendars (Apple) — checkbox list of Apple calendars
//

import SwiftData
import SwiftUI
import UIKit

struct LureliaEventCalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Bindable var settings: UserSettings
    @Query(sort: \LureliaCalendar.name) private var lureliaCalendars: [LureliaCalendar]

    @StateObject private var eventService = LureliaEventService.shared
    @State private var selectedIDs: Set<String> = []
    @State private var defaultView: LureliaEventsTab? = .agenda
    @State private var editingCalendar: LureliaCalendar?

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header

                        defaultViewSection
                        myCalendarsSection
                        appleTogglesSection

                        if eventService.hasCalendarAccess {
                            syncDestinationSection
                            visibleAppleCalendarsSection
                        } else {
                            connectAppleSection
                        }

                        doneButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 60)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingCalendar) { calendar in
                LureliaAddCalendarSheet(editing: calendar)
            }
            .task {
                selectedIDs = Set(settings.selectedAppleCalendarIDs)
                eventService.refreshAuthorizationStatus()
                if selectedIDs.isEmpty {
                    selectedIDs = Set(eventService.appleCalendars.map(\.id))
                }
                defaultView = LureliaEventsTab(rawValue: settings.defaultEventsViewRaw) ?? .agenda
            }
            .onChange(of: defaultView) { _, newValue in
                if let raw = newValue?.rawValue {
                    settings.defaultEventsViewRaw = raw
                    try? modelContext.save()
                }
            }
            .onChange(of: settings.twoWayAppleCalendarSyncEnabled) { wasOn, isOn in
                // When the user flips Two-Way Sync on, push any
                // Lurelia-authored events that don't exist in Apple yet.
                // Events that came from Apple (or were already mirrored) are
                // skipped inside the service so we never duplicate.
                guard !wasOn, isOn else { return }
                eventService.syncAllLocalEventsToApple(
                    context: modelContext,
                    defaultCalendarID: resolvedSyncDestinationID
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Calendar Settings")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button { commitAndDismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .bubblyIconMaterial(tint: .white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Default View

    private var defaultViewSection: some View {
        section("Default View", icon: "starcal") {
            LureliaGradientDropdown(
                placeholder: "Agenda",
                options: LureliaEventsTab.allCases,
                selection: $defaultView,
                label: { $0.rawValue },
                tint: theme.palette.primaryAction,
                usesCardMaterial: true,
                usesDarkTypography: true,
                iconTint: .black
            )
        }
    }

    // MARK: - My Calendars

    private var myCalendarsSection: some View {
        section("My Calendars", icon: "ringstarcal") {
            if lureliaCalendars.isEmpty {
                Text("You haven't created any calendars yet. Tap the calendars icon in the Events header to add one.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(lureliaCalendars) { calendar in
                        myCalendarRow(calendar)
                    }
                }
            }
        }
    }

    private func myCalendarRow(_ calendar: LureliaCalendar) -> some View {
        let calendarColor = Color(lureliaHex: calendar.color)

        return HStack(spacing: 12) {
            visibilityCircleButton(for: calendar)

            Button {
                editingCalendar = calendar
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(calendarColor)
                        .frame(width: 14, height: 14)
                        .bubblyIconMaterial(tint: calendarColor)

                    Text(calendar.name.isEmpty ? "Untitled" : calendar.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Image("chevright")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.white)
                        .bubblyIconMaterial(tint: .white)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(calendarColor, lineWidth: 1)
        )
    }

    /// Hollow circle when the calendar is hidden; standalone material
    /// `checkwavy` when visible. Tap toggles.
    private func visibilityCircleButton(for calendar: LureliaCalendar) -> some View {
        Button {
            calendar.isHidden.toggle()
            try? modelContext.save()
        } label: {
            Group {
                if calendar.isHidden {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.38), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                } else {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white)
                        .bubblyIconMaterial(tint: .white)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.isHidden ? "Show \(calendar.name)" : "Hide \(calendar.name)")
    }

    // MARK: - Sync destination

    /// The Apple Calendar identifier we'll write Lurelia-authored events
    /// into. Prefers the user's explicit pick; falls back to the first
    /// writable calendar available.
    private var resolvedSyncDestinationID: String? {
        if let explicit = settings.defaultAppleSyncCalendarID,
           writableAppleCalendars.contains(where: { $0.id == explicit }) {
            return explicit
        }
        return writableAppleCalendars.first?.id
    }

    private var writableAppleCalendars: [LureliaAppleCalendarSource] {
        eventService.appleCalendars.filter(\.allowsContentModifications)
    }

    private var syncDestinationSection: some View {
        section("Sync To Calendar", icon: "lovecalendar") {
            if writableAppleCalendars.isEmpty {
                Text("No writable Apple calendars available. Add one in the Calendar app to enable sync.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LureliaGradientDropdown(
                    placeholder: "Choose a destination calendar",
                    options: writableAppleCalendars.map(\.id),
                    selection: syncDestinationBinding,
                    label: { id in
                        writableAppleCalendars.first(where: { $0.id == id })?.title ?? id
                    },
                    tint: theme.palette.indicators,
                    usesCardMaterial: true,
                    usesDarkTypography: true,
                    iconTint: .black
                )
            }
        }
    }

    /// Binds the dropdown to `settings.defaultAppleSyncCalendarID`. Writing
    /// nil clears the explicit choice and falls back to the first writable
    /// calendar automatically.
    private var syncDestinationBinding: Binding<String?> {
        Binding(
            get: { settings.defaultAppleSyncCalendarID ?? resolvedSyncDestinationID },
            set: { newValue in
                settings.defaultAppleSyncCalendarID = newValue
                try? modelContext.save()
            }
        )
    }

    // MARK: - Apple toggles

    private var appleTogglesSection: some View {
        section("Apple Calendar", icon: "dotscal") {
            VStack(alignment: .leading, spacing: 16) {
                calendarToggleRow(
                    title: "Show Apple Calendar Events",
                    subtitle: "Merge Apple Calendar into Lurelia's views",
                    isOn: $settings.showAppleCalendarEvents,
                    icon: "ringstarcal"
                )

                calendarToggleRow(
                    title: "Two-Way Sync",
                    subtitle: "Import Apple events into Lurelia automatically",
                    isOn: $settings.twoWayAppleCalendarSyncEnabled,
                    icon: "cloudsync"
                )
            }
            .padding(16)
            .background {
                BubblyCardMaterial(tint: theme.palette.surface, cornerRadius: 22)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.palette.secondaryAccent, lineWidth: 1)
            }
        }
    }

    private func calendarToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer(minLength: 8)

            LureliaSlidingIconToggle(
                isOn: isOn,
                iconName: icon,
                accentColor: theme.palette.secondaryAccent,
                accessibilityLabel: title,
                usesIconMaterial: true
            )
        }
    }

    // MARK: - Visible Apple calendars

    private var visibleAppleCalendarsSection: some View {
        section("Visible Apple Calendars", icon: "starcal") {
            if eventService.appleCalendars.isEmpty {
                Text("No Apple Calendars found.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(eventService.appleCalendars) { calendar in
                        appleCalendarRow(calendar)
                    }
                }
            }
        }
    }

    private func appleCalendarRow(_ calendar: LureliaAppleCalendarSource) -> some View {
        let isSelected = selectedIDs.contains(calendar.id)
        let calendarColor = Color(lureliaHex: calendar.colorHex)

        return Button {
            toggle(calendar.id)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(calendarColor)
                    .frame(width: 14, height: 14)
                    .bubblyIconMaterial(tint: calendarColor)

                Text(calendar.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Group {
                    if isSelected {
                        Image("checkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .bubblyIconMaterial(tint: .white)
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(theme.palette.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(calendarColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connect Apple

    private var connectAppleSection: some View {
        section("Connect Apple", icon: "dotscal") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Apple Calendar is not connected.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Button {
                    Task {
                        _ = await eventService.requestCalendarAccess()
                        selectedIDs = Set(eventService.appleCalendars.map(\.id))
                        settings.selectedAppleCalendarIDs = Array(selectedIDs)
                        settings.hasConfiguredAppleCalendarSelection = true
                    }
                } label: {
                    Text("Connect Apple Calendar")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(theme.palette.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background {
                BubblyCardMaterial(tint: theme.palette.surface, cornerRadius: 22)
            }
        }
    }

    // MARK: - Done

    private var doneButton: some View {
        Button { commitAndDismiss() } label: {
            Text("Done")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    BubblyCardMaterial(tint: theme.palette.primaryAction, cornerRadius: 22)
                }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.white)
                    .bubblyIconMaterial(tint: .white)

                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .bubblyIconMaterial(tint: .white)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)

            content()
        }
    }

    private func commitAndDismiss() {
        settings.selectedAppleCalendarIDs = Array(selectedIDs)
        // Mark configured so an empty visible-set is honored as "hide all"
        // instead of silently falling back to "show all".
        settings.hasConfiguredAppleCalendarSelection = true
        if let raw = defaultView?.rawValue {
            settings.defaultEventsViewRaw = raw
        }
        try? modelContext.save()
        dismiss()
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
