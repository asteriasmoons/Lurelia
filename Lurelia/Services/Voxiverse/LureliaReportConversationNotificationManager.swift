//
//  LureliaReportConversationNotificationManager.swift
//  Lurelia
//

import CloudKit
import Foundation
import UIKit
import UserNotifications

enum LureliaReportConversationNotificationManager {
    static let conversationNotificationOpened = Notification.Name("LureliaReportConversationNotificationOpened")
    static let conversationDataDidChange = Notification.Name("LureliaReportConversationDataDidChange")

    private static let container = CKContainer(identifier: LureliaReportConversationCloudKitSchema.containerIdentifier)
    private static let zoneSubscriptionPrefix = "lurelia-report-message-events-v3-"
    private static let invitationSubscriptionID = "lurelia-report-invitations-v3"
    private static let processedMessagePrefix = "lurelia.reportConversation.processedMessage."
    private static let processedInvitationPrefix = "lurelia.reportConversation.processedInvitation."
    private static let deduplicationLock = NSLock()

    static func prepareNotifications() async {
        _ = await requestAuthorizationIfNeeded()
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        do {
            try await ensureInvitationSubscription()
        } catch {
            reportNotifLog("invitation subscription registration FAILED [id=\(invitationSubscriptionID) type=CKQuerySubscription scope=public]: \(error.localizedDescription)")
        }
        // A message subscription must exist BEFORE a message arrives, so register
        // at launch on every database that can hold the ReportConversations zone:
        //   - shared DB: cross-account reporters (production) once the share is accepted
        //   - private DB: same-account / owner case, where the zone lives in the
        //     reporter's own private database
        if let zones = try? await container.sharedCloudDatabase.allRecordZones() {
            for zone in zones where zone.zoneID.zoneName == LureliaReportConversationCloudKitSchema.zoneName {
                await ensureMessageSubscriptionLogged(database: container.sharedCloudDatabase, zoneID: zone.zoneID)
            }
        }
        let privateZoneID = CKRecordZone.ID(zoneName: LureliaReportConversationCloudKitSchema.zoneName, ownerName: CKCurrentUserDefaultName)
        if let result = try? await container.privateCloudDatabase.recordZones(for: [privateZoneID])[privateZoneID], (try? result.get()) != nil {
            await ensureMessageSubscriptionLogged(database: container.privateCloudDatabase, zoneID: privateZoneID)
        }
    }

    private static func ensureMessageSubscriptionLogged(database: CKDatabase, zoneID: CKRecordZone.ID) async {
        do {
            try await ensureMessageSubscription(database: database, zoneID: zoneID)
        } catch {
            reportNotifLog("message subscription registration FAILED [type=CKRecordZoneSubscription scope=\(reportNotifScopeName(database.databaseScope)) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName)]: \(error.localizedDescription)")
        }
    }

    static func reportNotifLog(_ message: String) {
        #if DEBUG
        print("[ReportNotif][Lurelia] \(message)")
        #endif
    }

    static func reportNotifScopeName(_ scope: CKDatabase.Scope) -> String {
        switch scope {
        case .public: return "public"
        case .private: return "private"
        case .shared: return "shared"
        @unknown default: return "unknown"
        }
    }

    static func registerSharedConversationNotifications(database: CKDatabase, conversationRecordID: CKRecord.ID) async throws {
        await prepareNotifications()
        try await ensureMessageSubscription(database: database, zoneID: conversationRecordID.zoneID)
    }

