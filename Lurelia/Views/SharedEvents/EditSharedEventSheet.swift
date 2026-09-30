//
//  EditSharedEventSheet.swift
//  Lurelia
//
//  Edit sheet for an existing SharedEvent. It reuses the same live-tinted
//  fields as the creator while preserving its separate save action.
//

import SwiftUI

struct EditSharedEventSheet: View {
    let event: SharedEventDTO
    let currentUserID: String
    let onSaved: (SharedEventDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var title: String
    @State private var description: String
    @State private var locationName: String
    @State private var visibility: String
    @State private var selectedColor: Color
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var startHour: Int
    @State private var startMinute: Int

    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    init(
        event: SharedEventDTO,
        currentUserID: String,
        onSaved: @escaping (SharedEventDTO) -> Void,
    ) {
        self.event = event
        self.currentUserID = currentUserID
        self.onSaved = onSaved
        _title = State(initialValue: event.title)
        _description = State(initialValue: event.description ?? "")
        _locationName = State(initialValue: event.locationName ?? "")
        _visibility = State(initialValue: event.visibility)
        _selectedColor = State(initialValue: Color(lureliaHex: event.colorHex))
        _isAllDay = State(initialValue: event.isAllDay)
        let cal = Calendar.current
        _startDate = State(initialValue: event.startDate)
        _startHour = State(initialValue: cal.component(.hour, from: event.startDate))
        _startMinute = State(initialValue: cal.component(.minute, from: event.startDate))
    }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header

                    SharedEventFormFields(
                        title: $title,
                        description: $description,
                        locationName: $locationName,
                        visibility: $visibility,
                        selectedColor: $selectedColor,
                        isAllDay: $isAllDay,
                        startDate: $startDate,
                        startHour: $startHour,
                        startMinute: $startMinute
                    )

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(LColors.danger.opacity(0.72), lineWidth: 1)
                        }
                    }

                    Spacer().frame(height: 60)
                }
                .padding(.top, 12)
                .padding(.horizontal, LSpacing.pageHorizontal)
            }
        }
        .presentationBackground(theme.palette.background)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            SharedEventFormActionButton(
                title: "Cancel",
                tint: selectedColor,
                isEnabled: true,
                action: { dismiss() }
            )

            Spacer(minLength: 8)

            SharedEventFormActionButton(
                title: isSubmitting ? "..." : "Save",
                tint: selectedColor,
                isEnabled: canSubmit && !isSubmitting,
                action: { Task { await save() } }
            )
        }
    }

    // MARK: - Save

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedStartDate: Date {
        if isAllDay {
            return Calendar.current.startOfDay(for: startDate)
        }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
        comps.hour = startHour
        comps.minute = startMinute
        return Calendar.current.date(from: comps) ?? startDate
    }

    private func save() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let updated = try await SharedEventsService.shared.updateEvent(
                eventID: event.id,
                actorUserID: currentUserID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: selectedColor.toHex() ?? event.colorHex,
                startDate: resolvedStartDate,
                isAllDay: isAllDay,
                locationName: locationName.trimmingCharacters(in: .whitespacesAndNewlines),
                visibility: visibility
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
