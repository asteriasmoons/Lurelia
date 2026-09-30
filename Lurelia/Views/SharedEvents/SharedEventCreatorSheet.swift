//
//  SharedEventCreatorSheet.swift
//  Lurelia
//
//  Sheet for creating a new SharedEvent from inside the app. Backed by
//  SharedEventsService.createEvent — the server bootstraps Host,
//  Permissions, and a host Attendee row on receipt.
//

import SwiftUI

struct SharedEventCreationFlow: View {
    private enum Stage {
        case color
        case editor
    }

    let currentUserID: String
    let currentDisplayName: String
    let currentAvatarURL: String?
    let onColorChanged: (String) -> Void
    let onCreated: (SharedEventDTO) -> Void

    @State private var stage: Stage = .color
    @State private var selectedColor: Color

    init(
        currentUserID: String,
        currentDisplayName: String,
        currentAvatarURL: String?,
        initialColorHex: String,
        onColorChanged: @escaping (String) -> Void,
        onCreated: @escaping (SharedEventDTO) -> Void
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentAvatarURL = currentAvatarURL
        self.onColorChanged = onColorChanged
        self.onCreated = onCreated
        _selectedColor = State(initialValue: Color(lureliaHex: initialColorHex))
    }

    var body: some View {
        Group {
            switch stage {
            case .color:
                SharedEventColorGatekeeperView(color: $selectedColor) {
                    persistColor(selectedColor)
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        stage = .editor
                    }
                }
            case .editor:
                SharedEventCreatorSheet(
                    currentUserID: currentUserID,
                    currentDisplayName: currentDisplayName,
                    currentAvatarURL: currentAvatarURL,
                    initialColor: selectedColor,
                    onColorChanged: { color in
                        selectedColor = color
                        persistColor(color)
                    },
                    onCreated: onCreated
                )
            }
        }
        .presentationDetents(stage == .color ? [.height(330)] : [.large])
    }

    private func persistColor(_ color: Color) {
        onColorChanged(color.toHex() ?? "#03dbfc")
    }
}

struct SharedEventFormFields: View {
    @Environment(\.appTheme) private var theme

    @Binding var title: String
    @Binding var description: String
    @Binding var locationName: String
    @Binding var visibility: String
    @Binding var selectedColor: Color
    @Binding var isAllDay: Bool
    @Binding var startDate: Date
    @Binding var startHour: Int
    @Binding var startMinute: Int

    var body: some View {
        VStack(spacing: 18) {
            fieldSection("Title") {
                TextField("Give the event a name", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(14)
                    .background(fieldBackground(cornerRadius: 16))
            }

            fieldSection("Color") {
                ColorPicker(selection: $selectedColor, supportsOpacity: false) {
                    Text("Shared Event Color")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(fieldBackground(cornerRadius: 16))
            }

            fieldSection("Details") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $description)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 118)

                    if description.isEmpty {
                        Text("Description (optional)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }
                .background(fieldBackground(cornerRadius: 16))
            }

            fieldSection("Location") {
                TextField("Location (optional)", text: $locationName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(14)
                    .background(fieldBackground(cornerRadius: 16))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("All day")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Text(isAllDay ? "No event time" : "Use a start time")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                }

                Spacer()

                LureliaSlidingIconToggle(
                    isOn: $isAllDay,
                    iconName: "starcal",
                    accentColor: selectedColor,
                    accessibilityLabel: "All day shared event",
                    usesIconMaterial: true
                )
            }
            .padding(16)
            .background(fieldBackground(cornerRadius: 18))

            fieldSection("When") {
                HStack(alignment: .top, spacing: 10) {
                    LureliaCompactDateDrumPicker(
                        date: $startDate,
                        tint: selectedColor,
                        usesCardMaterial: true,
                        usesDarkTypography: true
                    )
                    .frame(maxWidth: .infinity)

                    if !isAllDay {
                        LureliaCompactTimeDrumPicker(
                            hour: $startHour,
                            minute: $startMinute,
                            tint: selectedColor,
                            usesDarkTypography: true
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Visibility")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)

                HStack(spacing: 8) {
                    visibilityButton("Private", value: "private")
                    visibilityButton("Link only", value: "link")
                    visibilityButton("Public", value: "public")
                }
            }
            .padding(16)
            .background(fieldBackground(cornerRadius: 18))
        }
    }

    private func fieldSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            content()
        }
    }

    private func fieldBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(theme.palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(selectedColor, lineWidth: 1)
            }
    }

    private func visibilityButton(_ label: String, value: String) -> some View {
        let isSelected = visibility == value

        return Button {
            visibility = value
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if isSelected {
                        BubblyIconMaterial(tint: selectedColor)
                            .clipShape(RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                        .strokeBorder(selectedColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct SharedEventFormActionButton: View {
    let title: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background {
                    BubblyIconMaterial(tint: tint)
                        .clipShape(Capsule())
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct SharedEventColorGatekeeperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Binding var color: Color
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Choose Shared Event Color")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)

                        Text("This color will carry through the event and can still be changed in the next sheet.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button { dismiss() } label: {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white)
                            .bubblyIconMaterial(tint: .white)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel shared event")
                }

                ColorPicker(selection: $color, supportsOpacity: false) {
                    Text("Shared Event Color")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(color, lineWidth: 1)
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background {
                            BubblyCardMaterial(tint: color, cornerRadius: 16)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.palette.background)
    }
}

struct SharedEventCreatorSheet: View {
    let currentUserID: String
    let currentDisplayName: String
    let currentAvatarURL: String?
    let onColorChanged: (Color) -> Void
    let onCreated: (SharedEventDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var locationName: String = ""
    @State private var visibility: String = "private"
    @State private var selectedColor: Color
    @State private var isAllDay: Bool = false
    @State private var startDate: Date = defaultStart()
    @State private var startHour: Int = 18
    @State private var startMinute: Int = 0
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    init(
        currentUserID: String,
        currentDisplayName: String,
        currentAvatarURL: String?,
        initialColor: Color,
        onColorChanged: @escaping (Color) -> Void,
        onCreated: @escaping (SharedEventDTO) -> Void
    ) {
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.currentAvatarURL = currentAvatarURL
        self.onColorChanged = onColorChanged
        self.onCreated = onCreated
        _selectedColor = State(initialValue: initialColor)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { selectedColor },
            set: { newColor in
                selectedColor = newColor
                onColorChanged(newColor)
            }
        )
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
                        selectedColor: colorBinding,
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

    // MARK: - Header

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
                title: isSubmitting ? "..." : "Create",
                tint: selectedColor,
                isEnabled: canSubmit && !isSubmitting,
                action: { Task { await create() } }
            )
        }
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !currentUserID.isEmpty
            && !currentDisplayName.isEmpty
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

    private func create() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let payload = SharedEventsService.CreateEventPayload(
            localID: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: nil,
            colorHex: selectedColor.toHex() ?? "#03dbfc",
            timezoneIdentifier: TimeZone.current.identifier,
            startDate: resolvedStartDate,
            endDate: nil,
            isAllDay: isAllDay,
            locationName: locationName.trimmingCharacters(in: .whitespacesAndNewlines),
            address: nil,
            visibility: visibility,
            hostUserID: currentUserID,
            hostDisplayName: currentDisplayName,
            hostAvatarURL: currentAvatarURL,
        )
        do {
            let event = try await SharedEventsService.shared.createEvent(payload)
            onCreated(event)
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Defaults

    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let now = Date()
        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        return day
    }
}
