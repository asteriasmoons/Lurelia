//
//  MainTabView.swift
//  Lurelia

import SwiftUI
import SwiftData
import UIKit

struct RoutineWrapper: Identifiable {
    let id = UUID()
    let routine: LureliaRoutine
}

enum LureliaTab: CaseIterable {
    case reminders
    case kantime
    case schedule
    case events
    case habits
    case journeys
    case routines
    case profile

    static let primaryTabs: [LureliaTab] = [
        .kantime,
        .routines,
        .habits,
        .events
    ]

    static let overflowTabs: [LureliaTab] = [
        .reminders,
        // .journeys,
        .profile,
        .schedule
    ]

    var icon: String {
        switch self {
        case .kantime:
            return "ringstarcal"
        case .reminders:
            return "bellfill"
        case .schedule:
            return "starnote"
        case .events:
            return "starmailing"
        case .habits:
            return "repeatfill"
        case .journeys:
            return "journey"
        case .routines:
            return "clockwavy"
        case .profile:
            return "profilewavy"
        }
    }

    var title: String {
        switch self {
        case .kantime:
            return "Timeline"
        case .reminders:
            return "Reminders"
        case .schedule:
            return "Kanban"
        case .events:
            return "Events"
        case .habits:
            return "Habits"
        case .journeys:
            return "Journeys"
        case .routines:
            return "Routines"
        case .profile:
            return "Profile"
        }
    }
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: LureliaTab = .kantime
    @State private var activeRoutineToOpen: RoutineWrapper?
    @State private var showingReleaseNotes = false
    
    @Query private var settings: [UserSettings]
    @Query private var routineRuns: [LureliaRoutineRun]
    
