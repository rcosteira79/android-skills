---
name: kotlin-flows
description: Use when working with Flow, StateFlow, SharedFlow, or Channel in Kotlin — including cold vs hot stream decisions, operator chains, lifecycle-safe collection, UI state management, callback bridging, or Channel migration in Android or KMP projects.
---

# Kotlin Flows

## Overview

Kotlin Flow is a cold, sequential stream built on coroutines. `StateFlow` and `SharedFlow` are hot variants for state and events. Choosing the right type, collecting safely, and never exposing mutable types are the core concerns here.

## Step 1: Project Context Check

Before writing or modifying any flow code:

1. Search for `Flow`, `StateFlow`, `SharedFlow`, `Channel`, `MutableStateFlow`, `MutableSharedFlow`, `LiveData`, `collect`, `collectAsState`
2. Identify which flow types are used and how they are collected
3. **If approach is sound:** match it
4. **If approach violates rules below:** explain why to the user, recommend the correct approach, and let them decide — do NOT produce code that follows the bad pattern
5. **Beyond violations:** also look for places where the operators and patterns in this skill could simplify existing code — manual `Job?` patterns that `flatMapLatest` could replace, flows collected inside transforms that `combine` could clean up, etc.

## Step 2: Channel Audit

During the context check, also identify Channel usage:

| Found | Action |
|---|---|
| `BroadcastChannel` | Always migrate → `SharedFlow` (deprecated) |
| `ConflatedBroadcastChannel` | Always migrate → `StateFlow` (deprecated) |
| `Channel` used as single-consumer fire-once events (nav commands, snackbars, one-shot side effects) | **Keep — correct use case.** This is what Channel is for. |
| `Channel` used as broadcast to multiple collectors | Migrate → `SharedFlow`. `Channel.receiveAsFlow()` is fan-out, not broadcast — each event reaches one collector, not all. |
| `Channel` as producer-consumer queue | Keep — correct use case |

**Default for single-consumer fire-once events: `Channel(Channel.BUFFERED).receiveAsFlow()`.**

```kotlin
private val _events = Channel<UiEvent>(Channel.BUFFERED)
val events: Flow<UiEvent> = _events.receiveAsFlow()

fun onItemClick(id: String) {
    viewModelScope.launch {
        _events.send(UiEvent.NavigateToDetail(id))
    }
}
```

Navigation commands, snackbar prompts, and one-shot effects must not be missed when the UI is briefly inactive (rotation, modal stacking, background). `Channel` suspends `send` until a receiver consumes, so the event is queued — never silently dropped. `SharedFlow(replay = 0)` drops the emission if no collector is active at the exact moment of emission.

**Use `SharedFlow` only when:**
- Multiple collectors must receive the same event simultaneously (e.g. logging + analytics + UI), or
- Missing events under load is genuinely acceptable (tooltips, sound effects, non-critical UI cues), and
- You're willing to choose between `replay = 0` (collectors miss past events) and `replay > 0` (collectors get the last N — but then it's caching, not pure broadcast).

**Critical semantic note:** `Channel.receiveAsFlow()` is **fan-out**, not broadcast. With multiple collectors, each event is delivered to **one** collector — the framework picks which. If you need every collector to see every event, you need `SharedFlow`, not `Channel`.

## Choosing the Right Type

| Type | Hot/Cold | Retains state | Use for |
|---|---|---|---|
| `Flow` | Cold | No | One-off streams, repository data |
| `StateFlow` | Hot | Yes (last value) | UI state |
| `Channel(BUFFERED).receiveAsFlow()` | Hot | No (queued until consumed) | **Single-consumer fire-once events: nav, snackbars, one-shot effects** |
| `SharedFlow` | Hot | Configurable | Multi-collector broadcast where missed events are acceptable |

- Representing current state that new collectors need immediately? → `StateFlow`
- Single-consumer fire-once event that must not be missed? → `Channel(BUFFERED).receiveAsFlow()`
- Broadcasting to multiple collectors? → `SharedFlow`
- Simple data stream from one source? → `Flow`

## Creating Flows

```kotlin
// Standard cold flow
fun observeNews(): Flow<List<Article>> = flow {
    while (true) {
        emit(api.fetchNews())
        delay(30_000)
    }
}

// Polling flow — plain flow builder, no callback needed
fun pollStockPrice(symbol: String): Flow<Price> = flow {
    while (true) {
        emit(api.getPrice(symbol))
        delay(5_000)
    }
}

// Concurrent emissions from multiple sources
fun observeMultipleSensors(): Flow<SensorData> = channelFlow {
    launch { sensor1.readings().collect { send(it) } }
    launch { sensor2.readings().collect { send(it) } }
}
```

