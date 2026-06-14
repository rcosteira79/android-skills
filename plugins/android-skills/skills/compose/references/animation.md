# Animation in Jetpack Compose

This reference covers the animation traps, boundaries, and motion-token discipline, not the basics of `animate*AsState` / `AnimatedVisibility` / `AnimatedContent`. Always pass `label` for the inspector.

## `AnimatedContent` — `contentKey` on shape, not payload

For sealed wrappers (`UiState`, `Result<T>`), `AnimatedContent` re-triggers on *every* `targetState` change — so a payload change within the same shape (`Success([1,2,3])` → `Success([1,2,3,4])`) cross-fades when it shouldn't. Key on the shape:

```kotlin
AnimatedContent(
    targetState = uiState,
    contentKey = { when (it) { is Loading -> "loading"; is Success -> "success"; is Error -> "error" } },
    label = "uiState",
) { state -> when (state) { /* Loading / Success / Error */ } }
```

Now the cross-fade fires only on Loading↔Success↔Error, never on a Success-payload update. (In `transitionSpec`, combine exit+enter with **`togetherWith`** — the old `with` infix is deprecated — and `using SizeTransform(clip = false)` to animate the container size.)

## Defer animated reads to the latest phase

An animated value read in **composition** recomposes every frame; read in **layout** relayouts every frame; read in **draw** does neither. Prefer **lambda-based** modifiers (`graphicsLayer { }`, `offset { }`) over parameter-based (`graphicsLayer(alpha = …)`, `offset(x = …)`):

```kotlin
val alpha by animateFloatAsState(if (visible) 1f else 0f, label = "alpha")
Box(Modifier.graphicsLayer { this.alpha = alpha })        // draw phase only — best (not Modifier.alpha(alpha))

val xPx by animateIntAsState(if (moved) 300 else 0, label = "x")
Box(Modifier.offset { IntOffset(xPx, 0) })                 // layout phase (not Modifier.offset(x = xDp))
```

For state crossing a composable boundary (parent `scrollOffset` → child), pass a **provider lambda** (`() -> Int`) and read it inside `graphicsLayer { }`, not a snapshot value — see `compose/references/performance.md`.

## Use M3 motion tokens, not arbitrary durations

`tween(durationMillis = 347)` has no design rationale; pin to the M3 ladder (and prefer `spring()` for interruptible, natural motion). Pair each duration tier with its easing:

| Duration | ms | Easing token | Compose value |
|---|---|---|---|
| Short1–4 | 50 / 100 / 150 / 200 | Emphasized | `CubicBezierEasing(0.2f, 0f, 0f, 1f)` |
| Medium1–4 | 250 / 300 / 350 / 400 | EmphasizedDecelerate | `CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)` |
| Long1–4 | 450 / 500 / 550 / 600 | EmphasizedAccelerate | `CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)` |
| ExtraLong1–4 | 700 / 800 / 900 / 1000 | Standard / Decelerate / Accelerate | `FastOutSlowIn` / `LinearOutSlowIn` / `FastOutLinearIn` |

Spring feel: stiffness `Low`(200) / `MediumLow`(400) / `Medium`(1500) / `High`(10000) = gentle→snappy; damping `NoBouncy`(1.0) / `LowBouncy`(0.75) / `MediumBouncy`(0.5) / `HighBouncy`(0.2) = none→cartoonish. Convert a Figma spring with `dampingRatio = damping / (2 * sqrt(stiffness * mass))`.

## A few real anti-patterns

- **`Animatable` created in composition** is recreated every recomposition — always `remember { Animatable(0f) }`.
- **Mutating animated state in the composition body** (`position = position + 10f` at the top level) is an infinite recomposition loop — drive it from a `LaunchedEffect`.
- **`updateTransition` for independent properties** couples animations that don't need syncing — use separate `animate*AsState`; reserve `rememberTransition` / `updateTransition` for properties that must animate in sync from one state.

## Don't bolt `AnimatedContent` on navigation destination swaps

Navigation already animates between destinations (`NavHost.enterTransition` / `exitTransition` / `popEnterTransition` / `popExitTransition`; in **Nav3**, `NavDisplay` owns its transitions). Wrapping a destination's whole content in `AnimatedContent` double-animates — the destination swaps, then the new content cross-fades on top.

```kotlin
// WRONG — animates inside an already-animating destination
composable("list") { AnimatedContent(targetState = uiState) { … } }

// RIGHT — let the nav host own destination transitions; use AnimatedContent only for intra-screen state
NavHost(navController, startDestination = "list",
    enterTransition = { slideInHorizontally { it } + fadeIn() },
    exitTransition = { slideOutHorizontally { -it / 3 } + fadeOut() },
) { composable("list") { ListScreen(...) } }
```

See `references/navigation.md` for the Nav3 carry-over.
