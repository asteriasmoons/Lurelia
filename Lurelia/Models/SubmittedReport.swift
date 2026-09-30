import Foundation
import SwiftData

@Model
final class SubmittedReport {
    var id: UUID = UUID()
    var reportID: String = ""
    var reportType: String = "Bug Report"
    var title: String = ""
    var descriptionText: String = ""
    var expectedBehavior: String = ""
    var steps: [String] = []
    var areaGroup: String = ""
    var category: String = ""
    var severity: String = ""
    var frequency: String = ""
    var overallExperience: String = ""
    var testedWhat: String = ""
    var workedWell: String = ""
    var couldBeBetter: String = ""
    var unexpected: String = ""
    var featureType: String = ""
    var featureImportance: String = ""
    var intendedAudience: String = ""
    var featureDescription: String = ""
    var imaginedWorkflow: String = ""
    var desiredLocation: String = ""
    var relatedExistingFeature: String = ""
    var problemAddressed: String = ""
    var desiredResult: String = ""
    var requiresSavedData: String = ""
    var needsNotifications: String = ""
    var needsSharing: String = ""
    var needsAI: String = ""
    var additionalDetails: String = ""
    var appName: String = ""
    var appVersion: String = ""
    var buildNumber: String = ""
    var bundleIdentifier: String = ""
    var deviceModel: String = ""
    var iOSVersion: String = ""
    var locale: String = ""
    var timeZone: String = ""
    var screenName: String = ""
    var additionalNotes: String = ""
    var status: String = "Submitted"
    var submittedAt: Date = Date()
    var conversationRecordName: String = ""
    var conversationZoneName: String = ""
    var conversationZoneOwnerName: String = ""
    var conversationShareURL: String = ""
    var conversationStateRawValue: String = "notStarted"
    var conversationUpdatedAt: Date?
    var conversationLastMessageAt: Date?
    var conversationUnreadCount: Int = 0
    var conversationLastReadAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SubmittedReportAttachment.report)
    private var storedAttachments: [SubmittedReportAttachment]?

    var attachments: [SubmittedReportAttachment] {
        get { storedAttachments ?? [] }
        set {
            storedAttachments = newValue
            for attachment in newValue where attachment.report !== self {
                attachment.report = self
            }
        }
    }

    init(
        id: UUID = UUID(),
        reportID: String,
        reportType: String = "Bug Report",
        title: String,
        descriptionText: String,
        expectedBehavior: String,
        steps: [String],
        areaGroup: String = "",
        category: String,
        severity: String,
        frequency: String,
        overallExperience: String = "",
        testedWhat: String = "",
        workedWell: String = "",
        couldBeBetter: String = "",
        unexpected: String = "",
        featureType: String = "",
        featureImportance: String = "",
        intendedAudience: String = "",
        featureDescription: String = "",
        imaginedWorkflow: String = "",
        desiredLocation: String = "",
        relatedExistingFeature: String = "",
        problemAddressed: String = "",
        desiredResult: String = "",
        requiresSavedData: String = "",
        needsNotifications: String = "",
        needsSharing: String = "",
        needsAI: String = "",
        additionalDetails: String = "",
        appName: String = "",
        appVersion: String = "",
        buildNumber: String = "",
        bundleIdentifier: String = "",
        deviceModel: String = "",
        iOSVersion: String = "",
        locale: String = "",
        timeZone: String = "",
        screenName: String = "",
        additionalNotes: String,
        status: String = "Submitted",
        submittedAt: Date = Date.now,
        conversationRecordName: String = "",
        conversationZoneName: String = "",
        conversationZoneOwnerName: String = "",
        conversationShareURL: String = "",
        conversationState: LureliaReportConversationState = .notStarted,
        conversationUpdatedAt: Date? = nil,
        conversationLastMessageAt: Date? = nil,
        conversationUnreadCount: Int = 0,
        conversationLastReadAt: Date? = nil,
        attachments: [SubmittedReportAttachment] = []
    ) {
        self.id = id
        self.reportID = reportID
        self.reportType = reportType
        self.title = title
        self.descriptionText = descriptionText
        self.expectedBehavior = expectedBehavior
        self.steps = steps
        self.areaGroup = areaGroup
        self.category = category
        self.severity = severity
        self.frequency = frequency
        self.overallExperience = overallExperience
        self.testedWhat = testedWhat
        self.workedWell = workedWell
        self.couldBeBetter = couldBeBetter
        self.unexpected = unexpected
        self.featureType = featureType
        self.featureImportance = featureImportance
        self.intendedAudience = intendedAudience
        self.featureDescription = featureDescription
        self.imaginedWorkflow = imaginedWorkflow
        self.desiredLocation = desiredLocation
        self.relatedExistingFeature = relatedExistingFeature
        self.problemAddressed = problemAddressed
        self.desiredResult = desiredResult
        self.requiresSavedData = requiresSavedData
        self.needsNotifications = needsNotifications
        self.needsSharing = needsSharing
        self.needsAI = needsAI
        self.additionalDetails = additionalDetails
        self.appName = appName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
        self.deviceModel = deviceModel
        self.iOSVersion = iOSVersion
        self.locale = locale
        self.timeZone = timeZone
        self.screenName = screenName
        self.additionalNotes = additionalNotes
        self.status = status
        self.submittedAt = submittedAt
        self.conversationRecordName = conversationRecordName
        self.conversationZoneName = conversationZoneName
        self.conversationZoneOwnerName = conversationZoneOwnerName
        self.conversationShareURL = conversationShareURL
        self.conversationStateRawValue = conversationState.rawValue
        self.conversationUpdatedAt = conversationUpdatedAt
        self.conversationLastMessageAt = conversationLastMessageAt
        self.conversationUnreadCount = conversationUnreadCount
        self.conversationLastReadAt = conversationLastReadAt
        self.storedAttachments = attachments

        for attachment in attachments {
            attachment.report = self
        }
    }

    var conversationState: LureliaReportConversationState {
        get { LureliaReportConversationState(rawValue: conversationStateRawValue) ?? .notStarted }
        set { conversationStateRawValue = newValue.rawValue }
    }
}

@Model
final class SubmittedReportAttachment {
    var id: UUID = UUID()
    var displayName: String = ""
    @Attribute(.externalStorage) var imageData: Data = Data()
    var createdAt: Date = Date()
    var report: SubmittedReport?

    init(
        id: UUID = UUID(),
        displayName: String,
        imageData: Data,
        createdAt: Date = Date.now
    ) {
        self.id = id
        self.displayName = displayName
        self.imageData = imageData
        self.createdAt = createdAt
    }
}
