//
//  SharedEventsService.swift
//  Lurelia
//
//  HTTP client for vox-api's /api/lurelia/events surface. Kept small on
//  purpose — this is the read/write layer used by SharedEventsView and
//  SharedEventDetailView. Phase 1A.5 adds the socket subscriber and the
//  full offline mutation queue that mirrors these calls into SyncState.
//

import Foundation
import Combine

@MainActor
final class SharedEventsService: ObservableObject {
    static let shared = SharedEventsService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init(session: URLSession = .shared) {
        self.session = session
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case http(Int, String)
        case decoding(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(_, let msg): return msg
            case .decoding(let msg): return "Decoding failed: \(msg)"
            case .badResponse: return "Bad response from server."
            }
        }
    }

    // MARK: - Events

    func listEvents(userID: String) async throws -> SharedEventListBucketsDTO {
        var comps = URLComponents(url: LureliaAPIConfig.route("/events"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "userID", value: userID)]
        let payload: SharedEventListPayload = try await get(url: comps.url!)
        return SharedEventListBucketsDTO(
            asHost: payload.events.asHost.filter { $0.cancelledAt == nil },
            asAttendee: payload.events.asAttendee.filter { $0.cancelledAt == nil }
        )
    }

    func getEvent(_ id: String) async throws -> SharedEventDTO {
        let payload: SharedEventSinglePayload = try await get(
            url: LureliaAPIConfig.route("/events/\(id)"),
        )
        return payload.event
    }

    struct CreateEventPayload: Encodable {
        let localID: String
        let title: String
        let description: String?
        let iconName: String?
        let colorHex: String?
        let timezoneIdentifier: String?
        let startDate: Date
        let endDate: Date?
        let isAllDay: Bool?
        let locationName: String?
        let address: String?
        let visibility: String?
        let hostUserID: String
        let hostDisplayName: String
        let hostAvatarURL: String?
    }

    func createEvent(_ payload: CreateEventPayload) async throws -> SharedEventDTO {
        let response: SharedEventSinglePayload = try await post(
            url: LureliaAPIConfig.route("/events"),
            body: payload,
        )
        return response.event
    }

    func cancelEvent(_ id: String, actorUserID: String, reason: String) async throws -> SharedEventDTO {
        struct Body: Encodable {
            let actorUserID: String
            let reason: String
        }
        let response: SharedEventSinglePayload = try await post(
            url: LureliaAPIConfig.route("/events/\(id)/cancel"),
            body: Body(actorUserID: actorUserID, reason: reason),
        )
        return response.event
    }

    // MARK: - RSVP

    func setRSVP(
        eventID: String,
        userID: String,
        displayName: String,
        status: String,
        note: String? = nil,
    ) async throws {
        struct Body: Encodable {
            let userID: String
            let displayName: String
            let status: String
            let note: String?
        }
        struct Wrap: Decodable { let rsvp: RSVPDTO }
        let _: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/rsvp"),
            body: Body(userID: userID, displayName: displayName, status: status, note: note),
        )
    }

    func listRSVPs(_ eventID: String) async throws -> [RSVPDTO] {
        let payload: RSVPListPayload = try await get(
            url: LureliaAPIConfig.route("/events/\(eventID)/rsvps"),
        )
        return payload.rsvps
    }

    // MARK: - Attendees

    func listAttendees(_ eventID: String) async throws -> [AttendeeDTO] {
        let payload: AttendeeListPayload = try await get(
            url: LureliaAPIConfig.route("/events/\(eventID)/attendees"),
        )
        return payload.attendees
    }

    func leaveEvent(_ eventID: String, userID: String) async throws {
        struct Body: Encodable {
            let userID: String
        }
        struct Wrap: Decodable {
            let attendee: AttendeeDTO
        }

        let _: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/leave"),
            body: Body(userID: userID),
        )
    }

    // MARK: - Discussion

    func listComments(
        _ eventID: String,
        postID: String? = nil,
        viewerUserID: String? = nil,
    ) async throws -> [CommentDTO] {
        var comps = URLComponents(
            url: LureliaAPIConfig.route("/events/\(eventID)/comments"),
            resolvingAgainstBaseURL: false,
        )!
        var queryItems: [URLQueryItem] = []
        if let postID {
            queryItems.append(URLQueryItem(name: "eventPostID", value: postID))
        }
        if let viewerUserID {
            queryItems.append(URLQueryItem(name: "viewerUserID", value: viewerUserID))
        }
        comps.queryItems = queryItems.isEmpty ? nil : queryItems
        let payload: CommentListPayload = try await get(url: comps.url!)
        return payload.comments
    }

    func createComment(
        eventID: String,
        authorUserID: String,
        authorDisplayName: String,
        authorAvatarURL: String? = nil,
        body: String,
        attachmentIDs: [String]? = nil,
    ) async throws -> CommentDTO {
        struct Body: Encodable {
            let authorUserID: String
            let authorDisplayName: String
            let authorAvatarURL: String?
            let body: String
            let attachmentIDs: [String]?
        }
        struct Wrap: Decodable { let comment: CommentDTO }
        let wrap: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/comments"),
            body: Body(
                authorUserID: authorUserID,
                authorDisplayName: authorDisplayName,
                authorAvatarURL: authorAvatarURL,
                body: body,
                attachmentIDs: attachmentIDs,
            ),
        )
        return wrap.comment
    }

    func createReply(
        commentID: String,
        parentReplyID: String?,
        authorUserID: String,
        authorDisplayName: String,
        authorAvatarURL: String? = nil,
        body: String,
    ) async throws -> CommentReplyDTO {
        struct Body: Encodable {
            let parentReplyID: String?
            let authorUserID: String
            let authorDisplayName: String
            let authorAvatarURL: String?
            let body: String
        }
        struct Wrap: Decodable { let reply: CommentReplyDTO }
        let wrap: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/comments/\(commentID)/replies"),
            body: Body(
                parentReplyID: parentReplyID,
                authorUserID: authorUserID,
                authorDisplayName: authorDisplayName,
                authorAvatarURL: authorAvatarURL,
                body: body,
            ),
        )
        return wrap.reply
    }

    func toggleCommentLike(
        commentID: String,
        userID: String,
        userDisplayName: String,
    ) async throws -> CommentReactionPayload {
        struct Body: Encodable {
            let commentID: String
            let userID: String
            let userDisplayName: String
            let kind: String
        }
        return try await post(
            url: LureliaAPIConfig.route("/events/reactions"),
            body: Body(
                commentID: commentID,
                userID: userID,
                userDisplayName: userDisplayName,
                kind: "like",
            ),
        )
    }

    func toggleReplyLike(
        replyID: String,
        userID: String,
        userDisplayName: String,
    ) async throws -> CommentReactionPayload {
        struct Body: Encodable {
            let replyID: String
            let userID: String
            let userDisplayName: String
            let kind: String
        }
        return try await post(
            url: LureliaAPIConfig.route("/events/reactions"),
            body: Body(
                replyID: replyID,
                userID: userID,
                userDisplayName: userDisplayName,
                kind: "like",
            ),
        )
    }

    func deleteComment(commentID: String, actorUserID: String) async throws {
        var comps = URLComponents(
            url: LureliaAPIConfig.route("/events/comments/\(commentID)"),
            resolvingAgainstBaseURL: false,
        )!
        comps.queryItems = [URLQueryItem(name: "actorUserID", value: actorUserID)]
        try await delete(url: comps.url!)
    }

    func deleteReply(replyID: String, actorUserID: String) async throws {
        var comps = URLComponents(
            url: LureliaAPIConfig.route("/events/replies/\(replyID)"),
            resolvingAgainstBaseURL: false,
        )!
        comps.queryItems = [URLQueryItem(name: "actorUserID", value: actorUserID)]
        try await delete(url: comps.url!)
    }

    // MARK: - Posts

    func listPosts(_ eventID: String) async throws -> [EventPostDTO] {
        let payload: EventPostListPayload = try await get(
            url: LureliaAPIConfig.route("/events/\(eventID)/posts"),
        )
        return payload.posts
    }

    func createPost(
        eventID: String,
        authorUserID: String,
        authorDisplayName: String,
        title: String,
        bodyMarkdown: String,
        bodyHTML: String,
        isPinned: Bool,
    ) async throws -> EventPostDTO {
        struct Body: Encodable {
            let authorUserID: String
            let authorDisplayName: String
            let title: String
            let bodyMarkdown: String
            let bodyHTML: String
            let isPinned: Bool
        }
        struct Wrap: Decodable { let post: EventPostDTO }
        let wrap: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/posts"),
            body: Body(
                authorUserID: authorUserID,
                authorDisplayName: authorDisplayName,
                title: title,
                bodyMarkdown: bodyMarkdown,
                bodyHTML: bodyHTML,
                isPinned: isPinned,
            ),
        )
        return wrap.post
    }

    func updatePost(
        postID: String,
        actorUserID: String,
        title: String,
        bodyMarkdown: String,
        bodyHTML: String,
        isPinned: Bool,
    ) async throws -> EventPostDTO {
        struct Body: Encodable {
            let actorUserID: String
            let title: String
            let bodyMarkdown: String
            let bodyHTML: String
            let isPinned: Bool
        }
        struct Wrap: Decodable { let post: EventPostDTO }
        let wrap: Wrap = try await patch(
            url: LureliaAPIConfig.route("/events/posts/\(postID)"),
            body: Body(
                actorUserID: actorUserID,
                title: title,
                bodyMarkdown: bodyMarkdown,
                bodyHTML: bodyHTML,
                isPinned: isPinned,
            ),
        )
        return wrap.post
    }

    func deletePost(postID: String, actorUserID: String) async throws {
        var comps = URLComponents(
            url: LureliaAPIConfig.route("/events/posts/\(postID)"),
            resolvingAgainstBaseURL: false,
        )!
        comps.queryItems = [URLQueryItem(name: "actorUserID", value: actorUserID)]
        try await delete(url: comps.url!)
    }

    // MARK: - Announcements

    func listAnnouncements(_ eventID: String) async throws -> [AnnouncementDTO] {
        let payload: AnnouncementListPayload = try await get(
            url: LureliaAPIConfig.route("/events/\(eventID)/announcements"),
        )
        return payload.announcements
    }

    func createAnnouncement(
        eventID: String,
        authorUserID: String,
        authorDisplayName: String,
        title: String,
        bodyMarkdown: String,
        bodyHTML: String,
    ) async throws -> AnnouncementDTO {
        struct Body: Encodable {
            let authorUserID: String
            let authorDisplayName: String
            let title: String
            let bodyMarkdown: String
            let bodyHTML: String
        }
        struct Wrap: Decodable { let announcement: AnnouncementDTO }
        let wrap: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/announcements"),
            body: Body(
                authorUserID: authorUserID,
                authorDisplayName: authorDisplayName,
                title: title,
                bodyMarkdown: bodyMarkdown,
                bodyHTML: bodyHTML,
            ),
        )
        return wrap.announcement
    }

    func updateAnnouncement(
        announcementID: String,
        actorUserID: String,
        title: String,
        bodyMarkdown: String,
        bodyHTML: String,
    ) async throws -> AnnouncementDTO {
        struct Body: Encodable {
            let actorUserID: String
            let title: String
            let bodyMarkdown: String
            let bodyHTML: String
        }
        struct Wrap: Decodable { let announcement: AnnouncementDTO }
        let wrap: Wrap = try await patch(
            url: LureliaAPIConfig.route("/events/announcements/\(announcementID)"),
            body: Body(
                actorUserID: actorUserID,
                title: title,
                bodyMarkdown: bodyMarkdown,
                bodyHTML: bodyHTML,
            ),
        )
        return wrap.announcement
    }

    func deleteAnnouncement(announcementID: String, actorUserID: String) async throws {
        var comps = URLComponents(
            url: LureliaAPIConfig.route("/events/announcements/\(announcementID)"),
            resolvingAgainstBaseURL: false,
        )!
        comps.queryItems = [URLQueryItem(name: "actorUserID", value: actorUserID)]
        try await delete(url: comps.url!)
    }

    // MARK: - Debug (compile-in DEBUG only)

    #if DEBUG
    /// Ask the server to simulate activity from another participant.
    /// Backend endpoint 404s unless `LURELIA_DEBUG_ENABLED=true` is set
    /// on vox-api, so this is safe to leave compiled in dev builds.
    ///
    /// `kind` ∈ { "join", "rsvp", "comment", "hostPost", "announcement" }.
    /// For hostPost / announcement, pass the current user's remoteUserID
    /// + displayName so the simulated action is attributed to the host
    /// and dispatches notifications to attendees (including this device).
    func simulateActivity(
        eventID: String,
        kind: String,
        status: String? = nil,
        body: String? = nil,
        hostUserID: String? = nil,
        hostDisplayName: String? = nil,
    ) async throws {
        struct Body: Encodable {
            let kind: String
            let status: String?
            let body: String?
            let hostUserID: String?
            let hostDisplayName: String?
        }
        struct Wrap: Decodable { let success: Bool }
        let _: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/debug/simulate"),
            body: Body(
                kind: kind,
                status: status,
                body: body,
                hostUserID: hostUserID,
                hostDisplayName: hostDisplayName,
            ),
        )
    }
    #endif

    // MARK: - Notifications

    func subscribeNotifications(
        eventID: String,
        userID: String,
        deviceToken: String,
        enabledKinds: [String]? = nil,
        platform: String = "ios",
    ) async throws {
        struct Body: Encodable {
            let sharedEventID: String
            let userID: String
            let deviceToken: String
            let platform: String
            let enabledKinds: [String]?
        }
        // Server returns { success, subscription: { …, enabledKinds: [...] } }.
        // We don't consume the body, so decode into an empty shell to sidestep
        // schema drift on the returned document.
        struct Wrap: Decodable {}
        let _: Wrap = try await post(
            url: LureliaAPIConfig.route("/notifications/subscribe"),
            body: Body(
                sharedEventID: eventID,
                userID: userID,
                deviceToken: deviceToken,
                platform: platform,
                enabledKinds: enabledKinds,
            ),
        )
    }

    func unsubscribeNotifications(
        eventID: String,
        userID: String,
        deviceToken: String,
    ) async throws {
        struct Body: Encodable {
            let sharedEventID: String
            let userID: String
            let deviceToken: String
        }
        struct Wrap: Decodable {}
        let _: Wrap = try await post(
            url: LureliaAPIConfig.route("/notifications/unsubscribe"),
            body: Body(
                sharedEventID: eventID,
                userID: userID,
                deviceToken: deviceToken,
            ),
        )
    }

    // MARK: - Invitations

    struct InvitationCreatePayload: Encodable {
        let senderUserID: String
        let senderDisplayName: String
        let recipientUserID: String?
        let recipientDisplayName: String?
        let recipientEmail: String?
        let message: String?
        let channel: String
    }

    func createInvitation(
        eventID: String,
        _ payload: InvitationCreatePayload,
    ) async throws {
        struct Wrap: Decodable { let invitation: [String: String]? }
        let _: Wrap = try await post(
            url: LureliaAPIConfig.route("/events/\(eventID)/invitations"),
            body: payload,
        )
    }

    // MARK: - HTTP core

    private func get<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post<Body: Encodable, T: Decodable>(url: URL, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func patch<Body: Encodable, T: Decodable>(url: URL, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func delete(url: URL) async throws {
        struct EmptyResponse: Decodable {}
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let _: EmptyResponse = try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try? JSONSerialization.jsonObject(with: data)
            let msg = ((errBody as? [String: Any])?["error"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw ServiceError.http(http.statusCode, msg)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ServiceError.decoding(String(describing: error))
        }
    }
}
