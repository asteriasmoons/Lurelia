import PhotosUI
import SwiftData
import SwiftUI

struct LureliaBetaFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var appState: LureliaReportRouter

    @State private var title = ""
    @State private var areaGroup = LureliaReportFormOptions.defaultAreaGroup
    @State private var area = LureliaReportFormOptions.defaultArea(for: LureliaReportFormOptions.defaultAreaGroup)
    @State private var overallExperience = "Good"
    @State private var testedWhat = ""
    @State private var workedWell = ""
    @State private var couldBeBetter = ""
    @State private var unexpected = ""
    @State private var additionalThoughts = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachmentData: [Data] = []
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var submittedReportID: String?

    private let overallExperiences = ["Excellent", "Good", "Okay", "Poor"]

    private var canSubmit: Bool {
        !title.trimmed.isEmpty &&
        !area.trimmed.isEmpty &&
        !overallExperience.trimmed.isEmpty &&
        !testedWhat.trimmed.isEmpty &&
        !isSubmitting
    }

    var body: some View {
        LureliaReportFormScaffold {
            LureliaReportHeader(
                eyebrow: "VOXIVERSE",
                title: "Beta Feedback",
                eyebrowColor: theme.palette.secondaryAccent,
                bubbly: true
            ) {
                dismiss()
            }
            LureliaReportInfoCard(
                title: "Send beta feedback to Voxiverse",
                message: "Share what you tested, what worked, and what needs improvement. Lurelia will attach the same automatic diagnostics used for reports.",
                borderColor: theme.palette.primaryAction
            )
            detailsSection
            testingSection
            LureliaReportAttachmentsPicker(
                title: "Attachments",
                selectedPhotos: $selectedPhotos,
                attachmentData: attachmentData,
                accentColor: theme.palette.indicators,
                sectionColor: theme.palette.indicators,
                bubbly: true
            )
            LureliaReportDiagnosticsCard(screenName: "Beta Feedback", borderColor: theme.palette.primaryAction)
            LureliaReportStatusCards(successTitle: "Feedback Sent", reportID: submittedReportID, error: submissionError)
            LureliaReportSubmitButton(
                title: "Submit Beta Feedback",
                sendingTitle: "Sending...",
                canSubmit: canSubmit,
                isSubmitting: isSubmitting,
                bubblyTint: theme.palette.secondaryAccent,
                usesCardMaterial: true
            ) {
                Task { await submitFeedback() }
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await loadAttachments(from: newItems) }
        }
        .onChange(of: areaGroup) { _, newGroup in
            area = LureliaReportFormOptions.defaultArea(for: newGroup)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Feedback Details", color: theme.palette.primaryAction, bubbly: true)
            LureliaReportTextField(title: "Title", placeholder: "Short summary of the feedback", text: $title, borderColor: theme.palette.primaryAction)
            LureliaReportPickerField(title: "Category", options: LureliaReportFormOptions.areaGroups, selection: $areaGroup, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
            LureliaReportPickerField(title: "Area", options: LureliaReportFormOptions.areas(for: areaGroup), selection: $area, bubblyTint: theme.palette.secondaryAccent, usesCardMaterial: true)
            LureliaReportPickerField(title: "Overall Experience", options: overallExperiences, selection: $overallExperience, bubblyTint: theme.palette.indicators, usesCardMaterial: true)
        }
    }

    private var testingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Testing Notes", color: theme.palette.secondaryAccent, bubbly: true)
            LureliaReportTextEditor(title: "What Did You Test?", placeholder: "Which feature, workflow, screen, or part of Lurelia were you testing?", text: $testedWhat, minHeight: 130, borderColor: theme.palette.secondaryAccent)
            LureliaReportTextEditor(title: "What Worked Well?", placeholder: "What felt good, clear, useful, or polished?", text: $workedWell, minHeight: 110, borderColor: theme.palette.indicators)
            LureliaReportTextEditor(title: "What Could Be Better?", placeholder: "What felt awkward, confusing, incomplete, slow, or visually off?", text: $couldBeBetter, minHeight: 110, borderColor: theme.palette.primaryAction)
            LureliaReportTextEditor(title: "Anything Unexpected?", placeholder: "Anything surprising that was not necessarily a bug?", text: $unexpected, minHeight: 100, borderColor: theme.palette.secondaryAccent)
            LureliaReportTextEditor(title: "Additional Thoughts", placeholder: "Anything else you want to share?", text: $additionalThoughts, minHeight: 100, borderColor: theme.palette.indicators)
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
    private func submitFeedback() async {
        isSubmitting = true
        submissionError = nil
        submittedReportID = nil

        let payload = VoxiverseBetaFeedbackPayload(
            title: title,
            areaGroup: areaGroup,
            area: area,
            overallExperience: overallExperience,
            testedWhat: testedWhat,
            workedWell: workedWell,
            couldBeBetter: couldBeBetter,
            unexpected: unexpected,
            additionalThoughts: additionalThoughts,
            attachmentData: attachmentData,
            reporterName: reporterName
        )

        do {
            let result = try await VoxiverseReportSubmissionService.shared.submitBetaFeedback(payload)
            do {
                try saveSubmittedFeedback(reportID: result.reportID, diagnostics: result.diagnostics)
                resetForm()
                dismiss()
            } catch {
                submittedReportID = result.reportID
                submissionError = "The feedback was sent, but its local Submitted copy could not be saved: \(error.localizedDescription)"
                isSubmitting = false
            }
        } catch {
            submissionError = error.localizedDescription
            isSubmitting = false
        }
    }

    @MainActor
    private func resetForm() {
        title = ""
        areaGroup = LureliaReportFormOptions.defaultAreaGroup
        area = LureliaReportFormOptions.defaultArea(for: LureliaReportFormOptions.defaultAreaGroup)
        overallExperience = "Good"
        testedWhat = ""
        workedWell = ""
        couldBeBetter = ""
        unexpected = ""
        additionalThoughts = ""
        selectedPhotos = []
        attachmentData = []
        submissionError = nil
        submittedReportID = nil
        isSubmitting = false
    }

    @MainActor
    private func saveSubmittedFeedback(reportID: String, diagnostics: LureliaReportDiagnostics) throws {
        let savedAttachments = attachmentData.prefix(3).enumerated().map { index, data in
            SubmittedReportAttachment(displayName: "Screenshot \(index + 1)", imageData: data)
        }
        let report = SubmittedReport(
            reportID: reportID,
            reportType: "Beta Feedback",
            title: title.trimmed,
            descriptionText: testedWhat.trimmed,
            expectedBehavior: "",
            steps: [],
            areaGroup: areaGroup,
            category: area,
            severity: "",
            frequency: "",
            overallExperience: overallExperience,
            testedWhat: testedWhat.trimmed,
            workedWell: workedWell.trimmed,
            couldBeBetter: couldBeBetter.trimmed,
            unexpected: unexpected.trimmed,
            appName: diagnostics.appName,
            appVersion: diagnostics.appVersion,
            buildNumber: diagnostics.buildNumber,
            bundleIdentifier: diagnostics.bundleIdentifier,
            deviceModel: diagnostics.deviceModel,
            iOSVersion: diagnostics.iOSVersion,
            locale: diagnostics.locale,
            timeZone: diagnostics.timeZone,
            screenName: diagnostics.screenName,
            additionalNotes: additionalThoughts.trimmed,
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
