import CloudKit
import Foundation

struct VoxiverseBugReportPayload {
    let title: String
    let description: String
    let expectedBehavior: String
    let steps: [String]
    let areaGroup: String
    let category: String
    let severity: String
    let frequency: String
    let additionalNotes: String
    let attachmentData: [Data]
    let reporterName: String
}

struct VoxiverseBetaFeedbackPayload {
    let title: String
    let areaGroup: String
    let area: String
    let overallExperience: String
    let testedWhat: String
    let workedWell: String
    let couldBeBetter: String
    let unexpected: String
    let additionalThoughts: String
    let attachmentData: [Data]
    let reporterName: String
}

struct VoxiverseFeatureRequestPayload {
    let featureTitle: String
    let areaGroup: String
    let area: String
    let featureType: String
    let importance: String
    let intendedAudience: String
    let featureDescription: String
    let imaginedWorkflow: String
    let desiredLocation: String
    let relatedExistingFeature: String
    let problemAddressed: String
    let desiredResult: String
    let requiresSavedData: String
    let needsNotifications: String
    let needsSharing: String
    let needsAI: String
    let additionalDetails: String
    let attachmentData: [Data]
    let reporterName: String
}

enum VoxiverseReportSubmissionError: LocalizedError {
    case missingRequiredFields

    var errorDescription: String? {
        switch self {
        case .missingRequiredFields:
            return "Please complete the required fields before submitting."
        }
    }
}

final class VoxiverseReportSubmissionService {
    static let shared = VoxiverseReportSubmissionService()

    static let containerIdentifier = "iCloud.im.lystaria.Voxiverse"
    static let sourceAppName = "Lurelia"

    private let database: CKDatabase

    private init() {
        database = CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase
    }

    @MainActor
    func submitBugReport(_ payload: VoxiverseBugReportPayload) async throws -> (reportID: String, diagnostics: LureliaReportDiagnostics) {
        let trimmedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = payload.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSteps = payload.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTitle.isEmpty, !trimmedDescription.isEmpty, !cleanedSteps.isEmpty else {
            throw VoxiverseReportSubmissionError.missingRequiredFields
        }

        let diagnostics = LureliaReportDiagnostics.current(screenName: "Settings > Bug Report")
        let reportID = makeReportID()
        let record = CKRecord(recordType: "Report", recordID: CKRecord.ID(recordName: reportID))
        record["reportID"] = reportID as CKRecordValue
        record["appID"] = appID(from: diagnostics) as CKRecordValue
        record["appName"] = Self.sourceAppName as CKRecordValue
        record["reporterName"] = reporterName(from: payload.reporterName) as CKRecordValue
        record["reportType"] = "Bug Report" as CKRecordValue
        record["title"] = trimmedTitle as CKRecordValue
        record["descriptionText"] = trimmedDescription as CKRecordValue
        record["expectedBehavior"] = payload.expectedBehavior.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["stepsToReproduce"] = cleanedSteps.joined(separator: "\n") as CKRecordValue
        record["areaGroup"] = payload.areaGroup as CKRecordValue
        record["category"] = payload.category as CKRecordValue
        record["priority"] = payload.severity as CKRecordValue
        record["frequency"] = payload.frequency as CKRecordValue
        record["status"] = "New" as CKRecordValue
        record["internalNotes"] = payload.additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        applyDiagnostics(diagnostics, to: record)

        try await save(record, attachments: payload.attachmentData, folderName: "VoxiverseLureliaBugReports")
        return (reportID, diagnostics)
    }

