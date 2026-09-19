//
//  LureliaAppShortcuts.swift
//  Lurelia
//
//  Registers the main app's Shortcuts actions so they surface when searching
//  for "Lurelia" in Apple's Shortcuts app. This is the *app* target's
//  AppShortcutsProvider (the widget extension has its own, separate one, which
//  is left untouched).
//

import AppIntents

struct LureliaAppShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRoutineIntent(),
            phrases: [
                "Get \(.applicationName) routine",
                "Get a routine from \(.applicationName)"
            ],
            shortTitle: "Get Routine",
            systemImageName: "list.bullet.rectangle"
        )
        AppShortcut(
            intent: GetRoutineTasksIntent(),
            phrases: [
                "Get \(.applicationName) routine tasks",
                "Get routine tasks from \(.applicationName)"
            ],
            shortTitle: "Get Routine Tasks",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: GetRoutineTaskIntent(),
            phrases: [
                "Get a \(.applicationName) routine task",
                "Pick a \(.applicationName) routine task"
            ],
            shortTitle: "Get Routine Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: StartRoutineIntent(),
            phrases: [
                "Start \(.applicationName) routine",
                "Run \(.applicationName) routine",
                "Start a routine in \(.applicationName)"
            ],
            shortTitle: "Start Routine",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: GetRoutineTaskNamesIntent(),
            phrases: [
                "Get \(.applicationName) routine task names",
                "Get task names from \(.applicationName)"
            ],
            shortTitle: "Get Routine Task Names",
            systemImageName: "text.alignleft"
        )
    }
}
