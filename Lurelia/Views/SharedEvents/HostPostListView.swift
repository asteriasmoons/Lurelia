//
//  HostPostListView.swift
//  Lurelia
//
//  Full list of a shared event's host posts (and, optionally,
//  announcements). Pinned posts appear at the top in their own group, so
//  the timeline you scroll into always starts with what the host wants
//  you to see first. Tapping any preview opens the fully-rendered post.
//

import SwiftUI

enum HostPostFeedKind: Equatable {
    case posts
    case announcements
    case combined
}

struct HostPostListView: View {
    let eventID: String
    let eventTitle: String
    let kind: HostPostFeedKind
    let currentUserID: String
    let currentDisplayName: String
    let canModerate: Bool
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @StateObject private var service = SharedEventsService.shared

    @State private var posts: [EventPostDTO] = []
    @State private var announcements: [AnnouncementDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Which post/announcement is opened.
    @State private var openedPost: EventPostDTO?
    @State private var openedAnnouncement: AnnouncementDTO?
    @State private var editingPost: EventPostDTO?
    @State private var editingAnnouncement: AnnouncementDTO?

    // MARK: Body

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    if isLoading, posts.isEmpty, announcements.isEmpty {
                        loadingCard
                    } else if let err = errorMessage {
                        errorCard(err)
                    } else if allEmpty {
                        emptyCard
                    } else {
                        pinnedSection
                        timelineSection
                    }

                    Spacer().frame(height: 120)
                }
                .padding(.top, 12)
                .padding(.horizontal, LSpacing.pageHorizontal)
            }
        }
        .presentationBackground(theme.palette.background)
        .task { await reload() }
        .sheet(item: $openedPost) { post in
            HostPostRenderedView(
                title: previewText(for: post).text,
                author: post.authorDisplayName,
                createdAt: post.createdAt,
                isPinned: post.isPinned,
                isAnnouncement: false,
                bodyHTML: post.bodyHTML ?? "",
                bodyMarkdown: post.bodyMarkdown,
                onClose: { openedPost = nil },
                onEdit: canManage(post) ? {
                    openedPost = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        editingPost = post
                    }
                } : nil,
                onDelete: canManage(post) ? {
                    Task<Void, Never> { await deletePost(post) }
                } : nil,
            )
        }
        .sheet(item: $openedAnnouncement) { announcement in
            HostPostRenderedView(
                title: previewText(for: announcement).text,
                author: announcement.authorDisplayName,
                createdAt: announcement.createdAt,
                isPinned: announcement.isPinned,
                isAnnouncement: true,
                bodyHTML: announcement.bodyHTML ?? "",
                bodyMarkdown: announcement.bodyMarkdown,
                onClose: { openedAnnouncement = nil },
                onEdit: canManage(announcement) ? {
                    openedAnnouncement = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        editingAnnouncement = announcement
                    }
                } : nil,
                onDelete: canManage(announcement) ? {
                    Task<Void, Never> { await deleteAnnouncement(announcement) }
                } : nil,
            )
        }
        .sheet(item: $editingPost) { post in
            HostPostEditorView(
                kind: .post,
                sharedEventID: eventID,
                currentUserID: currentUserID,
                tint: tint,
                initialTitle: previewText(for: post).text,
                initialMarkdown: post.bodyMarkdown,
                initialIsPinned: post.isPinned,
                isEditing: true,
                mediaUploader: TiptapMediaUploader(baseURL: LureliaAPIConfig.baseURL),
                onSave: { draft in
                    Task<Void, Never> { await updatePost(post, draft: draft) }
                },
                onCancel: { editingPost = nil },
            )
        }
        .sheet(item: $editingAnnouncement) { announcement in
            HostPostEditorView(
                kind: .announcement,
                sharedEventID: eventID,
                currentUserID: currentUserID,
                tint: tint,
                initialTitle: previewText(for: announcement).text,
                initialMarkdown: announcement.bodyMarkdown,
                initialIsPinned: announcement.isPinned,
                isEditing: true,
                mediaUploader: TiptapMediaUploader(baseURL: LureliaAPIConfig.baseURL),
                onSave: { draft in
                    Task<Void, Never> { await updateAnnouncement(announcement, draft: draft) }
                },
                onCancel: { editingAnnouncement = nil },
            )
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pageTitle)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                Text(eventTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
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
            .accessibilityLabel("Close")
        }
    }

    private var pageTitle: String {
        switch kind {
        case .posts: return "Host posts"
        case .announcements: return "Announcements"
        case .combined: return "Posts & announcements"
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var pinnedSection: some View {
        let pinnedPosts = posts.filter { $0.isPinned && $0.deletedAt == nil }
        let pinnedAnn = announcements.filter { $0.isPinned && $0.deletedAt == nil }
        if !pinnedPosts.isEmpty || !pinnedAnn.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pinned")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)

                ForEach(pinnedAnn) { announcement in
                    Button {
                        openedAnnouncement = announcement
                    } label: {
                        previewCard(for: announcement)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(pinnedPosts) { post in
                    Button {
                        openedPost = post
                    } label: {
                        previewCard(for: post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        let unpinnedPosts = posts.filter { !$0.isPinned && $0.deletedAt == nil }
        let unpinnedAnn = announcements.filter { !$0.isPinned && $0.deletedAt == nil }
        let allItems: [FeedItem] = (
            unpinnedPosts.map { .post($0) } + unpinnedAnn.map { .announcement($0) }
        ).sorted { $0.createdAt > $1.createdAt }

        if !allItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Timeline")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)

                ForEach(allItems) { item in
                    switch item {
                    case .post(let post):
                        Button {
                            openedPost = post
                        } label: {
                            previewCard(for: post)
                        }
                        .buttonStyle(.plain)
                    case .announcement(let announcement):
                        Button {
                            openedAnnouncement = announcement
                        } label: {
                            previewCard(for: announcement)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Preview builders

    private func previewCard(for post: EventPostDTO) -> some View {
        let extracted = HostPostPreview.title(explicit: post.title, markdown: post.bodyMarkdown)
        return HostPostPreviewCard(
            title: extracted.text,
            author: post.authorDisplayName,
            previewText: extracted.text,
            previewIsHeading: extracted.isHeading,
            createdAt: post.createdAt,
            isPinned: post.isPinned,
            isAnnouncement: false,
            tint: tint
        )
    }

    private func previewCard(for announcement: AnnouncementDTO) -> some View {
        let extracted = HostPostPreview.title(
            explicit: announcement.title,
            markdown: announcement.bodyMarkdown,
        )
        return HostPostPreviewCard(
            title: extracted.text,
            author: announcement.authorDisplayName,
            previewText: extracted.text,
            previewIsHeading: extracted.isHeading,
            createdAt: announcement.createdAt,
            isPinned: announcement.isPinned,
            isAnnouncement: true,
            tint: tint
        )
    }

    private func previewText(for post: EventPostDTO) -> (text: String, isHeading: Bool) {
        HostPostPreview.title(explicit: post.title, markdown: post.bodyMarkdown)
    }

    private func previewText(for announcement: AnnouncementDTO) -> (text: String, isHeading: Bool) {
        HostPostPreview.title(explicit: announcement.title, markdown: announcement.bodyMarkdown)
    }

    // MARK: State cards

    private var loadingCard: some View {
        stateSurface {
            HStack {
                Spacer()
                ProgressView().tint(tint)
                Spacer()
            }
            .padding(.vertical, 24)
        }
    }

    private var emptyCard: some View {
        stateSurface {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing here yet")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                Text("Posts from the host will appear here as they publish.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
            }
        }
    }

    private func errorCard(_ err: String) -> some View {
        stateSurface {
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't load posts")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                Text(err)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LColors.textSecondary)
                    .lineLimit(3)
            }
        }
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
                    .strokeBorder(tint, lineWidth: 1)
            }
    }

    private var allEmpty: Bool {
        posts.filter { $0.deletedAt == nil }.isEmpty
            && announcements.filter { $0.deletedAt == nil }.isEmpty
    }

    // MARK: Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch kind {
            case .posts:
                posts = try await service.listPosts(eventID)
                announcements = []
            case .announcements:
                posts = []
                announcements = try await service.listAnnouncements(eventID)
            case .combined:
                async let p = service.listPosts(eventID)
                async let a = service.listAnnouncements(eventID)
                posts = try await p
                announcements = try await a
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func updatePost(_ post: EventPostDTO, draft: HostPostDraft) async {
        do {
            let updated = try await service.updatePost(
                postID: post.id,
                actorUserID: currentUserID,
                title: draft.title,
                bodyMarkdown: draft.bodyMarkdown,
                bodyHTML: draft.bodyHTML,
                isPinned: draft.isPinned,
            )
            editingPost = nil
            replacePost(updated)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deletePost(_ post: EventPostDTO) async {
        do {
            try await service.deletePost(postID: post.id, actorUserID: currentUserID)
            openedPost = nil
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func updateAnnouncement(_ announcement: AnnouncementDTO, draft: HostPostDraft) async {
        do {
            let updated = try await service.updateAnnouncement(
                announcementID: announcement.id,
                actorUserID: currentUserID,
                title: draft.title,
                bodyMarkdown: draft.bodyMarkdown,
                bodyHTML: draft.bodyHTML,
            )
            editingAnnouncement = nil
            replaceAnnouncement(updated)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deleteAnnouncement(_ announcement: AnnouncementDTO) async {
        do {
            try await service.deleteAnnouncement(
                announcementID: announcement.id,
                actorUserID: currentUserID,
            )
            openedAnnouncement = nil
            announcements.removeAll { $0.id == announcement.id }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func canManage(_ post: EventPostDTO) -> Bool {
        canModerate || post.authorUserID == currentUserID
    }

    private func canManage(_ announcement: AnnouncementDTO) -> Bool {
        canModerate || announcement.authorUserID == currentUserID
    }

    private func replacePost(_ updated: EventPostDTO) {
        if let index = posts.firstIndex(where: { $0.id == updated.id }) {
            posts[index] = updated
        } else {
            posts.insert(updated, at: 0)
        }
    }

    private func replaceAnnouncement(_ updated: AnnouncementDTO) {
        if let index = announcements.firstIndex(where: { $0.id == updated.id }) {
            announcements[index] = updated
        } else {
            announcements.insert(updated, at: 0)
        }
    }
}

// MARK: - Feed union type

private enum FeedItem: Identifiable {
    case post(EventPostDTO)
    case announcement(AnnouncementDTO)

    var id: String {
        switch self {
        case .post(let p): return "post-\(p.id)"
        case .announcement(let a): return "ann-\(a.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .post(let p): return p.createdAt
        case .announcement(let a): return a.createdAt
        }
    }
}