    @MainActor
    func submitBetaFeedback(_ payload: VoxiverseBetaFeedbackPayload) async throws -> (reportID: String, diagnostics: LureliaReportDiagnostics) {
        let trimmedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArea = payload.area.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOverallExperience = payload.overallExperience.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTestedWhat = payload.testedWhat.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty,
              !trimmedArea.isEmpty,
              !trimmedOverallExperience.isEmpty,
              !trimmedTestedWhat.isEmpty else {
            throw VoxiverseReportSubmissionError.missingRequiredFields
        }

        let diagnostics = LureliaReportDiagnostics.current(screenName: "Settings > Beta Feedback")
        let reportID = makeReportID()
        let record = CKRecord(recordType: "Report", recordID: CKRecord.ID(recordName: reportID))
        record["reportID"] = reportID as CKRecordValue
        record["appID"] = appID(from: diagnostics) as CKRecordValue
        record["appName"] = Self.sourceAppName as CKRecordValue
        record["reporterName"] = reporterName(from: payload.reporterName) as CKRecordValue
        record["reportType"] = "Beta Feedback" as CKRecordValue
        record["title"] = trimmedTitle as CKRecordValue
        record["descriptionText"] = trimmedTestedWhat as CKRecordValue
        record["areaGroup"] = payload.areaGroup as CKRecordValue
        record["category"] = trimmedArea as CKRecordValue
        record["overallExperience"] = trimmedOverallExperience as CKRecordValue
        record["testedWhat"] = trimmedTestedWhat as CKRecordValue
        record["workedWell"] = payload.workedWell.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["couldBeBetter"] = payload.couldBeBetter.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["anythingUnexpected"] = payload.unexpected.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["internalNotes"] = payload.additionalThoughts.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["status"] = "New" as CKRecordValue
        applyDiagnostics(diagnostics, to: record)

        try await save(record, attachments: payload.attachmentData, folderName: "VoxiverseLureliaBetaFeedback")
        return (reportID, diagnostics)
    }

    @MainActor
    func submitFeatureRequest(_ payload: VoxiverseFeatureRequestPayload) async throws -> (reportID: String, diagnostics: LureliaReportDiagnostics) {
        let trimmedTitle = payload.featureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArea = payload.area.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFeatureType = payload.featureType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImportance = payload.importance.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAudience = payload.intendedAudience.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = payload.featureDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkflow = payload.imaginedWorkflow.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = payload.desiredLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProblem = payload.problemAddressed.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResult = payload.desiredResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSavedData = payload.requiresSavedData.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotifications = payload.needsNotifications.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSharing = payload.needsSharing.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAI = payload.needsAI.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty,
              !trimmedArea.isEmpty,
              !trimmedFeatureType.isEmpty,
              !trimmedImportance.isEmpty,
              !trimmedAudience.isEmpty,
              !trimmedDescription.isEmpty,
              !trimmedWorkflow.isEmpty,
              !trimmedLocation.isEmpty,
              !trimmedProblem.isEmpty,
              !trimmedResult.isEmpty,
              !trimmedSavedData.isEmpty,
              !trimmedNotifications.isEmpty,
              !trimmedSharing.isEmpty,
              !trimmedAI.isEmpty else {
            throw VoxiverseReportSubmissionError.missingRequiredFields
        }

        let diagnostics = LureliaReportDiagnostics.current(screenName: "Settings > Feature Request")
        let reportID = makeReportID()
        let record = CKRecord(recordType: "Report", recordID: CKRecord.ID(recordName: reportID))
        record["reportID"] = reportID as CKRecordValue
        record["requestID"] = reportID as CKRecordValue
        record["appID"] = appID(from: diagnostics) as CKRecordValue
        record["appName"] = Self.sourceAppName as CKRecordValue
        record["reporterName"] = reporterName(from: payload.reporterName) as CKRecordValue
        record["reportType"] = "Feature Request" as CKRecordValue
        record["title"] = trimmedTitle as CKRecordValue
        record["areaGroup"] = payload.areaGroup as CKRecordValue
        record["category"] = trimmedArea as CKRecordValue
        record["status"] = "New" as CKRecordValue
        record["submittedAt"] = diagnostics.submittedAt as CKRecordValue
        record["createdAt"] = diagnostics.submittedAt as CKRecordValue
        record["updatedAt"] = diagnostics.submittedAt as CKRecordValue
        record["requestCount"] = 1 as CKRecordValue
        record["descriptionText"] = trimmedDescription as CKRecordValue
        record["featureType"] = trimmedFeatureType as CKRecordValue
        record["importance"] = trimmedImportance as CKRecordValue
        record["intendedAudience"] = trimmedAudience as CKRecordValue
        record["featureDescription"] = trimmedDescription as CKRecordValue
        record["imaginedWorkflow"] = trimmedWorkflow as CKRecordValue
        record["desiredLocation"] = trimmedLocation as CKRecordValue
        record["relatedExistingFeature"] = payload.relatedExistingFeature.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["problemAddressed"] = trimmedProblem as CKRecordValue
        record["desiredResult"] = trimmedResult as CKRecordValue
        record["requiresSavedData"] = trimmedSavedData as CKRecordValue
        record["needsNotifications"] = trimmedNotifications as CKRecordValue
        record["needsSharing"] = trimmedSharing as CKRecordValue
        record["needsAI"] = trimmedAI as CKRecordValue
        record["additionalDetails"] = payload.additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["internalNotes"] = payload.additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        applyDiagnostics(diagnostics, to: record)

        try await save(record, attachments: payload.attachmentData, folderName: "VoxiverseLureliaFeatureRequests")
        return (reportID, diagnostics)
    }

