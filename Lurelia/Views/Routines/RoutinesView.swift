//
//  RoutinesView.swift
//  Lurelia
//

import SwiftUI
import SwiftData
import WidgetKit

struct RoutinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme

    @Query(sort: \LureliaRoutine.sortOrder)
    private var routines: [LureliaRoutine]

    @State private var activeRoutine: LureliaRoutine? = nil
    @State private var routineColorSelection: RoutineEditorLaunchRequest?
    @State private var queuedRoutineEditor: RoutineEditorLaunchRequest?
    @State private var routineEditor: RoutineEditorLaunchRequest?
    @State private var showTemplateLibrary = false
    @State private var showContracts = false

    /// Explicit navigation path shared by routine and task detail destinations.
    @State private var navPath: [PersistentIdentifier] = []

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                LureliaBackgroundAlt()

                GeometryReader { proxy in
                    let gridSpacing: CGFloat = 12
                    let gridWidth = max(0, proxy.size.width - 48)
                    let cardWidth = max(0, (gridWidth - gridSpacing) / 2)
                    let columns = [
                        GridItem(.fixed(cardWidth), spacing: gridSpacing),
                        GridItem(.fixed(cardWidth), spacing: 0)
                    ]

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {

                            // MARK: - Header

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Routines")
                                        .font(.system(size: 30, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("Build flexible flows you can start, pause, and complete.")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.5))
                                }

                                Spacer()

                                Button {
                                    showContracts = true
                                } label: {
                                    Image("stardoc")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 25, height: 25)
                                        .foregroundStyle(.white)
                                        .bubblyIconMaterial(tint: theme.palette.primaryAction)
                                        .padding(.trailing, 6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("My Contracts")

                                Button {
                                    showTemplateLibrary = true
                                } label: {
                                    Image("cardlines")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 26, height: 26)
                                        .foregroundStyle(.white)
                                        .bubblyIconMaterial(tint: theme.palette.secondaryAccent)
                                        .padding(.trailing, 6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Task Templates")

                                Button {
                                    beginRoutineEditor(for: nil)
                                } label: {
                                    Image("addwavy")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundStyle(.white)
                                        .bubblyIconMaterial(tint: theme.palette.indicators)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 20)

                            if routines.isEmpty {
                                emptyState
                            } else {
                                LazyVGrid(columns: columns, spacing: 14) {
                                    ForEach(routines) { routine in
                                        NavigationLink(value: routine.id) {
                                            RoutineCard(
                                                routine: routine,
                                                onRun: {
                                                    if let run = routine.activeRun, run.isPaused {
                                                        RoutineManager.shared.resumeRun(
                                                            run: run,
                                                            routine: routine
                                                        )
                                                    }

                                                    activeRoutine = routine
                                                },
                                                onPause: {
                                                    if let run = routine.activeRun {
                                                        RoutineManager.shared.pauseRun(
                                                            run: run,
                                                            routine: routine
                                                        )
                                                    }
                                                },
                                                onStop: {
                                                    if let run = routine.activeRun {
                                                        RoutineManager.shared.finishRun(
                                                            run: run,
                                                            routine: routine,
                                                            wasCompleted: false
                                                        )
                                                    }
                                                },
                                                onEdit: {
                                                    beginRoutineEditor(for: routine)
                                                },
                                                fixedWidth: cardWidth
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: cardWidth, height: RoutineCard.cardHeight)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deleteRoutine(routine)
                                            } label: {
                                                Label("Delete Routine", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .frame(width: gridWidth)
                            }
                        }
                        .padding(.bottom, 120)
                        .frame(width: proxy.size.width, alignment: .top)
                    }
                    .routinePageScrollClipped()
                }
            }
            .sheet(item: $routineColorSelection, onDismiss: presentQueuedRoutineEditor) { request in
                RoutineColorSelectionSheet(initialColor: request.color) { color in
                    queuedRoutineEditor = RoutineEditorLaunchRequest(
                        routine: request.routine,
                        color: color
                    )
                }
            }
            .sheet(item: $routineEditor) { request in
                AddRoutineView(
                    editingRoutine: request.routine,
                    initialColor: request.color
                )
            }
            .sheet(isPresented: $showTemplateLibrary) {
                RoutineTaskTemplateLibraryView()
            }
            .sheet(isPresented: $showContracts) {
                RoutineContractsView()
            }
            .fullScreenCover(item: $activeRoutine) { routine in
                RoutineRunView(routine: routine)
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if routines.contains(where: { $0.id == id }) {
                    RoutineDetailView(routineID: id)
                } else if let task = routines.flatMap({ $0.tasks ?? [] }).first(where: { $0.id == id }) {
                    RoutineTaskDetailView(
                        task: task,
                        routineTint: task.routine.map { Color(lureliaHex: $0.colorHex) } ?? LColors.gradientPurple
                    )
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    refreshOnForeground()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshOnForeground()
            }
        }
    }

    /// Let SwiftData process external mutations without rebuilding the
    /// NavigationStack or resetting the scroll position.
    private func refreshOnForeground() {
        modelContext.processPendingChanges()
    }

    private func beginRoutineEditor(for routine: LureliaRoutine?) {
        queuedRoutineEditor = nil
        routineColorSelection = RoutineEditorLaunchRequest(
            routine: routine,
            color: routine.map { Color(lureliaHex: $0.colorHex) } ?? theme.palette.primaryAction
        )
    }

    private func presentQueuedRoutineEditor() {
        guard let queuedRoutineEditor else { return }
        self.queuedRoutineEditor = nil
        routineEditor = queuedRoutineEditor
    }

    private func deleteRoutine(_ routine: LureliaRoutine) {
        if activeRoutine?.persistentID == routine.persistentID {
            activeRoutine = nil
        }

        if routineColorSelection?.routine?.persistentID == routine.persistentID {
            routineColorSelection = nil
        }

        if queuedRoutineEditor?.routine?.persistentID == routine.persistentID {
            queuedRoutineEditor = nil
        }

        if routineEditor?.routine?.persistentID == routine.persistentID {
            routineEditor = nil
        }

        modelContext.delete(routine)
        try? modelContext.save()
        LureliaWidgetReloads.reloadDueRoutines()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 80)

            Image("qwill")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(LColors.textPrimary)

            Text("No routines yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(LColors.textSecondary)

            Text("Tap + to build your first routine")
                .font(.subheadline)
                .foregroundStyle(LColors.textSecondary.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
