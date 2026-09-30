//
//  HostManagementView.swift
//  Lurelia
//
//  Consolidated host / co-host control surface for a shared event.
//  Presented from the Host Tools card in SharedEventDetailView. Split
//  into three sections: Attendees (moderation), Event settings
//  (permissions + registration + visibility), Danger zone (transfer /
//  cancel).
//
//  All server calls route through the existing `SharedEventsService` +
//  `SharedEventsService+Host` extension — no parallel networking layer.
//

import SwiftUI

struct HostManagementView: View {
    let event: SharedEventDTO
    let currentUserID: String
    let currentDisplayName: String
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @StateObject private var service = SharedEventsService.shared

    @State private var attendees: [AttendeeDTO] = []
    @State private var banned: [AttendeeDTO] = []
    @State private var permissions: PermissionsDTO?
    @State private var eventLocal: SharedEventDTO
    @State private var isBusy: Bool = false
    @State private var errorMessage: String?

    // Confirmation dialogs.
    @State private var attendeeForRemoval: AttendeeDTO?
    @State private var attendeeForBan: AttendeeDTO?
    @State private var showingTransferConfirm: AttendeeDTO?
    @State private var showingCancelConfirm = false

    private var sharedColor: Color {
        Color(lureliaHex: eventLocal.colorHex)
    }

