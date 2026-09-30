//
//  SharedEventsService+Host.swift
//  Lurelia
//
//  Host / moderation endpoints added in Prompt 1B. All server-side
//  authorization is done by vox-api's `assertActorCanModerate`, so
//  callers just pass the current user's ID as `actorUserID` and let the
//  server reject non-hosts with `FORBIDDEN`.
//
//  Intentionally an extension on the existing service — no new networking
//  layer. Reuses the private `post`, `get`, `delete` helpers via new
//  wrapper methods.
//

import Foundation

extension SharedEventsService {

    // MARK: - Ban / unban

    @discardableResult
    func banAttendee(
        eventID: String,
        actorUserID: String,
        targetUserID: String,
        reason: String = "",
    ) async throws -> AttendeeDTO {
        struct Body: Encodable { let actorUserID: String; let reason: String }
        struct Wrap: Decodable { let attendee: AttendeeDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/attendees/\(targetUserID)/ban",
            body: Body(actorUserID: actorUserID, reason: reason),
        )
        return wrap.attendee
    }

    @discardableResult
    func unbanAttendee(
        eventID: String,
        actorUserID: String,
        targetUserID: String,
    ) async throws -> AttendeeDTO {
        struct Body: Encodable { let actorUserID: String }
        struct Wrap: Decodable { let attendee: AttendeeDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/attendees/\(targetUserID)/unban",
            body: Body(actorUserID: actorUserID),
        )
        return wrap.attendee
    }

    func listBannedAttendees(eventID: String) async throws -> [AttendeeDTO] {
        struct Wrap: Decodable { let attendees: [AttendeeDTO] }
        let wrap: Wrap = try await hostGet(
            path: "/events/\(eventID)/attendees/banned",
        )
        return wrap.attendees
    }

    // MARK: - Promote / demote

    @discardableResult
    func promoteToCoHost(
        eventID: String,
        actorUserID: String,
        targetUserID: String,
    ) async throws -> AttendeeDTO {
        struct Body: Encodable { let actorUserID: String }
        struct Wrap: Decodable { let attendee: AttendeeDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/attendees/\(targetUserID)/promote",
            body: Body(actorUserID: actorUserID),
        )
        return wrap.attendee
    }

    @discardableResult
    func demoteCoHost(
        eventID: String,
        actorUserID: String,
        targetUserID: String,
    ) async throws -> AttendeeDTO {
        struct Body: Encodable { let actorUserID: String }
        struct Wrap: Decodable { let attendee: AttendeeDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/attendees/\(targetUserID)/demote",
            body: Body(actorUserID: actorUserID),
        )
        return wrap.attendee
    }

    // MARK: - Registration open / close

    @discardableResult
    func setRegistrationClosed(
        eventID: String,
        actorUserID: String,
        closed: Bool,
    ) async throws -> SharedEventDTO {
        struct Body: Encodable { let actorUserID: String; let closed: Bool }
        struct Wrap: Decodable { let event: SharedEventDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/registration",
            body: Body(actorUserID: actorUserID, closed: closed),
        )
        return wrap.event
    }

    // MARK: - Duplicate

    @discardableResult
    func duplicateEvent(
        eventID: String,
        actorUserID: String,
    ) async throws -> SharedEventDTO {
        struct Body: Encodable { let actorUserID: String }
        struct Wrap: Decodable { let event: SharedEventDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/duplicate",
            body: Body(actorUserID: actorUserID),
        )
        return wrap.event
    }

    // MARK: - Permissions

    func getPermissions(eventID: String) async throws -> PermissionsDTO {
        struct Wrap: Decodable { let permissions: PermissionsDTO }
        let wrap: Wrap = try await hostGet(
            path: "/events/\(eventID)/permissions",
        )
        return wrap.permissions
    }

    @discardableResult
    func updatePermissions(
        eventID: String,
        actorUserID: String,
        allowGuestPosts: Bool? = nil,
        allowGuestInvites: Bool? = nil,
        allowComments: Bool? = nil,
        allowRSVPChanges: Bool? = nil,
        requireApprovalToJoin: Bool? = nil,
        showAttendeeList: Bool? = nil,
        allowDeclinedComments: Bool? = nil,
    ) async throws -> PermissionsDTO {
        struct Body: Encodable {
            let actorUserID: String
            let allowGuestPosts: Bool?
            let allowGuestInvites: Bool?
            let allowComments: Bool?
            let allowRSVPChanges: Bool?
            let requireApprovalToJoin: Bool?
            let showAttendeeList: Bool?
            let allowDeclinedComments: Bool?
        }
        struct Wrap: Decodable { let permissions: PermissionsDTO }
        let wrap: Wrap = try await hostPatch(
            path: "/events/\(eventID)/permissions",
            body: Body(
                actorUserID: actorUserID,
                allowGuestPosts: allowGuestPosts,
                allowGuestInvites: allowGuestInvites,
                allowComments: allowComments,
                allowRSVPChanges: allowRSVPChanges,
                requireApprovalToJoin: requireApprovalToJoin,
                showAttendeeList: showAttendeeList,
                allowDeclinedComments: allowDeclinedComments,
            ),
        )
        return wrap.permissions
    }

