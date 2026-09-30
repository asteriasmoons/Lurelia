//
//  PracticeDetailView.swift
//  Lurelia
//

import SwiftUI
import SwiftData

struct PracticeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var practice: LureliaPractice
    
    @Query(sort: \LureliaRoutine.sortOrder)
    private var allRoutines: [LureliaRoutine]
    
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showCompletionBanner = false
    @State private var bannerMessage = "Done!"
    
    private var practiceTint: Color {
        Color(lureliaHex: practice.colorHex)
    }
    
    private var adaptiveTextColor: Color {
        practiceTint.isLightColor ? .black.opacity(0.88) : .white
    }
    
    private var adaptiveSecondaryTextColor: Color {
        practiceTint.isLightColor ? .black.opacity(0.62) : .white.opacity(0.72)
    }
    
    private var linkedRoutines: [LureliaRoutine] {
        let practiceIDString = practice.id.uuidString
        return allRoutines
            .filter { $0.practiceID == practiceIDString }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private var progress: Double {
        guard !linkedRoutines.isEmpty else { return 0 }
        var totalTasks = 0
        var completedTasks = 0
        for routine in linkedRoutines {
            let tasks = routine.tasks ?? []
            totalTasks += tasks.count
            completedTasks += tasks.filter { $0.isCompleted || $0.isSkipped }.count
        }
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }
    
    private var totalTaskCount: Int {
        linkedRoutines.reduce(0) { $0 + ($1.tasks ?? []).count }
    }
    
    private var scheduledRoutines: [LureliaRoutine] {
        linkedRoutines.filter { $0.scheduleEnabled && !$0.scheduledDays.isEmpty }
    }
    
    var body: some View {
        ZStack {
            LureliaBackgroundAlt()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    customHeader
                    heroCard
                    statsGrid
                    
                    if !practice.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        purposeCard
                    }
                    
                    if !practice.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        descriptionCard
                    }
                    
                    if !practice.principles.isEmpty {
                        principlesCard
                    }
                    
                    if !scheduledRoutines.isEmpty {
                        weekdaysCard
                    }
                    
                    routinesCard
                    deleteButton
                    
                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEdit) {
            AddPracticeView(editingPractice: practice)
        }
        .alert("Delete Practice", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deletePractice() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the practice but keep all linked routines.")
        }
        .completionBanner(isShowing: showCompletionBanner, message: bannerMessage)
    }
    
    private func triggerBanner(_ message: String) {
        bannerMessage = message
        showCompletionBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCompletionBanner = false
        }
    }
}

// MARK: - Header + Hero

extension PracticeDetailView {
    
    private var customHeader: some View {
        HStack(spacing: 12) {
            Text(practice.title)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(practiceTint)
                .lineLimit(2)
            
            Spacer()
            
            Button {
                showEdit = true
            } label: {
                Image("settings")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(adaptiveTextColor)
                    .frame(width: 40, height: 40)
                    .background(practiceTint, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            
            Button {
                dismiss()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(adaptiveTextColor)
                    .frame(width: 40, height: 40)
                    .background(practiceTint, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }
    
    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(practiceTint.opacity(0.18))
                    .frame(width: 78, height: 78)
                    .overlay(
                        Circle().strokeBorder(LColors.glassBorderStrong, lineWidth: 1)
                    )
                
                Circle()
                    .fill(practiceTint.opacity(0.24))
                    .frame(width: 54, height: 54)
                    .blur(radius: 16)
                
                LureliaIconView(iconId: practice.icon, size: 34)
                    .foregroundStyle(adaptiveTextColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(practice.title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(adaptiveTextColor)
                    .lineLimit(2)
                
                if !practice.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(practice.purpose)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(adaptiveSecondaryTextColor)
                        .lineLimit(2)
                }
                
                Text("\(linkedRoutines.count) routine\(linkedRoutines.count == 1 ? "" : "s") · \(totalTaskCount) task\(totalTaskCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(adaptiveSecondaryTextColor)
            }
            
            Spacer()
            
            DottedProgressRing(
                progress: progress,
                size: 56,
                dotCount: 24,
                dotDiameter: 4,
                trackColor: adaptiveTextColor.opacity(0.18),
                fillColor: adaptiveTextColor
            ) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(adaptiveTextColor)
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LColors.glassSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(practiceTint.opacity(0.30))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(practiceTint.opacity(0.55), lineWidth: 1.1)
                }
        }
        .shadow(color: practiceTint.opacity(0.16), radius: 18, x: 0, y: 10)
    }
    
    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            statCard(value: "\(linkedRoutines.count)", label: "Routines")
            statCard(value: "\(totalTaskCount)", label: "Tasks")
            statCard(value: "\(Int(progress * 100))%", label: "Progress")
        }
    }
}

// MARK: - Content Cards

extension PracticeDetailView {
    