## Callback Bridging

### Single-value callbacks → suspend function

```kotlin
// suspendCancellableCoroutine — always prefer this (supports cancellation)
suspend fun authenticate(token: String): User = suspendCancellableCoroutine { continuation ->
    val call = authApi.authenticate(token) { user, error ->
        if (user != null) continuation.resume(user)
        else continuation.resumeWithException(error ?: Exception("Unknown error"))
    }
    continuation.invokeOnCancellation { call.cancel() }
}

// suspendCoroutine — only when the API has no cancellation concept at all
suspend fun getStaticConfig(): Config = suspendCoroutine { continuation ->
    configService.fetch { config -> continuation.resume(config) }
}
```

### Stream callbacks → Flow

```kotlin
// Android API example
fun EditText.textChanges(): Flow<String> = callbackFlow {
    val watcher = object : TextWatcher {
        override fun afterTextChanged(s: Editable?) { trySend(s.toString()) }
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
    }
    addTextChangedListener(watcher)
    awaitClose { removeTextChangedListener(watcher) } // CRITICAL — always clean up
}

// Location updates
fun LocationManager.locationUpdates(provider: String): Flow<Location> = callbackFlow {
    val listener = LocationListener { location -> trySend(location) }
    requestLocationUpdates(provider, 1000L, 0f, listener)
    awaitClose { removeUpdates(listener) }
}
```

**Rule:** `awaitClose {}` is mandatory in `callbackFlow`. Omitting it leaks the registered callback and prevents the flow from completing.

For third-party SDKs without a deregistration API: use a flag inside `awaitClose` to signal shutdown and document the limitation to the caller.

## Operator Rules

| Goal | Operator |
|---|---|
| Transform each value | `map` |
| Filter values | `filter` |
| Side effects without transformation | `onEach` — never `map` for side effects |
| Cancel previous on new emission | `flatMapLatest` — search queries, user input; cancels in-flight work — never use for writes or mutations. Also the fix for manual `Job?` cancellation + re-launch patterns (see pitfalls) |
| Process all concurrently | `flatMapMerge` — parallel independent work |
| Process sequentially in order | `flatMapConcat` — ordered operations |
| Debounce rapid input | `debounce(ms)` |
| Skip duplicate consecutive values | `distinctUntilChanged()` |
| Buffer slow collectors | `buffer(capacity)` |
| Drop old values when collector is slow | `conflate()` |
| Change upstream execution context | `flowOn(dispatcher)` |
| Convert cold flow to hot StateFlow | `stateIn(scope, started, initialValue)` |
| Convert cold flow to hot SharedFlow | `shareIn(scope, started, replay)` |
| Combine latest values from multiple flows | `combine(flowA, flowB) { a, b -> }` — emits when **any** upstream emits; use for derived UI state from multiple StateFlows. **Warning:** waits for *every* input to emit at least once before producing its first value. If one input is a cold flow that never emits, the combined flow never emits — a common "screen stuck on loading" bug. Make every input a `StateFlow`, give cold inputs `onStart { emit(initial) }`, or sentinel-prefix them. Also: `combine(a, b) { (x, y) -> ... }` does **not** compile — destructuring isn't supported. |
| Pair emissions one-to-one across flows | `zip(flowA, flowB) { a, b -> }` — waits for both to emit before combining; use when pairings must align |
| Cancel previous collector block on new emission | `collectLatest { }` — use when processing a new item should cancel processing the previous one (e.g. updating UI) |

## Error Handling

### `.catch` — upstream errors only

`.catch` intercepts exceptions thrown **upstream** in the flow. It does not catch exceptions thrown inside the `collect {}` block. Unlike `try/catch`, it does not intercept `CancellationException`.

```kotlin
// Emit a fallback on upstream error
repository.getItems()
    .catch { e -> emit(emptyList()) }
    .collect { items -> updateUi(items) }

// Rethrow after logging
repository.getItems()
    .catch { e ->
        logger.error(e)
        throw e
    }
    .collect { items -> updateUi(items) }

// .catch does NOT cover collector errors — these propagate to the coroutine scope
repository.getItems()
    .catch { e -> /* does not catch exceptions thrown below */ }
    .collect { items ->
        riskyOperation(items) // exception here escapes .catch
    }

// For collector errors, use try/catch inside collect
repository.getItems()
    .collect { items ->
        try {
            riskyOperation(items)
        } catch (e: SpecificException) {
            handleError(e)
        }
    }
```

