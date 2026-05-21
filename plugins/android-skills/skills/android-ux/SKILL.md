---
name: android-ux
description: Use when designing or reviewing Android UI — applies Material Design 3 UX principles covering touch targets, spacing, navigation patterns, accessibility, animation timing, and platform conventions. Includes an M3 compliance audit that scores screens across 10 categories. Complements the compose skill with design-level decisions.
---

# Android UX

Material Design 3 and Android platform UX principles for building apps that feel native, accessible, and responsive.

## Touch & Interaction

### Touch target size

- Minimum **48×48dp** for any interactive element (buttons, icons, checkboxes, list items)
- If the visual element is smaller, expand the touch area with `Modifier.minimumInteractiveComponentSize()` or extra padding
- Minimum **8dp gap** between adjacent touch targets to prevent mis-taps

```kotlin
// Visual icon is 24dp but touch target is 48dp
IconButton(onClick = onClose) {          // IconButton enforces 48dp by default
    Icon(Icons.Default.Close, contentDescription = "Close")
}

// Custom component: expand tap area explicitly
Box(
    modifier = Modifier
        .size(48.dp)                     // Touch target
        .wrapContentSize(Alignment.Center)
) {
    Icon(modifier = Modifier.size(24.dp), ...)
}
```

### Press feedback

- All interactive elements must give visual feedback within **100ms** of a tap
- Use **Material state layers** (ripple, highlight) — never suppress them on tappable surfaces
- Apply subtle scale (0.95–1.05) on press for cards and prominent CTAs

### Gestures

- Don't interfere with system gestures: predictive back (Android 13+), home swipe, notification pull-down
- One primary gesture per screen region — avoid conflicts between swipe-to-dismiss and swipe-to-scroll
- Always provide a visible control as an alternative to any gesture-only action

### Haptic feedback

Use haptics to confirm significant actions (destructive operations, long press, toggle):

```kotlin
val haptic = LocalHapticFeedback.current
Button(onClick = {
    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
    onDelete()
}) { Text("Delete") }
```

---

## Navigation Patterns

### Top-level navigation

- **Bottom Navigation Bar** for 3–5 top-level destinations — max 5 items, each with icon + label
- **Navigation Rail** on medium screens (600dp+), **Navigation Drawer** on large screens (840dp+)
- Use `NavigationSuiteScaffold` to adapt automatically across screen sizes

```kotlin
// Correct: both icon and label
NavigationBarItem(
    icon = { Icon(Icons.Default.Home, contentDescription = null) },
    label = { Text("Home") },
    selected = currentDestination?.hasRoute<Home>() == true,
    onClick = { navController.navigate(Home) }
)

// Wrong: icon only (breaks accessibility and usability)
NavigationBarItem(
    icon = { Icon(Icons.Default.Home, contentDescription = "Home") },
    selected = ...,
    onClick = ...
)
```

### Back and predictive back

- All screens reachable via deep navigation must support back — never trap the user
- Opt in to **predictive back** (Android 13+): set `android:enableOnBackInvokedCallback="true"` in the manifest and use `BackHandler` in Compose
- Modals and bottom sheets must offer a visible close affordance **and** support swipe-down to dismiss

### Safe areas

Keep primary content and touch targets clear of:
- Status bar and navigation bar insets
- Gesture exclusion zones (bottom edge)
- Display cutouts (punch-hole cameras, curved edges)

```kotlin
Scaffold(
    modifier = Modifier.fillMaxSize()
) { innerPadding ->
    // innerPadding already accounts for system bars — always consume it
    LazyColumn(contentPadding = innerPadding) { ... }
}
```

Never hardcode top/bottom padding to approximate system bar heights — use `WindowInsets` APIs.

---

## Spacing & Layout

- Use an **8dp base grid** for all spacing, margins, and padding — multiples of 4dp are acceptable for micro-spacing
- Minimum body text size: **14sp** (prefer 16sp for reading-heavy screens) — smaller sizes trigger iOS auto-zoom and hurt Android readability
- Avoid horizontal scroll — it breaks expected mobile scrolling conventions
- Design **mobile-first**, then scale up to tablet/foldable

