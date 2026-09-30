//
//  SharedEventCalendarSyncCard.swift
//  Lurelia
//
//  Per-event card that lets the user mirror a shared event into their
//  Apple Calendar. Sits inside SharedEventDetailView; per-device state
//  lives in the local `SharedEventAppleMirror` @Model.
//

import SwiftUI
import SwiftData

struct SharedEventCalendarSyncCard: View {
    let event: SharedEventDTO
    let tint: Color

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @StateObject private var eventService = LureliaEventService.shared

    @State private var mirror: SharedEventAppleMirror?
    @State private var pickedCalendarID: String = ""
    @State private var pickedMode: SharedEventCalendarSyncMode = .off
    @State private var isBusy: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                header

                if !hasCalendarAccess {
                    Button {
                        Task { await requestAccess() }
                    } label: {
                        Text("Allow calendar access")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                BubblyCardMaterial(tint: tint, cornerRadius: 18)
                            }
                    }
                    .buttonStyle(.plain)
                } else {
                    calendarPicker
                    modePicker
                    actionButtons
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.danger)
                        .lineLimit(3)
                }

                if let lastSync = mirror?.lastSyncedAt {
                    Text("Last synced ").font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                        + Text(lastSync, style: .relative)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                }
        }
        .padding(16)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint, lineWidth: 1)
        }
        .task { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Apple Calendar sync")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
            Spacer()
            if let mirror, mirror.isEnabled {
                Text(mirror.syncMode.rawValue.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        BubblyIconMaterial(tint: tint)
                            .clipShape(Capsule())
                    }
            }
        }
    }

    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Write into calendar")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textSecondary)

            let calendars = eventService.appleCalendars.filter { $0.allowsContentModifications }
            if calendars.isEmpty {
                Text("No writable calendars.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
            } else {
                LureliaGradientDropdown(
                    placeholder: "Choose a calendar",
                    options: calendars.map(\.id),
                    selection: calendarSelectionBinding,
                    label: { calendarID in
                        calendars.first(where: { $0.id == calendarID })?.title ?? "Calendar"
                    },
                    tint: tint,
                    usesCardMaterial: true,
                    usesDarkTypography: true,
                    iconTint: .black,
                    maxVisibleOptions: 4
                )
            }
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync mode")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textSecondary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8,
            ) {
                modeButton(.off, label: "Off")
                modeButton(.mirror, label: "Mirror once")
                modeButton(.exportOnly, label: "Export")
                modeButton(.importOnly, label: "Import")
                modeButton(.oneWay, label: "One-way")
                modeButton(.twoWay, label: "Two-way")
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await runSync() }
            } label: {
                Text(isBusy ? "Syncing…" : "Apply")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        BubblyCardMaterial(tint: tint, cornerRadius: 18)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isBusy || pickedCalendarID.isEmpty || pickedMode == .off)
            .opacity((isBusy || pickedCalendarID.isEmpty || pickedMode == .off) ? 0.45 : 1)

            if mirror?.isEnabled == true {
                Button {
                    Task { await stopMirror() }
                } label: {
                    Text("Stop")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(theme.palette.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(tint, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private func modeButton(_ mode: SharedEventCalendarSyncMode, label: String) -> some View {
        let isActive = pickedMode == mode
        return Button {
            pickedMode = mode
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isActive ? Color.black : theme.palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        BubblyIconMaterial(tint: tint)
                            .clipShape(RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                        .strokeBorder(tint, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var hasCalendarAccess: Bool { eventService.hasCalendarAccess }

    private var calendarSelectionBinding: Binding<String?> {
        Binding(
            get: { pickedCalendarID.isEmpty ? nil : pickedCalendarID },
            set: { pickedCalendarID = $0 ?? "" }
        )
    }

    // MARK: - Actions

    private func requestAccess() async {
        let ok = await SharedEventCalendarSync.shared.ensureAccess()
        if ok {
            eventService.refreshAuthorizationStatus()
        } else {
            errorMessage = "Access denied. Enable in Settings → Lurelia → Calendars."
        }
    }

    private func load() async {
        eventService.refreshAuthorizationStatus()
        let m = SharedEventCalendarSync.shared.mirror(
            for: event.id,
            context: modelContext,
        )
        mirror = m
        pickedCalendarID = m.appleCalendarIdentifier ?? ""
        pickedMode = m.syncMode == .off ? .exportOnly : m.syncMode
    }

    private func runSync() async {
        guard let mirror else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        mirror.syncMode = pickedMode
        mirror.appleCalendarIdentifier = pickedCalendarID
        try? modelContext.save()

        do {
            switch pickedMode {
            case .off:
                break
            case .mirror, .exportOnly, .oneWay:
                try await SharedEventCalendarSync.shared.mirrorOnce(
                    event,
                    direction: .toApple,
                    calendarID: pickedCalendarID,
                    mirror: mirror,
                    context: modelContext,
                )
            case .importOnly:
                _ = await SharedEventCalendarSync.shared.importFromAppleCalendar(mirror: mirror)
            case .twoWay:
                try await SharedEventCalendarSync.shared.mirrorOnce(
                    event,
                    direction: .toApple,
                    calendarID: pickedCalendarID,
                    mirror: mirror,
                    context: modelContext,
                )
                await SharedEventCalendarSync.shared.syncTwoWay(
                    event,
                    mirror: mirror,
                    context: modelContext,
                )
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func stopMirror() async {
        guard let mirror else { return }
        isBusy = true
        defer { isBusy = false }
        await SharedEventCalendarSync.shared.stopMirroring(
            mirror: mirror,
            context: modelContext,
        )
        self.mirror = nil
        pickedMode = .off
        pickedCalendarID = ""
    }
}
