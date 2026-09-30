//
//  RoutineTaskFieldsForm.swift
//  Lurelia
//
//  Single shared field UI for a routine task's full blueprint. Used by BOTH
//  the create-routine add-task sheet (AddCustomRoutineTaskView, draft-backed)
//  and the per-task editor (RoutineTaskEditorView, @Model-backed) so the two
//  can never drift apart. Operates purely on bindings.
//

import SwiftUI
import Combine
import AVFoundation
import UIKit

// MARK: - Alarm Sound Preview Player

final class AlarmSoundPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingFileName: String?

    private var player: AVAudioPlayer?

    func toggle(_ sound: LureliaReminderAlarmSound) {
        if playingFileName == sound.fileName {
            stop()
            return
        }

        stop()

        guard let url = sound.bundleURL else {
            print("🔈 [AlarmPreview] No bundle URL for \(sound.fileName)")
            return
        }

        do {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            playingFileName = sound.fileName
        } catch {
            print("🔈 [AlarmPreview] Play error for \(sound.fileName): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingFileName = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        playingFileName = nil
    }
}

// MARK: - Value-Type Drafts (shared)

struct StepDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false
}

struct SupplyDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
}

struct ObstacleDraft: Identifiable, Hashable {
    var id: UUID = UUID()
    var obstacle: String
    var solution: String = ""
}

// MARK: - Shared Form

struct RoutineTaskFieldsForm: View {
    @Environment(\.appTheme) private var theme

    /// Accent shape style used for fills, strokes, and icon tints. This is the
    /// brand gradient during routine creation (no routine color exists yet) and
    /// the routine's own tint color when editing an existing routine's task.
    var accent: AnyShapeStyle
    /// A concrete color companion for the few places that need a `Color`
    /// (toggle tint, the time-drum picker, and adaptive text contrast).
    var accentColor: Color

    @Binding var title: String
    @Binding var notes: String
    @Binding var taskContext: String
    @Binding var selectedIcon: String

    @Binding var purpose: String
    @Binding var motivation: String
    @Binding var trigger: String
    @Binding var triggerType: LureliaCueType?
    @Binding var triggerReason: String
    @Binding var environment: String
    @Binding var reward: String
    @Binding var rewardEnabled: Bool
    @Binding var consequence: String
    @Binding var consequenceEnabled: Bool
    @Binding var recoveryPlan: String

    @Binding var hasDueTime: Bool
    @Binding var dueHour: Int
    @Binding var dueMinute: Int
    @Binding var estimatedDuration: Int
    @Binding var repeatsOnDays: Bool
    @Binding var scheduledDays: Set<Int>

    @Binding var notificationsEnabled: Bool
    @Binding var leadMinutes: Set<Int>
    @Binding var alarmEnabled: Bool
    @Binding var alarmSoundName: String

    @Binding var steps: [StepDraft]
    @Binding var supplies: [SupplyDraft]
    @Binding var obstacles: [ObstacleDraft]

    @State private var showIconPicker = false
    @State private var environmentIsCustom = false
    @State private var soundsExpanded = false
    @State private var isFillingDetails = false
    @State private var fillDetailsError: String?
    @StateObject private var soundPreview = AlarmSoundPreviewPlayer()

    private let leadOptions = [0, 5, 10, 15, 30, 60]
    private let placePresets = ["Bedroom", "Bathroom", "Kitchen", "Office", "Car", "Living Room", "Gym", "Outdoors"]

    private var textColor: Color {
        theme.palette.textPrimary
    }

    private var secondaryTextColor: Color {
        theme.palette.textSecondary
    }