### Adaptive layouts

Scale navigation and content layout based on window size class:

| Window width | Navigation | Layout |
|---|---|---|
| Compact (<600dp) | Bottom Bar | Single pane |
| Medium (600–840dp) | Navigation Rail | Two pane optional |
| Expanded (>840dp) | Navigation Drawer | Two pane |

### Canonical layouts

M3 defines three canonical layout patterns. Start from one of these rather than building from a raw grid:

- **Feed** — browsable collection of items (social feed, news, product grid). Single column on compact, 2-column on medium, 3+ columns on expanded.
- **List-Detail** — list of items with detailed content (email, contacts, file browser). Single pane with navigation on compact, side-by-side list (1/3) + detail (2/3) on medium+.
- **Supporting Pane** — primary content with supplementary info (document + properties, video + comments). Stacked on compact, side-by-side (2/3 primary + 1/3 supporting) on medium+.

### Foldable postures

Foldable devices introduce postures beyond standard window size classes. Use `WindowInfoTracker` and `FoldingFeature` from Jetpack WindowManager to detect them:

| Posture | Description | Layout behavior |
|---|---|---|
| Flat (unfolded) | Device fully open | Treat as Medium or Expanded based on width |
| Half-opened (tabletop) | Horizontal fold, bottom half on surface | Content on top half, controls on bottom half |
| Half-opened (book) | Vertical fold, held like a book | List on left half, detail on right half |
| Folded | Device closed, cover screen | Treat as Compact |

**Critical rule:** Never place interactive content or critical information across the hinge area.

```kotlin
@Composable
fun FoldAwareLayout() {
    val context = LocalContext.current
    val layoutInfo by WindowInfoTracker.getOrCreate(context)
        .windowLayoutInfo(context)  // accepts @UiContext — Activity, InputMethodService, or createWindowContext()
        .collectAsStateWithLifecycle(initialValue = WindowLayoutInfo(emptyList()))

    val foldingFeature = layoutInfo.displayFeatures
        .filterIsInstance<FoldingFeature>()
        .firstOrNull()

    when {
        foldingFeature?.state == FoldingFeature.State.HALF_OPENED -> {
            if (foldingFeature.orientation == FoldingFeature.Orientation.HORIZONTAL) {
                TabletopLayout()  // top: content, bottom: controls
            } else {
                BookLayout()  // left: list, right: detail
            }
        }
        else -> {
            // Standard adaptive layout based on window size class
            StandardAdaptiveLayout()
        }
    }
}
```

---

## Accessibility

### Content descriptions

Every `Icon` and `Image` that carries meaning needs a `contentDescription`. Purely decorative elements pass `null`.

```kotlin
// Meaningful icon
Icon(Icons.Default.Favorite, contentDescription = "Add to favourites")

// Decorative — screen reader skips it
Icon(Icons.Default.Circle, contentDescription = null)
```

### Semantics

Use `Modifier.semantics` to express roles, states, and actions that aren't obvious from the visual structure:

```kotlin
Box(
    modifier = Modifier.semantics {
        role = Role.Button
        stateDescription = if (isExpanded) "Expanded" else "Collapsed"
        onClick(label = "Toggle section") { onToggle(); true }
    }
)
```

### Grouping related elements

Use `mergeDescendants = true` to announce a composite item (e.g. a row with an icon and text) as a single unit instead of separate elements:

```kotlin
Row(
    modifier = Modifier.semantics(mergeDescendants = true) {}
) {
    Icon(Icons.Default.Star, contentDescription = null)  // null — merged into parent
    Text("4.8 rating")
}
// TalkBack announces: "4.8 rating"
```

Without `mergeDescendants`, TalkBack would announce the icon and text as two separate focusable items.

### Section headings

Mark section titles with `heading()` so screen reader users can jump between sections:

```kotlin
Text(
    text = "Recent Orders",
    style = MaterialTheme.typography.titleMedium,
    modifier = Modifier.semantics { heading() }
)
```

### Minimum contrast

