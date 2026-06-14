---
name: android-ux
description: Use when designing or reviewing Android UI — applies Material Design 3 UX principles covering touch targets, spacing, navigation patterns, accessibility, animation timing, and platform conventions. Includes an M3 compliance audit that scores screens across 10 categories. Complements the compose skill with design-level decisions.
---

# Android UX

This reference covers the non-obvious platform facts and **reviewing** an existing screen for M3 compliance, not the basics of building M3-correct UI.

## Non-obvious platform facts

### Foldable postures

Foldables introduce postures beyond window size classes. Detect them with `WindowInfoTracker` + `FoldingFeature` (Jetpack WindowManager), and **never place interactive content or critical information across the hinge**.

| Posture | Detection | Layout behavior |
|---|---|---|
| Flat (unfolded) | no folding feature | Treat as Medium/Expanded by width |
| Half-opened, horizontal fold (tabletop) | `HALF_OPENED` + `Orientation.HORIZONTAL` | Content top half, controls bottom half |
| Half-opened, vertical fold (book) | `HALF_OPENED` + `Orientation.VERTICAL` | List left, detail right |
| Folded (cover screen) | — | Treat as Compact |

```kotlin
@Composable
fun FoldAwareLayout() {
    val context = LocalContext.current
    val layoutInfo by WindowInfoTracker.getOrCreate(context)
        .windowLayoutInfo(context)  // accepts @UiContext — Activity, InputMethodService, or createWindowContext()
        .collectAsStateWithLifecycle(initialValue = WindowLayoutInfo(emptyList()))

    val fold = layoutInfo.displayFeatures.filterIsInstance<FoldingFeature>().firstOrNull()
    when {
        fold?.state == FoldingFeature.State.HALF_OPENED ->
            if (fold.orientation == FoldingFeature.Orientation.HORIZONTAL) TabletopLayout() else BookLayout()
        else -> StandardAdaptiveLayout()  // by window size class
    }
}
```

### M3 contrast levels (user-controlled contrast)

Compose's `dynamicLightColorScheme` / `dynamicDarkColorScheme` read the system contrast setting automatically (SDK 34+) and expose **no** contrast parameter. To offer *in-app* contrast control (Standard 0.0 / Medium 0.5 / High 1.0 tonal distance), build the scheme from `Hct` + `SchemeContent`:

```kotlin
// com.google.android.material:material (MDC-Android), package com.google.android.material.color.utilities
// Marked @RestrictTo(LIBRARY_GROUP) — internal API, may change between versions; re-check on version bumps.
val hct = Hct.fromInt(0xFF6750A4.toInt())
val scheme = SchemeContent(hct, /* isDark = */ false, /* contrastLevel = */ 1.0)
val colorScheme = lightColorScheme(
    primary = Color(scheme.primary),
    onPrimary = Color(scheme.onPrimary),
    // ... map remaining roles
)
```

For multiplatform or a stable public API, `com.materialkolor:material-color-utilities` is a KMP alternative.

### Motion: duration tokens + reduced motion

Pair M3's duration ladder with easing (`short*` → `FastOutSlowIn`; `medium*` → `Emphasized(De/Ac)celerate`; `long*`/`extraLong*` → `Emphasized`) rather than arbitrary millis. Reach for `MotionScheme` (Compose M3 1.4+) where available; otherwise hold durations at one source of truth in the theme.

| Token group | Range | Typical use |
|---|---|---|
| `short1`…`short4` | 50–200ms | Micro-interactions, state changes (ripple, selection, switch) |
| `medium1`…`medium4` | 250–400ms | Standard transitions (screen enter/exit, expansion, reveal) |
| `long1`…`long4` | 450–600ms | Container transforms, fade-through between large surfaces |
| `extraLong1`…`extraLong4` | 700–1000ms | Shared-element / hero transitions on tablets/foldables |

Animations must be interruptible and never block input. **Respect reduced motion** — Compose has no built-in `LocalReducedMotion`, so read `ANIMATOR_DURATION_SCALE` and provide one:

```kotlin
val LocalReducedMotion = staticCompositionLocalOf { false }

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    CompositionLocalProvider(LocalReducedMotion provides reduceMotion) { MaterialTheme { content() } }
}

// at the call site
AnimatedVisibility(
    visible = isVisible,
    enter = if (LocalReducedMotion.current) EnterTransition.None else fadeIn() + slideInVertically(),
) { Content() }
```

(`staticCompositionLocalOf` + keyless `remember` read the setting once per Activity; for live updates switch to `compositionLocalOf` + a `ContentObserver` on `ANIMATOR_DURATION_SCALE`.)

---

## M3 Compliance Audit