    private func makeReportID() -> String {
        "LUR-\(UUID().uuidString.prefix(8).uppercased())"
    }

    private func appID(from _: LureliaReportDiagnostics) -> String {
        "lurelia"
    }

    private func reporterName(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lurelia" : trimmed
    }

    private func applyDiagnostics(_ diagnostics: LureliaReportDiagnostics, to record: CKRecord) {
        record["submittedAt"] = diagnostics.submittedAt as CKRecordValue
        record["deviceModel"] = diagnostics.deviceModel as CKRecordValue
        record["iOSVersion"] = diagnostics.iOSVersion as CKRecordValue
        record["appVersion"] = diagnostics.appVersion as CKRecordValue
        record["buildNumber"] = diagnostics.buildNumber as CKRecordValue
        record["bundleIdentifier"] = diagnostics.bundleIdentifier as CKRecordValue
        record["screenName"] = diagnostics.screenName as CKRecordValue
        record["locale"] = diagnostics.locale as CKRecordValue
        record["timeZone"] = diagnostics.timeZone as CKRecordValue
    }

    private func save(_ record: CKRecord, attachments: [Data], folderName: String) async throws {
        let tempURLs = try makeAttachmentFiles(from: attachments, reportID: record.recordID.recordName, folderName: folderName)
        defer { tempURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        for (index, url) in tempURLs.enumerated() {
            record["attachment\(index + 1)"] = CKAsset(fileURL: url)
        }

        _ = try await database.save(record)
        try await addToInbox(recordName: record.recordID.recordName)
    }

    private func addToInbox(recordName: String) async throws {
        let inboxID = CKRecord.ID(recordName: "VoxiverseReportInbox")
        let inbox: CKRecord

        do {
            inbox = try await database.record(for: inboxID)
        } catch let error as CKError where error.code == .unknownItem {
            inbox = CKRecord(recordType: "ReportInbox", recordID: inboxID)
        }

        var names = inbox["reportRecordNames"] as? [String] ?? []
        if !names.contains(recordName) {
            names.append(recordName)
            inbox["reportRecordNames"] = names as CKRecordValue
            _ = try await database.save(inbox)
        }
    }

    private func makeAttachmentFiles(from dataItems: [Data], reportID: String, folderName: String) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try dataItems.prefix(3).enumerated().map { index, data in
            let url = directory.appendingPathComponent("\(reportID)-\(index + 1).jpg")
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