    private var activeRoutineRun: LureliaRoutineRun? {
        routineRuns.first { $0.endedAt == nil }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LureliaBackgroundAlt()
                .ignoresSafeArea()

            selectedTabView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 120)
                }

            VStack(spacing: 12) {
                if let activeRoutineRun {
                    ActiveRoutineBanner(run: activeRoutineRun) {
                        if let routine = activeRoutineRun.routine {
                            activeRoutineToOpen = RoutineWrapper(routine: routine)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                LureliaTabBar(selectedTab: $selectedTab)
                    .padding(.bottom, 4)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(item: $activeRoutineToOpen) { wrapper in
            RoutineRunView(routine: wrapper.routine)
        }
        .adaptiveReleaseNotesPresentation(
            isPresented: $showingReleaseNotes,
            useFullScreenCover: horizontalSizeClass == .regular,
            onDismiss: markLatestReleaseNoteSeen
        ) {
            ReleaseNotesPage()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .task {
            presentReleaseNotesIfNeeded()
        }
        .onChange(of: selectedTab) { _, newTab in
            guard newTab == .kantime else { return }
            presentReleaseNotesIfNeeded()
        }
    }

    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .kantime:
            KanbanTimelineView()
        case .reminders:
            RemindersView()
        case .schedule:
            ScheduleView()
        case .events:
            LureliaEventsView()
        case .habits:
            HabitsView()
        case .journeys:
            JourneysView()
        case .routines:
            RoutinesView()
        case .profile:
            ProfileView()
        }
    }

    private func presentReleaseNotesIfNeeded() {
        guard selectedTab == .kantime,
              !showingReleaseNotes,
              let userSettings = settings.first,
              let latestReleaseNoteID = ReleaseNotesCatalog.notes.first?.id,
              latestReleaseNoteID != userSettings.lastSeenReleaseNoteID
        else {
            return
        }

        showingReleaseNotes = true
    }

    private func markLatestReleaseNoteSeen() {
        guard let latestReleaseNoteID = ReleaseNotesCatalog.notes.first?.id,
              let userSettings = settings.first,
              userSettings.lastSeenReleaseNoteID != latestReleaseNoteID
        else {
            return
        }

        userSettings.lastSeenReleaseNoteID = latestReleaseNoteID
        userSettings.updatedAt = Date()
        try? modelContext.save()
    }
}

private extension View {
    @ViewBuilder
    func adaptiveReleaseNotesPresentation<Content: View>(
        isPresented: Binding<Bool>,
        useFullScreenCover: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if useFullScreenCover {
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        } else {
            sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        }
    }
}

// MARK: - Floating Tab Bar

struct LureliaTabBar: View {
    @Binding var selectedTab: LureliaTab

    @Environment(\.appTheme) private var theme

    @State private var showMoreTabs = false

    private var primaryTabs: [LureliaTab] {
        LureliaTab.primaryTabs
    }

    private var overflowTabs: [LureliaTab] {
        LureliaTab.overflowTabs
    }

    private var leadingTabs: [LureliaTab] {
        Array(primaryTabs.prefix(2))
    }

    private var trailingTabs: [LureliaTab] {
        Array(primaryTabs.dropFirst(2))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if showMoreTabs && !overflowTabs.isEmpty {
                moreTabsMenu
                    .frame(maxWidth: 280)
                    .padding(.bottom, 116)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            tabControlRow
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background {
                Capsule()
                    .fill(theme.palette.background)
                    .overlay {
                        Capsule()
                            .strokeBorder(theme.palette.primaryAction, lineWidth: 1)
                    }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 42)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: showMoreTabs)
    }

    private var tabControlRow: some View {
        tabControls
    }

    private var tabControls: some View {
        HStack(spacing: 10) {
            ForEach(leadingTabs, id: \.self) { tab in
                tabButton(tab)
            }

            centerAddButton

            ForEach(trailingTabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: LureliaTab) -> some View {
        let tint = tabTint(for: tab)

        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                selectedTab = tab
                showMoreTabs = false
            }
        } label: {
            Image(tab.icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .bubblyIconMaterial(tint: tint)
                .frame(width: 42, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var centerAddButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                showMoreTabs.toggle()
            }
        } label: {
            Image("addwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .bubblyIconMaterial(tint: theme.palette.indicators)
                .rotationEffect(.degrees(showMoreTabs ? 45 : 0))
                .frame(width: 54, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(overflowTabs.isEmpty)
        .opacity(overflowTabs.isEmpty ? 0.45 : 1)
    }

    private func tabTint(for tab: LureliaTab) -> Color {
        guard let tabIndex = primaryTabs.firstIndex(of: tab) else {
            return theme.palette.primaryAction
        }

        let displayedIndex = tabIndex < 2 ? tabIndex : tabIndex + 1
        let rotation = theme.palette.rotation
        return rotation[displayedIndex % rotation.count]
    }

    private var moreTabsMenu: some View {
        moreTabsContent
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.palette.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(theme.palette.primaryAction, lineWidth: 1)
                }
        }
    }

    private var moreTabsContent: some View {
        VStack(spacing: 6) {
            ForEach(overflowTabs, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        selectedTab = tab
                        showMoreTabs = false
                    }
                } label: {
                    moreTabRow(tab)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moreTabRow(_ tab: LureliaTab) -> some View {
        let tint = overflowTabTint(for: tab)

        return HStack(spacing: 12) {
            Image(tab.icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .bubblyIconMaterial(tint: tint)
                .frame(width: 34, height: 34)

            Text(tab.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(LColors.textPrimary)

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            if selectedTab == tab {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LColors.neutralGlassHighlight.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(LColors.neutralGlassHighlight.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }

    private func overflowTabTint(for tab: LureliaTab) -> Color {
        guard let tabIndex = overflowTabs.firstIndex(of: tab) else {
            return theme.palette.primaryAction
        }

        let rotation = theme.palette.rotation
        return rotation[tabIndex % rotation.count]
    }
}

// MARK: - Placeholder Tab View

struct PlaceholderTabView: View {
    let icon: String
    let title: String
    var isSF: Bool = false
    
    var body: some View {
        ZStack {
            LureliaBackgroundAlt()
            
            VStack(spacing: 16) {
                if isSF {
                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    Color.white.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    Color.white.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Coming soon")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}