- Body text: **4.5:1** against background (WCAG AA)
- Large text (18sp+ / 14sp+ bold) and UI components: **3:1**
- Test in both light and dark themes independently

### M3 contrast levels

Material Design 3 supports three contrast levels that adjust the tonal distance between paired color roles (e.g., `primary` and `onPrimary`):

| Level | Value | Effect |
|---|---|---|
| Standard | 0.0 | Default tonal distance |
| Medium | 0.5 | Increased tonal distance, easier to read |
| High | 1.0 | Maximum tonal distance, highest legibility |

Compose's `dynamicLightColorScheme`/`dynamicDarkColorScheme` do **not** expose a contrast parameter — they read the system's current setting automatically (SDK 34+). To offer in-app contrast control, use `Hct` and `SchemeContent` from MDC-Android:

```kotlin
// These classes live in com.google.android.material:material (MDC-Android)
// Package: com.google.android.material.color.utilities
// Note: marked @RestrictTo(LIBRARY_GROUP) — internal API, may change between versions

val hct = Hct.fromInt(0xFF6750A4.toInt())
val scheme = SchemeContent(hct, /* isDark = */ false, /* contrastLevel = */ 1.0)

val colorScheme = lightColorScheme(
    primary = Color(scheme.primary),
    onPrimary = Color(scheme.onPrimary),
    // ... map remaining roles from scheme
)
```

Since these are internal MDC APIs, check for updates when bumping Material library versions. Third-party KMP alternatives exist (e.g., `com.materialkolor:material-color-utilities`) if you need multiplatform support or a stable public API.

### Dynamic type

Respect the user's system font size — never clamp `fontSize` to a fixed value in a way that overrides scaling. Use `sp` units (not `dp`) for text so the system can scale it.

---

## Animation Timing

| Type | Duration | Easing |
|---|---|---|
| Micro-interactions (button press, toggle) | 100–150ms | `FastOutSlowIn` |
| Standard transitions (screen enter/exit) | 200–300ms | `FastOutSlowIn` / `EmphasizedDecelerate` |
| Complex choreography (shared elements) | 300–500ms | `Emphasized` |

### M3 motion duration tokens

Material 3 ships a 16-step duration ladder. When pairing motion duration with the easing rule above, prefer tokens over arbitrary millisecond values — they survive theme changes and stay consistent across components.

| Token group | Range | Typical use |
|---|---|---|
| `short1` … `short4` | 50–200ms | Micro-interactions, state changes (ripples, selection, switches) |
| `medium1` … `medium4` | 250–400ms | Standard transitions (screen enter/exit, expansion, reveal) |
| `long1` … `long4` | 450–600ms | Container transforms, fade-through between large surfaces |
| `extraLong1` … `extraLong4` | 700–1000ms | Shared-element choreography, hero transitions on tablets/foldables |

The token tier maps directly to the easing rule: `short*` with `FastOutSlowIn`, `medium*` with `EmphasizedDecelerate`/`EmphasizedAccelerate`, `long*`/`extraLong*` with `Emphasized`. Reach for `MotionScheme` (Compose Material 3 1.4+) where available; otherwise hold the duration value at a single source of truth in your theme rather than per-call-site.

Rules:
- Animations must be **interruptible** — a tap during animation should respond immediately
- Never block user input during an animation
- Respect reduced motion settings — skip or simplify motion when the user has enabled "Remove animations" in system accessibility settings. Compose does not provide a built-in `LocalReducedMotion` CompositionLocal, so create one or check the system setting:

```kotlin
// Option 1: Check system setting via CompositionLocal (create once, provide from theme)
val LocalReducedMotion = staticCompositionLocalOf {
    false // default: animations enabled
}

// In your theme, read the system setting:
@Composable
fun AppTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f
        ) == 0f
    }
    CompositionLocalProvider(LocalReducedMotion provides reduceMotion) {
        MaterialTheme(...) { content() }
    }
}

// Then use it in composables:
val reducedMotion = LocalReducedMotion.current

AnimatedVisibility(
    visible = isVisible,
    enter = if (reducedMotion) EnterTransition.None else fadeIn() + slideInVertically()
) {
    Content()
}
```

