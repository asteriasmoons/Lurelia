//
//  LureliaReportRouter.swift
//  Lurelia
//
//  Lightweight router that lets a tapped report notification (or a
//  lurelia://report-conversation deep link) open the matching conversation
//  in the Report Center. Injected as an environment object at the app root.
//

import Foundation
import Combine

@MainActor
final class LureliaReportRouter: ObservableObject {
    @Published var pendingReportConversationID: String?

    func handleReportConversationURL(_ url: URL) {
        guard url.scheme?.lowercased() == "lurelia" else { return }
        let host = url.host?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard host == "report-conversation" || path == "report-conversation" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let reportID = components?.queryItems?.first(where: { $0.name == "reportID" || $0.name == "reportId" })?.value
        if let reportID, !reportID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handleReportConversationID(reportID)
        }
    }

    func handleReportConversationID(_ reportID: String) {
        let trimmed = reportID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingReportConversationID = trimmed
    }

    func consumePendingReportConversationID() -> String? {
        let value = pendingReportConversationID
        pendingReportConversationID = nil
        return value
    }
}
