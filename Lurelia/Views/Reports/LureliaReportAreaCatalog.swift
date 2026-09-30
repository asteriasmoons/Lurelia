//
//  LureliaReportAreaCatalog.swift
//  Lurelia
//
//  Hierarchical report areas: a top-level Category (group) drives a dependent
//  Area (specific item) dropdown. Kept verbatim from the product taxonomy.
//

import Foundation

extension LureliaReportFormOptions {

    /// Top-level report categories (parent dropdown), in display order.
    static let areaGroups: [String] = [
        "App-Wide / General",
        "Timeline",
        "Routines",
        "Routine Task Details",
        "Routine Contracts",
        "Habits",
        "Habit Blueprint",
        "Reminders",
        "Events",
        "Apple Calendar",
        "Shared Events",
        "Shared Event Posts / Announcements",
        "Shared Event Comments",
        "Journeys",
        "Kanban",
        "Profile",
        "Onboarding",
        "Notifications",
        "Widgets",
        "Live Activities",
        "In-App Reporting",
        "Design / Interface",
        "Performance / Reliability",
    ]

    /// Specific areas (child dropdown) for each category.
    static let areasByGroup: [String: [String]] = [
        "App-Wide / General": [
            "Entire App", "App Launch / Startup", "Main Navigation", "Floating Tab Bar",
            "More / Overflow Navigation Menu", "Screen Navigation", "Sheets / Full-Screen Views", "Alerts / Confirmation Dialogs",
            "Completion Messages", "Loading States", "Empty States", "Keyboard / Text Input",
            "Scrolling", "Animations / Transitions", "Touch / Tap Targets", "iPhone Layout",
            "iPad Layout", "App Background", "App Theme", "Colors / Gradients",
            "Typography", "Icons / Images", "App Permissions", "Notifications",
            "Widgets", "Live Activities", "Release Notes",
        ],
        "Timeline": [
            "Timeline Home", "Daily Timeline", "Timeline Date", "Timeline Navigation",
            "Routine Tasks on Timeline", "Reminder Items on Timeline", "Habit Items on Timeline", "Event Items on Timeline",
            "Kanban Items on Timeline", "Timeline Cards", "Timeline Item Details", "Timeline Item Editing",
            "Completing Items From Timeline", "Skipping Items From Timeline", "Creating Items From Timeline", "Timeline Sorting",
            "Timeline Time Display", "Timeline Empty States",
        ],
        "Routines": [
            "Routines Home", "Routine List", "Routine Cards", "Creating Routines",
            "Editing Routines", "Deleting Routines", "Routine Details", "Routine Name",
            "Routine Description", "Routine Purpose", "Routine Schedule", "Routine Start Time",
            "Routine End Time", "Routine Days", "Routine Color / Appearance", "Routine Icon",
            "Routine Tasks", "Adding Routine Tasks", "Editing Routine Tasks", "Deleting Routine Tasks",
            "Reordering Routine Tasks", "Routine Task Details", "Starting a Routine", "Active Routine",
            "Active Routine Banner", "Routine Run", "Completing Routine Tasks", "Skipping Routine Tasks",
            "Ending a Routine", "Routine Progress", "Routine Completion", "Routine History",
            "Routine Notifications", "Routine Task Notifications", "Routine Task Alarms", "Routine Live Activity",
        ],
        "Routine Task Details": [
            "Task Name", "Task Description", "Task Steps", "Task Purpose",
            "Task Motivation", "Trigger Type", "Trigger", "Environment",
            "Obstacles", "Obstacle Solutions", "Reward", "Consequence",
            "Recovery Plan", "Task Duration", "Task Notes", "Task Notification",
            "Task Alarm", "Task Scheduling",
        ],
        "Routine Contracts": [
            "Routine Contracts", "Contract List", "Creating Contracts", "Editing Contracts",
            "Deleting Contracts", "Contract Details", "Contract Terms", "Contract Rules",
            "Contract Rewards", "Contract Consequences",
        ],
        "Habits": [
            "Habits Home", "Habit List", "Habit Cards", "Creating Habits",
            "Editing Habits", "Deleting Habits", "Habit Details", "Habit Name",
            "Habit Description", "Habit Schedule", "Habit Frequency", "Habit Goal",
            "Habit Progress", "Completing Habits", "Skipping Habits", "Habit Streak",
            "Habit History", "Habit History Overlay", "Habit Notifications", "Habit Widget",
        ],
        "Habit Blueprint": [
            "Habit Blueprint", "Blueprint Details", "Habit Purpose", "Habit Motivation",
            "Trigger", "Environment", "Obstacles", "Solutions",
            "Reward", "Consequence", "Recovery Plan",
        ],
        "Reminders": [
            "Reminders Home", "Reminder List", "Creating Reminders", "Editing Reminders",
            "Deleting Reminders", "Reminder Details", "Reminder Name", "Reminder Description",
            "Reminder Date", "Reminder Time", "Reminder Schedule", "Repeating Reminders",
            "Reminder Notifications", "Reminder Alarm", "Reminder Completion", "Skipping Reminders",
            "Reminder History", "Completed Reminders", "Reminder Widget",
        ],
        "Events": [
            "Events Home", "Event List", "Event Calendar", "Month Calendar",
            "Agenda View", "Event Details", "Creating Events", "Editing Events",
            "Deleting Events", "Event Title", "Event Description", "Event Date",
            "Event Time", "All-Day Events", "Event Schedule", "Repeating Events",
            "Event Location", "Location Picker", "Event Notes", "Event Notifications",
            "Upcoming Events", "Past Events", "Event Occurrences", "Calendar Settings",
            "Adding Calendars", "Calendar Selection", "Event Empty States",
        ],
        "Apple Calendar": [
            "Apple Calendar Integration", "Calendar Permission", "Apple Calendar Events", "Apple Event Details",
            "Calendar Selection", "Adding Apple Calendars", "Showing / Hiding Calendars", "Event Sync",
            "Calendar Sync", "Synced Event Details", "Editing Synced Events", "Calendar Settings",
        ],
        "Shared Events": [
            "Shared Events Home", "Shared Event List", "Creating Shared Events", "Editing Shared Events",
            "Deleting Shared Events", "Shared Event Details", "Shared Event Title", "Shared Event Description",
            "Shared Event Date / Time", "Shared Event Location", "Shared Event Host", "Shared Event Participants",
            "Event Invitations", "Joining Shared Events", "Leaving Shared Events", "RSVP",
            "RSVP Status", "Guest List", "Share Link", "QR Code Sharing",
            "Sharing Shared Events", "Shared Event Calendar Sync", "Host Management",
        ],
        "Shared Event Posts / Announcements": [
            "Event Posts", "Host Posts", "Announcements", "Post List",
            "Post Details", "Post Preview", "Creating Posts", "Editing Posts",
            "Deleting Posts", "Rich Text Posts", "Post Formatting", "Links in Posts",
            "Images in Posts",
        ],
        "Shared Event Comments": [
            "Event Comments", "Comment List", "Adding Comments", "Editing Comments",
            "Deleting Comments", "Comment Replies", "Comment Attachments", "Image Attachments",
            "Comment Loading", "Comment Errors",
        ],
        "Journeys": [
            "Journeys Home", "Journey List", "Creating Journeys", "Editing Journeys",
            "Deleting Journeys", "Journey Details", "Journey Name", "Journey Description",
            "Journey Goal", "Journey Progress", "Journey Timeline", "Journey Notes",
            "Adding Journey Notes", "Editing Journey Notes", "Journey Steps", "Creating Journey Steps",
            "Editing Journey Steps", "Deleting Journey Steps", "Step Details", "Completing Journey Steps",
            "Journey Milestones", "Creating Milestones", "Editing Milestones", "Deleting Milestones",
            "Milestone Details", "Milestone Progress", "Journey Completion",
        ],
        "Kanban": [
            "Kanban Home", "Kanban Board", "Kanban Columns", "Creating Columns",
            "Editing Columns", "Deleting Columns", "Reordering Columns", "Kanban Cards",
            "Adding Cards", "Editing Cards", "Deleting Cards", "Moving Cards Between Columns",
            "Card Picker", "Assigning Routine Tasks", "Kanban Timeline", "Timeline Cards",
            "Completing Tasks From Kanban", "Skipping Tasks From Kanban", "Creating Tasks From Kanban", "Calendar View",
            "Schedule View",
        ],
        "Profile": [
            "Profile Home", "User Profile", "Profile Information", "Display Name",
            "Username", "Avatar / Profile Image", "Profile Editing", "Profile Loading",
            "Saving Profile", "Account Information", "Release Notes", "Sign Out",
        ],
        "Onboarding": [
            "Onboarding", "Welcome Screens", "Onboarding Navigation", "Initial Setup",
            "Permissions Setup", "Onboarding Completion",
        ],
        "Notifications": [
            "Notifications — General", "Notification Permission", "Routine Notifications", "Routine Task Notifications",
            "Routine Task Alarms", "Reminder Notifications", "Reminder Alarms", "Habit Notifications",
            "Event Notifications", "Notification Timing", "Notification Delivery", "Opening Notifications",
        ],
        "Widgets": [
            "Widgets — General", "Routine Tasks Widget", "Reminders Widget", "Habits Widget",
            "Widget Configuration", "Widget Appearance", "Widget Content", "Widget Refresh",
            "Widget Interaction", "Completing Items From Widget", "Skipping Items From Widget",
        ],
        "Live Activities": [
            "Routine Live Activity", "Starting Live Activity", "Active Routine Progress", "Lock Screen Live Activity",
            "Dynamic Island", "Live Activity Updates", "Ending Live Activity",
        ],
        "In-App Reporting": [
            "Report Center", "Bug Report", "Feature Request", "Beta Feedback",
            "Report Form", "Affected Area Selection", "Report Submission", "Report Attachments",
            "Image Attachments", "Submitted Reports", "Report History", "Submitted Report Details",
            "Submitted Report Images", "Report Status", "Developer Conversation Invite", "Report Conversation",
            "Conversation Messages", "Sending Messages", "Conversation Loading", "Report Notifications",
            "Opening Report Conversations",
        ],
        "Design / Interface": [
            "App Background", "Theme", "Colors", "Gradients",
            "Typography", "Icons", "Images", "Glass Surfaces",
            "Buttons", "Cards", "Forms", "Input Fields",
            "Pickers", "Navigation Appearance", "Floating Tab Bar Appearance", "Overflow Menu Appearance",
            "Timeline Appearance", "Sheet Appearance", "Full-Screen Appearance", "iPhone Layout",
            "iPad Layout",
        ],
        "Performance / Reliability": [
            "App Performance", "Slow Loading", "Lag / Stuttering", "Freezes",
            "Crashes", "Unexpected App Restarts", "Timeline Performance", "Routine Performance",
            "Habit Performance", "Reminder Performance", "Event Performance", "Shared Event Performance",
            "Journey Performance", "Kanban Performance", "Widget Reliability", "Live Activity Reliability",
            "Notification Reliability",
        ]
    ]

    /// Children for a given category (empty if unknown).
    static func areas(for group: String) -> [String] {
        areasByGroup[group] ?? []
    }

    /// Default category shown when a form first appears.
    static var defaultAreaGroup: String { areaGroups.first ?? "" }

    /// Default specific area for a category.
    static func defaultArea(for group: String) -> String {
        areas(for: group).first ?? ""
    }
}