    @discardableResult
    func setDiscussionLocked(
        eventID: String,
        actorUserID: String,
        locked: Bool,
    ) async throws -> PermissionsDTO {
        struct Body: Encodable { let actorUserID: String; let locked: Bool }
        struct Wrap: Decodable { let permissions: PermissionsDTO }
        let wrap: Wrap = try await hostPost(
            path: "/events/\(eventID)/discussion",
            body: Body(actorUserID: actorUserID, locked: locked),
        )
        return wrap.permissions
    }

    // MARK: - Update event

    @discardableResult
    func updateEvent(
        eventID: String,
        actorUserID: String,
        title: String? = nil,
        description: String? = nil,
        colorHex: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool? = nil,
        locationName: String? = nil,
        visibility: String? = nil,
    ) async throws -> SharedEventDTO {
        struct Body: Encodable {
            let actorUserID: String
            let title: String?
            let description: String?
            let colorHex: String?
            let startDate: Date?
            let endDate: Date?
            let isAllDay: Bool?
            let locationName: String?
            let visibility: String?
        }
        struct Wrap: Decodable { let event: SharedEventDTO }
        let wrap: Wrap = try await hostPatch(
            path: "/events/\(eventID)",
            body: Body(
                actorUserID: actorUserID,
                title: title,
                description: description,
                colorHex: colorHex,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                locationName: locationName,
                visibility: visibility,
            ),
        )
        return wrap.event
    }

    // MARK: - Transfer ownership

    @discardableResult
    func transferOwnership(
        eventID: String,
        currentHostUserID: String,
        newHostUserID: String,
    ) async throws -> SharedEventDTO {
        struct Body: Encodable {
            let currentHostUserID: String
            let newHostUserID: String
        }
        struct Wrap: Decodable {
            let sharedEventID: String
        }
        let _: Wrap = try await hostPost(
            path: "/events/\(eventID)/transfer",
            body: Body(
                currentHostUserID: currentHostUserID,
                newHostUserID: newHostUserID,
            ),
        )
        return try await getEvent(eventID)
    }

    // MARK: - Remove attendee (existing endpoint, just a client wrapper)

    func removeAttendee(
        eventID: String,
        actorUserID: String,
        targetUserID: String,
    ) async throws {
        struct EmptyIn: Encodable {}
        struct Wrap: Decodable { let success: Bool }
        var comps = URLComponents(
            url: LureliaAPIConfig.route("/events/\(eventID)/attendees/\(targetUserID)"),
            resolvingAgainstBaseURL: false,
        )!
        comps.queryItems = [URLQueryItem(name: "actorUserID", value: actorUserID)]
        let _: Wrap = try await performRequest(
            url: comps.url!,
            method: "DELETE",
            body: EmptyIn(),
        )
    }

    // MARK: - Small typed wrappers around the private core

    private func hostPost<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
    ) async throws -> T {
        try await performRequest(
            url: LureliaAPIConfig.route(path),
            method: "POST",
            body: body,
        )
    }

    private func hostPatch<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
    ) async throws -> T {
        try await performRequest(
            url: LureliaAPIConfig.route(path),
            method: "PATCH",
            body: body,
        )
    }

    private func hostGet<T: Decodable>(path: String) async throws -> T {
        try await performRequest(
            url: LureliaAPIConfig.route(path),
            method: "GET",
            body: EmptyBody(),
        )
    }
}

private struct EmptyBody: Encodable {}

// MARK: - Shared request core

fileprivate extension SharedEventsService {
    /// Thin request runner that mirrors the private helpers in the base
    /// class so this extension doesn't reach into private members. Uses
    /// `URLSession.shared` and the same date-strategy JSON coders.
    func performRequest<Body: Encodable, T: Decodable>(
        url: URL,
        method: String,
        body: Body,
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            request.httpBody = try enc.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = try? JSONSerialization.jsonObject(with: data)
            let msg = ((errBody as? [String: Any])?["error"] as? String)
                ?? "HTTP \(http.statusCode)"
            throw ServiceError.http(http.statusCode, msg)
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        do {
            return try dec.decode(T.self, from: data)
        } catch {
            throw ServiceError.decoding(String(describing: error))
        }
    }
}
