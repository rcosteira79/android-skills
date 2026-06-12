# Compose Side Effects — what isn't default-obvious

A strong model already knows the effect APIs and picks them correctly by default: `LaunchedEffect(keys)` for keyed coroutines — keyed on the data it depends on, not `Unit` (avoiding both the run-once-stale bug and the changing-key infinite loop); `DisposableEffect(key) { … onDispose { } }` for listeners/resources, always with cleanup; `SideEffect` for per-composition mirroring; `rememberCoroutineScope().launch` from event handlers (never `runBlocking`); `produceState` to adapt callbacks/flows into `State`; `rememberUpdatedState` to capture a fresh callback inside a long-running effect (and *not* as a substitute for keying); `snapshotFlow` to turn Compose state into a `Flow`. Always reach for the **smallest** effect that does the job. This reference keeps the parts the default gets wrong.

## Effects are UI-owned work, not business operations

A network request, database write, or domain validation inside a `LaunchedEffect` is a scope violation even though the API allows it. `LaunchedEffect` is for *UI-owned keyed work* — observing scroll for analytics, debouncing input, restoring focus after navigation. Move repository/network calls to the ViewModel; the composable receives state. (See `android-skills:android-data-layer` and `compose/references/state-management.md` for the hoisting boundary.)

## Lifecycle effects — prefer the modern APIs (the default reaches for the legacy one)

The default still hand-rolls `DisposableEffect` + `LifecycleEventObserver` for "run X while the screen is STARTED/RESUMED." Since `lifecycle-runtime-compose` 2.8 there are purpose-built effects that replace ~90% of that boilerplate:

```kotlin
LifecycleStartEffect(Unit) {
    onStart()
    onStopOrDispose { onStop() }                          // STARTED ⇄ STOPPED, paired cleanup
}

LifecycleResumeEffect(Unit) {
    analytics.screenView("home")
    onPauseOrDispose { analytics.screenLeave("home") }    // RESUMED ⇄ PAUSED
}

// single event, no pair semantics:
LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { saveDraft() }
```

The key argument follows the `LaunchedEffect` rules. Between these three the modern APIs cover every event — reach for the legacy `DisposableEffect + LifecycleEventObserver` only on lifecycle 2.7 and older, or for an event they don't expose.

## Anti-patterns the default commits

### Don't manufacture event-flag state to trigger an effect — the click *is* the event

```kotlin
// WRONG — invented state machine for what's already a single event
var shouldShowSnackbar by remember { mutableStateOf(false) }
LaunchedEffect(shouldShowSnackbar) {
    if (shouldShowSnackbar) { snackbarHostState.showSnackbar("Done"); shouldShowSnackbar = false }
}
Button(onClick = { shouldShowSnackbar = true }) { Text("Save") }

// RIGHT — launch from the event handler
val scope = rememberCoroutineScope()
Button(onClick = { scope.launch { snackbarHostState.showSnackbar("Done") } }) { Text("Save") }
```

### Don't drive side work from an `if` in the composable body

A `Boolean` like `focused` / `isExpanded` / `selected` gating a side effect from a plain `if` in the body fires on every recomposition and has no cleanup when it flips back. The condition must drive an *effect*, not a body branch.

```kotlin
// WRONG — runs on every recomposition while focused; no cancellation when focus is lost
if (focused) preloadImages(profile.avatarUrls)

// RIGHT — keyed effect; cancels automatically when the flag flips
LaunchedEffect(profile.id, focused) {
    if (focused) preloadImages(profile.avatarUrls)
}
```

### `snapshotFlow` needs a terminal operator

Flow chains are cold — without `collect` / `first` / `toList` the chain is a no-op. Use `onEach` (not `map`) for side effects, then `collect`.

```kotlin
// WRONG — no terminal; the chain never runs
snapshotFlow { listState.firstVisibleItemIndex }.distinctUntilChanged().map { vm.onScroll(it) }

// RIGHT
snapshotFlow { listState.firstVisibleItemIndex }.distinctUntilChanged().collect { vm.onScroll(it) }
```

See `android-skills:kotlin-flows` for the cold-vs-hot and terminal-operator rules.

### `onSizeChanged` writing state read in composition

`onSizeChanged` fires after layout; writing a `MutableState` from it that's then read in composition creates a back-writing feedback loop (layout → invalidate → layout → …). See `compose/references/state-management.md` → "Cross-Phase Back-Writing" for the `Modifier.decorateMeasureConstraints` fix.
