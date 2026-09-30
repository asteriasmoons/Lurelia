//
//  UserSettings.swift
//  Lurelia
//

import Foundation
import SwiftData

@Model
final class UserSettings {
    
    // MARK: - Onboarding
    
    var hasCompletedOnboarding: Bool = false
    var shouldReplayOnboarding: Bool = false
    
    // MARK: - Categories
    
    var selectedCategoriesStorage: Data?
    
    // MARK: - Starter Routines
    
    var selectedStarterRoutinesStorage: Data?
    
    // MARK: - Preferences
    
    var autoClearTasks: Bool = false
    var notificationsEnabled: Bool = false
    var hideCompletedReminders: Bool = false
    var defaultTimelineBoardIDString: String?
    var defaultTimelineBoardIDsStorage: Data?
    var selectedAppleCalendarIDsStorage: Data?
    /// True once the user has explicitly saved their Apple Calendar
    /// visibility picks. Before that, an empty `selectedAppleCalendarIDs`
    /// is treated as "no configuration yet, show everything". Once true,
    /// an empty set is honored literally — meaning the user chose to hide
    /// every Apple calendar and no Apple events should render.
    var hasConfiguredAppleCalendarSelection: Bool = false
    var showAppleCalendarEvents: Bool = true
    var twoWayAppleCalendarSyncEnabled: Bool = false
    /// Raw value of the default tab shown when the Events feature opens.
    /// Backed by `LureliaEventsTab.rawValue` — "Agenda" / "Month" / "Week".
    var defaultEventsViewRaw: String = "Agenda"
    /// The newest release note the user has already dismissed.
    /// Empty means no release note has been acknowledged yet.
    var lastSeenReleaseNoteID: String = ""
    /// The Apple Calendar identifier that Lurelia should mirror
    /// Lurelia-authored events into. Used by the bulk-push and by the
    /// event editor's default calendar selection. Nil means "no explicit
    /// choice yet" — the editor and bulk sync will fall back to the first
    /// visible writable calendar.
    var defaultAppleSyncCalendarID: String?

    // MARK: - Shared event platform identity

    /// Stable identifier the vox-api recognizes for this user across the
    /// shared event platform. Set once during onboarding (or on first
    /// sync) and reused for RSVPs, comments, invitations, and host posts.
    /// Empty string means "not yet linked".
    var remoteUserID: String = ""

    /// Human display name shown alongside the user's RSVP / comments /
    /// host posts. Kept on-device so views can render before the server
    /// round-trip returns.
    var remoteDisplayName: String = ""

    /// Cloudinary URL for the user's profile avatar. This is the value sent to
    /// shared-event APIs so comments and replies do not upload raw image data.
    var remoteAvatarURL: String?

    // MARK: - Coins
    
    var coinBalance: Int = 0
    
    // MARK: - Profile
    
    @Attribute(.externalStorage)
    var profileImageData: Data?
    
    // MARK: - Dates
    
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // MARK: - Init
    
    init(
        hasCompletedOnboarding: Bool = false,
        selectedCategories: [String] = [],
        selectedStarterRoutines: [String] = [],
        autoClearTasks: Bool = false,
        notificationsEnabled: Bool = false,
        hideCompletedReminders: Bool = false,
        defaultTimelineBoardIDString: String? = nil,
        defaultTimelineBoardIDs: [UUID] = [],
        selectedAppleCalendarIDs: [String] = [],
        showAppleCalendarEvents: Bool = true,
        twoWayAppleCalendarSyncEnabled: Bool = false,
        lastSeenReleaseNoteID: String = "",
        coinBalance: Int = 0,
        profileImageData: Data? = nil,
        remoteAvatarURL: String? = nil
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.selectedCategories = selectedCategories
        self.selectedStarterRoutines = selectedStarterRoutines
        self.autoClearTasks = autoClearTasks
        self.notificationsEnabled = notificationsEnabled
        self.hideCompletedReminders = hideCompletedReminders
        self.defaultTimelineBoardIDString = defaultTimelineBoardIDString
        if !defaultTimelineBoardIDs.isEmpty {
            self.defaultTimelineBoardIDsStorage = try? JSONEncoder().encode(defaultTimelineBoardIDs.map(\.uuidString))
        }
        self.selectedAppleCalendarIDs = selectedAppleCalendarIDs
        self.showAppleCalendarEvents = showAppleCalendarEvents
        self.twoWayAppleCalendarSyncEnabled = twoWayAppleCalendarSyncEnabled
        self.lastSeenReleaseNoteID = lastSeenReleaseNoteID
        self.coinBalance = coinBalance
        self.createdAt = Date()
        self.updatedAt = Date()
        self.profileImageData = profileImageData
        self.remoteAvatarURL = remoteAvatarURL
    }
}

// MARK: - Codable Helpers

extension UserSettings {
    
    var selectedCategories: [String] {
        get {
            guard
                let data = selectedCategoriesStorage,
                let decoded = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            
            return decoded
        }
        set {
            selectedCategoriesStorage = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
    
    var selectedStarterRoutines: [String] {
        get {
            guard
                let data = selectedStarterRoutinesStorage,
                let decoded = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            
            return decoded
        }
        set {
            selectedStarterRoutinesStorage = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var defaultTimelineBoardID: UUID? {
        get {
            guard let defaultTimelineBoardIDString else { return nil }
            return UUID(uuidString: defaultTimelineBoardIDString)
        }
        set {
            defaultTimelineBoardIDString = newValue?.uuidString
            updatedAt = Date()
        }
    }

    var defaultTimelineBoardIDs: [UUID] {
        get {
            if let data = defaultTimelineBoardIDsStorage,
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                return decoded.compactMap(UUID.init(uuidString:))
            }

            if let legacyID = defaultTimelineBoardID {
                return [legacyID]
            }

            return []
        }
        set {
            defaultTimelineBoardIDsStorage = try? JSONEncoder().encode(newValue.map(\.uuidString))
            defaultTimelineBoardIDString = newValue.first?.uuidString
            updatedAt = Date()
        }
    }

    var selectedAppleCalendarIDs: [String] {
        get {
            guard let data = selectedAppleCalendarIDsStorage,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }

            return decoded
        }
        set {
            selectedAppleCalendarIDsStorage = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }
}
