# Jetpack Compose Side Effects Reference

Compose is declarative, but apps must interact with the imperative world: launch coroutines, register listeners, manage resources. Side effects are the bridge. Understanding when and how to use them is essential for correctness.

## Pick the Smallest Effect That Does the Job

**Pick the smallest effect that does the job.** Reaching for `LaunchedEffect` when `rememberCoroutineScope` would do is overuse; reaching for `SideEffect` when `LaunchedEffect(key)` is needed misses the point.

| Need | API |
|---|---|
| Run a coroutine when keys change; cancel when they change again or composable leaves | `LaunchedEffect(keys)` |
| Run cleanup when keys change or composable leaves | `DisposableEffect(keys) { ... onDispose { ... } }` |
| Run after every successful composition (no cleanup, no keys) | `SideEffect` |
| Launch from an event handler (click, gesture, drag) | `rememberCoroutineScope().launch` |
| Convert non-Compose state source to Compose `State` | `produceState` |
| Keep latest value of a frequently-changing callback in a long-running effect | `rememberUpdatedState` |
| Convert Compose state to `Flow` | `snapshotFlow` |

## Effects Are for UI-Owned Work, Not Business Operations

**Composable bodies emit UI; they don't perform business operations.** A network request, database write, or domain validation inside a `LaunchedEffect` is a scope violation, even though the API technically permits it. `LaunchedEffect` is for *UI-owned keyed work* — observing scroll for analytics, debouncing user input, restoring focus after navigation. Move repository/network calls to a ViewModel; the composable receives state.

See `android-skills:android-data-layer` for repository patterns and `compose/references/state-management.md` for the state-hoisting boundary between UI and ViewModel.

## The Effect Mental Model

Compose recomposes when state changes. Effects are blocks of code that run outside the normal composition and recomposition cycle:

- **Composition**: Calculate the UI tree
- **Side effects**: Run imperative code (coroutines, callbacks, lifecycle events)
- **Layout**: Measure and position elements
- **Drawing**: Render to screen

Effects run *after* composition succeeds. If composition fails, the effect doesn't run.

```kotlin
@Composable
fun MyScreen() {
    // This runs during composition
    val state = remember { mutableStateOf("initial") }

    // This runs AFTER composition, and only when 'state.value' changes
    LaunchedEffect(state.value) {
        println("State changed to: ${state.value}")
    }

    // This runs after every composition (use sparingly)
    SideEffect {
        println("Recomposition happened")
    }

    // This runs when composable leaves composition
    DisposableEffect(Unit) {
        onDispose {
            println("Composable is leaving composition")
        }
    }

    Button(onClick = { state.value = "updated" }) {
        Text(state.value)
    }
}
```

## SideEffect — After Every Successful Composition

`SideEffect` runs after *every* successful composition. It has no cleanup, no keys, and always executes.

```kotlin
@Composable
fun MyComposable() {
    var clickCount by remember { mutableStateOf(0) }

    // Runs after every recomposition
    SideEffect {
        println("Recomposed! Click count: $clickCount")
    }

    Button(onClick = { clickCount++ }) {
        Text("Clicks: $clickCount")
    }
}
```

### Use Cases

- Synchronizing Compose state with external systems (e.g., Analytics logging)
- Updating non-Compose UI elements
- One-way synchronization where cleanup isn't needed

```kotlin
@Composable
fun TrackScreenView(screenName: String) {
    SideEffect {
        Analytics.logScreenView(screenName)
    }
}
```

**Do:** Use for simple, stateless synchronization.
**Don't:** Use for resource allocation (use `DisposableEffect` instead).

### SideEffect vs Keyed LaunchedEffect for Analytics

**`SideEffect` runs after every successful composition** — use when the action should publish *every time the composable renders*, e.g., mirroring snapshot state to a non-Compose system.

**`LaunchedEffect(key)` runs once per unique key value** — use when the action should fire *once per logical event*, not per recomposition. Example: an impression log fires once when an article becomes visible, not every time it recomposes.

```kotlin
// SideEffect — mirror current state to a non-Compose observable every frame
SideEffect { externalStateBridge.update(currentState) }

// LaunchedEffect — fire once per impression
LaunchedEffect(article.id) { analytics.logImpression(article.id) }
```