### `retry` / `retryWhen`

```kotlin
// retry — resubscribes on predicated exception, up to n times
repository.getItems()
    .retry(3) { cause -> cause is IOException }
    .collect { ... }

// retryWhen — stateful retry with attempt count and delay
repository.getItems()
    .retryWhen { cause, attempt ->
        if (cause is IOException && attempt < 3) {
            delay((attempt + 1) * 1_000L)
            true  // retry
        } else {
            false // give up
        }
    }
    .collect { ... }
```

`attempt` is the 0-based retry index. `cause` is the exception. Always guard both — without a count check, the flow retries forever.

## StateFlow Patterns

**Never expose `MutableStateFlow` publicly.** Even when the existing codebase does it, do NOT add new usages — flag it to the user and recommend the correct pattern.

```kotlin
class NewsViewModel : ViewModel() {
    // DO: private mutable, public immutable
    private val _uiState = MutableStateFlow<NewsUiState>(NewsUiState.Loading)
    val uiState: StateFlow<NewsUiState> = _uiState

    // DO NOT: expose mutable type — allows external callers to mutate state, bypassing ViewModel logic
    // val uiState = MutableStateFlow<NewsUiState>(NewsUiState.Loading)

    fun refresh() {
        viewModelScope.launch {
            // DO: thread-safe atomic update
            _uiState.update { currentState -> currentState.copy(isRefreshing = true) }

            // DO NOT: non-atomic read-modify-write (race condition in concurrent code)
            // _uiState.value = _uiState.value.copy(isRefreshing = true)
        }
    }
}
```

**The `update { }` lambda can be retried on contention.** `MutableStateFlow.update` re-executes the lambda if a concurrent update lost a CAS race. Don't put expensive work or side effects inside it — only the state transform. Build the new value before the call.

```kotlin
// WRONG — analytics fires twice on contention
_state.update { current ->
    analytics.logStateChange(current)  // re-runs on retry
    current.copy(isLoading = true)
}

// RIGHT — build/observe outside, transform inside
val current = _state.value
analytics.logStateChange(current)
_state.update { it.copy(isLoading = true) }
```

### Sentinel Anti-Pattern in StateFlow

**Never invent sentinel domain values for `StateFlow` initial state.** Things like `User.NoUser`, `Items.Empty`, or placeholder IDs force every consumer to handle the fake value as if it were real. The `StateFlow` initial-value requirement isn't a license to invent sentinels.

Two correct alternatives:

**Phase the StateFlow** — expose it only when the real value exists:
```kotlin
// WRONG — sentinel forces every consumer to check
private val _user = MutableStateFlow(User.NoUser)
val user: StateFlow<User> = _user

// RIGHT — phase: don't expose the flow until the real value exists
private var _user: MutableStateFlow<User>? = null
val user: StateFlow<User> get() = checkNotNull(_user) { "User not loaded yet" }

fun loadUser(id: String) {
    viewModelScope.launch {
        val loaded = repository.getUser(id)
        _user = MutableStateFlow(loaded)
    }
}
```

**Model loaded/unloaded explicitly** with a sealed `UiState` (Loading / Success / Error) — that's a domain decision, not a sentinel.

**`stateIn` vs `MutableStateFlow` — when to use which:**
- **`stateIn`** — when a repository or data layer exposes a cold `Flow` and the ViewModel wants to expose it as a `StateFlow`. The flow drives the state; the ViewModel doesn't write to it directly.
- **`MutableStateFlow`** — when the ViewModel drives state imperatively: loading results, reacting to user actions, combining multiple sources. The ViewModel owns and writes to the state.

**`stateIn` sharing strategies:**
- `SharingStarted.WhileSubscribed(5_000)` — stops when no collectors, survives config changes; use in ViewModels
- `SharingStarted.Eagerly` — starts immediately, never stops
- `SharingStarted.Lazily` — starts on first collector, never stops

**Calling `stateIn(scope, ...)` inside a function launches a fresh shared coroutine on every call.** Each invocation creates a new `StateFlow` with its own collector on `scope`, none of which complete. Performance degrades fast under repeated reads.

