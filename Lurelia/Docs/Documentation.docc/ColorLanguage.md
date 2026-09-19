# Lurelia Color Language

## Color Treatment for User Choice

`RoutineDetailView` is the source of truth for Lurelia's treatment of UI whose identity color is explicitly chosen by the user.

This applies to content such as routines, routine tasks, habits, and other models where the user selects the identifying color. It does **not** define the treatment for Lurelia-owned UI where the user does not choose a color.

The user's chosen color should strongly identify the content without becoming a completely flat, opaque surface. The canonical language combines Lurelia's dark glass foundation with a substantial user-color tint, a stronger same-color border, subtle same-color depth, and full-strength color for selected or high-emphasis elements.

### Canonical Variables

- `routineTint` — the user's chosen routine color in `RoutineDetailView`; this is the canonical identity-color variable.
- `LColors.glassSurface` — Lurelia's neutral dark glass base beneath the user color.
- Other views may call the equivalent color `accent`, `accentColor`, or another model-specific name. Those variables should perform the same role as `routineTint` when this language is applied.

### Canonical Layering Order

1. Draw the component using `LColors.glassSurface` as the base.
2. Overlay the same shape using `routineTint` at the opacity appropriate to its hierarchy.
3. Stroke the shape using `routineTint` at a stronger opacity than the fill overlay.
4. Where the component needs depth, use a restrained shadow derived from `routineTint`.
5. Use full-strength `routineTint` selectively for active controls, selected states, important icons, progress, and other high-emphasis UI.

### Primary / Hero Surface

The large identifying surface in `RoutineDetailView` is the strongest expression of the user's chosen color.

```swift
RoundedRectangle(cornerRadius: ..., style: .continuous)
    .fill(LColors.glassSurface)
    .overlay {
        RoundedRectangle(cornerRadius: ..., style: .continuous)
            .fill(routineTint.opacity(0.30))
    }
    .overlay {
        RoundedRectangle(cornerRadius: ..., style: .continuous)
            .strokeBorder(routineTint.opacity(0.55), lineWidth: 1)
    }
```

Canonical values:

- Base: `LColors.glassSurface`
- User-color overlay: `routineTint.opacity(0.30)`
- Border: `routineTint.opacity(0.55)`
- Subtle same-color depth/shadow: approximately `routineTint.opacity(0.16)` where used by the source view

The hero should therefore read as a **colored dark-glass surface**, not as faint colored transparency and not as a completely solid block of `routineTint`.

### Secondary / Supporting Surfaces

Smaller cards and supporting surfaces retain the same formula while stepping the user color down slightly so the hero remains visually dominant.

```swift
RoundedRectangle(cornerRadius: ..., style: .continuous)
    .fill(LColors.glassSurface)
    .overlay {
        RoundedRectangle(cornerRadius: ..., style: .continuous)
            .fill(routineTint.opacity(0.22))
    }
    .overlay {
        RoundedRectangle(cornerRadius: ..., style: .continuous)
            .strokeBorder(routineTint.opacity(0.50), lineWidth: 1)
    }
```

Canonical supporting values:

- Base: `LColors.glassSurface`
- User-color overlay: approximately `routineTint.opacity(0.22)`
- Border: approximately `routineTint.opacity(0.50)`

The exact component hierarchy may justify small differences, but `RoutineDetailView` remains the reference. Do not reduce ordinary user-colored surfaces to a faint atmospheric tint unless that reduced emphasis is intentionally part of the hierarchy.

### Full-Strength User Color

`routineTint` may be used at full strength when the UI needs a clear active or identifying state. Examples include:

- Primary/active controls
- Selected states
- Important icons
- Progress indicators and fills
- Active schedule/day states
- Other deliberate emphasis elements

These stronger accents are supported by the tinted glass surfaces around them. They should not turn every surface into a flat full-strength color.

### Consistency Rule

When a component represents something with a user-selected identity color, prefer this `RoutineDetailView` language instead of inventing a separate opacity system for that feature.

In particular, avoid the weaker Exhibit A / Kanban-style treatment as the default user-color language:

```swift
accentColor.opacity(0.10) // surface
accentColor.opacity(0.35) // border
```

That treatment reads primarily as dark/translucent UI with a faint atmospheric color. The canonical `RoutineDetailView` treatment intentionally allows the user's color to participate much more strongly in the surface itself.

**Source of truth:** `RoutineDetailView`.