//
//  LureliaEventEditorView.swift
//  Lurelia
//
//  New/edit event sheet. Date and time drums are edited inline in the
//  Schedule card. The selected primary calendar drives the form-element tint.
//  Category
//  uses LureliaGradientDropdown with predefined LureliaEventCategory
//  options. Recurrence uses
//  LureliaGradientStepper and LureliaGradientDropdown. Reminders are
//  tap-tiles instead of toggles. Attachments are their own card with a
//  real photo + file picker, saved into Documents/EventAttachments/.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

private struct EventDarkMaterialModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .foregroundStyle(Color.black)
                .bubblyIconMaterial(tint: .black)
                .overlay {
                    content.foregroundStyle(Color.black.opacity(0.78))
                }
        } else {
            content
        }
    }
}

private extension View {
    func eventDarkMaterial(isEnabled: Bool = true) -> some View {
        modifier(EventDarkMaterialModifier(isEnabled: isEnabled))
    }
}

struct LureliaEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    let event: LureliaEvent?
    let tags: [LureliaEventTag]
    @Bindable var settings: UserSettings

    init(
        event: LureliaEvent?,
        tags: [LureliaEventTag],
        settings: UserSettings,
        initialCalendar: LureliaCalendar? = nil
    ) {
        self.event = event
        self.tags = tags
        self.settings = settings
        _selectedLureliaCalendar = State(initialValue: initialCalendar ?? event?.calendar)
    }

    @StateObject private var eventService = LureliaEventService.shared

    @Query(sort: \LureliaCalendar.name) private var lureliaCalendars: [LureliaCalendar]

    @State private var title = ""
    @State private var description = ""
    @State private var icon = "starcal"
    @State private var category: LureliaEventCategory? = nil
    /// Primary Calendar — required-ish single-select. Drives the event's
    /// inherited color across cards, detail view, and the events widget.
    @State private var selectedLureliaCalendar: LureliaCalendar? = nil
    /// Additional Calendars — optional multi-select. The event also belongs
    /// to these but they NEVER affect color. Kept mutually exclusive with
    /// `selectedLureliaCalendar` via `onChange` below and `sanitize…` on save.
    @State private var additionalCalendarIDs: Set<UUID> = []
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var startHour = 9
    @State private var startMinute = 0
    @State private var endHour = 10
    @State private var endMinute = 0
    @State private var isAllDay = false
    @State private var locationName = ""
    @State private var address = ""
    @State private var latitude: Double? = nil
    @State private var longitude: Double? = nil
    @State private var showLocationPicker = false
    @State private var notes = ""
    @State private var notifications: Set<LureliaEventNotificationOffset> = [.tenMinutes]
    @State private var recurrenceEnabled = false
    @State private var recurrenceFrequency: LureliaEventFrequency = .weekly
    @State private var recurrenceInterval = 1
    @State private var recurrenceWeekdays: Set<LureliaEventWeekday> = []
    @State private var recurrenceEndType: LureliaEventRecurrenceEndType? = .never
    @State private var recurrenceEndDate = Date()
    @State private var recurrenceCount = 10
    @State private var syncWithAppleCalendar = false
    @State private var selectedCalendarID: String?
    @State private var showIconPicker = false

    // Attachments (file-picker driven)
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var attachmentDrafts: [AttachmentDraft] = []
    @State private var originalAttachmentIDs: Set<UUID> = []

    private var isEditing: Bool { event != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            selectedLureliaCalendar != nil
    }

    private var eventTint: Color {
        guard let colorHex = selectedLureliaCalendar?.color,
              !colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return theme.palette.primaryAction }

        return Color(lureliaHex: colorHex)
    }

    private var eventTintIdentity: String {
        guard let selectedLureliaCalendar else {
            return "theme-primary"
        }

        return "\(selectedLureliaCalendar.id.uuidString)|\(selectedLureliaCalendar.color)"
    }

    private var primaryCalendarSelection: Binding<LureliaCalendar?> {
        Binding(
            get: { selectedLureliaCalendar },
            set: { newCalendar in
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedLureliaCalendar = newCalendar
                    if let newCalendar {
                        additionalCalendarIDs.remove(newCalendar.id)
                    }
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header

                        iconCard
                        titleCard
                        descriptionCard
                        categoryCard
                        calendarCard
                        additionalCalendarsCard

                        scheduleCard
                        recurrenceCard
                        reminderCard
                        locationCard
                        notesCard
                        attachmentsCard
                        appleCalendarCard

                        saveButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 60)
                    .animation(.easeInOut(duration: 0.18), value: eventTintIdentity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $icon)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                ingestFilePickerResult(result)
            }
            .onChange(of: photoSelection) { _, newItems in
                ingestPhotoSelection(newItems)
            }
            .onChange(of: startHour) { _, _ in commitStartTime() }
            .onChange(of: startMinute) { _, _ in commitStartTime() }
            .onChange(of: endHour) { _, _ in commitEndTime() }
            .onChange(of: endMinute) { _, _ in commitEndTime() }
            .task {
                load()
                loadScheduleDrumValues()
                eventService.refreshAuthorizationStatus()
                // Prefer the user's explicit Sync-To-Calendar pick; fall back
                // to their first visible Apple calendar, then to the first
                // writable Apple calendar overall.
                selectedCalendarID = selectedCalendarID
                    ?? settings.defaultAppleSyncCalendarID
                    ?? settings.selectedAppleCalendarIDs.first
                    ?? eventService.appleCalendars.first(where: { $0.allowsContentModifications })?.id
                // For a brand new event, default "Sync This Event" to the
                // user's global Two-Way Sync preference so events actually
                // mirror to Apple without an extra per-event toggle step.
                if event == nil && settings.twoWayAppleCalendarSyncEnabled {
                    syncWithAppleCalendar = true
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(isEditing ? "Edit Event" : "New Event")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LGradients.header)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Basic cards

    private func eventEditorCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(LSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(eventTint, lineWidth: 1)
            }
    }

    private func eventSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(theme.palette.textSecondary)
    }

    private var iconCard: some View {
        Button { showIconPicker = true } label: {
            eventEditorCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.56))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Circle()
                                    .strokeBorder(eventTint, lineWidth: 1)
                            }
                        LureliaIconView(iconId: icon, size: 23)
                            .foregroundStyle(eventTint)
                            .bubblyIconMaterial(tint: eventTint)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Event Icon")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tap to change")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    Image("chevright")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(eventTint)
                        .bubblyIconMaterial(tint: eventTint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var titleCard: some View {
        eventEditorCard {
            TextField("Event title", text: $title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var descriptionCard: some View {
        eventEditorCard {
            ZStack(alignment: .topLeading) {
                if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Description...")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
                TextEditor(text: $description)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .frame(minHeight: 90)
            }
        }
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            eventSectionLabel("CATEGORY")

            LureliaGradientDropdown(
                placeholder: "Choose a category",
                options: LureliaEventCategory.allCases,
                selection: $category,
                allowsClear: true,
                label: { $0.rawValue },
                tint: eventTint,
                usesCardMaterial: true,
                usesDarkTypography: true,
                maxVisibleOptions: 4
            )
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            eventSectionLabel("PRIMARY CALENDAR")

            if lureliaCalendars.isEmpty {
                Text("No calendars yet. Create one from the Events header to group your events.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                LureliaGradientDropdown(
                    placeholder: "Choose a calendar",
                    options: lureliaCalendars,
                    selection: primaryCalendarSelection,
                    allowsClear: false,
                    label: { $0.name.isEmpty ? "Untitled" : $0.name },
                    tint: eventTint,
                    usesCardMaterial: true,
                    usesDarkTypography: true
                )

                Text("Determines the event's color across the app and widgets.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    private var additionalCalendarsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            eventSectionLabel("ADDITIONAL CALENDARS")

            if lureliaCalendars.isEmpty {
                Text("No calendars available.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                LureliaGradientMultiSelectDropdown(
                    placeholder: "Choose additional calendars",
                    options: lureliaCalendars,
                    selection: $additionalCalendarIDs,
                    label: { $0.name.isEmpty ? "Untitled" : $0.name },
                    optionsFilter: { $0.id != selectedLureliaCalendar?.id },
                    tint: eventTint,
                    usesCardMaterial: true,
                    usesDarkTypography: true
                )

                Text("Optional. This event will appear under each selected calendar. Additional calendars do not change the event's color.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        eventEditorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("SCHEDULE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))

                    Spacer()

                    Text("All Day")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    LureliaSlidingIconToggle(
                        isOn: $isAllDay,
                        iconName: "ringstarcal",
                        accentColor: eventTint,
                        accessibilityLabel: "All Day",
                        usesIconMaterial: true
                    )
                }

                inlineScheduleRow(
                    title: "STARTS",
                    date: $startDate,
                    hour: $startHour,
                    minute: $startMinute
                )

                Divider()
                    .overlay(Color.white.opacity(0.12))

                inlineScheduleRow(
                    title: "ENDS",
                    date: $endDate,
                    hour: $endHour,
                    minute: $endMinute
                )
            }
        }
    }

    private func inlineScheduleRow(
        title: String,
        date: Binding<Date>,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))

            if isAllDay {
                LureliaGradientDateDrumPicker(
                    date: date,
                    tint: eventTint,
                    usesCardMaterial: true,
                    usesDarkTypography: true
                )
            } else {
                HStack(alignment: .top, spacing: 10) {
                    LureliaCompactDateDrumPicker(
                        date: date,
                        tint: eventTint,
                        usesCardMaterial: true,
                        usesDarkTypography: true
                    )
                        .frame(maxWidth: .infinity)

                    LureliaCompactTimeDrumPicker(
                        hour: hour,
                        minute: minute,
                        tint: eventTint,
                        usesDarkTypography: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Recurrence

    private var recurrenceCard: some View {
        eventEditorCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("RECURRENCE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 12) {
                    Text("Repeats")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Spacer()

                    LureliaSlidingIconToggle(
                        isOn: $recurrenceEnabled,
                        iconName: "repeat",
                        accentColor: eventTint,
                        accessibilityLabel: "Repeats",
                        usesIconMaterial: true
                    )
                }

                if recurrenceEnabled {
                    recurrenceFrequencyPicker

                    LureliaGradientStepper(
                        title: "Every",
                        subtitle: recurrenceInterval == 1 ? recurrenceFrequency.rawValue : recurrenceFrequency.rawValue + "s",
                        value: $recurrenceInterval,
                        range: 1...30,
                        tint: eventTint,
                        showsContainer: false,
                        usesTintedMaterialButtons: true
                    )

                    if recurrenceFrequency == .weekly {
                        HStack(spacing: 7) {
                            Spacer(minLength: 0)
                            ForEach(LureliaEventWeekday.allCases) { weekday in
                                weekdayPill(weekday)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ENDS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))

                        LureliaGradientDropdown(
                            placeholder: "Never",
                            options: LureliaEventRecurrenceEndType.allCases,
                            selection: $recurrenceEndType,
                            label: { $0.label },
                            tint: eventTint,
                            usesCardMaterial: true,
                            usesDarkTypography: true
                        )
                    }

                    if recurrenceEndType == .onDate {
                        DatePicker(
                            "End On",
                            selection: $recurrenceEndDate,
                            displayedComponents: .date
                        )
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .tint(eventTint)
                    } else if recurrenceEndType == .afterOccurrences {
                        LureliaGradientStepper(
                            title: "After",
                            subtitle: recurrenceCount == 1 ? "event" : "events",
                            value: $recurrenceCount,
                            range: 1...999,
                            tint: eventTint,
                            showsContainer: false,
                            usesTintedMaterialButtons: true
                        )
                    }
                }
            }
        }
    }

    private var recurrenceFrequencyPicker: some View {
        HStack(spacing: 6) {
            ForEach(LureliaEventFrequency.allCases) { frequency in
                let isSelected = recurrenceFrequency == frequency

                Button {
                    recurrenceFrequency = frequency
                } label: {
                    Text(frequency.label)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                        .eventDarkMaterial(isEnabled: isSelected)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if isSelected {
                                BubblyIconMaterial(tint: eventTint)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(theme.palette.surface)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSelected ? eventTint : theme.palette.textPrimary.opacity(0.12),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func weekdayPill(_ weekday: LureliaEventWeekday) -> some View {
        let isSelected = recurrenceWeekdays.contains(weekday)
        Button {
            if isSelected {
                recurrenceWeekdays.remove(weekday)
            } else {
                recurrenceWeekdays.insert(weekday)
            }
        } label: {
            Text(weekday.shortLabel)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                .eventDarkMaterial(isEnabled: isSelected)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        BubblyIconMaterial(tint: eventTint)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? eventTint : theme.palette.textPrimary.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reminders (tap tiles)

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            eventSectionLabel("REMINDERS")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(LureliaEventNotificationOffset.allCases) { offset in
                    reminderTile(offset)
                }
            }
        }
    }

    @ViewBuilder
    private func reminderTile(_ offset: LureliaEventNotificationOffset) -> some View {
        let isSelected = notifications.contains(offset)
        Button {
            if isSelected {
                notifications.remove(offset)
            } else {
                notifications.insert(offset)
            }
        } label: {
            Text(offset.label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                .eventDarkMaterial(isEnabled: isSelected)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        BubblyIconMaterial(tint: eventTint)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? eventTint : theme.palette.textPrimary.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Location

    private var locationCard: some View {
        eventEditorCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("LOCATION")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                if locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // No location yet — search entry point.
                    Button {
                        showLocationPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image("starpinlocation")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(eventTint)
                                .bubblyIconMaterial(tint: eventTint)

                            Text("Search for a place…")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    // Selected place — name in a box (matches the detail
                    // view's Place tile), a link-icon button below, and
                    // an X on the name box to clear.
                    selectedLocationTile

                    Button {
                        LureliaMapsOpener.open(
                            name: locationName,
                            address: address.isEmpty ? nil : address,
                            latitude: latitude,
                            longitude: longitude
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image("link")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.white)

                            Text("Open in Maps")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()
                        }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(eventTint, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            LureliaLocationPickerSheet { result in
                locationName = result.name
                address = result.addressLine
                latitude = result.latitude
                longitude = result.longitude
            }
        }
    }

    /// Selected-location tile — shows just the name (matches the detail
    /// view's Place tile) with a small X button to clear the selection.
    private var selectedLocationTile: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("starpinlocation")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(eventTint)
                .bubblyIconMaterial(tint: eventTint)

            Text(locationName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                clearLocation()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(eventTint)
                    .bubblyIconMaterial(tint: eventTint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(eventTint, lineWidth: 1)
        )
    }

    private func clearLocation() {
        locationName = ""
        address = ""
        latitude = nil
        longitude = nil
    }

    // MARK: - Notes (no longer holds attachments)

    private var notesCard: some View {
        eventEditorCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("NOTES")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                ZStack(alignment: .topLeading) {
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Notes...")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                    TextEditor(text: $notes)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 90)
                }
            }
        }
    }

    // MARK: - Attachments (photo + file picker)

    private var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            eventSectionLabel("ATTACHMENTS")

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $photoSelection,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    attachmentActionLabel(iconAsset: "starcal", title: "Add Photo")
                }

                Button {
                    showFileImporter = true
                } label: {
                    attachmentActionLabel(iconAsset: "notespen", title: "Add File")
                }
                .buttonStyle(.plain)
            }

            if !attachmentDrafts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(attachmentDrafts) { draft in
                        attachmentRow(draft)
                    }
                }
            }
        }
    }

    private func attachmentActionLabel(iconAsset: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(iconAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .eventDarkMaterial()

            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .eventDarkMaterial()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background {
            BubblyCardMaterial(tint: eventTint, cornerRadius: 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(eventTint, lineWidth: 1)
        )
    }

    private func attachmentRow(_ draft: AttachmentDraft) -> some View {
        HStack(spacing: 10) {
            Image(draft.mimeType.hasPrefix("image/") ? "starcal" : "notespen")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(eventTint)
                .bubblyIconMaterial(tint: eventTint)

            Text(draft.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                removeDraft(draft)
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(eventTint, lineWidth: 1)
        )
    }

    // MARK: - Apple Calendar

    private var appleCalendarCard: some View {
        eventEditorCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("APPLE CALENDAR")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 12) {
                    Text("Sync This Event")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Spacer()

                    LureliaSlidingIconToggle(
                        isOn: $syncWithAppleCalendar,
                        iconName: "cloudsync",
                        accentColor: eventTint,
                        accessibilityLabel: "Sync This Event",
                        usesIconMaterial: true
                    )
                }

                if syncWithAppleCalendar {
                    if eventService.hasCalendarAccess {
                        LureliaGradientDropdown(
                            placeholder: "Choose a calendar",
                            options: eventService.appleCalendars.filter(\.allowsContentModifications).map(\.id),
                            selection: Binding(
                                get: { selectedCalendarID },
                                set: { selectedCalendarID = $0 }
                            ),
                            label: { id in
                                eventService.appleCalendars.first(where: { $0.id == id })?.title ?? id
                            },
                            tint: eventTint,
                            usesCardMaterial: true,
                            usesDarkTypography: true
                        )
                    } else {
                        Button {
                            Task { _ = await eventService.requestCalendarAccess() }
                        } label: {
                            Text("Connect Apple Calendar")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .eventDarkMaterial()
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background { BubblyCardMaterial(tint: eventTint, cornerRadius: 16) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button { save() } label: {
            Text(isEditing ? "Save Event" : "Create Event")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background { BubblyCardMaterial(tint: eventTint, cornerRadius: 22) }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(eventTint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
        .padding(.top, 6)
    }

    // MARK: - Load

    private func load() {
        guard let event else { return }

        title = event.title
        description = event.eventDescription ?? ""
        icon = event.displayIcon
        category = LureliaEventCategory.matching(event.categoryName)
        selectedLureliaCalendar = event.calendar
        // Load additional-calendar membership. The setter on save re-runs
        // the primary-excluded invariant so we don't need to filter here.
        additionalCalendarIDs = Set(event.additionalCalendarIDs)
        startDate = event.startDate
        endDate = event.endDate ?? event.startDate
        startTime = event.startTime ?? event.startDate
        endTime = event.endTime ?? event.endDate ?? event.startDate.addingTimeInterval(event.duration)
        isAllDay = event.isAllDay
        locationName = event.locationName ?? ""
        address = event.address ?? ""
        latitude = event.latitude
        longitude = event.longitude
        notes = event.notes ?? ""
        notifications = Set((event.notifications ?? []).compactMap { LureliaEventNotificationOffset(rawValue: $0.offsetMinutes) })
        syncWithAppleCalendar = event.syncsWithAppleCalendar
        selectedCalendarID = event.appleCalendarIdentifier ?? settings.selectedAppleCalendarIDs.first

        if let recurrence = event.recurrence {
            recurrenceEnabled = true
            recurrenceFrequency = recurrence.frequency
            recurrenceInterval = recurrence.interval
            recurrenceWeekdays = Set(recurrence.weekdays)
            recurrenceEndType = recurrence.endType
            recurrenceEndDate = recurrence.endDate ?? Date()
            recurrenceCount = recurrence.occurrenceCount ?? 10
        }

        // Load existing attachments as drafts.
        let existing = event.attachments ?? []
        attachmentDrafts = existing.map { model in
            AttachmentDraft(
                id: model.id,
                title: model.title.isEmpty ? (model.fileName ?? "Attachment") : model.title,
                fileName: model.fileName ?? "",
                mimeType: model.mimeType ?? "application/octet-stream",
                isExisting: true
            )
        }
        originalAttachmentIDs = Set(existing.map(\.id))
    }

    private func loadScheduleDrumValues() {
        let startComponents = Calendar.current.dateComponents(
            [.hour, .minute],
            from: startTime
        )
        startHour = startComponents.hour ?? 9
        startMinute = startComponents.minute ?? 0

        let endComponents = Calendar.current.dateComponents(
            [.hour, .minute],
            from: endTime
        )
        endHour = endComponents.hour ?? 10
        endMinute = endComponents.minute ?? 0
    }

    private func commitStartTime() {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: startTime
        )
        components.hour = startHour
        components.minute = startMinute
        components.second = 0

        guard let newTime = Calendar.current.date(from: components),
              newTime != startTime
        else { return }

        startTime = newTime
    }

    private func commitEndTime() {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: endTime
        )
        components.hour = endHour
        components.minute = endMinute
        components.second = 0

        guard let newTime = Calendar.current.date(from: components),
              newTime != endTime
        else { return }

        endTime = newTime
    }

    // MARK: - Save

    private func save() {
        let target = event ?? LureliaEvent()
        if event == nil {
            modelContext.insert(target)
        }

        target.markNativeLureliaEvent()
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.eventDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        target.icon = icon
        target.categoryName = category?.rawValue
        target.calendar = selectedLureliaCalendar
        // Persist additional calendars, enforcing that the primary is
        // never also in the additional list.
        let additionalCalendars = lureliaCalendars.filter { additionalCalendarIDs.contains($0.id) }
        target.setAdditionalCalendars(
            additionalCalendars,
            primaryOverride: selectedLureliaCalendar
        )
        target.startDate = startDate
        target.endDate = endDate
        target.startTime = isAllDay ? nil : startTime
        target.endTime = isAllDay ? nil : endTime
        target.isAllDay = isAllDay
        target.duration = max(0, endTime.timeIntervalSince(startTime))
        target.locationName = locationName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        target.address = address.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        target.latitude = latitude
        target.longitude = longitude
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        target.modifiedDate = Date()

        replaceNotifications(on: target)
        replaceRecurrence(on: target)
        reconcileAttachments(on: target)

        if syncWithAppleCalendar {
            do {
                try eventService.saveToAppleCalendar(target, calendarIdentifier: selectedCalendarID)
            } catch {
                // Surface the exact reason instead of swallowing it — this
                // is what silently lost events to the void before.
                print("🚨 [EventEditor] Failed to mirror event to Apple Calendar: \(error)")
            }
        } else if target.syncsWithAppleCalendar {
            do {
                try eventService.deleteFromAppleCalendar(target)
            } catch {
                print("🚨 [EventEditor] Failed to remove event from Apple Calendar: \(error)")
            }
        }

        LureliaEventNotificationManager.shared.scheduleNotifications(for: target)
        try? modelContext.save()

        // Propagate to the upcoming-events widget so it refreshes right
        // after the user saves (same pattern the habits/reminders/routines
        // widgets rely on).
        LureliaWidgetReloads.reloadAll()

        dismiss()
    }

    private func replaceNotifications(on target: LureliaEvent) {
        for notification in target.notifications ?? [] {
            modelContext.delete(notification)
        }

        target.notifications = notifications.sorted { $0.rawValue < $1.rawValue }.map { offset in
            let notification = LureliaEventNotification(offset: offset)
            notification.event = target
            modelContext.insert(notification)
            return notification
        }
    }

    private func replaceRecurrence(on target: LureliaEvent) {
        if let existing = target.recurrence {
            modelContext.delete(existing)
            target.recurrence = nil
        }

        guard recurrenceEnabled else { return }

        let endType = recurrenceEndType ?? .never
        let recurrence = LureliaEventRecurrence(
            frequency: recurrenceFrequency,
            interval: recurrenceInterval,
            weekdays: Array(recurrenceWeekdays),
            endType: endType
        )
        recurrence.endDate = endType == .onDate ? recurrenceEndDate : nil
        recurrence.occurrenceCount = endType == .afterOccurrences ? recurrenceCount : nil
        recurrence.dayOfMonth = recurrenceFrequency == .monthly ? Calendar.current.component(.day, from: startDate) : nil
        recurrence.month = recurrenceFrequency == .yearly ? Calendar.current.component(.month, from: startDate) : nil
        recurrence.day = recurrenceFrequency == .yearly ? Calendar.current.component(.day, from: startDate) : nil
        recurrence.event = target
        modelContext.insert(recurrence)
        target.recurrence = recurrence
    }

    private func reconcileAttachments(on target: LureliaEvent) {
        let currentDraftIDs = Set(attachmentDrafts.map(\.id))
        let removedIDs = originalAttachmentIDs.subtracting(currentDraftIDs)

        // Delete removed attachments (both model + file).
        for attachment in (target.attachments ?? []) where removedIDs.contains(attachment.id) {
            if let fileName = attachment.fileName {
                try? FileManager.default.removeItem(at: attachmentsDirectory().appendingPathComponent(fileName))
            }
            modelContext.delete(attachment)
        }

        // Insert new drafts (those with isExisting == false) as new attachments.
        var updated = (target.attachments ?? []).filter { !removedIDs.contains($0.id) }
        for draft in attachmentDrafts where !draft.isExisting {
            let attachment = LureliaEventAttachment(
                title: draft.title,
                fileName: draft.fileName,
                urlString: nil,
                mimeType: draft.mimeType
            )
            attachment.id = draft.id
            attachment.event = target
            modelContext.insert(attachment)
            updated.append(attachment)
        }
        target.attachments = updated
    }

    // MARK: - Attachment picker ingestion

    private func ingestPhotoSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let capture = items
        photoSelection = []

        Task { @MainActor in
            for item in capture {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let id = UUID()
                let ext = "jpg"
                let fileName = "\(id.uuidString).\(ext)"
                let url = attachmentsDirectory().appendingPathComponent(fileName)
                do {
                    try data.write(to: url, options: .atomic)
                    attachmentDrafts.append(
                        AttachmentDraft(
                            id: id,
                            title: "Photo",
                            fileName: fileName,
                            mimeType: "image/jpeg",
                            isExisting: false
                        )
                    )
                } catch {
                    print("[EventEditor] Failed to save photo attachment: \(error)")
                }
            }
        }
    }

    private func ingestFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            print("[EventEditor] File picker failed: \(error)")
        case .success(let urls):
            for source in urls {
                ingestFile(at: source)
            }
        }
    }

    private func ingestFile(at source: URL) {
        let didStart = source.startAccessingSecurityScopedResource()
        defer { if didStart { source.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: source) else { return }
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destination = attachmentsDirectory().appendingPathComponent(fileName)
        do {
            try data.write(to: destination, options: .atomic)
            let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            attachmentDrafts.append(
                AttachmentDraft(
                    id: id,
                    title: source.lastPathComponent,
                    fileName: fileName,
                    mimeType: mimeType,
                    isExisting: false
                )
            )
        } catch {
            print("[EventEditor] Failed to save file attachment: \(error)")
        }
    }

    private func removeDraft(_ draft: AttachmentDraft) {
        // For a new (never-saved) draft, delete the temp file immediately.
        // For an existing draft, we keep the file until reconcileAttachments.
        if !draft.isExisting {
            let url = attachmentsDirectory().appendingPathComponent(draft.fileName)
            try? FileManager.default.removeItem(at: url)
        }
        attachmentDrafts.removeAll { $0.id == draft.id }
    }

    private func attachmentsDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("EventAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

// MARK: - Local attachment draft

struct AttachmentDraft: Identifiable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var mimeType: String
    var isExisting: Bool
}

private extension String {
    var nonEmptyOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
