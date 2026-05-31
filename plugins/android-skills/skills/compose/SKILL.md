---
name: compose
description: >
  Compose and Compose Multiplatform expert for UI development across Android, Desktop, iOS,
  and Web. Covers state management, composition, animations, navigation, performance,
  design-to-code workflows, and production crash patterns, backed by source analysis from
  androidx/androidx and JetBrains/compose-multiplatform-core. Use whenever the user mentions
  Compose, @Composable, remember, LaunchedEffect, Scaffold, NavHost, NavDisplay, MaterialTheme,
  LazyColumn, Modifier, recomposition, Compose Multiplatform/CMP, commonMain, expect/actual,
  ComposeUIViewController, UIKitView, ComposeViewport, Res.drawable/Res.string, or any
  Compose API. Also trigger on phrases like "design to compose", "build this UI",
  "implement this design", or any modern Kotlin UI question — including casual mentions
  like "my compose screen is slow". Plus focus topics: FocusRequester,
  focusProperties, onPreviewKeyEvent, D-pad, TV remote, ChromeOS, androidx.tv.material3.
---

# Compose Expert Skill

Non-opinionated, practical guidance for writing correct, performant Compose code —
across Android, Desktop, iOS, and Web. Covers Jetpack Compose and Compose Multiplatform.
Backed by analysis of actual source code from `androidx/androidx` and
`JetBrains/compose-multiplatform-core`.

## Workflow

When helping with Compose code, follow this checklist:

### 1. Understand the request
- What Compose layer is involved? (Runtime, UI, Foundation, Material3, Navigation)
- Is this a state problem, layout problem, performance problem, or architecture question?
- Is this Android-only or Compose Multiplatform (CMP)?

### 2. Analyze the design (if visual reference provided)
- If the user shares a Figma frame, screenshot, or design spec, consult `references/design-to-compose.md`
- Decompose the design into a composable tree using the 5-step methodology
- Map design tokens to MaterialTheme, spacing to CompositionLocals
- Identify animation needs — `references/animation.md` (primitives, specs, decision tree), `references/animation-recipes.md` (recipe cookbook + choreography), or `references/animation-advanced.md` (shared-element, gesture-driven, predictive back, `graphicsLayer`)

### 3. Consult the right reference
Read the relevant reference file(s) from `references/` before answering:

| Topic | Reference File |
|-------|---------------|
| `@State`, `remember`, `mutableStateOf`, state hoisting, `derivedStateOf`, `snapshotFlow` | `references/state-management.md` |
| Composable naming, slot pattern, extraction, statefulness, preview annotations, reusability, anti-patterns | `references/view-composition.md` |
| Screen-level composables, screen structure patterns, adaptive layouts | `references/screen-structure.md` |
| Modifier ordering, custom modifiers, `Modifier.Node` | `references/modifiers.md` |
| `LaunchedEffect`, `DisposableEffect`, `SideEffect`, `rememberCoroutineScope` | `references/side-effects.md` |
| `CompositionLocal`, `LocalContext`, `LocalDensity`, custom locals | `references/composition-locals.md` |
| `LazyColumn`, `LazyRow`, `LazyGrid`, `Pager`, keys, content types | `references/lists-scrolling.md` |
| `NavHost`, type-safe routes, deep links, shared element transitions, Navigation 3 (`NavDisplay`, back-stack-as-state) | `references/navigation.md` |
| `animate*AsState`, `AnimatedVisibility`, `Crossfade`, `updateTransition`, specs (spring/tween/keyframes), decision tree | `references/animation.md` |
| Animation recipes (shimmer, expandable card, parallax, FAB morph, pull-to-refresh), sequential/parallel/staggered choreography | `references/animation-recipes.md` |
| Shared element transitions, gesture-driven animations (`Animatable`, `AnchoredDraggable`, `Transformable`), predictive back, `graphicsLayer` performance | `references/animation-advanced.md` |
| `MaterialTheme`, `ColorScheme`, dynamic color, `Typography`, shapes | `references/theming-material3.md` |
| Touch targets, spacing, canonical layouts, foldables, M3 compliance audit | `android-skills:android-ux` |
| Recomposition skipping, stability, baseline profiles, benchmarking | `references/performance.md` |
| Semantics, content descriptions, traversal order, testing | `references/accessibility.md` |
| `FocusRequester`, `focusable()`, `focusProperties`, key events, D-pad, TV, keyboard, focus restoration | `references/focus-navigation.md` |
| Removed/replaced APIs, migration paths from older Compose versions | `references/deprecated-patterns.md` |
| **Styles API** (experimental): `Style {}`, `MutableStyleState`, `Modifier.styleable()` | `references/styles-experimental.md` |
| Figma/screenshot decomposition, design tokens, spacing, modifier ordering | `references/design-to-compose.md` |
| Production crash patterns, defensive coding, state/performance rules | `references/production-crash-playbook.md` |
| Compose Multiplatform, `expect`/`actual`, resources (`Res.*`), migration | `references/multiplatform.md` |
| Desktop (Window, Tray, MenuBar), iOS (UIKitView), Web (ComposeViewport) | `references/platform-specifics.md` |