> **Design note:** `staticCompositionLocalOf` and keyless `remember` mean the value is read once per Activity lifecycle. If the user toggles "Remove animations" in system settings and returns to the app, the stale value persists until the Activity is recreated. This is intentional — live-updating this setting is overkill for most apps. If you do need live updates, switch to `compositionLocalOf` and observe `ANIMATOR_DURATION_SCALE` via a `ContentObserver`.

---

## Forms & Input

- Mobile input height: **≥48dp** to meet touch target requirements
- Use semantic `KeyboardOptions` to trigger the correct keyboard:

```kotlin
TextField(
    value = email,
    onValueChange = { email = it },
    keyboardOptions = KeyboardOptions(
        keyboardType = KeyboardType.Email,
        imeAction = ImeAction.Next
    )
)
```

| Input type | `keyboardType` |
|---|---|
| Email | `KeyboardType.Email` |
| Phone | `KeyboardType.Phone` |
| Number (integer) | `KeyboardType.Number` |
| Password | `KeyboardType.Password` |
| URL | `KeyboardType.Uri` |

- Enable autofill with `Modifier.semantics { contentType = ContentType.EmailAddress }`
- Show a password visibility toggle on all password fields
- Validate inline on focus-out, not on every keystroke

---

## M3 Compliance Audit

Use this when reviewing a screen or feature for Material Design 3 compliance. Score each category as **Pass**, **Partial**, or **Fail**, then address any Partial/Fail items before shipping.

### 1. Color tokens

- All colors reference `MaterialTheme.colorScheme` roles — no hardcoded hex/ARGB values
- Correct role usage: `primary` for key actions, `secondary` for less prominent elements, `tertiary` for accents, `error` for error states
- `surface`, `surfaceVariant`, `surfaceContainerLow/High` used for layered surfaces — not arbitrary grays
- `on*` colors paired correctly (e.g. text on `primary` uses `onPrimary`)
- Outlines paired correctly — `outline` for interactive boundaries needing 3:1 contrast (text field borders, focus rings), `outline-variant` for decorative dividers
- Dynamic color supported on Android 12+ (`dynamicLightColorScheme` / `dynamicDarkColorScheme`) with a static fallback

### 2. Typography

- All text styles come from `MaterialTheme.typography` — no inline `fontSize`/`fontWeight` overrides
- Correct scale usage: `display*` for hero text, `headline*` for section headers, `title*` for card/dialog titles, `body*` for content, `label*` for buttons and captions
- No use of deprecated or custom text styles that bypass the type scale

### 3. Shape

- Corner radii come from `MaterialTheme.shapes` — not hardcoded `RoundedCornerShape` values
- Correct shape scale: `extraSmall` (4dp) for chips/small elements, `small` (8dp) for cards, `medium` (12dp) for dialogs, `large` (16dp) for sheets, `extraLarge` (28dp) for FABs
- Consistent shape language across the screen — don't mix sharp and rounded arbitrarily

### 4. Elevation & surface

- Elevation expressed through **tonal color** (surface containers), not drop shadows — M3 uses tonal elevation
- Shadow elevation reserved for components that need it (dialogs, menus, FABs)
- `ElevatedCard`, `ElevatedButton` used instead of manual `shadowElevation` on generic surfaces
- Surface container hierarchy is monotonic by tone: `surfaceContainerLowest < surfaceContainerLow < surfaceContainer < surfaceContainerHigh < surfaceContainerHighest`. If two adjacent layers render at the same color in either theme, the elevation cue is broken

### 5. Components

- Using M3 components (`androidx.compose.material3.*`), not Material 2 (`androidx.compose.material.*`)
- No M2/M3 component mixing on the same screen
- Components used as intended: `FloatingActionButton` for the primary screen action, `Card` for grouped content, `TopAppBar` for screen-level actions — not repurposed for unrelated patterns

### Quick grep checks

Three one-liners that surface the most common M3 violations across an Android module. Run from the project root:

```bash
# 1. Hardcoded color literals in Compose — should be MaterialTheme.colorScheme.* roles
rg --type kt 'Color\(0x[0-9a-fA-F]{6,8}\)' --files-with-matches | head

# 2. Hardcoded corner radii — should reference MaterialTheme.shapes.*
rg --type kt 'RoundedCornerShape\(\s*\d+(?:\.\d+)?\s*\.dp\s*\)' --files-with-matches | head

# 3. Material 2 import contamination — should be androidx.compose.material3.*
rg --type kt 'import androidx\.compose\.material\.' --files-with-matches | head
```

The grep output gives the audit a concrete starting list — each hit is a category-1, category-3, or category-5 violation respectively, before any human review begins.

### 6. Layout & spacing

- 8dp grid respected for all padding and margins
- Content width constrained on wide screens (no full-bleed text on tablets) — cap body content at 840–1040dp on Large (1200dp+) and Extra-large (1600dp+) and center it; the full window width is for navigation chrome, not paragraphs
- Responsive breakpoints applied: compact / medium / expanded window size classes
- Screen maps to a canonical layout (Feed, List-Detail, or Supporting Pane) where applicable
- Foldable postures handled: no content across hinge, tabletop/book mode layouts where relevant
- Dialogs centered (not full-screen) on Medium and wider window classes — full-screen dialogs are a Compact-only pattern
- Bottom sheets convert to side sheets on Expanded and wider — a bottom sheet stretched across a tablet wastes the horizontal axis and forces awkward thumb reach

### 7. Navigation

- Navigation component matches screen width (Bottom Bar / Rail / Drawer)
- Items have both icon and label
- Current destination visually indicated via `selected` state with active indicator

### 8. Motion

- Transitions use M3 easing and duration tokens (see Animation Timing section)
- Shared element transitions use `Emphasized` easing at 300–500ms
- Enter/exit patterns follow M3 conventions (fade through, container transform)
- Animations are interruptible and respect reduced motion

### 9. Accessibility

- All meaningful images/icons have `contentDescription`
- Contrast ratios meet WCAG AA (4.5:1 body, 3:1 large text and UI components)
- M3 contrast levels considered (Standard/Medium/High) if the app supports user-controlled contrast
- Touch targets meet 48dp minimum
- Screen reader traversal order is logical (`semantics { traversalIndex }` where needed)
- Section headings marked with `semantics { heading() }`

### 10. Theming consistency

- Single `MaterialTheme` wrapping the app — no nested or conflicting themes
- Light and dark themes both tested and functional
- Custom theme extensions (if any) use `CompositionLocal`, not global objects
- Brand colors integrated via custom `ColorScheme`, not by overriding individual component colors

### Audit summary template

```
Screen: [name]
Date: [date]

| # | Category              | Score   | Notes                  |
|---|-----------------------|---------|------------------------|
| 1 | Color tokens          | Pass    |                        |
| 2 | Typography            | Partial | bodySmall hardcoded    |
| 3 | Shape                 | Pass    |                        |
| 4 | Elevation & surface   | Pass    |                        |
| 5 | Components            | Fail    | M2 Scaffold still used |
| 6 | Layout & spacing      | Partial | No tablet breakpoint   |
| 7 | Navigation            | Pass    |                        |
| 8 | Motion                | Pass    |                        |
| 9 | Accessibility         | Partial | Missing headings       |
| 10| Theming consistency   | Pass    |                        |

Action items:
- [ ] ...
```

---

## Checklist

Before shipping any screen, verify:

- [ ] All interactive elements are ≥48×48dp with ≥8dp spacing between them
- [ ] Press feedback is visible within 100ms (ripple or state layer present)
- [ ] Back navigation works from every screen state
- [ ] Safe area insets consumed via `Scaffold` / `WindowInsets` (no hardcoded padding)
- [ ] All icons have `contentDescription` or `null` where decorative
- [ ] Text uses `sp` units
- [ ] Tested in both light and dark themes
- [ ] Predictive back enabled if targeting Android 13+
- [ ] Reduced motion respected
- [ ] Keyboard type set correctly on all text inputs
- [ ] Foldable: no interactive content or critical information placed across the hinge
- [ ] Large screens: content width constrained (not stretching to fill ultra-wide)
