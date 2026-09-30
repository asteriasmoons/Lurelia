//
//  RoutineTaskTemplateDetailView.swift
//  Lurelia
//
//  Read-only preview of a `RoutineTaskTemplate`. Mirrors the structure of
//  `RoutineTaskDetailView` (identity card, schedule tiles, steps, purpose,
//  trigger, environment, supplies, obstacles, rewards, consequence) but
//  drops the runtime-only sections that don't apply to a blueprint
//  (status, completion actions, statistics, history, tiny nudge). Its
//  material treatment matches RoutineTaskDetailView using the template's
//  rotating library accent.
//

import SwiftData
import SwiftUI
import UIKit

private extension View {
    func routineTemplateDarkInset<S: Shape>(in shape: S) -> some View {
        background {
            shape.fill(Color.black.opacity(0.34))
        }
    }
}

struct RoutineTaskTemplateDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    let template: RoutineTaskTemplate
    let tint: Color
    var onUse: () -> Void
    var onEdit: () -> Void

    init(
        template: RoutineTaskTemplate,
        tint: Color = LColors.gradientPurple,
        onUse: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.template = template
        self.tint = tint
        self.onUse = onUse
        self.onEdit = onEdit
    }

    private var templateIcon: String {
        let icon = template.icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "sparkle" : icon
    }

    private var cleanedNotes: String {
        template.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var triggerType: LureliaCueType? {
        template.triggerTypeRaw.flatMap(LureliaCueType.init(rawValue:))
    }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header

                    identityCard

                    scheduleSection

                    stepsSection

                    if !template.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Purpose", icon: "loveflame") {
                            sectionLabel("Why does this task exist?")
                            sectionBody(template.purpose)
                        }
                    }

                    if triggerType != nil || !template.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Trigger", icon: "sparkbolt") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let type = triggerType {
                                    HStack(spacing: 10) {
                                        Image(type.iconName)
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(tint)
                                            .bubblyIconMaterial(tint: tint)

                                        Text(type.label)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .routineTemplateDarkInset(in: Capsule())
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                                }

                                if !template.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sectionLabel("Trigger")
                                    sectionBody(template.trigger)
                                }

                                if !template.triggerReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    sectionLabel("Why this trigger works")
                                    sectionBody(template.triggerReason)
                                }
                            }
                        }
                    }

                    if !template.environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Environment", icon: "houseoutline") {
                            sectionLabel("Where is this normally done?")
                            sectionBody(template.environment)
                        }
                    }

                    if !template.supplies.isEmpty {
                        suppliesSection
                    }

                    if !template.obstacles.isEmpty {
                        obstaclesSection
                    }

                    if !template.motivation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Motivation", icon: "starhandtrophy") {
                            sectionBody(template.motivation)
                        }
                    }

                    let rewardText = template.reward.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (template.rewardEnabled ?? !rewardText.isEmpty) && !rewardText.isEmpty {
                        sectionCard(title: "Rewards", icon: "starhandtrophy") {
                            sectionLabel("What do I get for completing this?")
                            sectionBody(rewardText)
                        }
                    }

                    let consequenceText = template.consequence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (template.consequenceEnabled ?? !consequenceText.isEmpty) && !consequenceText.isEmpty {
                        sectionCard(title: "Consequence", icon: "minuswavy") {
                            sectionLabel("What happens if this gets skipped?")
                            sectionBody(consequenceText)
                        }
                    }

                    if !template.recoveryPlan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sectionCard(title: "Recovery Plan", icon: "arrowscircle") {
                            sectionBody(template.recoveryPlan)
                        }
                    }

                    actionButtons

                    Spacer().frame(height: 40)
                }
                .padding(.top, 6)
                .routinePageWidthLocked()
            }
            .routinePageScrollClipped()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Template")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background {
                        BubblyIconMaterial(tint: tint)
                            .clipShape(Circle())
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Identity

    private var identityCard: some View {
        tintedCard(role: .hero) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.42))
                        .frame(width: 64, height: 64)

                    Circle()
                        .strokeBorder(tint.opacity(0.85), lineWidth: 1)
                        .frame(width: 64, height: 64)

                    LureliaIconView(iconId: templateIcon, size: 38)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .bubblyIconMaterial(tint: tint)
                }

                Text(template.title.isEmpty ? "Untitled Template" : template.title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if !cleanedNotes.isEmpty {
                    Text(cleanedNotes)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Image("cardlines")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(tint)
                        .bubblyIconMaterial(tint: tint)

                    Text("TEMPLATE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .routineTemplateDarkInset(in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Schedule Defaults", icon: "ringstarcal")

            tintedCard {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        metricTile(icon: "repeatfill", label: "Repeats", value: repeatsSummary)
                        metricTile(icon: "dotscal", label: "Due", value: dueSummary)
                    }
                    HStack(spacing: 10) {
                        metricTile(icon: "bellfill", label: "Notifications", value: notificationsSummary)
                        metricTile(icon: "clockfill", label: "Alarm", value: alarmSummary)
                    }
                    HStack(spacing: 10) {
                        metricTile(icon: "hourglassfill", label: "Est. Duration", value: durationSummary)
                        metricTile(icon: "starcal", label: "Days", value: daysSummary)
                    }

                    if template.repeatsOnDays && !template.scheduledDays.isEmpty && template.scheduledDays.count < 7 {
                        weekdayChips
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var repeatsSummary: String {
        guard template.repeatsOnDays else { return "Once" }
        if template.scheduledDays.isEmpty { return "Daily" }
        if template.scheduledDays.count == 7 { return "Every day" }
        let weekdayValues = Set([2, 3, 4, 5, 6])
        if Set(template.scheduledDays) == weekdayValues { return "Weekdays" }
        if Set(template.scheduledDays) == Set([1, 7]) { return "Weekends" }
        return "\(template.scheduledDays.count) days"
    }

    private var dueSummary: String {
        guard template.hasDueTime else { return "No time" }
        var comps = DateComponents()
        comps.hour = template.dueHour
        comps.minute = template.dueMinute
        guard let date = Calendar.current.date(from: comps) else {
            return String(format: "%d:%02d", template.dueHour, template.dueMinute)
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var notificationsSummary: String {
        guard template.notificationsEnabled else { return "Off" }
        let count = template.notificationLeadMinutes.count
        return count == 0 ? "On" : (count == 1 ? "1" : "\(count)")
    }

    private var alarmSummary: String {
        guard template.alarmEnabled else { return "Off" }
        let name = template.alarmSoundName ?? "radiate.m4a"
        return LureliaReminderAlarmSound.displayNames[name]
            ?? name.replacingOccurrences(of: ".m4a", with: "").capitalized
    }

    private var durationSummary: String {
        template.estimatedDurationMinutes > 0 ? "\(template.estimatedDurationMinutes) min" : "—"
    }

    private var daysSummary: String {
        guard template.repeatsOnDays, !template.scheduledDays.isEmpty else { return "Any" }
        if template.scheduledDays.count == 7 { return "All" }
        return "\(template.scheduledDays.count)"
    }

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(weekdayList, id: \.value) { wd in
                let active = template.scheduledDays.contains(wd.value)
                Text(wd.short)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(active ? .white : .white.opacity(0.25))
                    .frame(width: 34, height: 30)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

                        if active {
                            shape.fill(tint)
                        } else {
                            shape.fill(Color.black.opacity(0.34))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Group {
            if !template.steps.isEmpty {
                sectionCard(title: "Steps", icon: "starblist") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(template.steps.enumerated()), id: \.offset) { index, step in
                            HStack(spacing: 10) {
                                wavyNumberIcon(index + 1)

                                Text(step.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Supplies

    private var suppliesSection: some View {
        sectionCard(title: "Supplies", icon: "backpack") {
            TagFlowLayout(spacing: 8) {
                ForEach(Array(template.supplies.enumerated()), id: \.offset) { _, supply in
                    HStack(spacing: 6) {
                        Image("checkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(tint)
                            .bubblyIconMaterial(tint: tint)

                        Text(supply.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .routineTemplateDarkInset(in: Capsule())
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Obstacles

    private var obstaclesSection: some View {
        sectionCard(title: "Obstacles & Solutions", icon: "crossroads") {
            VStack(alignment: .leading, spacing: 14) {
                let obstacles = Array(template.obstacles.prefix(9))
                ForEach(Array(obstacles.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 12) {
                            wavyNumberIcon(index + 1)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.obstacle)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                let solution = item.solution.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !solution.isEmpty {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image("rightwavy")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .foregroundStyle(LColors.success)
                                            .bubblyIconMaterial(tint: tint)

                                        Text(solution)
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundStyle(LColors.success.opacity(0.85))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if index < obstacles.count - 1 {
                            Rectangle()
                                .fill(.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action buttons (Use / Edit)

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
                onUse()
            } label: {
                actionButtonLabel(title: "Use Template", icon: "checkwavy", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
                onEdit()
            } label: {
                actionButtonLabel(title: "Edit Template", icon: "pencilcircle", filled: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func actionButtonLabel(title: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            if filled {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.68), radius: 2, x: 0, y: 1)

                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.68), radius: 2, x: 0, y: 1)
            } else {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(tint)
                    .wcagContrastLift(on: tint, isActive: false)
                    .bubblyIconMaterial(tint: tint)

                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .wcagContrastLift(on: tint, isActive: false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background {
            if filled {
                BubblyCardMaterial(
                    tint: tint,
                    cornerRadius: 16
                )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Reusable helpers (mirrors RoutineTaskDetailView pattern)

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(tint)
                .bubblyIconMaterial(tint: tint)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: title, icon: icon)
            tintedCard {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    private func tintedCard<Content: View>(
        role: LureliaUserChoiceSurfaceRole = .supporting,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(18)
            .background {
                BubblyCardMaterial(
                    tint: tint,
                    cornerRadius: 22
                )
            }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.6)
    }

    private func sectionBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func wavyNumberIcon(_ number: Int, dimmed: Bool = false) -> some View {
        Image("\(min(max(number, 1), 9))wavy")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(dimmed ? tint.opacity(0.45) : tint)
            .bubblyIconMaterial(tint: tint)
    }

    private func metricTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(tint)
                .bubblyIconMaterial(tint: tint)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .tracking(0.5)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .routineTemplateDarkInset(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
    }

    private let weekdayList: [(value: Int, short: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]
}