```kotlin
// WRONG — fresh stateIn per call
class Repository(private val scope: CoroutineScope) {
    fun getPreferences(): StateFlow<Preferences> = preferencesDataSource.flow
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), Preferences.Default)
}

// RIGHT — stateIn at property declaration; one shared flow per instance
class Repository(scope: CoroutineScope) {
    val preferences: StateFlow<Preferences> = preferencesDataSource.flow
        .stateIn(scope, SharingStarted.WhileSubscribed(5_000), Preferences.Default)
}
```

**Operators on a `StateFlow` return `Flow`, not `StateFlow`.** `userState.map { it.name }` is a `Flow<String>` — no `.value`, no replay-on-collect, no initial value. Re-terminate with `.stateIn(...)` if you need state semantics:

```kotlin
// WRONG — .value access fails
val userName: Flow<String> = userState.map { it.name }

// RIGHT — re-terminate as StateFlow with derived initial value
val userName: StateFlow<String> = userState
    .map { it.name }
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), userState.value.name)
```

## SharedFlow Patterns

**Never expose `MutableSharedFlow` publicly.** Same rule as `MutableStateFlow`.

```kotlin
// DO: private mutable, public immutable
private val _events = MutableSharedFlow<UiEvent>()
val events: SharedFlow<UiEvent> = _events.asSharedFlow()
```

### Emitting effects — `launch { emit() }` vs `tryEmit`

**Default: use `launch { emit() }` for one-shot UI effects.**

```kotlin
// Safe — suspends until the collector is ready; effect is never silently dropped
fun onItemClick(id: String) {
    viewModelScope.launch {
        _events.emit(UiEvent.NavigateToDetail(id))
    }
}
```

`tryEmit()` on a `MutableSharedFlow()` with default parameters (no buffer) **silently drops emissions** when there is no active subscriber or when the subscriber is not immediately ready. This is a silent loss — no error, no indication the event was dropped.

Adding `extraBufferCapacity = 1` makes `tryEmit()` succeed by buffering the value, but introduces a different risk: if two effects are emitted in quick succession while the buffer is already full (e.g. two rapid user actions while the UI is backgrounded), the second `tryEmit()` returns `false` and the second effect is silently dropped.

```kotlin
// Only safe if you can guarantee at most one buffered event at a time
private val _events = MutableSharedFlow<UiEvent>(extraBufferCapacity = 1)

fun onItemClick(id: String) {
    _events.tryEmit(UiEvent.NavigateToDetail(id)) // drops silently if buffer is full
}
```

**When `tryEmit` + `extraBufferCapacity` is acceptable:** non-critical effects (e.g. show a tooltip, play a sound) where a missed emission under load is tolerable and you want to avoid the coroutine overhead.

**When to keep `launch { emit() }`:** navigation commands, dialogs, and any effect where a missed emission is a visible bug.

- `replay = 0` (default) — new collectors miss past events; use for one-shot UI events
- `replay = 1` — new collectors get the last event; use for last-known-state broadcasts
- `extraBufferCapacity` — buffer emissions when collectors are slow
- `onBufferOverflow = DROP_OLDEST` — drop oldest buffered value when full

**One-shot UI events — implementing the `Channel` default:**

**Step 2: Channel Audit** (above) covers *why* `Channel(Channel.BUFFERED).receiveAsFlow()` is the default for single-consumer fire-once events — exactly-once delivery, and `SharedFlow(replay = 0)` drops events when no collector is active. The implementation specifics:

```kotlin
// DEFAULT — Channel for single-consumer fire-once events
private val _events = Channel<UiEvent>(Channel.BUFFERED)
val events: Flow<UiEvent> = _events.receiveAsFlow()

// Collect once inside a LaunchedEffect — Flow exposed externally, not Channel
LaunchedEffect(Unit) {
    viewModel.events.collect { event ->
        when (event) {
            is UiEvent.Navigate -> onNavigate(event.route)
            is UiEvent.Snackbar -> snackbarHostState.showSnackbar(event.message)
        }
    }
}
```

- **Collect with `collect` inside `LaunchedEffect` — never `collectAsStateWithLifecycle`.** The latter preserves the last emission as state, re-consuming the event on every recomposition or configuration change.
- **Don't expose the `Channel` itself.** Expose `Flow` via `receiveAsFlow()` so callers can't `send`, `close`, or `tryReceive`.
- **If you do use `SharedFlow(replay = 0)`** for the multi-collector or miss-tolerable cases (see Step 2), note `repeatOnLifecycle` stops collection below `STARTED`, so emissions during pause are lost.