    init(
        event: SharedEventDTO,
        currentUserID: String,
        currentDisplayName: String,
        onChanged: @escaping () -> Void,
    ) {
        self.event = event
        self.currentUserID = currentUserID
        self.currentDisplayName = currentDisplayName
        self.onChanged = onChanged
        self._eventLocal = State(initialValue: event)
    }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    attendeesCard
                    bannedCard
                    settingsCard
                    dangerCard

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                theme.palette.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(sharedColor, lineWidth: 1)
                            }
                    }

                    Spacer().frame(height: 60)
                }
                .padding(.top, 12)
                .padding(.horizontal, LSpacing.pageHorizontal)
            }
        }
        .presentationBackground(theme.palette.background)
        .task { await loadAll() }
        .confirmationDialog(
            "Remove attendee?",
            isPresented: Binding(
                get: { attendeeForRemoval != nil },
                set: { if !$0 { attendeeForRemoval = nil } },
            ),
            presenting: attendeeForRemoval,
        ) { attendee in
            Button("Remove \(attendee.displayName)", role: .destructive) {
                Task { await removeAttendee(attendee) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Ban attendee?",
            isPresented: Binding(
                get: { attendeeForBan != nil },
                set: { if !$0 { attendeeForBan = nil } },
            ),
            presenting: attendeeForBan,
        ) { attendee in
            Button("Ban \(attendee.displayName)", role: .destructive) {
                Task { await banAttendee(attendee) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They won't be able to rejoin this event.")
        }
        .confirmationDialog(
            "Transfer ownership?",
            isPresented: Binding(
                get: { showingTransferConfirm != nil },
                set: { if !$0 { showingTransferConfirm = nil } },
            ),
            presenting: showingTransferConfirm,
        ) { attendee in
            Button("Make \(attendee.displayName) host", role: .destructive) {
                Task { await transferOwnership(to: attendee) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You'll become a co-host. This can't be undone from your side.")
        }
        .confirmationDialog(
            "Cancel this event?",
            isPresented: $showingCancelConfirm,
        ) {
            Button("Cancel event", role: .destructive) {
                Task { await cancelEvent() }
            }
            Button("Keep event", role: .cancel) {}
        } message: {
            Text("Attendees will be notified.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manage event")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                Text(eventLocal.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                BubblyIconMaterial(tint: .white)
                    .mask {
                        Image("xmarkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    }
                    .frame(width: 20, height: 20)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Attendees

    private var attendeesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attendees")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)

            if attendees.isEmpty {
                Text("No attendees yet.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                ForEach(attendees) { attendee in
                    attendeeTile(attendee)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func attendeeTile(_ attendee: AttendeeDTO) -> some View {
        let isHost = attendee.role == "host"
        HStack(alignment: .center, spacing: 10) {
            attendeeAvatar(attendee, isHost: isHost)

            VStack(alignment: .leading, spacing: 6) {
                Text(attendee.displayName)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)

                rolePill(roleTitle(for: attendee))
            }

            Spacer(minLength: 8)

            if isHost {
                sharedMaterialPill(
                    "Host",
                    horizontalPadding: 10,
                    verticalPadding: 6
                )
            } else {
                Menu {
                    if attendee.role == "coHost" {
                        Button("Demote to member") {
                            Task { await demote(attendee) }
                        }
                    } else if attendee.role == "member" {
                        Button("Promote to co-host") {
                            Task { await promote(attendee) }
                        }
                    }
                    if attendee.role == "member" || attendee.role == "coHost" {
                        Button("Transfer ownership to them") {
                            showingTransferConfirm = attendee
                        }
                    }
                    Button("Remove", role: .destructive) {
                        attendeeForRemoval = attendee
                    }
                    Button("Ban", role: .destructive) {
                        attendeeForBan = attendee
                    }
                } label: {
                    managePill
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(sharedTileBorder(cornerRadius: 16))
    }

    // MARK: - Banned

    private var bannedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Banned")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)

            if banned.isEmpty {
                Text("No one is banned.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                ForEach(banned) { attendee in
                    bannedAttendeeTile(attendee)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event settings")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)

            permissionGrid

            Divider().overlay(sharedColor.opacity(0.5))

            Text("Visibility")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            HStack(spacing: 8) {
                visibilityButton("Private", value: "private")
                visibilityButton("Link only", value: "link")
                visibilityButton("Public", value: "public")
            }
        }
    }

    private var permissionGrid: some View {
        let registrationOpen = !(eventLocal.registrationClosed ?? false)
        let discussionOpen = permissions?.allowComments ?? true
        let guestsCanPost = permissions?.allowGuestPosts ?? false
        let guestsCanInvite = permissions?.allowGuestInvites ?? false
        let attendeeListVisible = permissions?.showAttendeeList ?? true
        let approvalRequired = permissions?.requireApprovalToJoin ?? false
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            permissionTile(
                title: "Registrations",
                state: registrationOpen ? "OPEN" : "CLOSED",
                isActive: registrationOpen,
            ) {
                Task { await setRegistrationClosed(registrationOpen) }
            }

            permissionTile(
                title: "Discussion",
                state: discussionOpen ? "OPEN" : "LOCKED",
                isActive: discussionOpen,
            ) {
                Task { await setDiscussionLocked(discussionOpen) }
            }

            permissionTile(
                title: "Guest Posting",
                state: guestsCanPost ? "ON" : "OFF",
                isActive: guestsCanPost,
            ) {
                Task { await patchPermissions(.guestPosts(!guestsCanPost)) }
            }

            permissionTile(
                title: "Guest Invites",
                state: guestsCanInvite ? "ON" : "OFF",
                isActive: guestsCanInvite,
            ) {
                Task { await patchPermissions(.guestInvites(!guestsCanInvite)) }
            }

            permissionTile(
                title: "Attendee List",
                state: attendeeListVisible ? "VISIBLE" : "HIDDEN",
                isActive: attendeeListVisible,
            ) {
                Task { await patchPermissions(.showAttendees(!attendeeListVisible)) }
            }

            permissionTile(
                title: "Join Approval",
                state: approvalRequired ? "REQUIRED" : "NOT REQUIRED",
                isActive: approvalRequired,
            ) {
                Task { await patchPermissions(.requireApproval(!approvalRequired)) }
            }
        }
    }

    private func bannedAttendeeTile(_ attendee: AttendeeDTO) -> some View {
        HStack(alignment: .center, spacing: 10) {
            attendeeAvatar(attendee, isHost: false)

            VStack(alignment: .leading, spacing: 6) {
                Text(attendee.displayName)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(1)

                sharedMaterialPill("BANNED")
            }

            Spacer(minLength: 8)

            Button {
                Task { await unban(attendee) }
            } label: {
                sharedMaterialPill(
                    "Unban",
                    fontSize: 11,
                    horizontalPadding: 12,
                    verticalPadding: 8
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(sharedTileBorder(cornerRadius: 16))
    }

    private func permissionTile(
        title: String,
        state: String,
        isActive: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button {
            guard !isBusy else { return }
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                sharedMaterialPill(state, verticalPadding: 5)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(sharedTileBorder(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(state)
    }

    private func attendeeAvatar(_ attendee: AttendeeDTO, isHost: Bool) -> some View {
        Text(initials(for: attendee.displayName))
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background {
                Circle()
                    .fill(theme.palette.surface)
            }
            .overlay(Circle().strokeBorder(sharedColor, lineWidth: 1))
    }

    private func rolePill(_ title: String) -> some View {
        sharedMaterialPill(title)
    }

    private var managePill: some View {
        sharedMaterialPill(
            "Manage",
            fontSize: 11,
            horizontalPadding: 12,
            verticalPadding: 8
        )
    }

    private func roleTitle(for attendee: AttendeeDTO) -> String {
        switch attendee.role {
        case "host":
            return "Host"
        case "coHost":
            return "Co-host"
        default:
            return "Member"
        }
    }

    private func initials(for name: String) -> String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(parts).uppercased()
        return value.isEmpty ? "?" : value
    }

    private func sharedTileBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(sharedColor, lineWidth: 1)
    }

    private func sharedMaterialPill(
        _ title: String,
        fontSize: CGFloat = 10,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4
    ) -> some View {
        Text(title)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                BubblyIconMaterial(tint: sharedColor)
                    .clipShape(Capsule())
            }
    }

    private func visibilityButton(_ label: String, value: String) -> some View {
        let isActive = eventLocal.visibility == value
        return Button {
            Task { await changeVisibility(to: value) }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isActive ? .black : theme.palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        BubblyIconMaterial(tint: sharedColor)
                            .clipShape(
                                RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                            .fill(theme.palette.surface)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LSpacing.buttonRadius, style: .continuous)
                        .strokeBorder(sharedColor, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: - Danger zone

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger zone")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .bubblyIconMaterial(tint: sharedColor)

            Button {
                Task { await duplicateEvent() }
            } label: {
                Text("Duplicate event")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(theme.palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(sharedColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)

            Button {
                showingCancelConfirm = true
            } label: {
                Text("Cancel event")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        BubblyIconMaterial(tint: sharedColor)
                            .clipShape(Capsule())
                    }
            }
            .buttonStyle(.plain)
            .disabled(isBusy || eventLocal.cancelledAt != nil)
        }
    }

    // MARK: - Actions

    private enum PermissionsField {
        case guestPosts(Bool)
        case guestInvites(Bool)
        case showAttendees(Bool)
        case requireApproval(Bool)
    }

    private func loadAll() async {
        isBusy = true
        defer { isBusy = false }
        do {
            async let evt = service.getEvent(eventLocal.id)
            async let atts = service.listAttendees(eventLocal.id)
            async let bans = service.listBannedAttendees(eventID: eventLocal.id)
            async let perms = service.getPermissions(eventID: eventLocal.id)
            eventLocal = try await evt
            attendees = try await atts
            banned = try await bans
            permissions = try await perms
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func removeAttendee(_ a: AttendeeDTO) async {
        do {
            try await service.removeAttendee(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                targetUserID: a.userID,
            )
            attendees.removeAll { $0.id == a.id }
            onChanged()
        } catch { errorMessage = String(describing: error) }
    }

    private func banAttendee(_ a: AttendeeDTO) async {
        do {
            _ = try await service.banAttendee(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                targetUserID: a.userID,
            )
            await loadAll()
            onChanged()
        } catch { errorMessage = String(describing: error) }
    }

    private func unban(_ a: AttendeeDTO) async {
        do {
            _ = try await service.unbanAttendee(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                targetUserID: a.userID,
            )
            await loadAll()
        } catch { errorMessage = String(describing: error) }
    }

    private func promote(_ a: AttendeeDTO) async {
        do {
            _ = try await service.promoteToCoHost(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                targetUserID: a.userID,
            )
            await loadAll()
        } catch { errorMessage = String(describing: error) }
    }

    private func demote(_ a: AttendeeDTO) async {
        do {
            _ = try await service.demoteCoHost(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                targetUserID: a.userID,
            )
            await loadAll()
        } catch { errorMessage = String(describing: error) }
    }

    private func transferOwnership(to a: AttendeeDTO) async {
        do {
            _ = try await service.transferOwnership(
                eventID: eventLocal.id,
                currentHostUserID: currentUserID,
                newHostUserID: a.userID,
            )
            onChanged()
            dismiss()
        } catch { errorMessage = String(describing: error) }
    }

    private func setRegistrationClosed(_ closed: Bool) async {
        do {
            let updated = try await service.setRegistrationClosed(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                closed: closed,
            )
            eventLocal = updated
            onChanged()
        } catch { errorMessage = String(describing: error) }
    }

    private func setDiscussionLocked(_ locked: Bool) async {
        do {
            let perms = try await service.setDiscussionLocked(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                locked: locked,
            )
            permissions = perms
            onChanged()
        } catch { errorMessage = String(describing: error) }
    }

    private func patchPermissions(_ field: PermissionsField) async {
        do {
            let perms: PermissionsDTO
            switch field {
            case .guestPosts(let v):
                perms = try await service.updatePermissions(
                    eventID: eventLocal.id,
                    actorUserID: currentUserID,
                    allowGuestPosts: v,
                )
            case .guestInvites(let v):
                perms = try await service.updatePermissions(
                    eventID: eventLocal.id,
                    actorUserID: currentUserID,
                    allowGuestInvites: v,
                )
            case .showAttendees(let v):
                perms = try await service.updatePermissions(
                    eventID: eventLocal.id,
                    actorUserID: currentUserID,
                    showAttendeeList: v,
                )
            case .requireApproval(let v):
                perms = try await service.updatePermissions(
                    eventID: eventLocal.id,
                    actorUserID: currentUserID,
                    requireApprovalToJoin: v,
                )
            }
            permissions = perms
            onChanged()
        } catch { errorMessage = String(describing: error) }
    }

    private func changeVisibility(to visibility: String) async {
        do {
            let updated = try await service.updateEvent(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
                title: nil,
                description: nil,
                startDate: nil,
                endDate: nil,
                isAllDay: nil,
                locationName: nil,
                visibility: visibility,
            )
            eventLocal = updated
            onChanged()
        } catch { errorMessage = String(describing: error) }
    }

    private func duplicateEvent() async {
        do {
            _ = try await service.duplicateEvent(
                eventID: eventLocal.id,
                actorUserID: currentUserID,
            )
            onChanged()
            dismiss()
        } catch { errorMessage = String(describing: error) }
    }

    private func cancelEvent() async {
        do {
            let updated = try await service.cancelEvent(
                eventLocal.id,
                actorUserID: currentUserID,
                reason: "",
            )
            eventLocal = updated
            onChanged()
            dismiss()
        } catch { errorMessage = String(describing: error) }
    }
}
