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
| `Channel` used as event bus | Ask user (see trade-offs below), then migrate → `SharedFlow` or keep as `Channel` |
| `Channel` as producer-consumer queue | Keep — correct use case |

**Always prompt the user before migrating any Channel:**

> "This `Channel` is used as an event bus. `SharedFlow` is the idiomatic replacement and integrates cleanly with lifecycle-safe collection. However, `Channel` guarantees that every emission is consumed exactly once — `SharedFlow` does not (emissions are missed if no collector is active). Do you need exactly-once delivery, or is `SharedFlow` acceptable here?"

## Choosing the Right Type

| Type | Hot/Cold | Retains state | Use for |
|---|---|---|---|
| `Flow` | Cold | No | One-off streams, repository data |
| `StateFlow` | Hot | Yes (last value) | UI state |
| `SharedFlow` | Hot | Configurable | Events, broadcasts |

- Representing current state that new collectors need immediately? → `StateFlow`
- Broadcasting events to multiple collectors? → `SharedFlow`
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
| Combine latest values from multiple flows | `combine(flowA, flowB) { a, b -> }` — emits when **any** upstream emits; use for derived UI state from multiple StateFlows |
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

**`stateIn` vs `MutableStateFlow` — when to use which:**
- **`stateIn`** — when a repository or data layer exposes a cold `Flow` and the ViewModel wants to expose it as a `StateFlow`. The flow drives the state; the ViewModel doesn't write to it directly.
- **`MutableStateFlow`** — when the ViewModel drives state imperatively: loading results, reacting to user actions, combining multiple sources. The ViewModel owns and writes to the state.

**`stateIn` sharing strategies:**
- `SharingStarted.WhileSubscribed(5_000)` — stops when no collectors, survives config changes; use in ViewModels
- `SharingStarted.Eagerly` — starts immediately, never stops
- `SharingStarted.Lazily` — starts on first collector, never stops

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

**One-shot UI events — ask the user:**

> "Do you need guaranteed exactly-once delivery (the event must never be missed even if the UI is temporarily inactive), or is it acceptable to miss an event if no collector is subscribed at that moment?"

- **Can miss events when UI is inactive** → `SharedFlow(replay = 0)` with `repeatOnLifecycle` — simpler, no backpressure risk; preferred when `repeatOnLifecycle` ensures the collector is always active
- **Must never miss an event** → `Channel` — guarantees exactly-once delivery; suited for navigation commands or one-time side effects where a missed event would be a bug

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

## Testing

**Always ask the user before writing tests.**

Use [Turbine](https://github.com/cashapp/turbine) for flow testing:

```kotlin
// Add to build.gradle.kts:
// testImplementation("app.cash.turbine:turbine:<version>")

@Test
fun `emits loading then success states`() = runTest {
    val viewModel = NewsViewModel(FakeNewsRepository())

    viewModel.uiState.test {
        assertThat(awaitItem()).isEqualTo(NewsUiState.Loading)
        assertThat(awaitItem()).isInstanceOf(NewsUiState.Success::class.java)
        cancelAndIgnoreRemainingEvents()
    }
}
```

Testing StateFlow value directly:

```kotlin
@Test
fun `updates state to success after refresh`() = runTest {
    val viewModel = NewsViewModel(
        repository = FakeNewsRepository(),
        dispatchers = TestDispatcherProvider(StandardTestDispatcher(testScheduler))
    )

    viewModel.refresh()
    advanceUntilIdle()

    assertThat(viewModel.uiState.value).isInstanceOf(NewsUiState.Success::class.java)
}
```

Testing SharedFlow events:

```kotlin
@Test
fun `emits navigation event on item click`() = runTest {
    val viewModel = NewsViewModel(FakeNewsRepository())

    viewModel.events.test {
        viewModel.onArticleClick(articleId = "123")
        assertThat(awaitItem()).isEqualTo(UiEvent.NavigateToDetail("123"))
        cancelAndIgnoreRemainingEvents()
    }
}
```