**Do:** Use `LaunchedEffect(key)` for impressions, screen-view events, and anything that should fire once per logical state change.
**Don't:** Use `SideEffect` for analytics events that should fire once per impression — it will re-fire on every recomposition.

Source: `compose/runtime/runtime/src/commonMain/kotlin/androidx/compose/runtime/Effects.kt`

## LaunchedEffect(key) — Coroutines Scoped to Composition

`LaunchedEffect` launches a coroutine in a scope tied to the composable's lifecycle. The coroutine is cancelled if the key changes or the composable leaves composition.

```kotlin
@Composable
fun DataLoader(userId: String) {
    var data by remember { mutableStateOf<String?>(null) }

    // Coroutine runs when userId changes or composable enters composition
    LaunchedEffect(userId) {
        data = loadData(userId)  // suspend function
    }

    Text(data ?: "Loading...")
}
```

### Key Selection

```kotlin
// Key = Unit: runs once when composable enters composition, never cancels/restarts
LaunchedEffect(Unit) {
    setupOnce()
}

// Key = specific value: reruns whenever the value changes
var userId by remember { mutableStateOf("user1") }
LaunchedEffect(userId) {
    loadUserData(userId)  // reruns when userId changes
}

// Multiple keys: reruns if ANY key changes
LaunchedEffect(userId, postId) {
    loadUserAndPost(userId, postId)
}

// No key parameter (not recommended): equivalent to Unit
LaunchedEffect {
    setupOnce()
}
```

### Common Mistake: Wrong Key Selection

```kotlin
// Don't: Key changes every recomposition (creates infinite loop)
@Composable
fun BadKeySelection() {
    var count by remember { mutableStateOf(0) }
    val randomKey = Random.nextInt()  // Changes every recomposition!

    LaunchedEffect(randomKey) {
        count++  // This launches infinitely
    }

    Text("Count: $count")
}

// Do: Use stable keys that represent the data you depend on
@Composable
fun GoodKeySelection(userId: String) {
    var userData by remember { mutableStateOf<User?>(null) }

    LaunchedEffect(userId) {
        userData = fetchUser(userId)
    }

    Text(userData?.name ?: "Loading...")
}
```

### Cancellation Behavior

```kotlin
@Composable
fun ResourceUser(shouldLoad: Boolean) {
    LaunchedEffect(shouldLoad) {
        if (shouldLoad) {
            val resource = acquireResource()
            try {
                delay(5000)  // Long operation
                processResource(resource)
            } finally {
                resource.close()  // Runs even if cancelled
            }
        }
    }
}

// If shouldLoad becomes false, the LaunchedEffect coroutine is cancelled.
// The finally block ensures cleanup.
```

## DisposableEffect(key) — For Cleanup

`DisposableEffect` runs after composition and requires a cleanup function (onDispose). Use for listeners, registrations, and resources.

```kotlin
@Composable
fun LocationListener(context: Context) {
    DisposableEffect(context) {
        val listener = LocationListener { location ->
            println("Location: $location")
        }
        // Register listener
        locationManager.requestLocationUpdates(
            LocationManager.GPS_PROVIDER,
            0,
            0f,
            listener
        )

        // Cleanup: unregister listener
        onDispose {
            locationManager.removeUpdates(listener)
        }
    }
}
```

### Common Pattern: Lifecycle Events

```kotlin
@Composable
fun ScreenWithLifecycle() {
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> println("Screen resumed")
                Lifecycle.Event.ON_PAUSE -> println("Screen paused")
                else -> {}
            }
        }
        lifecycle.addObserver(observer)

        onDispose {
            lifecycle.removeObserver(observer)
        }
    }
}
```

**Do:** Use `DisposableEffect` for every resource you allocate.
**Don't:** Forget the `onDispose` block (resource leaks result).

Source: `compose/runtime/runtime/src/commonMain/kotlin/androidx/compose/runtime/Effects.kt`

## rememberCoroutineScope — Launching from Event Handlers

`rememberCoroutineScope` provides a coroutine scope tied to the composable. Use it to launch coroutines from event handlers (clicks, gestures).

```kotlin
@Composable
fun ButtonWithAsync() {
    val scope = rememberCoroutineScope()
    var result by remember { mutableStateOf("") }

    Button(
        onClick = {
            // Launch coroutine from click handler
            scope.launch {
                result = fetchData()
            }
        }
    ) {
        Text("Fetch")
    }

    Text(result)
}
```

