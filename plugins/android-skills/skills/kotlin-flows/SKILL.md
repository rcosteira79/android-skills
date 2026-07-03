---
name: kotlin-flows
description: Use when working with Flow, StateFlow, SharedFlow, or Channel in Kotlin — including cold vs hot stream decisions, operator chains, lifecycle-safe collection, UI state management, callback bridging, or Channel migration in Android or KMP projects.
---

# Kotlin Flows

This reference covers the Flow traps and semantic edge cases — Channel vs SharedFlow, callback bridging, retry/error handling, side effects in transforms, and KMP boundaries — not the basics of cold/hot streams, the operator table, or lifecycle-safe collection.

## Channel vs SharedFlow — the semantics that bite

| Found | Action |
|---|---|
| `BroadcastChannel` | Migrate → `SharedFlow` (deprecated) |
| `ConflatedBroadcastChannel` | Migrate → `StateFlow` (deprecated) |
| `Channel` for single-consumer fire-once events (nav, snackbars, one-shot effects) | **Keep — correct.** `Channel(BUFFERED).receiveAsFlow()` |
| `Channel` broadcast to multiple collectors | Migrate → `SharedFlow` (see below) |
| `Channel` as producer-consumer queue | Keep — correct |

**`Channel.receiveAsFlow()` is fan-out, NOT broadcast.** With multiple collectors, each event reaches **one** collector (the framework picks which), not all of them. If every collector must see every event, you need `SharedFlow`. This is the trap that's easy to fall into when reaching for `Channel` to multicast.

For single-consumer one-shot events, `Channel(BUFFERED).receiveAsFlow()` is the default because `send` suspends until consumed (the event is queued, never dropped), whereas `SharedFlow(replay = 0)` drops the emission if no collector is active at the instant of emission. Expose the `Flow`, never the `Channel`, and collect with `collect` inside `LaunchedEffect` — **not** `collectAsStateWithLifecycle`, which retains the last event as state and re-fires it on every recomposition / config change.

```kotlin
private val _events = Channel<UiEvent>(Channel.BUFFERED)
val events: Flow<UiEvent> = _events.receiveAsFlow()

// in the UI
LaunchedEffect(Unit) {
    viewModel.events.collect { event -> /* navigate / snackbar — consumed once */ }
}
```

**Exactly-once is really at-most-once-with-very-high-probability.** A `receiveAsFlow()` collector cancelled *after* `receive()` succeeds but *before* its block processes the element loses that element. Rare (most cancellations land between receives), but for payment/persistence-critical signals, store the outcome in durable state (a `pendingResult` field on `UiState`, cleared by the UI after consumption) — see `compose/references/state-management.md` "Durable state + acknowledgement".

### SharedFlow: `launch { emit() }` over `tryEmit`

Default to `launch { _events.emit(e) }` — it suspends until the collector is ready, so the effect is never silently lost. `tryEmit()` on a default `MutableSharedFlow()` (no buffer) **silently drops** when no subscriber is ready; adding `extraBufferCapacity = 1` only moves the cliff (a second rapid emission while the buffer is full returns `false` and is dropped with no error). Use `tryEmit` only for miss-tolerable effects (tooltip, sound).

## Exposing a read-only flow — explicit backing fields (Kotlin 2.4+)

The `_x` (mutable) / `x` (read-only) two-property idiom collapses into a single property with explicit backing fields — stable in Kotlin **2.4**, experimental in 2.3:

```kotlin
val uiState: StateFlow<UiState>
    field = MutableStateFlow(UiState())   // inside the class: uiState.update { … }; callers see StateFlow
```

Applies wherever a `StateFlow` / `SharedFlow` is exposed from a mutable backing (`MutableStateFlow` *is* a `StateFlow`, so the default getter type-checks). It does **not** fit a `Channel` exposed as a `Flow` — a `Channel` isn't a `Flow`, so keep the explicit `_events` / `receiveAsFlow()` pair above. On Kotlin < 2.4 (check the version catalog), keep the classic `private val _x` + `val x = _x.asStateFlow()`.

## Callback bridging

```kotlin
// Single value: suspendCancellableCoroutine — always prefer it (propagates cancellation)
suspend fun authenticate(token: String): User = suspendCancellableCoroutine { cont ->
    val call = authApi.authenticate(token) { user, error ->
        if (user != null) cont.resume(user) else cont.resumeWithException(error ?: Exception())
    }
    cont.invokeOnCancellation { call.cancel() }
}
// suspendCoroutine only when the API has no cancellation concept at all.

// Stream: callbackFlow — awaitClose is MANDATORY (omitting it leaks the callback and never completes)
fun LocationManager.locationUpdates(provider: String): Flow<Location> = callbackFlow {
    val listener = LocationListener { trySend(it) }
    requestLocationUpdates(provider, 1000L, 0f, listener)
    awaitClose { removeUpdates(listener) }
}
```

For a third-party SDK with no deregistration API, set a flag inside `awaitClose` to signal shutdown and document the limitation.

## retry / retryWhen — always guard the attempt count

```kotlin
repository.getItems()
    .retryWhen { cause, attempt ->
        if (cause is IOException && attempt < 3) { delay((attempt + 1) * 1_000L); true } else false
    }
    .collect { ... }
```

`attempt` is the 0-based retry index. Without the `attempt <` count check the flow retries **forever** on a persistent error. (`retry(3) { it is IOException }` is the simple form.)

## Error handling — `.catch` scope and the cancellation trap

`.catch` intercepts **upstream** errors only (not exceptions thrown inside `collect {}`), and — unlike `try/catch` — it does not swallow `CancellationException`. So prefer the operator form, and for collector-side work catch **specific** types.

```kotlin
// ✓ upstream errors, cancellation-safe
repository.getItems().onEach { process(it) }.catch { logger.error(it) }.collect()

// ✗ catch (e: Exception) inside collect/any suspend fn swallows CancellationException and breaks
//   structured concurrency — the single most common coroutine bug.
//   If a broad catch is unavoidable: if (e is CancellationException) throw e  // before handling
```

## Side effects belong outside `combine`/`map` transforms

Transform lambdas are pure and **re-execute on every upstream emission and every resubscription** (e.g. rotation with `WhileSubscribed`). A `viewModelScope.launch {}` or event emission inside one fires repeatedly. Move it to `onEach` after the transform:

```kotlin
combine(userFlow, settingsFlow) { user, settings -> UiState(user, settings) }
    .onEach { analytics.logView(it.user.id) }   // not inside combine
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Empty)
```

**`combine` waits for every input to emit at least once before its first emission.** If one input is a cold flow that never emits, the combined flow never emits — the classic "screen stuck on Loading" bug. Make each input a `StateFlow`, give cold inputs `onStart { emit(initial) }`, or sentinel-prefix them. (`combine(a, b) { (x, y) -> … }` destructuring doesn't compile.)

## KMP

Expose `Flow` from shared code; collect per-platform (iOS: SKIE or a `CoroutineScope` wrapper). Avoid reading `StateFlow.value` from non-coroutine iOS contexts — use a collection wrapper.

## Testing

Flow testing lives in `android-skills:android-testing` — read the two-schedulers trap (`runTest` + `MainDispatcherRule` must share one scheduler) before asserting on hot flows.