**Edge case: element lost after `receive`-before-`process`.** A `Channel.BUFFERED.receiveAsFlow()` collector that is cancelled *after* `receive()` succeeds but *before* the collector's block processes the element will lose that element — the value is no longer in the channel, but the collector never acted on it. This is rare in practice (most cancellations happen between receives), but it makes "exactly-once" technically "at-most-once-with-very-high-probability." For payment/persistence-critical signals where even this loss would be unacceptable, store the outcome in durable state (a `pendingResult` field on `UiState`, cleared by the UI after consumption) — see `android-skills:compose` → `state-management.md` "Durable state + acknowledgement".

## Lifecycle-Safe Collection (Android)

```kotlin
// DO: collectAsStateWithLifecycle in Compose (preferred)
@Composable
fun NewsScreen(viewModel: NewsViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
}

// DO: repeatOnLifecycle in non-Compose code
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.uiState.collect { state -> updateUi(state) }
    }
}

// DO NOT: collects even when app is in background — resource leak and unnecessary processing
lifecycleScope.launch {
    viewModel.uiState.collect { state -> updateUi(state) }
}
```

## KMP Patterns

- Expose `Flow` from shared code; collect on each platform using platform-specific wrappers
- On iOS: use SKIE or manual `collect` wrapping via `CoroutineScope`
- Avoid accessing `StateFlow.value` directly from non-coroutine iOS contexts — use collection wrappers

## Common Pitfalls

| Pitfall | Fix |
|---|---|
| `lifecycleScope.launch { flow.collect {} }` without `repeatOnLifecycle` | Wrap with `repeatOnLifecycle(Lifecycle.State.STARTED)` |
| Missing `awaitClose {}` in `callbackFlow` | Always add `awaitClose { unregister() }` |
| `suspendCoroutine` for cancellable operations | Use `suspendCancellableCoroutine` |
| `map { sideEffect(); value }` | Use `onEach { sideEffect() }` then `map { }` separately |
| `MutableStateFlow` or `MutableSharedFlow` exposed publicly | Private mutable, public immutable — flag and refuse even if codebase does it |
| `_state.value = _state.value.copy(...)` in concurrent code | Use `_state.update { it.copy(...) }` |
| `SharingStarted.Eagerly` in ViewModel | Use `WhileSubscribed(5_000)` to stop flow when no subscribers |
| `StateFlow` for one-shot events (replays on resubscription) | Use `SharedFlow(replay = 0)` |
| `try { } catch (e: Exception)` inside `collect {}`, flow builders, or any `suspend fun` called from a coroutine | Swallows `CancellationException` — use the `.catch` operator for flow errors, or catch specific types only in suspend functions; if a broad catch is unavoidable, always rethrow `CancellationException` explicitly |
| `viewModelScope.launch {}` or effect emission inside a `combine`/`map` transform | Transform lambdas are pure — they re-execute on every resubscription (e.g. rotation), causing effects to fire repeatedly. Move side effects to `onEach` or a dedicated event handler outside the transform |
| Collecting a flow with `.firstOrNull()` / `.first()` inside a `map` or `combine` lambda | Hidden sequential call that re-fetches on every upstream emission — use `combine` to merge both flows reactively |
| Manual `Job?` cancellation + re-launch to restart a collection on new upstream value | Use `flatMapLatest` — it cancels the previous inner collection automatically when the upstream emits |
| `mutableStateFlow.emit(value)` inside a coroutine | `emit()` on `MutableStateFlow` is suspending but equivalent to `.value = value` — use `.value =` instead; `emit()` misleads readers and adds unnecessary suspension |
| Sentinel domain values (`NoUser`, `EmptyUser`) as `StateFlow` initial state | Phase the flow or model loaded state explicitly; sentinels force every consumer to check |
| `update { }` lambda contains side effects or expensive work | Lambda can be retried on CAS contention; build value outside, transform inside |
| `stateIn(scope, ...)` inside a function | Every call launches a fresh shared coroutine; move `stateIn` to property declaration |
| `.map` on `StateFlow` returns `Flow`, not `StateFlow` | Re-terminate with `.stateIn(...)` to preserve state semantics |

## RIGHT vs WRONG Patterns

### Exception handling inside `collect`

