//
//  SharedEventsView.swift
//  Lurelia
//
//  List of shared events the current user hosts or is attending. Reads
//  the caller's identity (`remoteUserID` / `remoteDisplayName`) from
//  `UserSettings` — writing back through the same rows when the user
//  sets up their handle for the first time via the identity card.
//

import SwiftData
import SwiftUI

struct SharedEventsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @Query private var settings: [UserSettings]

    @AppStorage("sharedEvents.defaultColorHex")
    private var defaultSharedEventColorHex = "#03dbfc"

    @StateObject private var service = SharedEventsService.shared

    // Identity setup (empty until the user picks a handle).
    @State private var handleDraft: String = ""

    // Listing.
    @State private var buckets: SharedEventListBucketsDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Sheets.
    @State private var selection: SharedEventDTO?
    @State private var showingCreator: Bool = false
    @State private var eventPendingDeletion: SharedEventDTO?

    private var settingsObject: UserSettings {
        if let existing = settings.first { return existing }
        let created = UserSettings()
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    private var currentUserID: String { settingsObject.remoteUserID }
    private var currentDisplayName: String { settingsObject.remoteDisplayName }
    private var currentAvatarURL: String? {
        settingsObject.remoteAvatarURL
    }
    private var hasIdentity: Bool {
        !currentUserID.isEmpty && !currentDisplayName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header

                        if !hasIdentity {
                            identityCard
                        } else if isLoading, buckets == nil {
                            loadingCard
                        } else if let err = errorMessage {
                            errorCard(err)
                        } else if let buckets {
                            if buckets.asHost.isEmpty && buckets.asAttendee.isEmpty {
                                emptyCard
                            } else {
                                if !buckets.asHost.isEmpty {
                                    section(title: "Hosting", events: buckets.asHost)
                                }
                                if !buckets.asAttendee.isEmpty {
                                    section(title: "Attending", events: buckets.asAttendee)
                                }
                            }
                        }

                        Spacer().frame(height: 120)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationBackground(theme.palette.background)
        .sheet(item: $selection, onDismiss: {
            Task { await reload() }
        }) { event in
            SharedEventDetailView(
                eventID: event.id,
                initialEvent: event,
                currentUserID: currentUserID,
                currentDisplayName: currentDisplayName,
                currentAvatarURL: currentAvatarURL,
            )
        }
        .sheet(isPresented: $showingCreator) {
            SharedEventCreationFlow(
                currentUserID: currentUserID,
                currentDisplayName: currentDisplayName,
                currentAvatarURL: currentAvatarURL,
                initialColorHex: defaultSharedEventColorHex,
                onColorChanged: { defaultSharedEventColorHex = $0 },
                onCreated: { event in
                    Task { await reload() }
                    selection = event
                },
            )
        }
        .confirmationDialog(
            "Delete shared event?",
            isPresented: Binding(
                get: { eventPendingDeletion != nil },
                set: { if !$0 { eventPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let event = eventPendingDeletion else { return }
                eventPendingDeletion = nil
                Task { await deleteSharedEvent(event) }
            }
            Button("Cancel", role: .cancel) {
                eventPendingDeletion = nil
            }
        } message: {
            Text("This removes \(eventPendingDeletion?.title ?? "this event") from Shared Events.")
        }
        .task { await reload() }
    }

    // MARK: - Header (title + create button)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared events")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Hosting, attending, and invited")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                if hasIdentity {
                    Button {
                        showingCreator = true
                    } label: {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundStyle(theme.palette.indicators)
                            .bubblyIconMaterial(tint: theme.palette.indicators)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New shared event")
                }

                Button { dismiss() } label: {
                    Image("xmarkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .bubblyIconMaterial(tint: .white)
                        .frame(width: 28, height: 28)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close shared events")
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Identity setup

    private var identityCard: some View {
        stateSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set up your handle")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text("Pick a display name so friends can find you in shared events. This is stored on your device and sent with each request.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Display name", text: $handleDraft)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.words)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(12)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(defaultSharedColor, lineWidth: 1)
                    }

                Button {
                    saveIdentity()
                } label: {
                    Text("Continue")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            BubblyCardMaterial(tint: defaultSharedColor, cornerRadius: 18)
                        }
                        .opacity(handleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(handleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, LSpacing.pageHorizontal)
    }

    private func saveIdentity() {
        let trimmed = handleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settingsObject.remoteDisplayName = trimmed
        if settingsObject.remoteUserID.isEmpty {
            settingsObject.remoteUserID = "u-\(UUID().uuidString.lowercased())"
        }
        try? modelContext.save()
        Task { await reload() }
    }

    // MARK: - Sections

    private func section(title: String, events: [SharedEventDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
                .padding(.horizontal, LSpacing.pageHorizontal)

            VStack(spacing: 12) {
                ForEach(events) { event in
                    Button {
                        selection = event
                    } label: {
                        row(for: event)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            eventPendingDeletion = event
                        } label: {
                            Label {
                                Text("Delete")
                            } icon: {
                                Image("trash")
                                    .renderingMode(.template)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LSpacing.pageHorizontal)
        }
    }

    private func row(for event: SharedEventDTO) -> some View {
        let sharedColor = Color(lureliaHex: event.colorHex)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .frame(width: 7, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.42), radius: 1.5, x: 0, y: 1)
                    .lineLimit(1)
                Text(subtitle(for: event))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .shadow(color: .black.opacity(0.36), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
            }
            Spacer()

            if let counts = event.counts {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(counts.going ?? 0) going")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                    Text("\(counts.attendees ?? 0) in")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
        }
        .padding(16)
        .background {
            BubblyCardMaterial(tint: sharedColor, cornerRadius: 20)
        }
    }

    private var loadingCard: some View {
        stateSurface {
            HStack {
                Spacer()
                ProgressView().tint(defaultSharedColor)
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .padding(.horizontal, LSpacing.pageHorizontal)
    }

    private var emptyCard: some View {
        stateSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text("No shared events yet")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                Text("Tap the plus button above to create your first one, or accept an invitation from a friend.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showingCreator = true
                } label: {
                    Text("Create a shared event")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            BubblyCardMaterial(tint: defaultSharedColor, cornerRadius: 18)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LSpacing.pageHorizontal)
    }

    private func errorCard(_ err: String) -> some View {
        stateSurface {
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't load shared events")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, LSpacing.pageHorizontal)
    }

    private var defaultSharedColor: Color {
        Color(lureliaHex: defaultSharedEventColorHex)
    }

    private func stateSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .background(
                theme.palette.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(defaultSharedColor, lineWidth: 1)
            }
    }

    private func subtitle(for event: SharedEventDTO) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: event.startDate)
    }

    private func reload() async {
        guard hasIdentity else {
            buckets = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            buckets = try await service.listEvents(userID: currentUserID)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deleteSharedEvent(_ event: SharedEventDTO) async {
        do {
            if event.hostUserID == currentUserID {
                _ = try await service.cancelEvent(
                    event.id,
                    actorUserID: currentUserID,
                    reason: "Deleted by host"
                )
            } else {
                try await service.leaveEvent(event.id, userID: currentUserID)
            }

            if selection?.id == event.id {
                selection = nil
            }

            await reload()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