Use this when **reviewing** a screen or feature for Material Design 3 compliance — the part that's easy to skip from memory. Score each category **Pass / Partial / Fail**, then fix any Partial/Fail before shipping.

### 1. Color tokens
- All colors reference `MaterialTheme.colorScheme` roles — no hardcoded hex/ARGB.
- Correct role usage: `primary` for key actions, `secondary`/`tertiary` for less prominent / accents, `error` for errors; `on*` paired correctly; layered surfaces via `surfaceContainerLow/High`, not arbitrary grays.
- Outlines: `outline` for interactive boundaries needing 3:1 (field borders, focus rings), `outlineVariant` for decorative dividers.
- Dynamic color on Android 12+ with a static fallback.

### 2. Typography
- All text from `MaterialTheme.typography` — no inline `fontSize`/`fontWeight`.
- Correct scale: `display*` hero, `headline*` section headers, `title*` card/dialog titles, `body*` content, `label*` buttons/captions.

### 3. Shape
- Corner radii from `MaterialTheme.shapes`, not hardcoded `RoundedCornerShape`.
- Scale: `extraSmall` (4dp) chips, `small` (8dp) cards, `medium` (12dp) dialogs, `large` (16dp) sheets, `extraLarge` (28dp) FABs. Consistent shape language.

### 4. Elevation & surface
- Elevation via **tonal color** (surface containers), not drop shadows; shadow elevation reserved for dialogs/menus/FABs.
- `ElevatedCard`/`ElevatedButton` over manual `shadowElevation`.
- Container hierarchy monotonic by tone (`surfaceContainerLowest < … < Highest`) — if two adjacent layers render the same color in either theme, the elevation cue is broken.

### 5. Components
- M3 components (`androidx.compose.material3.*`), no M2 (`androidx.compose.material.*`) and no M2/M3 mixing on a screen.
- Used as intended: `FloatingActionButton` for the primary action, `Card` for grouped content, `TopAppBar` for screen-level actions.

### Quick grep checks

Run from the project root — each hit is a category-1/3/5 violation to triage before human review:

```bash
rg --type kt 'Color\(0x[0-9a-fA-F]{6,8}\)' --files-with-matches | head            # 1: hardcoded colors
rg --type kt 'RoundedCornerShape\(\s*\d+(?:\.\d+)?\s*\.dp\s*\)' --files-with-matches | head  # 3: hardcoded radii
rg --type kt 'import androidx\.compose\.material\.' --files-with-matches | head    # 5: Material 2 imports
```

### 6. Layout & spacing
- 8dp grid for padding/margins; responsive compact/medium/expanded breakpoints; screen maps to a canonical layout (Feed, List-Detail, Supporting Pane).
- **Content width constrained on wide screens** — cap body content at ~840–1040dp on Large and center it; full width is for navigation chrome, not paragraphs.
- Foldable postures handled (no content across the hinge; tabletop/book layouts where relevant).
- Dialogs centered (not full-screen) on Medium+; bottom sheets convert to side sheets on Expanded+.

### 7. Navigation
- Navigation component matches width (Bottom Bar / Rail / Drawer); items have **both icon and label**; current destination indicated via `selected` + active indicator.

### 8. Motion
- Transitions use M3 easing + duration tokens; shared elements use `Emphasized` at 300–500ms; enter/exit follow M3 (fade-through, container transform); interruptible and **respect reduced motion**.

### 9. Accessibility
- Meaningful images/icons have `contentDescription`; contrast meets WCAG AA (4.5:1 body, 3:1 large text + UI components); touch targets ≥48dp.
- **Composite items merged** with `semantics(mergeDescendants = true)` so TalkBack announces them as one unit (icon `contentDescription = null` when merged).
- **Section titles marked** `semantics { heading() }` so screen-reader users can jump between sections.
- Traversal order logical (`semantics { traversalIndex }` where needed). User-controlled contrast (Standard/Medium/High) considered if supported.

### 10. Theming consistency
- Single `MaterialTheme` (no nested/conflicting themes); light + dark both tested; custom theme extensions via `CompositionLocal`, not globals; brand colors via a custom `ColorScheme`, not per-component overrides.

### Audit summary template

```
Screen: [name]   Date: [date]

| # | Category            | Score   | Notes                  |
|---|---------------------|---------|------------------------|
| 1 | Color tokens        | Pass    |                        |
| 2 | Typography          | Partial | bodySmall hardcoded    |
| 5 | Components          | Fail    | M2 Scaffold still used |
| 6 | Layout & spacing    | Partial | No tablet breakpoint   |
| 9 | Accessibility       | Partial | Missing headings       |
…

Action items:
- [ ] ...
```
