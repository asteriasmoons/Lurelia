//
//  ProfileView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var reportRouter: LureliaReportRouter
    
    @Query private var settings: [UserSettings]
    @Query(sort: \KanbanBoard.sortOrder) private var boards: [KanbanBoard]
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoSourceDialog = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showOnboardingResetConfirmation = false
    @State private var showTimelineBoardDropdown = false
    @State private var showingReleaseNotes = false
    @State private var showingReportCenter = false
    @State private var isUploadingProfileImage = false
    @State private var profileImageUploadError: String?
    @State private var hasAttemptedProfileImageUpload = false
    
    private var userSettings: UserSettings? {
        settings.first
    }
    
    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    
                    // MARK: - Header
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // MARK: - Profile Card
                    
                    profileCard
                        .padding(.horizontal, 24)

                    releaseNotesCard
                        .padding(.horizontal, 24)

                    reportCenterCard
                        .padding(.horizontal, 24)

                    timelineSettingsCard
                        .padding(.horizontal, 24)

                    devControlsCard
                        .padding(.horizontal, 24)
                    
                    Spacer()
                        .frame(height: 110)
                }
            }
            
            if showPhotoSourceDialog {
                photoSourcePopup
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(10)
            }

            if showOnboardingResetConfirmation {
                onboardingResetPopup
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .zIndex(11)
            }
        }
        .sheet(isPresented: $showCamera) {
            LureliaImagePicker(sourceType: .camera) { image in
                saveProfileImage(image)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) {
            Task {
                guard let item = selectedPhotoItem else { return }
                
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    saveProfileImage(image)
                }
            }
        }
        .task {
            await uploadExistingProfileAvatarIfNeeded()
        }
        .adaptivePresentation(isPresented: $showingReleaseNotes, useFullScreenCover: horizontalSizeClass == .regular) {
            ReleaseNotesPage()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .adaptivePresentation(isPresented: $showingReportCenter, useFullScreenCover: horizontalSizeClass == .regular) {
            LureliaReportCenterView()
                .environmentObject(reportRouter)
                .modelContainer(for: [SubmittedReport.self, SubmittedReportAttachment.self])
        }
    }

    private var photoSourcePopup: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(duration: 0.22)) {
                        showPhotoSourceDialog = false
                    }
                }
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LColors.glassSurface2)
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "camera.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(LGradients.header)
                }
                
                VStack(spacing: 5) {
                    Text("Profile Photo")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Choose a source for your profile picture.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            showPhotoSourceDialog = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            showPhotoPicker = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 14, weight: .bold))
                            
                            Text("Choose From Gallery")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.white.adaptivePrimaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(LGradients.header)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            showPhotoSourceDialog = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            showCamera = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14, weight: .bold))
                            
                            Text("Use Camera")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(LColors.glassSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .strokeBorder(LColors.glassBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            showPhotoSourceDialog = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(lureliaHex: "#10101A").opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85).opacity(0.42),
                                Color.white.opacity(0.85).opacity(0.42)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var onboardingResetPopup: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(duration: 0.22)) {
                        showOnboardingResetConfirmation = false
                    }
                }

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 52, height: 52)

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.red.opacity(0.92))
                }

                VStack(spacing: 5) {
                    Text("Replay Onboarding?")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("This will simply replay the onboarding experience so you can preview it again. None of your reminders, habits, settings, profile information, or other data will be changed.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button {
                        userSettings?.shouldReplayOnboarding = true

                        try? modelContext.save()

                        withAnimation(.spring(duration: 0.22)) {
                            showOnboardingResetConfirmation = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .bold))

                            Text("Replay Onboarding")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(Color.red.opacity(0.32))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.48), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            showOnboardingResetConfirmation = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(lureliaHex: "#10101A").opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.42),
                                Color.white.opacity(0.85).opacity(0.32)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .padding(.horizontal, 24)
        }
    }
    
    private func saveProfileImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            return
        }
        
        let userSettings: UserSettings
        
        if let existing = settings.first {
            userSettings = existing
        } else {
            userSettings = UserSettings()
            modelContext.insert(userSettings)
        }
        
        userSettings.profileImageData = data
        if userSettings.remoteUserID.isEmpty {
            userSettings.remoteUserID = "u-\(UUID().uuidString.lowercased())"
        }
        
        try? modelContext.save()

        Task {
            await uploadProfileAvatar(data, for: userSettings)
        }
    }

    private func uploadProfileAvatar(_ data: Data, for userSettings: UserSettings) async {
        guard !userSettings.remoteUserID.isEmpty else { return }
        isUploadingProfileImage = true
        defer { isUploadingProfileImage = false }

        do {
            let avatarURL = try await uploadProfileAvatarData(
                data,
                userID: userSettings.remoteUserID,
            )
            userSettings.remoteAvatarURL = avatarURL
            userSettings.updatedAt = Date()
            try? modelContext.save()
            profileImageUploadError = nil
        } catch {
            profileImageUploadError = String(describing: error)
        }
    }

    private func uploadExistingProfileAvatarIfNeeded() async {
        guard !hasAttemptedProfileImageUpload else { return }
        hasAttemptedProfileImageUpload = true

        guard let userSettings,
              userSettings.remoteAvatarURL?.isEmpty != false,
              let data = userSettings.profileImageData else {
            return
        }

        if userSettings.remoteUserID.isEmpty {
            userSettings.remoteUserID = "u-\(UUID().uuidString.lowercased())"
            try? modelContext.save()
        }

        await uploadProfileAvatar(data, for: userSettings)
    }

    private func uploadProfileAvatarData(_ data: Data, userID: String) async throws -> String {
        var request = URLRequest(url: LureliaAPIConfig.route("/media/profile-avatar"))
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type",
        )

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
                    .data(using: .utf8)!,
            )
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"avatar\"; filename=\"profile.jpg\"\r\n"
                .data(using: .utf8)!,
        )
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        appendField(name: "uploaderUserID", value: userID)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProfileAvatarUploadError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: responseData))
                .flatMap { ($0 as? [String: Any])?["error"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw ProfileAvatarUploadError.serverError(message)
        }

        let decoded = try JSONDecoder().decode(ProfileAvatarUploadResponse.self, from: responseData)
        return decoded.avatarURL
    }

    private var profileCard: some View {
        themedProfileCard(accentIndex: 0) {
            VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LColors.glassSurface)
                    .frame(width: 92, height: 92)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85).opacity(0.18),
                                Color.white.opacity(0.85).opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)
                
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85).opacity(0.65),
                                Color.white.opacity(0.85).opacity(0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 92, height: 92)
                
                Group {
                    if let data = userSettings?.profileImageData,
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image("profilewavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 38, height: 38)
                            .bubblyIconMaterial(tint: profileAccent(at: 0))
                            .padding(18)
                            .background(
                                Circle()
                                    .fill(theme.palette.raisedSurface)
                            )
                    }
                }
                .frame(width: 82, height: 82)
                .clipShape(Circle())
                
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Button {
                            showPhotoSourceDialog = true
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .bold))
                                .bubblyIconMaterial(tint: profileAccent(at: 0))
                                .frame(width: 28, height: 28)
                                .background(theme.palette.raisedSurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 92, height: 92)
               }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var timelineSettingsCard: some View {
        profileSectionCard(
            title: "Timeline Settings",
            icon: "calendar",
            accentIndex: 3
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Default timeline boards")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .textCase(.uppercase)
                    .tracking(0.7)

                Button {
                    guard !boards.isEmpty else { return }

                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        showTimelineBoardDropdown.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(theme.palette.raisedSurface)
                                .frame(width: 38, height: 38)

                            iconView("starcal", size: 18)
                                .bubblyIconMaterial(tint: profileAccent(at: 3))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(boards.isEmpty ? "No boards yet" : "\(defaultTimelineBoardIDs.count) Default Boards Selected")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("Used when Kanban Timeline opens")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.48))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(showTimelineBoardDropdown ? "chevdown" : "chevright")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .bubblyIconMaterial(tint: profileAccent(at: 3))
                            .rotationEffect(.degrees(showTimelineBoardDropdown ? 180 : 0))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 62)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LColors.glassSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(LColors.glassBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(boards.isEmpty)
                .opacity(boards.isEmpty ? 0.58 : 1)

                if showTimelineBoardDropdown {
                    VStack(spacing: 6) {
                        ForEach(boards) { board in
                            timelineBoardOption(board)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var releaseNotesCard: some View {
        Button {
            showingReleaseNotes = true
        } label: {
            themedProfileCard(accentIndex: 1) {
                HStack(alignment: .center, spacing: 14) {
                    Image("timebook")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .bubblyIconMaterial(tint: profileAccent(at: 1))
                        .frame(width: 42, height: 42)
                        .background(theme.palette.raisedSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Release Notes")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(LColors.textPrimary)

                        Text("See what changed across the latest Lurelia updates.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image("chevright")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .bubblyIconMaterial(tint: profileAccent(at: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var reportCenterCard: some View {
        Button {
            showingReportCenter = true
        } label: {
            themedProfileCard(accentIndex: 2) {
                HStack(alignment: .center, spacing: 14) {
                    Image("megaphone")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .bubblyIconMaterial(tint: profileAccent(at: 2))
                        .frame(width: 42, height: 42)
                        .background(theme.palette.raisedSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Report a Problem")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(LColors.textPrimary)

                        Text("Send a bug report, feature request, or beta feedback to Voxiverse.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image("chevright")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .bubblyIconMaterial(tint: profileAccent(at: 2))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var defaultTimelineBoardIDs: Set<UUID> {
        let availableIDs = Set(boards.map(\.id))
        return Set(userSettings?.defaultTimelineBoardIDs ?? []).intersection(availableIDs)
    }

    private func timelineBoardOption(_ board: KanbanBoard) -> some View {
        Button {
            toggleDefaultTimelineBoard(board)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            Color(lureliaHex: board.colorHex).opacity(0.48),
                            lineWidth: 1
                        )
                        .frame(width: 32, height: 32)

                    iconView(board.icon, size: 15)
                        .foregroundStyle(Color(lureliaHex: board.colorHex))
                        .bubblyIconMaterial(tint: Color(lureliaHex: board.colorHex))
                }

                Text(board.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()

                if isDefaultTimelineBoard(board) {
                    Image("checkwavy")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Color.white)
                        .bubblyIconMaterial(tint: Color.white)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isDefaultTimelineBoard(board) ? Color.white.opacity(0.09) : Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        isDefaultTimelineBoard(board)
                        ? Color(lureliaHex: board.colorHex).opacity(0.45)
                        : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func isDefaultTimelineBoard(_ board: KanbanBoard) -> Bool {
        defaultTimelineBoardIDs.contains(board.id)
    }

    private func toggleDefaultTimelineBoard(_ board: KanbanBoard) {
        let settings = resolvedUserSettings()
        var selectedIDs = Set(settings.defaultTimelineBoardIDs)

        if selectedIDs.contains(board.id) {
            selectedIDs.remove(board.id)
        } else {
            selectedIDs.insert(board.id)
        }

        settings.defaultTimelineBoardIDs = boards
            .map(\.id)
            .filter { selectedIDs.contains($0) }

        try? modelContext.save()
    }

    private func resolvedUserSettings() -> UserSettings {
        if let existing = settings.first {
            return existing
        }

        let created = UserSettings()
        modelContext.insert(created)
        return created
    }

    private var devControlsCard: some View {
        profileSectionCard(
            title: "Dev Controls",
            icon: "wrench.and.screwdriver.fill",
            accentIndex: 4
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Temporary testing controls for pre-release setup.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.spring(duration: 0.22)) {
                        showOnboardingResetConfirmation = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))

                        Text("Reset Onboarding State")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        BubblyTileSurface(
                            tint: theme.palette.secondaryAccent,
                            cornerRadius: 16
                        )
                    }
                    .bubblyTileLift()
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func profileSectionCard<Content: View>(
        title: String,
        icon: String,
        accentIndex: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let accent = profileAccent(at: accentIndex)

        return themedProfileCard(accentIndex: accentIndex) {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                iconView(icon, size: 18)
                    .bubblyIconMaterial(tint: accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.palette.raisedSurface)
                    )
                
                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
            }
            
            content()
            }
        }
    }

    private func themedProfileCard<Content: View>(
        accentIndex: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return content()
            .padding(LSpacing.cardPadding)
            .background(
                shape
                    .fill(theme.palette.surface)
                    .overlay {
                        shape.strokeBorder(profileAccent(at: accentIndex), lineWidth: 1)
                    }
            )
    }

    private func profileAccent(at index: Int) -> Color {
        let rotation = theme.palette.rotation
        guard !rotation.isEmpty else { return theme.palette.primaryAction }
        let normalizedIndex = ((index % rotation.count) + rotation.count) % rotation.count
        return rotation[normalizedIndex]
    }
    
    private func iconView(_ icon: String, size: CGFloat) -> some View {
        Group {
            if UIImage(named: icon) != nil {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
    }
}

private extension View {
    @ViewBuilder
    func adaptivePresentation<Content: View>(
        isPresented: Binding<Bool>,
        useFullScreenCover: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if useFullScreenCover {
            self.fullScreenCover(isPresented: isPresented, content: content)
        } else {
            self.sheet(isPresented: isPresented, content: content)
        }
    }
}

private struct ProfileAvatarUploadResponse: Decodable {
    let success: Bool
    let avatarURL: String
}

private enum ProfileAvatarUploadError: Error {
    case badResponse
    case serverError(String)
}


// MARK: - Image Picker

struct LureliaImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: LureliaImagePicker
        
        init(_ parent: LureliaImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
