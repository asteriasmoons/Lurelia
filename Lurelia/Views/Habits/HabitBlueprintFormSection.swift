//
//  HabitBlueprintFormSection.swift
//  Lurelia
//

import SwiftUI

struct HabitBlueprintFormSection: View {
    @Environment(\.appTheme) private var theme

    @Binding var identityStatement: String
    @Binding var habitPurpose: String
    @Binding var implementationIntention: String
    @Binding var selectedCueType: LureliaCueType?
    @Binding var cueDescription: String
    @Binding var cueReason: String
    @Binding var currentEnvironment: String
    @Binding var idealEnvironment: String
    @Binding var environmentChanges: String
    @Binding var temptationNeed: String
    @Binding var temptationWant: String
    @Binding var habitRules: [String]
    @Binding var habitObstacles: [String]
    @Binding var habitSolutions: [String]
    @Binding var levels: [LureliaHabitLevel]
    @Binding var immediateReward: String
    @Binding var longTermReward: String
    var tint: Color? = nil

    @State private var newRule = ""
    @State private var newObstacle = ""
    @State private var newSolution = ""
    @State private var newLevel = ""

    private var resolvedTint: Color {
        tint ?? theme.palette.primaryAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            sectionHeader("HABIT BLUEPRINT")

            // MARK: - Identity

            subsectionLabel("IDENTITY")
            blueprintCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Who am I becoming?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                    blueprintTextField(
                        placeholder: "e.g. I am someone who takes care of my skin every day.",
                        text: $identityStatement
                    )
                }
            }

            // MARK: - Purpose

            subsectionLabel("PURPOSE")
            blueprintCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Why does this habit exist?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                    blueprintTextField(
                        placeholder: "e.g. Healthy skin and a consistent morning routine.",
                        text: $habitPurpose
                    )
                }
            }

            // MARK: - Implementation Intention

            subsectionLabel("IMPLEMENTATION INTENTION")
            blueprintCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Write a clear when/where plan for this habit.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                    blueprintTextArea(
                        placeholder: "e.g. I will wash my face in the morning before I sit down at 8AM in the bathroom.",
                        text: $implementationIntention
                    )
                }
            }

            // MARK: - Cue

            subsectionLabel("CUE")

            VStack(alignment: .leading, spacing: 10) {
                Text("Cue Type")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                cueTypeGrid
            }

            blueprintCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What reminds you to begin this habit?")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                    blueprintTextField(
                        placeholder: "e.g. Headband sitting on top of my laptop.",
                        text: $cueDescription
                    )
                }
            }

            blueprintCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Why This Cue Works")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                    blueprintTextArea(
                        placeholder: "e.g. Because I always reach for my laptop immediately after waking up.",
                        text: $cueReason
                    )
                }
            }

            // MARK: - Environment

            subsectionLabel("ENVIRONMENT")

            blueprintCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Environment")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text("What does your current environment encourage?")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                        blueprintTextField(placeholder: "", text: $currentEnvironment)
                    }

                    Rectangle().fill(resolvedTint).frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ideal Environment")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text("What should the environment support instead?")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                        blueprintTextField(placeholder: "", text: $idealEnvironment)
                    }

                    Rectangle().fill(resolvedTint).frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Changes to Make")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                        Text("What small changes would make this habit easier?")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)
                        blueprintTextField(placeholder: "", text: $environmentChanges)
                    }
                }
            }
            
            // MARK: - Temptation Bundling

            subsectionLabel("TEMPTATION BUNDLING")

            blueprintCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Need")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)

                        Text("What do you need to do?")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)

                        blueprintTextField(
                            placeholder: "e.g. Read for 20 minutes.",
                            text: $temptationNeed
                        )
                    }

                    Rectangle()
                        .fill(resolvedTint)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Want")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)

                        Text("What do you want to do after or during it?")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textSecondary)

                        blueprintTextField(
                            placeholder: "e.g. Drink coffee or code guilt free.",
                            text: $temptationWant
                        )
                    }
                }
            }

            // MARK: - Rules

            subsectionLabel("HABIT RULES")
            VStack(alignment: .leading, spacing: 10) {
                listInputSurface {
                    TextField("Type a habit rule", text: $newRule)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(addRule)

                    addButton(accessibilityLabel: "Add rule", action: addRule)
                }

                ForEach(Array(habitRules.enumerated()), id: \.offset) { index, rule in
                    listResultSurface {
                        Text(rule)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        removeButton(accessibilityLabel: "Delete rule") {
                            habitRules.remove(at: index)
                        }
                    }
                }
            }

            // MARK: - Obstacles & Solutions

            subsectionLabel("OBSTACLES & SOLUTIONS")
            VStack(alignment: .leading, spacing: 10) {
                listInputSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Obstacle", text: $newObstacle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)

                        Rectangle()
                            .fill(resolvedTint)
                            .frame(height: 1)

                        TextField("Solution", text: $newSolution)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                            .submitLabel(.done)
                            .onSubmit(addObstacle)
                    }

                    addButton(accessibilityLabel: "Add obstacle", action: addObstacle)
                }

                ForEach(Array(habitObstacles.enumerated()), id: \.offset) { index, obstacle in
                    listResultSurface {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(obstacle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.black)

                            if index < habitSolutions.count,
                               !habitSolutions[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(habitSolutions[index])
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.black.opacity(0.72))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        removeButton(accessibilityLabel: "Delete obstacle") {
                            habitObstacles.remove(at: index)
                            if index < habitSolutions.count {
                                habitSolutions.remove(at: index)
                            }
                        }
                    }
                }
            }
            
            // MARK: - Habit Levels

            subsectionLabel("HABIT LEVELS")

            VStack(alignment: .leading, spacing: 10) {
                listInputSurface {
                    TextField("Type a habit level", text: $newLevel)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)
                        .submitLabel(.done)
                        .onSubmit(addLevel)

                    addButton(accessibilityLabel: "Add level", action: addLevel)
                }

                ForEach(Array(levels.enumerated()), id: \.element.id) { index, level in
                    listResultSurface {
                        Text(level.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        removeButton(accessibilityLabel: "Delete level") {
                            levels.remove(at: index)
                            normalizeLevelSortOrder()
                        }
                    }
                }
            }

            // MARK: - Rewards

            subsectionLabel("REWARDS")
            blueprintCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Immediate Reward")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                        blueprintTextField(
                            placeholder: "e.g. Fresh coffee, clean feeling, ten minutes of reading.",
                            text: $immediateReward
                        )
                    }

                    Rectangle().fill(resolvedTint).frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Long-Term Reward")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                        blueprintTextField(
                            placeholder: "e.g. Healthy skin, consistency, confidence.",
                            text: $longTermReward
                        )
                    }
                }
            }
        }
    }

    // MARK: - Cue Type Grid

    private var cueTypeGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(LureliaCueType.allCases) { cueType in
                let isSelected = selectedCueType == cueType
                Button {
                    if selectedCueType == cueType {
                        selectedCueType = nil
                    } else {
                        selectedCueType = cueType
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(cueType.iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .bubblyIconMaterial(
                                tint: .black,
                                isEnabled: isSelected
                            )
                            .overlay {
                                if isSelected {
                                    Image(cueType.iconName)
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(Color.black.opacity(0.58))
                                }
                            }

                        Text(cueType.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color.black : theme.palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            BubblyIconMaterial(tint: resolvedTint)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.palette.surface)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected ? resolvedTint : theme.palette.textPrimary.opacity(0.12),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image("linedpages")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(resolvedTint)
                .bubblyIconMaterial(tint: resolvedTint)

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textSecondary)
                .tracking(0.8)
        }
    }

    private func subsectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.palette.textSecondary)
            .tracking(0.6)
    }

    private func blueprintTextField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(theme.palette.textPrimary)
    }

    private func blueprintTextArea(placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary.opacity(0.55))
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }
            TextEditor(text: text)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70)
        }
    }

    private func blueprintCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.palette.surface,
                in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                    .strokeBorder(resolvedTint, lineWidth: 1)
            }
    }

    private func listInputSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            theme.palette.surface,
            in: RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                .strokeBorder(resolvedTint, lineWidth: 1)
        }
    }

    private func listResultSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            BubblyCardMaterial(
                tint: resolvedTint,
                cornerRadius: 14
            )
        }
    }

    private func addButton(
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image("addwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(resolvedTint)
                .bubblyIconMaterial(tint: resolvedTint)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func removeButton(
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image("xmarkwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(.black)
                .bubblyIconMaterial(tint: .black)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func addRule() {
        let trimmed = newRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        habitRules.append(trimmed)
        newRule = ""
    }

    private func addObstacle() {
        let obstacle = newObstacle.trimmingCharacters(in: .whitespacesAndNewlines)
        let solution = newSolution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !obstacle.isEmpty else { return }
        habitObstacles.append(obstacle)
        habitSolutions.append(solution)
        newObstacle = ""
        newSolution = ""
    }

    private func addLevel() {
        let title = newLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, levels.count < 9 else { return }
        levels.append(
            LureliaHabitLevel(
                title: title,
                sortOrder: levels.count
            )
        )
        newLevel = ""
    }

    private func normalizeLevelSortOrder() {
        for index in levels.indices {
            levels[index].sortOrder = index
            levels[index].updatedAt = Date()
        }
    }

}