### 4. Apply and verify
- Write code that follows the patterns in the reference
- Flag any anti-patterns you see in the user's existing code
- Suggest the minimal correct solution — don't over-engineer

### 5. Cite the source
When referencing Compose internals, point to the exact source file:
```
// See: compose/runtime/runtime/src/commonMain/kotlin/androidx/compose/runtime/Composer.kt
```

## Key Principles

1. **Compose thinks in three phases**: Composition → Layout → Drawing. State reads in each
   phase only trigger work for that phase and later ones.

2. **Recomposition is frequent and cheap** — but only if you help the compiler skip unchanged
   scopes. Use stable types, avoid allocations in composable bodies.

3. **Modifier order matters**. `Modifier.padding(16.dp).background(Color.Red)` is visually
   different from `Modifier.background(Color.Red).padding(16.dp)`.

4. **State should live as low as possible** and be hoisted only as high as needed. Don't put
   everything in a ViewModel just because you can.

5. **Side effects exist to bridge Compose's declarative world with imperative APIs**. Use the
   right one for the job — misusing them causes bugs that are hard to trace.

6. **Compose Multiplatform shares the runtime but not the platform**. UI code in
   `commonMain` is portable. Platform-specific APIs (`LocalContext`, `BackHandler`,
   `Window`) require `expect`/`actual` or conditional source sets.

## Source Code Verification

Always verify against **live source code** — never rely on training data alone.

### Tier 1 (Preferred): `android-sources` MCP server

When available, use the MCP tools for fast, precise lookups:

```
lookup_class(className: "LazyListState")
lookup_method(className: "Composer", methodName: "startRestartGroup")
search_in_source(query: "fun rememberLazyListState")
list_class_members(className: "Modifier")
get_class_hierarchy(className: "LazyListState")
find_references(className: "SnapshotState", methodName: "value")
```

### Tier 2 (Fallback): Raw GitHub URLs

If the MCP server is unavailable, fetch source directly:

- **AndroidX**: `https://raw.githubusercontent.com/androidx/androidx/androidx-main/{path}`
- **Directory listing**: `gh api repos/androidx/androidx/contents/{path}`
- **CMP**: `https://raw.githubusercontent.com/JetBrains/compose-multiplatform-core/jb-main/{path}`
- **AOSP platform**: `https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/{path}?format=TEXT` (base64)

### Two-layer approach
1. **Start with guidance** — read the topic-specific reference (e.g., `references/state-management.md`)
2. **Verify against live source** — use MCP tools or raw GitHub to confirm behavior

### Source tree map
```
androidx/androidx (branch: androidx-main)
├── compose/runtime/runtime/src/commonMain/kotlin/androidx/compose/runtime/
├── compose/ui/ui/src/androidMain/kotlin/androidx/compose/ui/platform/
├── compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/
├── compose/foundation/foundation/src/commonMain/kotlin/androidx/compose/foundation/
├── compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/
└── compose/navigation/navigation-compose/src/commonMain/kotlin/androidx/navigation/compose/

compose-multiplatform-core (branch: jb-main)
├── compose/ui/ui/src/desktopMain/kotlin/androidx/compose/ui/window/
├── compose/ui/ui/src/iosMain/kotlin/androidx/compose/ui/window/
├── compose/ui/ui/src/webMain/kotlin/androidx/compose/ui/window/
├── compose/ui/ui/src/skikoMain/kotlin/androidx/compose/ui/
└── compose/foundation/foundation/src/skikoMain/kotlin/androidx/compose/foundation/

compose-multiplatform (resources library)
└── components/resources/library/src/commonMain/
```

## Authoritative Docs

For guidance, best practices, or migration guides — things source code alone can't answer — prefer Google's Android Knowledge Base over web search:

```bash
android docs search "LazyColumn performance"              # ranked kb:// URLs + summaries
android docs fetch kb://android/develop/ui/compose/lists  # full content of a result
```

4800+ curated docs across Android, Wear, TV, KMP, and Glance. Use this when the internal files in `references/` don't cover your question; use source code lookups (above) when you need implementation details rather than guidance.