    static func clearReadConversationNotification(reportID: String) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        let identifiers = delivered.filter { ($0.request.content.userInfo["reportID"] as? String) == reportID }.map(\.request.identifier)
            + pending.filter { ($0.content.userInfo["reportID"] as? String) == reportID }.map(\.identifier)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        try? await center.setBadgeCount(0)
    }

    /// Foreground/scene-active reconciliation. CloudKit does not deliver
    /// subscription pushes to the same device/account that made the change, so
    /// relying on push alone yields no notifications during single-device
    /// testing. This re-scans the conversation zone (in whichever database
    /// actually holds it) using the SAME persistent change token, dedup, and
    /// sender/sourceApp filters, so only genuinely new staff messages notify.
    static func scanForNewMessages() async {
        await prepareNotifications()
        if let zones = try? await container.sharedCloudDatabase.allRecordZones() {
            for zone in zones where zone.zoneID.zoneName == LureliaReportConversationCloudKitSchema.zoneName {
                _ = await processMessageChanges(in: zone.zoneID, database: container.sharedCloudDatabase)
            }
        }
        let privateZoneID = CKRecordZone.ID(zoneName: LureliaReportConversationCloudKitSchema.zoneName, ownerName: CKCurrentUserDefaultName)
        if let result = try? await container.privateCloudDatabase.recordZones(for: [privateZoneID])[privateZoneID], (try? result.get()) != nil {
            _ = await processMessageChanges(in: privateZoneID, database: container.privateCloudDatabase)
        }
        await scanForPendingInvitations()
    }

    /// Fallback discovery of pending conversation invitations for THIS app when
    /// the public-database invitation push did not arrive (e.g. same-device /
    /// same-account testing). Reuses processInvitation, so dedup, accepted/
    /// declined exclusion, app routing, and single-notification semantics are
    /// identical to the push path. It never notifies merely because a record
    /// exists: processInvitation still requires conversationState == invited and
    /// a not-yet-processed stable conversation identifier.
    static func scanForPendingInvitations() async {
        let database = container.publicCloudDatabase
        let predicate = NSPredicate(format: "appID == %@", LureliaReportConversationCloudKitSchema.sourceAppID)
        let query = CKQuery(recordType: LureliaReportConversationCloudKitSchema.RecordType.report, predicate: predicate)
        guard let response = try? await database.records(matching: query) else { return }
        for (recordID, result) in response.matchResults {
            guard (try? result.get()) != nil else { continue }
            _ = await processInvitation(recordID: recordID)
        }
    }

    static func processMessageChanges(in zoneID: CKRecordZone.ID, databaseScope: CKDatabase.Scope) async -> Bool {
        let database = databaseScope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
        return await processMessageChanges(in: zoneID, database: database)
    }

    static func processMessageChanges(in zoneID: CKRecordZone.ID, database: CKDatabase) async -> Bool {
        guard var token = loadChangeToken(for: zoneID) else {
            try? await seedChangeToken(database: database, zoneID: zoneID)
            return false
        }
        var didNotify = false
        var moreComing = true
        while moreComing {
            do {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for result in changes.modificationResultsByID.values {
                    guard let record = try? result.get().record else { continue }
                    didNotify = await notifyForNewStaffMessage(record, database: database) || didNotify
                }
                token = changes.changeToken
                saveChangeToken(token, for: zoneID)
                moreComing = changes.moreComing
            } catch let error as CKError where error.code == .changeTokenExpired {
                try? await seedChangeToken(database: database, zoneID: zoneID)
                return didNotify
            } catch {
                reportNotifLog("zone change fetch FAILED [scope=\(reportNotifScopeName(database.databaseScope)) zone=\(zoneID.zoneName) owner=\(zoneID.ownerName)]: \(error.localizedDescription)")
                return didNotify
            }
        }
        return didNotify
    }

    static func processInvitation(recordID: CKRecord.ID) async -> Bool {
        let database = container.publicCloudDatabase
        guard let record = try? await database.record(for: recordID),
              record.lureliaString("appID") == LureliaReportConversationCloudKitSchema.sourceAppID,
              record.lureliaString(LureliaReportConversationCloudKitSchema.PublicReportField.conversationState) == LureliaReportConversationState.invited.rawValue else { return false }
        let conversationID = record.lureliaString(LureliaReportConversationCloudKitSchema.PublicReportField.conversationRecordName)
        guard !conversationID.isEmpty else { return false }
        let processedKey = processedInvitationPrefix + conversationID
        guard claimNotification(processedKey) else { return false }
        guard await requestAuthorizationIfNeeded() else { releaseNotification(processedKey); return false }
        let reportID = record.lureliaString("reportID").isEmpty ? recordID.recordName : record.lureliaString("reportID")
        let content = UNMutableNotificationContent()
        content.title = "Voxiverse"
        content.body = "Voxiverse invited you to a private conversation about your report."
        content.sound = .default
        content.userInfo = ["kind": "reportConversationInvitation", "reportID": reportID]
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lurelia-report-conversation-invite-\(conversationID)", content: content, trigger: nil))
            return true
        } catch { releaseNotification(processedKey); return false }
    }

    private static func ensureInvitationSubscription() async throws {
        let database = container.publicCloudDatabase
        // Save once per device so this device is added to the subscription's push
        // set (subscriptions are per-user, push targets are per-device).
        let deviceFlagKey = deviceSubscriptionFlagKey(invitationSubscriptionID)
        guard !UserDefaults.standard.bool(forKey: deviceFlagKey) else { return }
        let predicate = NSPredicate(format: "appID == %@", LureliaReportConversationCloudKitSchema.sourceAppID)
        let subscription = CKQuerySubscription(recordType: LureliaReportConversationCloudKitSchema.RecordType.report, predicate: predicate, subscriptionID: invitationSubscriptionID, options: [.firesOnRecordUpdate])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        UserDefaults.standard.set(true, forKey: deviceFlagKey)
    }

    private static func ensureMessageSubscription(database: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        let subscriptionID = zoneSubscriptionPrefix + zoneID.ownerName + "-" + zoneID.zoneName
        let oldSubscriptionID = "lurelia-report-conversations-\(zoneID.ownerName)-\(zoneID.zoneName)"
        if loadChangeToken(for: zoneID) == nil { try await seedChangeToken(database: database, zoneID: zoneID) }
        // CloudKit stores subscriptions per-user (one server-side copy), but push
        // delivery is per-device+per-app: a device is only added to a subscription's
        // push set when THAT device saves the subscription while registered for
        // remote notifications. Checking server-side existence and skipping would
        // leave a second device (where the subscription already exists) without any
        // push. So gate on a per-device flag and save once per install, matching
        // Apple's CloudKit sample apps.
        let deviceFlagKey = deviceSubscriptionFlagKey(subscriptionID)
        guard !UserDefaults.standard.bool(forKey: deviceFlagKey) else { return }
        _ = try? await database.modifySubscriptions(saving: [], deleting: [oldSubscriptionID]) // best-effort legacy cleanup
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        UserDefaults.standard.set(true, forKey: deviceFlagKey)
    }

    private static func deviceSubscriptionFlagKey(_ subscriptionID: String) -> String {
        "lurelia.reportConversation.deviceSubscriptionSaved.\(subscriptionID)"
    }

    private static func notifyForNewStaffMessage(_ message: CKRecord, database: CKDatabase) async -> Bool {
        guard message.recordType == LureliaReportConversationCloudKitSchema.RecordType.message,
              message.lureliaString(LureliaReportConversationCloudKitSchema.MessageField.senderRole) == LureliaReportConversationSenderRole.staff.rawValue else { return false }
        let messageID = message.lureliaString(LureliaReportConversationCloudKitSchema.MessageField.messageID).isEmpty ? message.recordID.recordName : message.lureliaString(LureliaReportConversationCloudKitSchema.MessageField.messageID)
        let processedKey = processedMessagePrefix + messageID
        guard claimNotification(processedKey) else { return false }
        let rootID = (message[LureliaReportConversationCloudKitSchema.MessageField.conversation] as? CKRecord.Reference)?.recordID
            ?? CKRecord.ID(recordName: message.lureliaString(LureliaReportConversationCloudKitSchema.MessageField.conversationRecordName), zoneID: message.recordID.zoneID)
        guard let root = try? await database.record(for: rootID),
              root.lureliaString(LureliaReportConversationCloudKitSchema.ConversationField.sourceAppID) == LureliaReportConversationCloudKitSchema.sourceAppID,
              root.lureliaString(LureliaReportConversationCloudKitSchema.ConversationField.invitationState) != LureliaReportConversationState.invited.rawValue else { releaseNotification(processedKey); return false }
        guard await requestAuthorizationIfNeeded() else { releaseNotification(processedKey); return false }
        let reportID = root.lureliaString(LureliaReportConversationCloudKitSchema.ConversationField.reportID)
        let content = UNMutableNotificationContent()
        content.title = "Voxiverse"
        content.body = "Voxiverse replied to your private report conversation."
        content.sound = .default
        content.userInfo = ["kind": "reportConversationReply", "reportID": reportID, "messageID": messageID]
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lurelia-report-conversation-message-\(messageID)", content: content, trigger: nil))
            return true
        } catch {
            reportNotifLog("local notification scheduling FAILED [messageID=\(messageID)]: \(error.localizedDescription)")
            releaseNotification(processedKey)
            return false
        }
    }

    private static func seedChangeToken(database: CKDatabase, zoneID: CKRecordZone.ID) async throws {
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, desiredKeys: [], resultsLimit: nil)
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        saveChangeToken(token, for: zoneID)
    }

    private static func changeTokenKey(for zoneID: CKRecordZone.ID) -> String {
        "lurelia.reportConversation.changeToken.\(zoneID.ownerName).\(zoneID.zoneName)"
    }

    private static func loadChangeToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey(for: zoneID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func saveChangeToken(_ token: CKServerChangeToken?, for zoneID: CKRecordZone.ID) {
        guard let token, let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: changeTokenKey(for: zoneID))
    }

    private static func claimNotification(_ key: String) -> Bool {
        deduplicationLock.lock()
        defer { deduplicationLock.unlock() }
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    private static func releaseNotification(_ key: String) {
        deduplicationLock.lock()
        UserDefaults.standard.removeObject(forKey: key)
        deduplicationLock.unlock()
    }

    private static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .ephemeral:
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return true
        case .provisional:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