    private var purposeCard: some View {
        sectionCard(title: "Purpose", icon: "sparkle") {
            Text(practice.purpose)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(adaptiveTextColor)
        }
    }
    
    private var descriptionCard: some View {
        sectionCard(title: "Description", icon: "starlinesdoc") {
            Text(practice.descriptionText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(adaptiveTextColor)
        }
    }
    
    private var principlesCard: some View {
        sectionCard(title: "Principles", icon: "balancewavy") {
            VStack(spacing: 12) {
                ForEach(practice.principles.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(practiceTint.opacity(0.18))
                                .frame(width: 34, height: 34)
                            
                            Circle()
                                .strokeBorder(practiceTint.opacity(0.8), lineWidth: 1.5)
                                .frame(width: 34, height: 34)
                            
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(adaptiveTextColor)
                        }
                        
                        Text(practice.principles[index])
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(adaptiveTextColor)
                        
                        Spacer()
                    }
                    
                    if index < practice.principles.count - 1 {
                        divider
                    }
                }
            }
        }
    }
    
    private var weekdaysCard: some View {
        sectionCard(title: "Weekdays", icon: "starcal") {
            VStack(spacing: 0) {
                ForEach(Array(scheduledRoutines.enumerated()), id: \.element.id) { index, routine in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            LureliaIconView(iconId: routine.icon, size: 14)
                                .foregroundStyle(adaptiveTextColor)
                            
                            Text(routine.name)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(adaptiveTextColor)
                        }
                        
                        HStack(spacing: 6) {
                            ForEach(routine.scheduledDays.sorted(), id: \.self) { weekday in
                                ZStack {
                                    Circle()
                                        .fill(practiceTint.opacity(0.18))
                                        .frame(width: 30, height: 30)
                                    
                                    Circle()
                                        .strokeBorder(practiceTint.opacity(0.6), lineWidth: 1)
                                        .frame(width: 30, height: 30)
                                    
                                    Text(shortWeekdayLabel(for: weekday))
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundStyle(adaptiveTextColor)
                                }
                            }
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            pillCapsule(icon: "clockfill", text: routine.formattedTimeRange)
                            pillCapsule(icon: "hourglassfill", text: "\(routine.durationMinutes)m")
                        }
                    }
                    .padding(.vertical, 10)
                    
                    if index < scheduledRoutines.count - 1 {
                        divider
                    }
                }
            }
        }
    }
    
    private var routinesCard: some View {
        sectionCard(title: "Routines", icon: "wand") {
            if linkedRoutines.isEmpty {
                emptySectionText("No routines linked to this practice yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(linkedRoutines.enumerated()), id: \.element.id) { index, routine in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(lureliaHex: routine.colorHex).opacity(0.2))
                                    .frame(width: 38, height: 38)
                                
                                Circle()
                                    .strokeBorder(
                                        Color(lureliaHex: routine.colorHex).opacity(0.8),
                                        lineWidth: 1.5
                                    )
                                    .frame(width: 38, height: 38)
                                
                                LureliaIconView(iconId: routine.icon, size: 17)
                                    .foregroundStyle(Color(lureliaHex: routine.colorHex))
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(routine.name)
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(
                                        routine.allTasksDone
                                        ? adaptiveSecondaryTextColor
                                        : adaptiveTextColor
                                    )
                                    .strikethrough(routine.allTasksDone, color: adaptiveSecondaryTextColor)
                                
                                Text("\((routine.tasks ?? []).count) tasks · \(routine.formattedDuration)")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(adaptiveSecondaryTextColor)
                                
                                if routine.allTasksDone {
                                    HStack(spacing: 4) {
                                        Image("checkwavy")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 9, height: 9)
                                        Text("Completed")
                                            .font(.system(size: 9, weight: .black, design: .rounded))
                                    }
                                    .foregroundStyle(adaptiveTextColor)
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        if routine.allTasksDone {
                                            let now = Date()
                                            routine.resetTaskStates()
                                            for task in routine.sortedTasks {
                                                LureliaRoutineTaskOccurrenceNotifications.restorePendingOccurrence(
                                                    for: task,
                                                    on: now,
                                                    now: now
                                                )
                                                LureliaRoutineTaskOccurrenceAlarms.restorePendingOccurrence(
                                                    for: task,
                                                    on: now,
                                                    now: now
                                                )
                                            }
                                        } else {
                                            RoutineManager.shared.completeRoutine(
                                                routine,
                                                context: modelContext
                                            )
                                        }
                                        try? modelContext.save()
                                    }
                                    triggerBanner(
                                        routine.allTasksDone
                                        ? "Tasks reset!"
                                        : "\(routine.name) completed!"
                                    )
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                routine.allTasksDone
                                                ? practiceTint.opacity(0.18)
                                                : Color.clear
                                            )
                                        
                                        Circle()
                                            .strokeBorder(practiceTint.opacity(0.75), lineWidth: 1.5)
                                        
                                        if routine.allTasksDone {
                                            Image("checkwavy")
                                                .renderingMode(.template)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 10, height: 10)
                                                .foregroundStyle(practiceTint)
                                        }
                                    }
                                    .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                
                                if !routine.allTasksDone {
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                            let now = Date()
                                            let pendingTasks = routine.sortedTasks.filter(\.isPending)
                                            routine.skipRoutine()
                                            for task in pendingTasks {
                                                LureliaRoutineTaskOccurrenceNotifications.cancelPendingOccurrence(
                                                    for: task,
                                                    on: now,
                                                    now: now
                                                )
                                                LureliaRoutineTaskOccurrenceAlarms.cancelPendingOccurrence(
                                                    for: task,
                                                    on: now,
                                                    now: now
                                                )
                                            }
                                            try? modelContext.save()
                                        }
                                        triggerBanner("\(routine.name) skipped")
                                    } label: {
                                        Image("skipwavy")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .foregroundStyle(adaptiveSecondaryTextColor)
                                            .frame(width: 28, height: 28)
                                            .background(LColors.glassSurface2, in: Circle())
                                            .overlay(
                                                Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                            let now = Date()
                                            routine.resetTaskStates()
                                            for task in routine.sortedTasks {
                                                LureliaRoutineTaskOccurrenceNotifications.restorePendingOccurrence(
                                                    for: task,
                                                    on: now,
                                                    now: now
                                                )
                                                LureliaRoutineTaskOccurrenceAlarms.restorePendingOccurrence(
                                                    for: task,
                                                    on: now,
                                                    now: now
                                                )
                                            }
                                            try? modelContext.save()
                                        }
                                        triggerBanner("Tasks reset!")
                                    } label: {
                                        Image("repeatfill")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .foregroundStyle(adaptiveSecondaryTextColor)
                                            .frame(width: 28, height: 28)
                                            .background(LColors.glassSurface2, in: Circle())
                                            .overlay(
                                                Circle().strokeBorder(LColors.glassBorder.opacity(0.75), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 11)
                        
                        if index < linkedRoutines.count - 1 {
                            divider
                        }
                    }
                }
            }
        }
    }
    
    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            Text("Delete Practice")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(LColors.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LColors.danger.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: LSpacing.cardRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LSpacing.cardRadius)
                        .strokeBorder(LColors.danger.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Components

extension PracticeDetailView {
    
    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveTextColor)
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveSecondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LColors.glassSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(practiceTint.opacity(0.22))
                }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(practiceTint.opacity(0.50), lineWidth: 1.05)
        )
    }
    
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Group {
                    if UIImage(named: icon) != nil {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .foregroundStyle(practiceTint)
                .frame(width: 15, height: 15)
                
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(practiceTint)
                
                Spacer()
            }
            
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LColors.glassSurface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(practiceTint.opacity(0.22))
                        }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(practiceTint.opacity(0.50), lineWidth: 1.05)
                )
        }
    }
    
    private func pillCapsule(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Group {
                if UIImage(named: icon) != nil {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: icon)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 11, height: 11)
            .foregroundStyle(practiceTint)
            
            Text(text)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(adaptiveSecondaryTextColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(practiceTint.opacity(0.18), in: Capsule())
        .overlay(
            Capsule().strokeBorder(practiceTint.opacity(0.45), lineWidth: 1)
        )
    }
    
    private func emptySectionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(adaptiveSecondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
    
    private func shortWeekdayLabel(for weekday: Int) -> String {
        guard weekday >= 1 && weekday <= 7 else { return "--" }
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }
    
    private var divider: some View {
        Divider().overlay(LColors.glassBorder)
    }
    
    private func deletePractice() {
        let practiceIDString = practice.id.uuidString
        for routine in allRoutines where routine.practiceID == practiceIDString {
            routine.practiceID = nil
            routine.updatedAt = Date()
        }
        modelContext.delete(practice)
        try? modelContext.save()
        dismiss()
    }
}
