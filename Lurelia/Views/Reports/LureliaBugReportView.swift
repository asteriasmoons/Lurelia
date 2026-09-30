import PhotosUI
import SwiftData
import SwiftUI

struct LureliaBugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var appState: LureliaReportRouter

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var expectedBehavior = ""
    @State private var steps = [""]
    @State private var areaGroup = LureliaReportFormOptions.defaultAreaGroup
    @State private var category = LureliaReportFormOptions.defaultArea(for: LureliaReportFormOptions.defaultAreaGroup)
    @State private var severity = "Medium"
    @State private var frequency = "Every Time"
    @State private var additionalNotes = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachmentData: [Data] = []
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var submittedReportID: String?

    private let severities = ["Low", "Medium", "High", "Critical"]
    private let frequencies = ["Once", "Sometimes", "Often", "Every Time"]

    private var canSubmit: Bool {
        !title.trimmed.isEmpty &&
        !descriptionText.trimmed.isEmpty &&
        steps.contains { !$0.trimmed.isEmpty } &&
        !isSubmitting
    }

    var body: some View {
        LureliaReportFormScaffold {
            LureliaReportHeader(
                eyebrow: "VOXIVERSE",
                title: "Report a Bug",
                eyebrowColor: theme.palette.secondaryAccent,
                bubbly: true
            ) {
                dismiss()
            }
            introCard
            detailsSection
            behaviorSection
            reproductionSection
            attachmentsSection(title: "Attachments")
            diagnosticsCard(screenName: "Settings > Bug Report")
            statusCards(successTitle: "Report Sent", reportID: submittedReportID, error: submissionError)
            submitButton(title: "Submit Bug Report")
        }
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await loadAttachments(from: newItems) }
        }
        .onChange(of: areaGroup) { _, newGroup in
            category = LureliaReportFormOptions.defaultArea(for: newGroup)
        }
    }

    private var introCard: some View {
        LureliaReportInfoCard(
            title: "Send this directly to Voxiverse",
            message: "Describe exactly what happened. Lurelia will attach the app version, build, device, iOS version, locale, time zone, and submission time automatically.",
            borderColor: theme.palette.primaryAction
        )
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Report Details", color: theme.palette.primaryAction, bubbly: true)
            LureliaReportTextField(title: "Title", placeholder: "Short description of the bug", text: $title, borderColor: theme.palette.primaryAction)
            LureliaReportPickerField(title: "Category", options: LureliaReportFormOptions.areaGroups, selection: $areaGroup, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
            LureliaReportPickerField(title: "Area", options: LureliaReportFormOptions.areas(for: areaGroup), selection: $category, bubblyTint: theme.palette.secondaryAccent, usesCardMaterial: true)
            LureliaReportPickerField(title: "Severity", options: severities, selection: $severity, bubblyTint: theme.palette.indicators, usesCardMaterial: true)
            LureliaReportPickerField(title: "Frequency", options: frequencies, selection: $frequency, bubblyTint: theme.palette.primaryAction, usesCardMaterial: true)
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "What Happened", color: theme.palette.secondaryAccent, bubbly: true)
            LureliaReportTextEditor(title: "Description", placeholder: "Tell me what happened, what you were doing, and what went wrong.", text: $descriptionText, minHeight: 150, borderColor: theme.palette.secondaryAccent)
            LureliaReportTextEditor(title: "Expected Behavior", placeholder: "What did you expect Lurelia to do instead?", text: $expectedBehavior, minHeight: 110, borderColor: theme.palette.indicators)
        }
    }

    private var reproductionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LureliaReportSectionHeader(title: "Reproduce the Bug", color: theme.palette.indicators, bubbly: true)
            LureliaReportDynamicStepsField(title: "Steps to Reproduce", steps: $steps, maxSteps: 10, accentColor: theme.palette.primaryAction, bubblyNumbers: true)
            LureliaReportTextEditor(title: "Additional Notes", placeholder: "Anything else that might help explain the problem?", text: $additionalNotes, minHeight: 100, borderColor: theme.palette.secondaryAccent)
        }
    }

    private func attachmentsSection(title: String) -> some View {
        LureliaReportAttachmentsPicker(
            title: title,
            selectedPhotos: $selectedPhotos,
            attachmentData: attachmentData,
            accentColor: theme.palette.indicators,
            sectionColor: theme.palette.indicators,
            bubbly: true
        )
    }

    private func diagnosticsCard(screenName: String) -> some View {
        LureliaReportDiagnosticsCard(screenName: screenName, borderColor: theme.palette.primaryAction)
    }

    private func statusCards(successTitle: String, reportID: String?, error: String?) -> some View {
        LureliaReportStatusCards(successTitle: successTitle, reportID: reportID, error: error)
    }

    private func submitButton(title buttonTitle: String) -> some View {
        LureliaReportSubmitButton(
            title: buttonTitle,
            sendingTitle: "Sending...",
            canSubmit: canSubmit,
            isSubmitting: isSubmitting,
            bubblyTint: theme.palette.secondaryAccent,
            usesCardMaterial: true
        ) {
            Task { await submitReport() }
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
    private func submitReport() async {
        isSubmitting = true
        submissionError = nil
        submittedReportID = nil

        let payload = VoxiverseBugReportPayload(
            title: title,
            description: descriptionText,
            expectedBehavior: expectedBehavior,
            steps: steps,
            areaGroup: areaGroup,
            category: category,
            severity: severity,
            frequency: frequency,
            additionalNotes: additionalNotes,
            attachmentData: attachmentData,
            reporterName: reporterName
        )

        do {
            let result = try await VoxiverseReportSubmissionService.shared.submitBugReport(payload)
            do {
                try saveSubmittedReport(reportID: result.reportID, diagnostics: result.diagnostics)
                resetForm()
                dismiss()
            } catch {
                submittedReportID = result.reportID
                submissionError = "The report was sent, but its local Submitted copy could not be saved: \(error.localizedDescription)"
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
        descriptionText = ""
        expectedBehavior = ""
        steps = [""]
        areaGroup = LureliaReportFormOptions.defaultAreaGroup
        category = LureliaReportFormOptions.defaultArea(for: LureliaReportFormOptions.defaultAreaGroup)
        severity = "Medium"
        frequency = "Every Time"
        additionalNotes = ""
        selectedPhotos = []
        attachmentData = []
        submissionError = nil
        submittedReportID = nil
        isSubmitting = false
    }

    @MainActor
    private func saveSubmittedReport(reportID: String, diagnostics: LureliaReportDiagnostics) throws {
        let savedAttachments = attachmentData.prefix(3).enumerated().map { index, data in
            SubmittedReportAttachment(displayName: "Screenshot \(index + 1)", imageData: data)
        }
        let report = SubmittedReport(
            reportID: reportID,
            title: title.trimmed,
            descriptionText: descriptionText.trimmed,
            expectedBehavior: expectedBehavior.trimmed,
            steps: steps.map(\.trimmed).filter { !$0.isEmpty },
            areaGroup: areaGroup,
            category: category,
            severity: severity,
            frequency: frequency,
            appName: diagnostics.appName,
            appVersion: diagnostics.appVersion,
            buildNumber: diagnostics.buildNumber,
            bundleIdentifier: diagnostics.bundleIdentifier,
            deviceModel: diagnostics.deviceModel,
            iOSVersion: diagnostics.iOSVersion,
            locale: diagnostics.locale,
            timeZone: diagnostics.timeZone,
            screenName: diagnostics.screenName,
            additionalNotes: additionalNotes.trimmed,
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
