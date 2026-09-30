//
//  ContentView.swift
//  Lurelia
//
//  Created by Asteria Moon on 5/16/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var reportRouter: LureliaReportRouter
    @Query private var settings: [UserSettings]

    var body: some View {
        ZStack {
            if let userSettings = settings.first,
               userSettings.hasCompletedOnboarding,
               !userSettings.shouldReplayOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onOpenURL { url in
            reportRouter.handleReportConversationURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: LureliaReportConversationNotificationManager.conversationNotificationOpened
        )) { notification in
            guard let reportID = notification.object as? String else { return }
            reportRouter.handleReportConversationID(reportID)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await LureliaReportConversationNotificationManager.scanForNewMessages() }
        }
    }

    private func createSettingsIfNeeded() {
        guard settings.isEmpty else { return }

        let newSettings = UserSettings()
        modelContext.insert(newSettings)

        try? modelContext.save()
    }
}

#Preview {
    ContentView()
        .environmentObject(LureliaReportRouter())
        .modelContainer(for: UserSettings.self, inMemory: true)
}
