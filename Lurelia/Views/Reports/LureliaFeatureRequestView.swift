import PhotosUI
import SwiftData
import SwiftUI

struct LureliaFeatureRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var appState: LureliaReportRouter

    @State private var featureTitle = ""
    @State private var areaGroup = LureliaReportFormOptions.defaultAreaGroup
    @State private var area = LureliaReportFormOptions.defaultArea(for: LureliaReportFormOptions.defaultAreaGroup)
    @State private var featureType = "New Feature"
    @State private var importance = "Useful"
    @State private var intendedAudience = "Everyone"
    @State private var featureDescription = ""
    @State private var imaginedWorkflow = ""
    @State private var desiredLocation = "Existing Area"
    @State private var relatedExistingFeature = "None"
    @State private var problemAddressed = ""
    @State private var desiredResult = ""
    @State private var requiresSavedData = "Unsure"
    @State private var needsNotifications = "Unsure"
    @State private var needsSharing = "Unsure"
    @State private var needsAI = "Unsure"
    @State private var additionalDetails = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachmentData: [Data] = []
    @State private var isSubmitting = false
    @State private var submissionError: String?

    private let featureTypes = LureliaReportFormOptions.featureTypes
    private let importanceOptions = ["Nice to Have", "Useful", "Important", "Essential"]
    private let audienceOptions = ["Everyone", "New Users", "Power Users", "Routine Builders", "Habit Builders", "Event Planners", "Accessibility Need", "Other"]
    private let locationOptions = ["Existing Area", "New Screen", "Timeline", "Routines", "Habits", "Reminders", "Events", "Journeys", "Kanban", "Settings", "App-Wide", "Unsure"]
    private let relatedFeatureOptions = ["None", "Timeline", "Routines", "Routine Contracts", "Habits", "Reminders", "Events", "Apple Calendar", "Shared Events", "Journeys", "Kanban", "Widgets", "Live Activities", "Notifications", "CloudKit / Sync", "Other"]
    private let yesNoUnsureOptions = ["Yes", "No", "Unsure"]
    private let yesNoOptionalUnsureOptions = ["Yes", "No", "Optional", "Unsure"]

    private var canSubmit: Bool {
        !featureTitle.trimmed.isEmpty &&
        !area.trimmed.isEmpty &&
        !featureType.trimmed.isEmpty &&
        !importance.trimmed.isEmpty &&
        !intendedAudience.trimmed.isEmpty &&
        !featureDescription.trimmed.isEmpty &&
        !imaginedWorkflow.trimmed.isEmpty &&
        !desiredLocation.trimmed.isEmpty &&
        !problemAddressed.trimmed.isEmpty &&
        !desiredResult.trimmed.isEmpty &&
        !requiresSavedData.trimmed.isEmpty &&
        !needsNotifications.trimmed.isEmpty &&
        !needsSharing.trimmed.isEmpty &&
        !needsAI.trimmed.isEmpty &&
        !isSubmitting
    }

    var body: some View {
        LureliaReportFormScaffold {
            LureliaReportHeader(
                eyebrow: "VOXIVERSE",
                title: "Feature Request",
                eyebrowColor: theme.palette.secondaryAccent,
                bubbly: true
            ) {
                dismiss()
            }
            LureliaReportInfoCard(
                title: "Send a feature request to Voxiverse",
                message: "Describe the feature, where it should live, how it should work, and what it would make possible in Lurelia.",
                borderColor: theme.palette.primaryAction
            )
            featureDetailsSection
            featureProposalSection
            requirementsSection
            LureliaReportAttachmentsPicker(
                title: "Reference Images",
                selectedPhotos: $selectedPhotos,
                attachmentData: attachmentData,
                accentColor: theme.palette.indicators,
                sectionColor: theme.palette.indicators,
                bubbly: true
            )
            LureliaReportDiagnosticsCard(screenName: "Settings > Feature Request", borderColor: theme.palette.primaryAction)
            LureliaReportStatusCards(successTitle: "Feature Request Sent", reportID: nil, error: submissionError)
            LureliaReportSubmitButton(
                title: "Submit Feature Request",
                sendingTitle: "Sending...",
                canSubmit: canSubmit,
                isSubmitting: isSubmitting,
                bubblyTint: theme.palette.secondaryAccent,
                usesCardMaterial: true
            ) {
                Task { await submitFeatureRequest() }
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await loadAttachments(from: newItems) }
        }
        .onChange(of: areaGroup) { _, newGroup in
            area = LureliaReportFormOptions.defaultArea(for: newGroup)
        }
    }

    private var featureDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Feature Details", color: theme.palette.primaryAction, bubbly: true)
            LureliaReportTextField(title: "Feature Title", placeholder: "Short clear name for the feature", text: $featureTitle, borderColor: theme.palette.primaryAction)
            LureliaReportPickerField(title: "Category", options: LureliaReportFormOptions.areaGroups, selection: $areaGroup, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
            LureliaReportPickerField(title: "Area", options: LureliaReportFormOptions.areas(for: areaGroup), selection: $area, bubblyTint: theme.palette.secondaryAccent, usesCardMaterial: true)
            LureliaReportPickerField(title: "Feature Type", options: featureTypes, selection: $featureType, bubblyTint: theme.palette.indicators, usesCardMaterial: true)
            LureliaReportPickerField(title: "Importance", options: importanceOptions, selection: $importance, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
            LureliaReportPickerField(title: "Who Is This For?", options: audienceOptions, selection: $intendedAudience, bubblyTint: theme.palette.secondaryAccent, usesCardMaterial: true)
        }
    }

    private var featureProposalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Feature Proposal", color: theme.palette.secondaryAccent, bubbly: true)
            LureliaReportTextEditor(title: "What Should the Feature Do?", placeholder: "Describe the actual capability you want added and what you should be able to accomplish with it.", text: $featureDescription, minHeight: 130, borderColor: theme.palette.secondaryAccent)
            LureliaReportTextEditor(title: "How Should It Work?", placeholder: "Describe how you imagine using the feature from beginning to end, including what you would tap, enter, select, create, or receive.", text: $imaginedWorkflow, minHeight: 130, borderColor: theme.palette.indicators)
            LureliaReportPickerField(title: "Where Should It Live?", options: locationOptions, selection: $desiredLocation, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
            LureliaReportPickerField(title: "Related Existing Feature", options: relatedFeatureOptions, selection: $relatedExistingFeature, bubblyTint: theme.palette.secondaryAccent, usesCardMaterial: true)
            LureliaReportTextEditor(title: "What Problem or Limitation Does It Address?", placeholder: "Explain what you currently cannot do, what feels limited, or what this feature would make easier or better.", text: $problemAddressed, minHeight: 130, borderColor: theme.palette.indicators)
            LureliaReportTextEditor(title: "Desired Result", placeholder: "Describe what should exist, happen, or become possible after successfully using the feature.", text: $desiredResult, minHeight: 120, borderColor: theme.palette.primaryAction)
        }
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Requirements", color: theme.palette.indicators, bubbly: true)
            LureliaReportPickerField(title: "Would This Require Saved Data?", options: yesNoUnsureOptions, selection: $requiresSavedData, bubblyTint: theme.palette.indicators, usesCardMaterial: true)
            LureliaReportPickerField(title: "Would This Need Notifications?", options: yesNoOptionalUnsureOptions, selection: $needsNotifications, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
            LureliaReportPickerField(title: "Would This Need Sharing?", options: yesNoOptionalUnsureOptions, selection: $needsSharing, bubblyTint: theme.palette.secondaryAccent, usesCardMaterial: true)
            LureliaReportPickerField(title: "Would This Need AI?", options: yesNoOptionalUnsureOptions, selection: $needsAI, bubblyTint: theme.palette.indicators, usesCardMaterial: true)
            LureliaReportTextEditor(title: "Additional Details", placeholder: "Add anything else that would help explain the request.", text: $additionalDetails, minHeight: 100, borderColor: theme.palette.primaryAction)
        }
    }

    private func loadAttachments(from items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        for item in items.prefix(3) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        await MainActor.run { attachmentData = loaded }
    }

    @MainActor
    private func submitFeatureRequest() async {
        isSubmitting = true
        submissionError = nil

        let payload = VoxiverseFeatureRequestPayload(
            featureTitle: featureTitle,
            areaGroup: areaGroup,
            area: area,
            featureType: featureType,
            importance: importance,
            intendedAudience: intendedAudience,
            featureDescription: featureDescription,
            imaginedWorkflow: imaginedWorkflow,
            desiredLocation: desiredLocation,
            relatedExistingFeature: relatedExistingFeature == "None" ? "" : relatedExistingFeature,
            problemAddressed: problemAddressed,
            desiredResult: desiredResult,
            requiresSavedData: requiresSavedData,
            needsNotifications: needsNotifications,
            needsSharing: needsSharing,
            needsAI: needsAI,
            additionalDetails: additionalDetails,
            attachmentData: attachmentData,
            reporterName: reporterName
        )

        do {
            let result = try await VoxiverseReportSubmissionService.shared.submitFeatureRequest(payload)
            do {
                try saveSubmittedFeatureRequest(reportID: result.reportID, diagnostics: result.diagnostics)
                resetForm()
                dismiss()
            } catch {
                submissionError = "The feature request was sent, but its local Submitted copy could not be saved: \(error.localizedDescription)"
                isSubmitting = false
            }
        } catch {
            submissionError = error.localizedDescription
            isSubmitting = false
        }
    }

    @MainActor
    private func resetForm() {
        featureTitle = ""
        areaGroup = LureliaReportFormOptions.defaultAreaGroup
        area = LureliaReportFormOptions.defaultArea(for: LureliaReportFormOptions.defaultAreaGroup)
        featureType = "New Feature"
        importance = "Useful"
        intendedAudience = "Everyone"
        featureDescription = ""
        imaginedWorkflow = ""
        desiredLocation = "Existing Area"
        relatedExistingFeature = "None"
        problemAddressed = ""
        desiredResult = ""
        requiresSavedData = "Unsure"
        needsNotifications = "Unsure"
        needsSharing = "Unsure"
        needsAI = "Unsure"
        additionalDetails = ""
        selectedPhotos = []
        attachmentData = []
        submissionError = nil
        isSubmitting = false
    }

    @MainActor
    private func saveSubmittedFeatureRequest(reportID: String, diagnostics: LureliaReportDiagnostics) throws {
        let savedAttachments = attachmentData.prefix(3).enumerated().map { index, data in
            SubmittedReportAttachment(displayName: "Reference Image \(index + 1)", imageData: data)
        }
        let report = SubmittedReport(
            reportID: reportID,
            reportType: "Feature Request",
            title: featureTitle.trimmed,
            descriptionText: featureDescription.trimmed,
            expectedBehavior: "",
            steps: [],
            areaGroup: areaGroup,
            category: area,
            severity: "",
            frequency: "",
            featureType: featureType,
            featureImportance: importance,
            intendedAudience: intendedAudience,
            featureDescription: featureDescription.trimmed,
            imaginedWorkflow: imaginedWorkflow.trimmed,
            desiredLocation: desiredLocation,
            relatedExistingFeature: relatedExistingFeature == "None" ? "" : relatedExistingFeature,
            problemAddressed: problemAddressed.trimmed,
            desiredResult: desiredResult.trimmed,
            requiresSavedData: requiresSavedData,
            needsNotifications: needsNotifications,
            needsSharing: needsSharing,
            needsAI: needsAI,
            additionalDetails: additionalDetails.trimmed,
            appName: diagnostics.appName,
            appVersion: diagnostics.appVersion,
            buildNumber: diagnostics.buildNumber,
            bundleIdentifier: diagnostics.bundleIdentifier,
            deviceModel: diagnostics.deviceModel,
            iOSVersion: diagnostics.iOSVersion,
            locale: diagnostics.locale,
            timeZone: diagnostics.timeZone,
            screenName: diagnostics.screenName,
            additionalNotes: additionalDetails.trimmed,
            submittedAt: diagnostics.submittedAt,
            attachments: savedAttachments
        )
        modelContext.insert(report)
        try modelContext.save()
    }

    private var reporterName: String {
        ""
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
