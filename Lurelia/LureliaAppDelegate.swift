//
//  LureliaAppDelegate.swift
//  Lurelia
//

import CloudKit
import UIKit
import UserNotifications
import SwiftData

class LureliaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    static weak var shared: LureliaAppDelegate?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LureliaAppDelegate.shared = self
        UNUserNotificationCenter.current().delegate = self
        Task { await LureliaReportConversationNotificationManager.prepareNotifications() }
        return true
    }

    // MARK: - APNs (shared event platform, Phase 1A.7)

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        Task { @MainActor in
            SharedEventNotificationManager.shared.receivedDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error,
    ) {
        Task { @MainActor in
            SharedEventNotificationManager.shared.registrationFailed(error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        // Voxiverse report-conversation pushes: invitations arrive as public-database
        // query pushes; conversation messages arrive as ReportConversations zone pushes.
        // Route these first (downstream sourceAppID + senderRole + dedup filters keep
        // this app-specific and prevent historical replay); everything else is the
        // shared-event platform path.
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            if notification.subscriptionID == "lurelia-report-invitations-v3",
               let recordID = (notification as? CKQueryNotification)?.recordID {
                Task {
                    let notified = await LureliaReportConversationNotificationManager.processInvitation(recordID: recordID)
                    NotificationCenter.default.post(name: LureliaReportConversationNotificationManager.conversationDataDidChange, object: nil)
                    completionHandler(notified ? .newData : .noData)
                }
                return
            } else if let zoneNotification = notification as? CKRecordZoneNotification,
                      let zoneID = zoneNotification.recordZoneID,
                      zoneID.zoneName == LureliaReportConversationCloudKitSchema.zoneName {
                Task {
                    let notified = await LureliaReportConversationNotificationManager.processMessageChanges(in: zoneID, databaseScope: zoneNotification.databaseScope)
                    NotificationCenter.default.post(name: LureliaReportConversationNotificationManager.conversationDataDidChange, object: nil)
                    completionHandler(notified ? .newData : .noData)
                }
                return
            }
        }
        Task { @MainActor in
            SharedEventNotificationManager.shared.presentForeground(userInfo: userInfo)
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        // Voxiverse report-conversation tap: open the matching conversation.
        if let kind = userInfo["kind"] as? String,
           kind == "reportConversationReply" || kind == "reportConversationInvitation",
           let reportID = userInfo["reportID"] as? String, !reportID.isEmpty {
            NotificationCenter.default.post(
                name: LureliaReportConversationNotificationManager.conversationNotificationOpened,
                object: reportID
            )
            completionHandler()
            return
        }

        // Habit notification actions
        if userInfo["habitID"] != nil,
           let container = LureliaNotificationManager.shared.modelContainer {
            Task { @MainActor in
                await HabitManager.shared.handleResponse(response, container: container)
            }
        }

        if actionID == LureliaNotificationManager.snoozeActionID,
           let reminderIDStr = userInfo["reminderID"] as? String {
            Task { @MainActor in
                guard let container = LureliaNotificationManager.shared.modelContainer else { return }
                let context = container.mainContext
                let descriptor = FetchDescriptor<LureliaReminder>()
                if let reminders = try? context.fetch(descriptor),
                   let reminder = reminders.first(where: { $0.notificationID == reminderIDStr }) {
                    LureliaNotificationManager.shared.snoozeReminder(reminder)
                }
            }
        }

        completionHandler()
    }
}
