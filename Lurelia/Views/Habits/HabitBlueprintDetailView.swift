//
//  HabitBlueprintDetailView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import UIKit

struct HabitBlueprintDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let habit: LureliaHabit

    @Query(sort: \LureliaHabit.createdAt)
    private var allHabits: [LureliaHabit]

    /// The habit's user-selected color. Drives the Blueprint's visual identity
    /// (replaces the app-wide cyan/purple gradient across this view).
    private var accent: Color { habit.color }
    private var accentStyle: AnyShapeStyle { AnyShapeStyle(accent) }
    
    @State private var frictionEditing = false
    @State private var frictionDraft = ""
    @State private var isGeneratingTinyNudge = false
    @State private var tinyNudgeResponse: TinyNudgeResponse?
    @State private var tinyNudgeError: String?

    var body: some View {
        ZStack {
            LureliaBackgroundAlt()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    // MARK: - Header

                    HStack {
                        Text("Habit Blueprint")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Spacer()

                        Button { dismiss() } label: {
                            Image("xmarkwavy")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(accentStyle)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .padding(.bottom, 4)

                    // MARK: - Icon + Title + Description

                    userChoiceCard(role: .hero) {
                        VStack(spacing: 10) {
                            BlueprintIconPreview(iconName: habit.iconName ?? "flame", tint: accent)

                            Text(habit.title)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            if let details = habit.details,
                               !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(details)
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)

                    undoProgressButton

                    // MARK: - Schedule & Frequency

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image("clockfill")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(accentStyle)

                            Text("Schedule")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        userChoiceCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    detailPill(scheduleSummary)
                                    detailPill("\(habit.target)x per day")
                                    detailPill("\(habit.daysPerWeek) day\(habit.daysPerWeek == 1 ? "" : "s")/week")
                                    detailPill(alarmSummary)
                                }

                                if habit.activeWeekdays.count < 7 {
                                    HStack(spacing: 6) {
                                        ForEach(weekdayList, id: \.value) { wd in
                                            let active = habit.activeWeekdays.contains(wd.value)
                                            Text(wd.short)
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(active ? .white : .white.opacity(0.25))
                                                .frame(width: 32, height: 28)
                                                .background(
                                                    active
                                                    ? accentStyle
                                                    : AnyShapeStyle(Color.white.opacity(0.06))
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)

                    // MARK: - Today's Progress

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image("starchart")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(accentStyle)

                            Text("Today's Progress")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        userChoiceCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 8) {
                                    ForEach(0..<habit.target, id: \.self) { i in
                                        Circle()
                                            .fill(
                                                i < habit.todaysCount
                                                ? accentStyle
                                                : AnyShapeStyle(Color.white.opacity(0.15))
                                            )
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        i < habit.todaysCount
                                                        ? Color.clear
                                                        : Color.white.opacity(0.2),
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                }

                                VStack(spacing: 5) {
                                    HStack {
                                        Text("\(habit.todaysCount) / \(habit.target) completed")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.45))

                                        Spacer()

                                        Text("\(Int(habit.progress * 100))%")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(.white.opacity(0.1))
                                                .frame(height: 6)

                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(accent)
                                                .frame(width: geo.size.width * habit.progress, height: 6)
                                                .animation(.spring(duration: 0.4), value: habit.progress)
                                        }
                                    }
                                    .frame(height: 6)
                                }

                                if habit.isCompletedToday {
                                    HStack(spacing: 6) {
                                        Image("checkwavy")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 14, height: 14)
                                            .foregroundStyle(LColors.success)

                                        Text("Completed today")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(LColors.success)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // MARK: - Streaks

                    HStack(spacing: 12) {
                        streakCard(label: "Daily Streak", value: "\(habit.dailyStreak)", unit: habit.dailyStreak == 1 ? "day" : "days")
                        streakCard(label: "Weekly Streak", value: "\(habit.weeklyStreak)", unit: habit.weeklyStreak == 1 ? "week" : "weeks")
                    }
                    .padding(.horizontal, 24)

                    // MARK: - Identity

                    if let identity = habit.identityStatement, !identity.isEmpty {
                        sectionCard(title: "Identity", icon: "loveeye") {
                            sectionLabel("Who am I becoming?")
                            sectionBody(identity)
                        }
                    }

                    // MARK: - Purpose

                    if let purpose = habit.habitPurpose, !purpose.isEmpty {
                        sectionCard(title: "Purpose", icon: "loveflame") {
                            sectionLabel("Why does this habit exist?")
                            sectionBody(purpose)
                        }
                    }
                    
                    // MARK: - Habit Levels

                    if habit.hasLevels {
                        sectionCard(title: "Habit Levels", icon: "starprogressbar") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(sortedLevels) { level in
                                    levelRow(level)
                                }
                            }
                        }
                    }

                    // MARK: - Implementation Intention

                    if let intention = habit.implementationIntention, !intention.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image("pencil")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(accentStyle)

                                Text("Implementation Intention")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }

                            userChoiceCard {
                                Text(intention)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 24)
                    }

                    // MARK: - Cue

                    if habit.cueType != nil || habit.cueDescription?.isEmpty == false || habit.cueReason?.isEmpty == false {
                        sectionCard(title: "Cue", icon: "sparkbolt") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let cueType = habit.cueType {
                                    HStack(spacing: 10) {
                                        Image(cueType.iconName)
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(accentStyle)

                                        Text(cueType.label)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                                }

                                if let cue = habit.cueDescription, !cue.isEmpty {
                                    sectionLabel("Cue")
                                    sectionBody(cue)
                                }

                                if let reason = habit.cueReason, !reason.isEmpty {
                                    sectionLabel("Why This Cue Works")
                                    sectionBody(reason)
                                }
                            }
                        }
                    }

                    // MARK: - Environment

                    if habit.currentEnvironment?.isEmpty == false ||
                       habit.idealEnvironment?.isEmpty == false ||
                       habit.environmentChanges?.isEmpty == false {
                        sectionCard(title: "Environment", icon: "houseoutline") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let current = habit.currentEnvironment, !current.isEmpty {
                                    sectionLabel("Current Environment")
                                    sectionBody(current)
                                }
                                if let ideal = habit.idealEnvironment, !ideal.isEmpty {
                                    sectionLabel("Ideal Environment")
                                    sectionBody(ideal)
                                }
                                if let changes = habit.environmentChanges, !changes.isEmpty {
                                    sectionLabel("Changes to Make")
                                    sectionBody(changes)
                                }
                            }
                        }
                    }
                    
                    // MARK: - Temptation Bundling

                    if habit.temptationNeed?.isEmpty == false ||
                       habit.temptationWant?.isEmpty == false {
                        sectionCard(title: "Temptation Bundling", icon: "heartunlock") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let need = habit.temptationNeed, !need.isEmpty {
                                    sectionLabel("Need")
                                    sectionBody(need)
                                }

                                if let want = habit.temptationWant, !want.isEmpty {
                                    sectionLabel("Want")
                                    sectionBody(want)
                                }
                            }
                        }
                    }

                    // MARK: - Rules

                    if !habit.habitRules.isEmpty {
                        sectionCard(title: "Habit Rules", icon: "lockwavy") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(habit.habitRules.enumerated()), id: \.offset) { index, rule in
                                    HStack(alignment: .top, spacing: 12) {
                                        numberedCircle(index + 1)

                                        Text(rule)
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.85))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - Obstacles & Solutions

                    if !habit.habitObstacles.isEmpty {
                        sectionCard(title: "Obstacles & Solutions", icon: "crossroads") {
                            VStack(alignment: .leading, spacing: 14) {
                                let obstacles = habit.habitObstacles
                                let solutions = habit.habitSolutions

                                ForEach(Array(obstacles.enumerated()), id: \.offset) { index, obstacle in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top, spacing: 12) {
                                            numberedCircle(index + 1)

                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(obstacle)
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.white)

                                                if index < solutions.count, !solutions[index].isEmpty {
                                                    HStack(alignment: .top, spacing: 6) {
                                                        Image("rightwavy")
                                                            .renderingMode(.template)
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 12, height: 12)
                                                            .foregroundStyle(LColors.success)

                                                        Text(solutions[index])
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
                    
                    // MARK: - Tiny Nudge

                    sectionCard(title: "Tiny Nudge", icon: "starchat") {
                        frictionBox
                    }

                    // MARK: - Rewards

                    if habit.immediateReward?.isEmpty == false ||
                       habit.longTermReward?.isEmpty == false {
                        sectionCard(title: "Rewards", icon: "starhandtrophy") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let immediate = habit.immediateReward, !immediate.isEmpty {
                                    sectionLabel("Immediate Reward")
                                    sectionBody(immediate)
                                }
                                if let longTerm = habit.longTermReward, !longTerm.isEmpty {
                                    sectionLabel("Long-Term Reward")
                                    sectionBody(longTerm)
                                }
                            }
                        }
                    }

                    // MARK: - Cue Insights

                    cueInsightsSection

                    Spacer().frame(height: 140)
                }
            }
            .onTapGesture {
                if frictionEditing {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        frictionEditing = false
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Reusable User-Choice Card

    private func userChoiceCard<Content: View>(
        role: LureliaUserChoiceSurfaceRole = .supporting,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(LSpacing.cardPadding)
            .background {
                LureliaUserChoiceSurface(
                    tint: accent,
                    role: role,
                    cornerRadius: 24
                )
            }
    }

    // MARK: - Reusable Section Card

    private var undoProgressButton: some View {
        Button {
            undoLatestCompletionToday()
        } label: {
            HStack(spacing: 10) {
                Image("minuswavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.white)

                Text("Undo Last Completion")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(hasProgressToday ? 0.24 : 0.08), lineWidth: 1)
            )
            .opacity(hasProgressToday ? 1 : 0.38)
        }
        .buttonStyle(.plain)
        .disabled(!hasProgressToday)
        .padding(.horizontal, 24)
    }

    private var hasProgressToday: Bool {
        guard let todayLog = habit.todaysLog() else { return false }
        return todayLog.count > 0 || !todayLog.completedFireTimes.isEmpty
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(accentStyle)

                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            userChoiceCard {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Streak Card

    private func streakCard(label: String, value: String, unit: String) -> some View {
        userChoiceCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(0.6)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text(unit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Cue Insights

    @ViewBuilder
    private var cueInsightsSection: some View {
        let activeHabits = allHabits.filter { !$0.isArchived }
        let cueCounts = computeCueCounts(from: activeHabits)

        if !cueCounts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image("starbars")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(accentStyle)

                    Text("Cue Insights")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                userChoiceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(cueCounts, id: \.type) { entry in
                            HStack(spacing: 12) {
                                Image(entry.type.iconName)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .foregroundStyle(accentStyle)

                                Text(entry.type.label)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)

                                Spacer()

                                Text("\(entry.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            if entry.type != cueCounts.last?.type {
                                Rectangle()
                                    .fill(.white.opacity(0.06))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Small Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
            .tracking(0.6)
    }

    private func sectionBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var frictionBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            if frictionEditing {
                TextField("What is making this habit harder?", text: $frictionDraft, axis: .vertical)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
                    .onTapGesture { }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()

                            Button("Done") {
                                dismissKeyboard()
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                    }

                Button {
                    let typedFriction = frictionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    saveFriction()

                    Task {
                        isGeneratingTinyNudge = true
                        tinyNudgeError = nil
                        tinyNudgeResponse = nil

                        do {
                            tinyNudgeResponse = try await TinyNudgeService.shared.convinceMe(
                                taskType: .habit,
                                taskName: habit.title,
                                friction: typedFriction
                            )
                        } catch {
                            tinyNudgeError = error.localizedDescription
                        }

                        isGeneratingTinyNudge = false
                    }
                } label: {
                    Text("Convince Me")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(accent)
                        )
                }
                .buttonStyle(.plain)

            } else {
                Button {
                    frictionDraft = ""

                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        frictionEditing = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image("addwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(accentStyle)

                        Text("Add Friction")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if isGeneratingTinyNudge {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)

                    Text("Writing your nudge...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let tinyNudgeResponse {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("Convince Me")
                    sectionBody(tinyNudgeResponse.encouragement)

                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(height: 1)

                    sectionLabel("Reduce Friction")
                    sectionBody(tinyNudgeResponse.frictionSuggestion)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            }

            if let tinyNudgeError {
                Text(tinyNudgeError)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(lureliaHex: "#ff9be6"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(lureliaHex: "#ff9be6").opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func saveFriction() {
        habit.friction = frictionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.updatedAt = Date()
        try? modelContext.save()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            frictionEditing = false
            frictionDraft = ""
        }
    }

    private func undoLatestCompletionToday() {
        let calendar = Calendar.current
        let today = Date()
        guard let todayLog = habit.todaysLog(calendar: calendar) else { return }
        todayLog.habitIDString = habit.id.uuidString

        let didUndo = todayLog.undoLatestCompletion(
            fireDates: habit.fireDates(on: today, calendar: calendar),
            calendar: calendar
        )
        guard didUndo else { return }

        if todayLog.count <= 0 && todayLog.completedFireTimes.isEmpty {
            modelContext.delete(todayLog)
            habit.logs = (habit.logs ?? []).filter {
                $0.persistentModelID != todayLog.persistentModelID
            }
        } else {
            habit.logs = (habit.logs ?? []).map { log in
                log.persistentModelID == todayLog.persistentModelID ? todayLog : log
            }
        }

        habit.updatedAt = Date()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            try? modelContext.save()
        }

        LureliaWidgetReloads.reloadAll()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func numberedCircle(_ number: Int) -> some View {
        ZStack {
            Circle()
                .strokeBorder(accent, lineWidth: 1.5)
                .frame(width: 26, height: 26)

            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
    
    private func levelRow(_ level: LureliaHabitLevel) -> some View {
        let iconNumber = (level.sortOrder + 1) % 10

        return HStack(spacing: 12) {

            Image("\(iconNumber)wavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(accentStyle)

            Text(level.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.055))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(
                .white.opacity(0.09),
                lineWidth: 1
            )
        )
    }

    private func detailPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private var scheduleSummary: String {
        let weekdays = habit.activeWeekdays
        if weekdays.count == 7 { return "Every day" }
        let labels: [Int: String] = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        return weekdays.sorted().compactMap { labels[$0] }.joined(separator: ", ")
    }

    private var alarmSummary: String {
        guard habit.alarmEnabled else { return "Alarm Off" }
        let storedAlarmCount = Set(
            habit.alarmFireTimes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        .filter { !$0.isEmpty }
        .count
        let count = storedAlarmCount > 0 ? storedAlarmCount : min(max(habit.timesOfDay.count, 1), 1)
        return count == 1 ? "1 alarm" : "\(count) alarms"
    }
    
    private var sortedLevels: [LureliaHabitLevel] {
        habit.levels
            .filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted {
                $0.sortOrder < $1.sortOrder
            }
    }

    private struct CueCountEntry {
        let type: LureliaCueType
        let count: Int
    }

    private func computeCueCounts(from habits: [LureliaHabit]) -> [CueCountEntry] {
        var counts: [LureliaCueType: Int] = [:]
        for h in habits {
            if let ct = h.cueType {
                counts[ct, default: 0] += 1
            }
        }
        return counts
            .map { CueCountEntry(type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private let weekdayList: [(value: Int, short: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]
}

// MARK: - Icon Preview

private struct BlueprintIconPreview: View {
    let iconName: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.22))
                .frame(width: 48, height: 48)

            Circle()
                .strokeBorder(tint, lineWidth: 1.15)
                .frame(width: 48, height: 48)

            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(.white)
        }
    }
}
