# Removing Unwanted Menu Button Backgrounds

## Overview

This document explains the visual bug and final implementation used for the add button in each Kanban column header.

The affected control is `KanbanColumnAddCardMenu` in `KanbanBoardView.swift`. It presents the hierarchical menu used to add reminders, routine tasks, and habits to a column.

The intended result is:

- The custom `addwavy` asset is the only visible trigger.
- The icon keeps its column-color `BubblyIconMaterial` treatment.
- The icon keeps its faint black shadow.
- No rectangular, square, capsule, or system-generated background appears around the icon.
- Tapping the icon still opens the native hierarchical `Menu`.
- Existing availability and pinned-item filtering remains unchanged.

This behavior is implemented and checked against Xcode 27.0 and Swift 6.4 for the iOS 27 codebase.

## The Visual Inconsistency

The Kanban column itself uses a rounded, color-tinted card material. Its header contains the column name, item count, and a small add icon. The add icon is designed as a compact decorative symbol rather than a separate rectangular control.

The problem was that SwiftUI rendered an additional rectangular control surface behind the add icon. The rectangle was especially obvious over lighter column colors because it introduced:

- A hard-edged shape that did not match the custom `addwavy` silhouette.
- A second material treatment on top of the column's card material.
- A brighter rectangular highlight around an icon that was supposed to stand alone.
- Inconsistent rendering compared with the page-level add and exit icons.
- A mismatch between the visible shape and the intended circular or icon-shaped tap target.

The icon's own material was not the source of this rectangle. `bubblyIconMaterial(tint:)` masks its material through the alpha shape of the icon. The unwanted rectangle came from the `Menu` trigger's control styling outside that icon mask.

## Original Implementation

The column add control was a SwiftUI `Menu` with a custom image label. The menu structure itself was correct and important because it preserved nested choices for reminders, routines, routine tasks, and habits.

The trigger initially relied on the menu's automatic styling plus a plain button style. Conceptually, it looked like this:

```swift
Menu {
    // Nested reminder, routine, and habit actions.
} label: {
    Image("addwavy")
        .bubblyIconMaterial(tint: accentColor)
}
.buttonStyle(.plain)
```

On iOS 27, `Menu` is a button-like control whose trigger appearance is also controlled by `MenuStyle`. Changing only the label or applying a regular button style does not necessarily opt the menu out of its automatic trigger chrome.

## Failed Hidden-Label Workaround

An intermediate workaround attempted to make the real menu label almost invisible and draw a second copy of the custom label on top:

```swift
Menu {
    // Menu content.
} label: {
    label()
        .opacity(0.001)
}
.buttonStyle(.plain)
.overlay {
    label()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
}
```

This did not solve the root problem.

The nearly transparent label was still the label of a `Menu`. SwiftUI continued to create and style the menu trigger around that label. Opacity changed the label's pixels, but it did not remove the parent control's automatically supplied background or material.

The visible overlay then sat on top of both the hidden trigger and the system-generated rectangular surface. As a result, the icon looked correct while the rectangle remained visible behind it.

This approach also had structural disadvantages:

- The visible label and interactive label were separate view instances.
- The displayed shape was not the same view that owned the interaction.
- Accessibility had to be manually suppressed on the duplicate.
- Material, layout, pressed state, and focus behavior could diverge between the two labels.
- It treated the symptom at the label layer instead of changing the menu trigger style.

The hidden-label and overlay technique should not be restored.

## Rejected Popover Approach

A plain `Button` opening a custom popover was briefly explored because a normal button gave complete control over the trigger appearance. That removed the rectangle, but it changed the interaction from a native hierarchical menu into a separate custom picker.

That approach was rejected because the requirement is to keep a menu. The existing menu hierarchy is useful and already models the feature correctly:

- Reminder
  - New Reminder
  - Existing Reminders
- Routine
  - Routine selection
  - Existing task selection
  - New task creation
- Habit
  - New Habit
  - Existing habits

The final fix therefore keeps the native SwiftUI `Menu` and changes only how its trigger is styled.

## Root Cause

The root cause was a mismatch between the styling layer being changed and the styling layer creating the unwanted rectangle.

The relevant layers are:

1. `BubblyIconMaterial` controls the pixels inside the custom icon mask.
2. The label view controls the icon's size, tint, and shadow.
3. `ButtonStyle` controls the button-like trigger used by the menu style.
4. `MenuStyle` controls how SwiftUI represents the `Menu` itself.

The earlier attempts changed layers 1 and 2 while leaving the automatic behavior in layers 3 and 4. The final implementation explicitly configures both control-style layers.

## Final Implementation

The working implementation uses one real label and two explicit styles:

```swift
Menu {
    // Existing hierarchical menu content.
} label: {
    label()
}
.menuStyle(.button)
.buttonStyle(.borderless)
```

### Why `.menuStyle(.button)` Is Required

`.menuStyle(.button)` explicitly tells SwiftUI to represent the menu using its button-based menu style instead of leaving the choice to the context-sensitive automatic style.

This makes the trigger's button styling intentional and gives the following modifier a defined button surface to control.

### Why `.buttonStyle(.borderless)` Is Required