### Do vs Don't

```kotlin
// Don't: regular function scope doesn't work
@Composable
fun BadAsync() {
    var result by remember { mutableStateOf("") }

    Button(
        onClick = {
            runBlocking {  // Blocks UI thread!
                result = fetchData()
            }
        }
    ) {
        Text("Fetch")
    }
}

// Do: use rememberCoroutineScope
@Composable
fun GoodAsync() {
    val scope = rememberCoroutineScope()
    var result by remember { mutableStateOf("") }

    Button(
        onClick = {
            scope.launch {
                result = fetchData()
            }
        }
    ) {
        Text("Fetch")
    }
}
```

## rememberUpdatedState — Capturing Latest Values

Long-running effects need the latest value of frequently-changing state, but you don't want to restart the effect on every change.

```kotlin
// Don't: effect restarts when callback changes
@Composable
fun BadCallback(onSuccess: (String) -> Unit) {
    LaunchedEffect(onSuccess) {  // Restarts whenever onSuccess changes!
        val result = expensiveOperation()
        onSuccess(result)
    }
}

// Do: use rememberUpdatedState to capture latest without restarting
@Composable
fun GoodCallback(onSuccess: (String) -> Unit) {
    val updatedOnSuccess = rememberUpdatedState(onSuccess)

    LaunchedEffect(Unit) {
        val result = expensiveOperation()
        updatedOnSuccess.value(result)
    }
}
```

### Another Example: Animations

```kotlin
@Composable
fun AnimateWithCallback(
    shouldAnimate: Boolean,
    onAnimationEnd: () -> Unit
) {
    val updatedCallback = rememberUpdatedState(onAnimationEnd)
    var progress by remember { mutableStateOf(0f) }

    LaunchedEffect(shouldAnimate) {
        if (shouldAnimate) {
            while (progress < 1f) {
                progress += 0.1f
                delay(16)
            }
            updatedCallback.value()  // Call latest callback without restarting
        }
    }
}
```

### Anti-Pattern: Using rememberUpdatedState to Avoid Keying

**Don't use `rememberUpdatedState` as a substitute for keying the effect properly.** If the effect should restart when a value changes, key the effect on the value.

```kotlin
// WRONG — wraps userId in rememberUpdatedState to keep LaunchedEffect(Unit) "stable"
@Composable
fun UserLoader(userId: String) {
    val latestUserId by rememberUpdatedState(userId)
    LaunchedEffect(Unit) {
        loadUser(latestUserId)  // value drifts; effect never restarts
    }
}

// RIGHT — key on the value
LaunchedEffect(userId) { loadUser(userId) }
```

**`rememberUpdatedState` is correct when:** the effect's lifecycle is genuinely 'start once and stay alive' (e.g., a long-running animation, a timer) but a callback inside it should always reflect the latest value (e.g., `onComplete: () -> Unit` that the caller may swap).

## produceState — Converting Non-Compose State to Compose State

`produceState` converts imperative state sources (callbacks, flows, coroutines) into Compose state.

```kotlin
@Composable
fun UserData(userId: String): State<User?> = produceState<User?>(initialValue = null) {
    value = fetchUser(userId)

    // Optional: for lifecycle cleanup
    snapshotFlow { userId }.collect { newUserId ->
        value = fetchUser(newUserId)
    }
}

// Usage
@Composable
fun UserScreen(userId: String) {
    val user by UserData(userId)
    Text(user?.name ?: "Loading...")
}
```

### Integration with Flows

```kotlin
@Composable
fun <T> Flow<T>.collectAsState(initial: T): State<T> = produceState(initial) {
    collect { value = it }
}

// Usage
@Composable
fun ObserveFlow(dataFlow: Flow<String>) {
    val data by dataFlow.collectAsState(initial = "")
    Text(data)
}
```

## Effect Ordering and Lifecycle

Effects execute in declaration order after composition:

```kotlin
@Composable
fun EffectOrder() {
    println("1. Composition")

    SideEffect {
        println("4. Side effect (after every composition)")
    }

    LaunchedEffect(Unit) {
        println("3. Launched effect (async, but scheduled)")
        delay(100)
        println("5. After delay in launched effect")
    }

    DisposableEffect(Unit) {
        println("2. Disposable effect setup (after composition)")

        onDispose {
            println("6. Cleanup when leaving composition")
        }
    }

    println("End of composition body")
}

// Output order (approximate):
// 1. Composition
// End of composition body
// 2. Disposable effect setup (after composition)
// 3. Launched effect (async, but scheduled)
// 4. Side effect (after every composition)
// 5. After delay in launched effect
// [... later when composable leaves ...]
// 6. Cleanup when leaving composition
```

## Common Mistakes

### Using LaunchedEffect(Unit) When Key Should Change

```kotlin
// Don't: effect runs once, never updates
@Composable
fun BadSearch(query: String) {
    var results by remember { mutableStateOf<List<String>>(emptyList()) }

    LaunchedEffect(Unit) {
        results = search(query)  // Only runs once!
    }

    Text("Results: ${results.size}")
}

// Do: use query as key
@Composable
fun GoodSearch(query: String) {
    var results by remember { mutableStateOf<List<String>>(emptyList()) }

    LaunchedEffect(query) {
        results = search(query)  // Reruns when query changes
    }

    Text("Results: ${results.size}")
}
```

### Forgetting Cleanup in DisposableEffect

```kotlin
// Don't: memory leak
@Composable
fun BadListener(context: Context) {
    DisposableEffect(Unit) {
        val listener = MyListener()
        context.registerListener(listener)
        // Missing: onDispose { context.unregisterListener(listener) }
    }
}

// Do: always clean up
@Composable
fun GoodListener(context: Context) {
    DisposableEffect(Unit) {
        val listener = MyListener()
        context.registerListener(listener)

        onDispose {
            context.unregisterListener(listener)
        }
    }
}
```

### Capturing Mutable State Directly

```kotlin
// Don't: stale state in effect
@Composable
fun BadCapture() {
    var count by remember { mutableStateOf(0) }

    LaunchedEffect(Unit) {
        delay(1000)
        println(count)  // May be stale!
    }

    Button(onClick = { count++ }) { Text("Click") }
}

// Do: use rememberUpdatedState or include in key
@Composable
fun GoodCapture() {
    var count by remember { mutableStateOf(0) }

    val updatedCount = rememberUpdatedState(count)
    LaunchedEffect(Unit) {
        delay(1000)
        println(updatedCount.value)  // Always current
    }

    Button(onClick = { count++ }) { Text("Click") }
}
```

### snapshotFlow Without a Terminal Operator

**Flow chains are cold.** Without a terminal operator (`collect`, `first`, `toList`), the chain doesn't execute.

```kotlin
// WRONG — no terminal; the entire chain is a no-op
LaunchedEffect(listState) {
    snapshotFlow { listState.firstVisibleItemIndex }
        .distinctUntilChanged()
        .map { viewModel.onScroll(it) }  // never runs
}

// RIGHT — use onEach for side effects (not map) and a terminal collect
LaunchedEffect(listState) {
    snapshotFlow { listState.firstVisibleItemIndex }
        .distinctUntilChanged()
        .collect { viewModel.onScroll(it) }
}
```

See `android-skills:kotlin-flows` for the cold-vs-hot distinction and terminal-operator rules.

### Event-Flag State to Trigger LaunchedEffect

**Don't manufacture event-flag state to trigger an effect — the click already is the event.**

```kotlin
// WRONG — invented state machine for what's already a single event
var shouldShowSnackbar by remember { mutableStateOf(false) }
LaunchedEffect(shouldShowSnackbar) {
    if (shouldShowSnackbar) {
        snackbarHostState.showSnackbar("Done")
        shouldShowSnackbar = false
    }
}
Button(onClick = { shouldShowSnackbar = true }) { Text("Save") }

// RIGHT — coroutine scope in the event handler
val scope = rememberCoroutineScope()
Button(onClick = {
    scope.launch { snackbarHostState.showSnackbar("Done") }
}) { Text("Save") }
```

---

**Summary:** Effects bridge declarative Compose with imperative systems. Master key selection in `LaunchedEffect`, always cleanup in `DisposableEffect`, use `rememberUpdatedState` for long-running effects that need fresh values, and prefer effect-based patterns over manual lifecycle management.