```kotlin
// WRONG — swallows CancellationException, breaks structured concurrency
repository.getItems()
    .collect { items ->
        try {
            processItems(items)
        } catch (e: Exception) { // catches CancellationException too!
            logger.error(e)
        }
    }

// RIGHT — catch only specific exceptions
repository.getItems()
    .collect { items ->
        try {
            processItems(items)
        } catch (e: ProcessingException) {
            logger.error(e)
        }
    }

// RIGHT — if broad catch is unavoidable, rethrow CancellationException
repository.getItems()
    .collect { items ->
        try {
            processItems(items)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            logger.error(e)
        }
    }

// RIGHT — use Flow's catch operator for upstream errors (skips CancellationException automatically)
repository.getItems()
    .onEach { items -> processItems(items) }
    .catch { e -> logger.error(e) }
    .collect()
```

WRONG because `catch (e: Exception)` intercepts `CancellationException`, which prevents the coroutine from being cancelled. The flow keeps running even after the parent scope is cancelled, leaking resources. This is the single most common coroutine bug. Flow's `catch` operator is often the cleanest alternative — it catches exceptions from upstream operators (like `onEach` or `map`) and automatically skips `CancellationException`.

### Side effects inside `combine`/`map` transforms

```kotlin
// WRONG — launches on every upstream emission AND every resubscription (rotation)
val uiState = combine(userFlow, settingsFlow) { user, settings ->
    viewModelScope.launch { analytics.logView(user.id) } // fires repeatedly
    UiState(user, settings)
}.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Empty)

// RIGHT — side effects in onEach, outside the transform
val uiState = combine(userFlow, settingsFlow) { user, settings ->
    UiState(user, settings)
}
.onEach { state -> analytics.logView(state.user.id) }
.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Empty)
```

WRONG because `combine` and `map` transforms are pure functions that re-execute on every upstream emission and on every resubscription (e.g., screen rotation with `WhileSubscribed`). Launching coroutines or emitting events inside them causes duplicate side effects.

### Collecting one-shot events with `collectAsStateWithLifecycle`

```kotlin
// WRONG — preserves last event as state; re-consumed on recomposition
val event by viewModel.events.collectAsStateWithLifecycle(initialValue = null)
LaunchedEffect(event) {
    event?.let { handleEvent(it) } // fires again after config change
}

// RIGHT — collect in LaunchedEffect; events are consumed once and discarded
LaunchedEffect(Unit) {
    viewModel.events.collect { event ->
        handleEvent(event) // processes once, no state retention
    }
}
```

WRONG because `collectAsStateWithLifecycle` converts the flow emission into Compose state, which persists across recompositions. One-shot events (navigation, snackbars) get re-consumed on configuration changes because the state still holds the last value.

### Manual `Job?` cancellation → `flatMapLatest`

```kotlin
// WRONG — manual Job lifecycle management; error-prone, verbose
class SearchViewModel : ViewModel() {
    private var searchJob: Job? = null

    fun onQueryChanged(query: String) {
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            _results.value = repository.search(query)
        }
    }
}

// RIGHT — flatMapLatest cancels previous collection automatically
class SearchViewModel : ViewModel() {
    private val query = MutableStateFlow("")

    val results = query
        .debounce(300)
        .flatMapLatest { q -> repository.searchFlow(q) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun onQueryChanged(q: String) { query.value = q }
}
```

WRONG because manual `Job?` tracking is fragile — easy to forget to cancel, easy to race between cancel and launch, and doesn't compose with other operators. `flatMapLatest` handles cancellation automatically and integrates with the reactive chain.

### Hidden sequential flow inside transform

```kotlin
// WRONG — fetches user on EVERY article emission; sequential, not reactive
val uiState = repository.getArticles()
    .map { articles ->
        val user = userRepository.getUser().first() // re-fetches every time
        UiState(articles, user)
    }
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Empty)

// RIGHT — combine merges both flows reactively
val uiState = combine(
    repository.getArticles(),
    userRepository.getUser()
) { articles, user ->
    UiState(articles, user)
}.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState.Empty)
```

WRONG because calling `.first()` inside a `map` lambda triggers a new collection of the inner flow on every upstream emission, creating hidden sequential I/O. `combine` merges both flows reactively — emitting whenever either changes — without redundant fetches.

## Testing

Flow testing lives in `android-skills:android-testing` — Turbine for hot flows, `backgroundScope` collection, `StateFlow.value` assertions, `MainDispatcherRule`, and the dispatcher/scheduler traps.