`.buttonStyle(.borderless)` applies `BorderlessButtonStyle` to the button used by the menu style. Apple defines this style as a button style that does not apply a border.

This is intentionally different from relying on `.buttonStyle(.plain)` alone. The final combination first selects a button-backed menu representation, then explicitly makes that button borderless.

### Why There Is Only One Label

The final control renders `label()` directly inside the `Menu`:

```swift
} label: {
    label()
}
```

There is no hidden copy and no overlay copy. The visible icon is also the interactive menu label, so its layout, hit testing, focus, accessibility, and pressed state remain aligned.

## Column Header Usage

`KanbanColumnView` supplies the custom add icon to `KanbanColumnAddCardMenu`:

```swift
KanbanColumnAddCardMenu(
    column: column,
    allReminders: allReminders,
    allRoutines: allRoutines,
    allHabits: allHabits,
    onCreateReminder: onCreateReminder,
    onCreateHabit: onCreateHabit,
    onAddCard: onAddCard,
    onAddTask: onAddTask
) {
    Image("addwavy")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
        .foregroundStyle(accentColor)
        .bubblyIconMaterial(tint: accentColor)
        .shadow(
            color: .black.opacity(0.42),
            radius: 3,
            x: 0,
            y: 2
        )
}
```

The label intentionally has no rectangle, capsule, circle, fill, or background modifier. Its only visible treatment is the custom icon material and shadow.

## Behavior Preserved by the Fix

The styling change does not alter the menu's data flow or actions.

The following behavior remains in `KanbanColumnAddCardMenu`:

- Reminders already pinned to a board are filtered out.
- Routine tasks pinned anywhere are detected and disabled.
- Archived habits are excluded.
- Habits already pinned to a board are filtered out.
- New reminder, routine task, and habit creation still routes through the existing callbacks.
- Existing reminders, tasks, and habits still use their existing item identifiers.
- The nested menu hierarchy remains native SwiftUI menu content.

No model, persistence, sorting, navigation, or creation behavior was changed to solve the visual problem.

## Approaches That Should Not Be Reintroduced

Do not use any of the following as a replacement for the final styling:

### Hiding the Menu Label with Opacity

Changing the label to `.opacity(0)` or `.opacity(0.001)` does not remove styling supplied by the parent control.

### Drawing a Duplicate Label in an Overlay

An overlay can cover the trigger's content, but it does not opt the `Menu` out of its automatic button treatment. It also separates the visible and interactive views.

### Adding `Color.clear` as a Background

A clear background is still a background layer. It does not remove a material or decoration drawn by an ancestor control style.

### Clipping or Masking the Whole Menu

Clipping the menu trigger risks clipping focus, pressed-state, accessibility, and presentation animations. The menu's own style should be corrected instead.

### Replacing the Menu with a Popover

A custom popover may remove the rectangle, but it changes the requested interaction model and requires reimplementing native menu hierarchy and behavior.

### Applying Another Glass Effect to the Trigger

Adding a second glass or material effect compounds the visual problem. The column already supplies its large card material, and the icon already supplies its compact icon material.

## iOS 27 Notes

This fix targets the iOS 27 generation of SwiftUI and was checked with:

- Xcode 27.0
- Build version `27A266a`
- Apple Swift 6.4

iOS 27 continues to refine Liquid Glass and automatic control appearance. For that reason, controls that need a deliberately undecorated trigger should not rely on `.automatic` menu styling.

The implementation follows Apple's current menu styling model:

- Use `menuStyle(_:)` to choose how the menu is represented.
- Use `buttonStyle(_:)` to style the button-like trigger selected by that menu style.
- Use the borderless button style when no control border or embellishment is wanted.

Apple references:

- [Menu](https://developer.apple.com/documentation/swiftui/menu)
- [MenuStyle](https://developer.apple.com/documentation/swiftui/menustyle)
- [BorderlessButtonStyle](https://developer.apple.com/documentation/swiftui/borderlessbuttonstyle)
- [What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)

## Regression Checklist

When this control is changed again, verify all of the following on iOS 27:

1. The idle add icon has no rectangular or square background.
2. The pressed add icon does not flash a rectangular background.
3. The icon retains its column color and `BubblyIconMaterial` treatment.
4. The icon's black shadow remains confined to the icon silhouette.
5. The menu opens from the icon without requiring a separate popover or sheet.
6. Reminder, routine, and habit submenus are all present.
7. Existing pinned-item filtering still works.
8. Disabled routine tasks remain disabled.
9. Tapping New Reminder, Add New Task, and New Habit still opens the correct creation flow.
10. VoiceOver exposes one add-menu control rather than duplicate hidden and visible controls.
11. Light and dark column colors do not reveal any system rectangle behind the icon.
12. Dismissing the menu does not leave a temporary rectangular material behind.

## Validation Boundary

The source implementation was validated with Swift frontend parsing and `git diff --check`. These checks confirm source syntax and diff integrity, but they do not prove the rendered iOS 27 appearance.

The visual result must still be verified in the iOS 27 simulator or on an iOS 27 device because the original bug was produced by runtime control styling and Liquid Glass rendering.
