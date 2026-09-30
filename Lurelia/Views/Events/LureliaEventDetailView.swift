//
//  LureliaEventDetailView.swift
//  Lurelia
//
//  Read-only event view. Header pattern matches every other sheet in the
//  app (title top-left, Edit pill + xmarkwavy top-right). The full sheet
//  uses the large-format tile background while its nested content uses
//  the same compact card material as the Kanban timeline.
//

import SwiftData
import SwiftUI
import UIKit
import WidgetKit

struct LureliaEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var event: LureliaEvent
    let onEdit: () -> Void

    /// Full calendar catalog used to resolve `additionalCalendarIDs` (stored
    /// as UUIDs, not model refs, so we look them up here).
    @Query(sort: \LureliaCalendar.name) private var allCalendars: [LureliaCalendar]

    private var additionalCalendars: [LureliaCalendar] {
        event.additionalCalendars(from: allCalendars)
    }

    private var eventTint: Color {
        Color(lureliaHex: event.displayColorHex)
    }

    private var tileColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top)
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                detailBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header

                        headerCard

                        if event.calendar != nil { calendarSection }
                        if !additionalCalendars.isEmpty { additionalCalendarsSection }
                        scheduleSection
                        if hasLocation { locationSection }
                        if hasReminders { remindersSection }
                        if hasDetails { detailsSection }

                        deleteButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 60)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header row

    private var header: some View {
        HStack(spacing: 10) {
            Text(event.title.isEmpty ? "Event" : event.title)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 8)

            Button { onEdit() } label: {
                Text("Edit")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background { LureliaNeutralGlassSurface(cornerRadius: 999) }
                    .overlay(Capsule().strokeBorder(LColors.neutralPearl.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                ZStack {
                    Color.clear

                    Image("xmarkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white)
                        .bubblyIconMaterial(tint: .white)
                        .shadow(color: Color.black.opacity(0.42), radius: 2, x: 0, y: 1)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Header card (icon / title / description)

    private var headerCard: some View {
        detailCard(cornerRadius: 24, padding: LSpacing.cardPadding) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.34))
                        .frame(width: 70, height: 70)

                    Circle()
                        .strokeBorder(lineWidth: 1.6)
                        .frame(width: 70, height: 70)
                        .bubblyIconMaterial(tint: eventTint)
                        .allowsHitTesting(false)

                    LureliaIconView(iconId: event.displayIcon, size: 36)
                        .foregroundStyle(eventTint)
                        .bubblyIconMaterial(tint: eventTint)
                }

                Text(event.title.isEmpty ? "Untitled Event" : event.title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let description = event.eventDescription, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var detailBackground: some View {
        BubblyTileBackground(tint: eventTint)
    }

    // MARK: - Sections (label outside GlassCard, tiles inside)

    private var calendarSection: some View {
        section("Primary Calendar", icon: "ringstarcal") {
            detailCard {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(lureliaHex: event.calendar?.color ?? "#03dbfc"))
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NAME")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))

                        Text(event.calendar?.name.isEmpty == false ? (event.calendar?.name ?? "Untitled") : "Untitled")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var additionalCalendarsSection: some View {
        section("Additional Calendars", icon: "starcal") {
            VStack(spacing: 8) {
                ForEach(additionalCalendars) { cal in
                    detailCard {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(lureliaHex: cal.color))
                                .frame(width: 14, height: 14)

                            Text(cal.name.isEmpty ? "Untitled" : cal.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        section("Schedule", icon: "hourglassfill") {
            let start = event.occurrenceStart()
            let end = event.occurrenceEnd(for: start)
            let displayEndDate = event.isAllDay ? (event.endDate ?? event.startDate) : end

            LazyVGrid(columns: tileColumns, spacing: 10) {
                dataTile(
                    "Start Date",
                    value: start.formatted(date: .abbreviated, time: .omitted)
                )
                dataTile(
                    "Start Time",
                    value: event.isAllDay ? "All day" : start.formatted(date: .omitted, time: .shortened)
                )
                dataTile(
                    "End Date",
                    value: displayEndDate.formatted(date: .abbreviated, time: .omitted)
                )
                dataTile(
                    "End Time",
                    value: event.isAllDay ? "All day" : end.formatted(date: .omitted, time: .shortened)
                )
                dataTile(
                    "Duration",
                    value: event.isAllDay ? "All day" : durationText(event.duration)
                )
                if let recurrence = event.recurrence {
                    dataTile("Repeats", value: recurrence.frequency.label)
                }
            }
        }
    }

    private var locationSection: some View {
        section("Location", icon: "starpinlocation") {
            VStack(spacing: 10) {
                if let place = event.locationName, !place.isEmpty {
                    dataTile("Place", value: place)
                }
                if let address = event.address, !address.isEmpty {
                    dataTile("Address", value: address)
                }

                // Open-in-Maps button — appears whenever we have any
                // locatable info (name/address/coords). Uses the `link`
                // custom asset per the app's no-SF-Symbols rule.
                if (event.locationName?.isEmpty == false)
                    || (event.address?.isEmpty == false)
                    || (event.latitude != nil && event.longitude != nil) {
                    Button {
                        LureliaMapsOpener.open(
                            name: event.locationName,
                            address: event.address,
                            latitude: event.latitude,
                            longitude: event.longitude
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image("link")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.white)
                                .bubblyIconMaterial(tint: .white)
                                .shadow(color: Color.black.opacity(0.42), radius: 2, x: 0, y: 1)

                            Text("Open in Maps")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var remindersSection: some View {
        section("Reminders", icon: "bellfill") {
            LazyVGrid(columns: tileColumns, spacing: 10) {
                ForEach(event.notifications ?? []) { notification in
                    dataTile("Alert", value: "\(notification.offsetMinutes) min before")
                }
            }
        }
    }

    private var detailsSection: some View {
        section("Details", icon: "writefeather") {
            VStack(spacing: 10) {
                if let notes = event.notes, !notes.isEmpty {
                    detailCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))

                            Text(notes)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                let tagList = event.tags ?? []
                let attachmentList = event.attachments ?? []
                if !tagList.isEmpty || !attachmentList.isEmpty {
                    LazyVGrid(columns: tileColumns, spacing: 10) {
                        ForEach(tagList) { tag in
                            dataTile("Tag", value: tag.name)
                        }
                        ForEach(attachmentList) { attachment in
                            dataTile(
                                "Attachment",
                                value: attachment.title.isEmpty
                                    ? (attachment.fileName ?? attachment.urlString ?? "Attachment")
                                    : attachment.title
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    /// A section = white icon + title above the frosty tiles.
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
                    .shadow(color: Color.black.opacity(0.42), radius: 2, x: 0, y: 1)

                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)

            content()
        }
    }

    private func detailCard<Content: View>(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    BubblyCardMaterial(tint: eventTint, cornerRadius: cornerRadius)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: 1.2)
                    .bubblyIconMaterial(tint: eventTint)
                    .allowsHitTesting(false)
            }
    }

    private func dataTile(_ label: String, value: String) -> some View {
        detailCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))

                Text(value)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            deleteEvent()
        } label: {
            Text("Delete Event")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background { LureliaNeutralGlassSurface(cornerRadius: 18) }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LColors.neutralPearl.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - Helpers

    private var hasLocation: Bool {
        (event.locationName?.isEmpty == false) || (event.address?.isEmpty == false)
    }

    private var hasReminders: Bool {
        !(event.notifications ?? []).isEmpty
    }

    private var hasDetails: Bool {
        (event.notes?.isEmpty == false)
            || !(event.tags ?? []).isEmpty
            || !(event.attachments ?? []).isEmpty
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    private func deleteEvent() {
        LureliaEventNotificationManager.shared.cancelNotifications(for: event)
        try? LureliaEventService.shared.deleteFromAppleCalendar(event)
        modelContext.delete(event)
        try? modelContext.save()

        // Refresh the upcoming-events widget so the deleted event doesn't
        // linger in the tile until the next scheduled reload.
        LureliaWidgetReloads.reloadAll()

        dismiss()
    }
}