    var body: some View {
        VStack(spacing: 14) {
            iconCard

            fieldCard(title: "Task Name") {
                TextField("Task name", text: $title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
            }

            fieldCard(title: "Description") {
                TextField("Short description", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
            }

            contextFillSection

            scheduleSection
            notificationSection
            contentSection
            blueprintSection
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
        )
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .onDisappear {
            soundPreview.stop()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var scheduleSection: some View {
        groupHeader("Schedule", icon: "ringstarcal")

        toggleCard(title: "Set a due time", subtitle: "Give this task its own time", isOn: $hasDueTime, icon: "ringstarcal")

        if hasDueTime {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Due Time")

                LureliaTintedTimeDrumPicker(
                    hour: $dueHour,
                    minute: $dueMinute,
                    tint: accentColor,
                    usesCardMaterial: true,
                    usesDarkTypography: true
                )
            }
        }

        LureliaGradientStepper(
            title: "Estimated Duration",
            subtitle: "Minutes",
            value: $estimatedDuration,
            range: 0...600,
            step: 1,
            tint: accentColor,
            usesRoutineMaterialStyle: true
        )

        toggleCard(title: "Repeat on days", subtitle: "Choose which days this applies", isOn: $repeatsOnDays, icon: "repeatfill")

        if repeatsOnDays {
            weekdaySelector
        }
    }

    @ViewBuilder
    private var notificationSection: some View {
        groupHeader("Notifications & Alarm", icon: "bellfill")

        toggleCard(
            title: "Notifications",
            subtitle: hasDueTime ? "Remind me before it's due" : "Requires a due time",
            isOn: $notificationsEnabled,
            icon: "bellfill"
        )

        if notificationsEnabled && hasDueTime {
            leadTimeSelector
        }

        toggleCard(
            title: "Alarm",
            subtitle: hasDueTime ? "Fire an alarm at the due time" : "Requires a due time",
            isOn: $alarmEnabled,
            icon: "clockwavy"
        )

        if alarmEnabled {
            alarmSoundPicker
        }
    }

    private var alarmSoundPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    soundsExpanded.toggle()
                    if !soundsExpanded { soundPreview.stop() }
                }
            } label: {
                HStack(spacing: 10) {
                    Image("bells")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(accentColor)
                        .bubblyIconMaterial(tint: accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sound")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(textColor)
                        Text(LureliaReminderAlarmSound.sound(named: alarmSoundName).displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    Image("chevright")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(accentColor)
                        .bubblyIconMaterial(tint: accentColor)
                        .rotationEffect(.degrees(soundsExpanded ? 90 : 0))
                }
                .padding(14)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accentColor, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if soundsExpanded {
                VStack(spacing: 8) {
                    ForEach(LureliaReminderAlarmSound.availableSounds) { sound in
                        alarmSoundRow(sound)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func alarmSoundRow(_ sound: LureliaReminderAlarmSound) -> some View {
        let isSelected = alarmSoundName == sound.fileName
        let isPlaying = soundPreview.playingFileName == sound.fileName

        return HStack(spacing: 10) {
            Button {
                alarmSoundName = sound.fileName
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(theme.palette.textSecondary.opacity(0.35)), lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        if isSelected {
                            Circle().fill(accent).frame(width: 10, height: 10)
                        }
                    }

                    Text(sound.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? textColor : secondaryTextColor)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                soundPreview.toggle(sound)
            } label: {
                Image(isPlaying ? "stopwavy" : "playwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(accentColor)
                    .bubblyIconMaterial(tint: accentColor)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected ? AnyShapeStyle(accentColor.opacity(0.14)) : AnyShapeStyle(theme.palette.surface),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(theme.palette.textPrimary.opacity(0.1)), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        groupHeader("Steps", icon: "listcircle")
        stepsEditor

        groupHeader("Supplies", icon: "backpack")
        suppliesEditor
    }

    @ViewBuilder
    private var blueprintSection: some View {
        groupHeader("Purpose", icon: "loveflame")
        multilineCard(title: "Purpose", placeholder: "Why does this task exist?", text: $purpose)

        groupHeader("Preparation", icon: "sparkbolt")

        VStack(alignment: .leading, spacing: 8) {
            Text("TRIGGER TYPE")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)
            triggerTypeGrid
        }

        multilineCard(title: "Trigger", placeholder: "What signals this task should begin?", text: $trigger)
        environmentSection

        groupHeader("Obstacles", icon: "crossroads")
        obstaclesEditor

        toggleCard(
            title: "Reward",
            subtitle: rewardEnabled ? "Optional reward is attached" : "Optional reward",
            isOn: $rewardEnabled,
            icon: "starsparklesbox"
        )

        if rewardEnabled {
            multilineCard(title: "Reward", placeholder: "What do you get for completing this?", text: $reward)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        toggleCard(
            title: "Consequence",
            subtitle: consequenceEnabled ? "Optional consequence is attached" : "Optional consequence",
            isOn: $consequenceEnabled,
            icon: "warnwavy"
        )

        if consequenceEnabled {
            multilineCard(title: "Consequence", placeholder: "What happens if this gets skipped?", text: $consequence)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var contextFillSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldCard(title: "Context") {
                TextField("Describe your goal for this task", text: $taskContext, axis: .vertical)
                    .lineLimit(3...7)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
            }

            Button {
                Task { await fillDetails() }
            } label: {
                HStack(spacing: 8) {
                    if isFillingDetails {
                        ProgressView()
                            .tint(fillDetailsButtonTextColor)
                    } else {
                        Image("sparkle")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .foregroundStyle(.black)
                    }

                    Text(isFillingDetails ? "Filling Details" : "Fill Details")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .foregroundStyle(fillDetailsButtonTextColor)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    if canFillDetails {
                        BubblyCardMaterial(tint: accentColor, cornerRadius: 16)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.palette.raisedSurface)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canFillDetails)

            if let fillDetailsError {
                Text(fillDetailsError)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(lureliaHex: "#ff9be6"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canFillDetails: Bool {
        !isFillingDetails && !taskContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fillDetailsButtonTextColor: Color {
        canFillDetails ? .black : theme.palette.textSecondary.opacity(0.45)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func fillDetails() async {
        guard canFillDetails else { return }

        isFillingDetails = true
        fillDetailsError = nil

        do {
            let response = try await RoutineTaskDetailsService.shared.fillDetails(
                RoutineTaskDetailsFillRequest(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    context: taskContext.trimmingCharacters(in: .whitespacesAndNewlines),
                    purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                    trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                    triggerType: triggerType?.rawValue,
                    environment: environment.trimmingCharacters(in: .whitespacesAndNewlines),
                    reward: reward.trimmingCharacters(in: .whitespacesAndNewlines),
                    consequence: consequence.trimmingCharacters(in: .whitespacesAndNewlines),
                    steps: steps
                        .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty },
                    supplies: supplies
                        .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty },
                    obstacles: obstacles.compactMap { item in
                        let obstacle = item.obstacle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !obstacle.isEmpty else { return nil }
                        return RoutineTaskDetailsFillObstacle(
                            obstacle: obstacle,
                            solution: item.solution.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                )
            )

            applyFilledDetails(response)
        } catch {
            fillDetailsError = error.localizedDescription
        }

        isFillingDetails = false
    }

    private func applyFilledDetails(_ response: RoutineTaskDetailsFillResponse) {
        title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes = response.description.trimmingCharacters(in: .whitespacesAndNewlines)
        purpose = response.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        trigger = response.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        triggerType = response.triggerType.flatMap(LureliaCueType.init(rawValue:))
        environment = response.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        environmentIsCustom = !environment.isEmpty && !placePresets.contains(environment)
        reward = response.reward.trimmingCharacters(in: .whitespacesAndNewlines)
        rewardEnabled = !reward.isEmpty
        consequence = response.consequence.trimmingCharacters(in: .whitespacesAndNewlines)
        consequenceEnabled = !consequence.isEmpty

        steps = response.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(9)
            .map { StepDraft(title: $0) }

        supplies = response.supplies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(12)
            .map { SupplyDraft(name: $0) }

        obstacles = response.obstacles
            .compactMap { item -> ObstacleDraft? in
                let obstacle = item.obstacle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !obstacle.isEmpty else { return nil }
                return ObstacleDraft(
                    obstacle: obstacle,
                    solution: item.solution.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .prefix(9)
            .map { $0 }
    }

    // MARK: - Icon

    private var iconCard: some View {
        Button { showIconPicker = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(theme.palette.raisedSurface).frame(width: 48, height: 48)
                    Circle().strokeBorder(accent.opacity(0.85), lineWidth: 1)
                    LureliaIconView(iconId: selectedIcon, size: 23)
                        .foregroundStyle(accentColor)
                        .bubblyIconMaterial(tint: accentColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Task Icon")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(textColor)
                    Text("Tap to change the icon")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Image("chevright")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(accentColor)
                    .bubblyIconMaterial(tint: accentColor)
            }
            .padding(14)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(accentColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable Field Building Blocks

    private func groupHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(accentColor)
                .bubblyIconMaterial(tint: accentColor)

            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(textColor)

            Spacer()
        }
        .padding(.top, 6)
    }

    private func fieldCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(title)

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accentColor, lineWidth: 1)
                }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(theme.palette.textSecondary)
    }

    private func multilineCard(title: String, placeholder: String, text: Binding<String>) -> some View {
        fieldCard(title: title) {
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(textColor)
                .submitLabel(.done)
                .onSubmit { dismissKeyboard() }
        }
    }

    private func toggleCard(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        icon: String,
        isDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(textColor)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            LureliaSlidingIconToggle(
                isOn: isOn,
                iconName: icon,
                accentColor: accentColor,
                accessibilityLabel: title,
                isDisabled: isDisabled,
                usesIconMaterial: true
            )
        }
        .padding(14)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accentColor, lineWidth: 1)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isOn.wrappedValue)
    }

    // MARK: - Environment (place picker + custom)

    @ViewBuilder
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ENVIRONMENT")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(placePresets, id: \.self) { place in
                    placeChip(title: place, isSelected: !environmentIsCustom && environment == place) {
                        environmentIsCustom = false
                        environment = place
                    }
                }

                placeChip(title: "Custom", isSelected: environmentIsCustom) {
                    if placePresets.contains(environment) { environment = "" }
                    environmentIsCustom = true
                }
            }

            if environmentIsCustom {
                TextField("Type where this is done...", text: $environment, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(accentColor, lineWidth: 1)
                    }
            }
        }
        .onAppear {
            environmentIsCustom = !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !placePresets.contains(environment)
        }
    }

    private func placeChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .black : secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    selectionMaterial(isSelected: isSelected, cornerRadius: 12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? accentColor : theme.palette.textPrimary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trigger Type Grid (mirrors habit Cue Type)

    private var triggerTypeGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(LureliaCueType.allCases) { type in
                let isSelected = triggerType == type
                Button {
                    if triggerType == type {
                        triggerType = nil
                    } else {
                        triggerType = type
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(type.iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)

                        Text(type.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? .black : secondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        selectionMaterial(isSelected: isSelected, cornerRadius: 12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? accentColor : theme.palette.textPrimary.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekdaySelector: some View {
        let days: [(value: Int, short: String)] = [
            (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
        ]
        return HStack(spacing: 6) {
            ForEach(days, id: \.value) { day in
                let active = scheduledDays.contains(day.value)
                Button {
                    if active { scheduledDays.remove(day.value) } else { scheduledDays.insert(day.value) }
                } label: {
                    Text(day.short)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? .black : secondaryTextColor.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            selectionMaterial(isSelected: active, cornerRadius: 12)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(active ? accentColor : theme.palette.textPrimary.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var leadTimeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REMIND BEFORE (MIN)")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)

            HStack(spacing: 8) {
                ForEach(leadOptions, id: \.self) { option in
                    let active = leadMinutes.contains(option)
                    Button {
                        if active { leadMinutes.remove(option) } else { leadMinutes.insert(option) }
                    } label: {
                        Text(option == 0 ? "On time" : "\(option)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(active ? .black : secondaryTextColor.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background {
                                selectionMaterial(isSelected: active, cornerRadius: 11)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(active ? accentColor : theme.palette.textPrimary.opacity(0.12), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionMaterial(isSelected: Bool, cornerRadius: CGFloat) -> some View {
        if isSelected {
            BubblyIconMaterial(tint: accentColor)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.palette.surface)
        }
    }

    private var stepsEditor: some View {
        VStack(spacing: 10) {
            ForEach($steps) { $step in
                HStack(spacing: 10) {
                    TextField("Step", text: $step.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(textColor)
                        .submitLabel(.done)
                        .onSubmit { dismissKeyboard() }
                            .padding(12)
                        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(accentColor, lineWidth: 1)
                        }

                    removeButton { steps.removeAll { $0.id == step.id } }
                }
            }

            if steps.count < 9 {
                addRowButton(title: "Add Step") {
                    steps.append(StepDraft(title: ""))
                }
            }
        }
    }

    private var suppliesEditor: some View {
        VStack(spacing: 10) {
            ForEach($supplies) { $supply in
                HStack(spacing: 10) {
                    TextField("Supply", text: $supply.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(textColor)
                        .submitLabel(.done)
                        .onSubmit { dismissKeyboard() }
                            .padding(12)
                        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(accentColor, lineWidth: 1)
                        }

                    removeButton { supplies.removeAll { $0.id == supply.id } }
                }
            }

            addRowButton(title: "Add Supply") {
                supplies.append(SupplyDraft(name: ""))
            }
        }
    }

    private var obstaclesEditor: some View {
        VStack(spacing: 12) {
            ForEach($obstacles) { $item in
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("Obstacle", text: $item.obstacle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(textColor)
                            .submitLabel(.done)
                            .onSubmit { dismissKeyboard() }
                                    .padding(12)
                            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(accentColor, lineWidth: 1)
                            }

                        removeButton { obstacles.removeAll { $0.id == item.id } }
                    }

                    TextField("Solution", text: $item.solution, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                        .submitLabel(.done)
                        .onSubmit { dismissKeyboard() }
                            .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(accentColor, lineWidth: 1)
                        }
                }
            }

            if obstacles.count < 9 {
                addRowButton(title: "Add Obstacle") {
                    obstacles.append(ObstacleDraft(obstacle: "", solution: ""))
                }
            }
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image("minuswavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(accentColor)
                .bubblyIconMaterial(tint: accentColor)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    private func addRowButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("addwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(accentColor)
                    .bubblyIconMaterial(tint: accentColor)

                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(secondaryTextColor)

                Spacer()
            }
            .padding(12)
            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accentColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
