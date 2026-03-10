---
name: android-ux
description: Use when designing or reviewing Android UI — applies Material Design 3 UX principles covering touch targets, spacing, navigation patterns, accessibility, animation timing, and platform conventions. Complements the compose skill with design-level decisions.
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

### Minimum contrast

- Body text: **4.5:1** against background (WCAG AA)
- Large text (18sp+ / 14sp+ bold) and UI components: **3:1**
- Test in both light and dark themes independently

### Dynamic type

Respect the user's system font size — never clamp `fontSize` to a fixed value in a way that overrides scaling. Use `sp` units (not `dp`) for text so the system can scale it.

---

## Animation Timing

| Type | Duration | Easing |
|---|---|---|
| Micro-interactions (button press, toggle) | 100–150ms | `FastOutSlowIn` |
| Standard transitions (screen enter/exit) | 200–300ms | `FastOutSlowIn` / `EmphasizedDecelerate` |
| Complex choreography (shared elements) | 300–500ms | `Emphasized` |

Rules:
- Animations must be **interruptible** — a tap during animation should respond immediately
- Never block user input during an animation
- Respect `LocalReducedMotion` — skip or simplify motion when the user has enabled reduced motion:

```kotlin
val reducedMotion = LocalReducedMotion.current

AnimatedVisibility(
    visible = isVisible,
    enter = if (reducedMotion) EnterTransition.None else fadeIn() + slideInVertically()
) {
    Content()
}
```

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
