# Kotlin Coroutines & Flows Skills — Design

Date: 2026-02-28

## Overview

Three focused skills for Kotlin coroutines, Kotlin flows, and RxJava migration. Targeting Android and KMP projects. Content drawn from official Kotlin docs, Google Android best practices, and community sources (Roman Elizarov, Marcin Moskala, KotlinConf talks).

**Content format:** Rule-based with rationale + before/after Kotlin code examples.

---

## Directory Structure

```
~/.claude/skills/
  kotlin-coroutines/
    SKILL.md
  kotlin-flows/
    SKILL.md
  rxjava-migration/
    SKILL.md
    migration-map.md     ← operator mapping table (too large for inline)
```

---

## Skill 1: `kotlin-coroutines`

**Trigger:** Use when writing, reviewing, or debugging coroutine code in Kotlin — including dispatcher selection, scope management, structured concurrency, cancellation, exception handling, or async patterns in Android or KMP projects.

### Sections

#### 1. Project context check *(always runs first)*
- Scan existing coroutine usage: which dispatchers, which scopes, how exceptions are handled
- Match the project's approach if it is sound
- If the approach is bad practice: explain why and recommend what to do instead — let the user decide whether to change it

#### 2. Dispatcher selection
- `Dispatchers.Main` — UI work only
- `Dispatchers.IO` — blocking I/O (network, disk)
- `Dispatchers.Default` — CPU-intensive work
- `Dispatchers.Unconfined` — avoid in production; explain why
- Rule: never hardcode dispatchers in business logic — inject via a `DispatcherProvider` interface
- **Main-safety rule** (from Android best practices):
  - Every suspend function must be safe to call from the main thread
  - If a function does blocking work, it owns the `withContext` call — callers should never need to switch context before calling it
  - Applies at every layer: repositories, data sources, use cases
  - Before/after: repository doing blocking HTTP call, wrong pattern (caller switches) vs. right pattern (callee uses `withContext`)
- **`DispatcherProvider` setup prompt:** ask user if they want to create:
  - `DispatcherProvider` interface (exposes `main`, `io`, `default`)
  - `DefaultDispatcherProvider` with real dispatchers
  - `TestDispatcherProvider` with test dispatchers
  - Show how to inject via constructor or Hilt

#### 3. Scope management
- `viewModelScope` — Android ViewModels; cancelled when ViewModel cleared
- `lifecycleScope` — Android UI; cancelled when lifecycle destroyed
- `coroutineScope` — structured, throws on child failure
- `supervisorScope` — structured, isolates child failures
- Rule: never use `GlobalScope`; explain why; inject external `CoroutineScope` instead
- **Layer responsibilities for coroutine creation:**
  - Data/business layers: use `coroutineScope` or `supervisorScope` when work is tied to the current screen
  - Data/business layers: inject an external `CoroutineScope` (not `GlobalScope`) when work must outlive the screen (e.g., completing a network write after user navigates away)
  - External `CoroutineScope` should be managed by `Application` or a navigation-graph-scoped `ViewModel`

#### 4. Structured concurrency
- What it means and why it matters
- Parent-child job relationships
- When to use `async`/`await` vs `launch`

#### 5. Cancellation & cooperative cancellation
- Why cancellation is cooperative
- `isActive`, `ensureActive()`, `yield()`
- Rule: always check for cancellation in long loops and CPU-intensive work
- Pitfall: catching `CancellationException` and not rethrowing it

#### 6. Exception handling
- `try/catch` placement rules (works in suspend fns, not across `launch`)
- `CoroutineExceptionHandler` — when and how to use
- `SupervisorJob` — when child failure should not cancel siblings
- **Specificity rule:**
  - Always catch specific exception types (`IOException`, `HttpException`) — never catch `Exception` or `Throwable` blindly
  - Never catch `CancellationException` without rethrowing — silently breaks cooperative cancellation
  - Before/after: `catch (e: Exception)` vs `catch (e: IOException)`
- Pitfall: using `try/catch` around `launch {}` expecting it to catch

#### 7. Android-specific rules
- `viewModelScope` for ViewModel coroutines
- `lifecycleScope` + `repeatOnLifecycle` for UI coroutines
- Never launch coroutines in `onStart`/`onResume` without proper lifecycle handling
- **ViewModel coroutine ownership rule:**
  - ViewModels should create coroutines via `viewModelScope.launch {}` and expose state through `StateFlow`
  - ViewModels should not expose `suspend fun` for business logic — callers should not be responsible for launching coroutines
  - Views should never trigger business logic coroutines directly — defer to the ViewModel
  - Exception: `suspend fun` in ViewModel is acceptable when emitting a single value rather than a stream
  - Before/after: exposing `suspend fun loadNews()` vs `fun loadNews()` with internal `viewModelScope.launch {}`
- **Layer responsibilities:**
  - Data and business layers expose `suspend fun` for one-shot calls and `Flow` for streams
  - Presentation layer controls execution lifecycle by calling these functions within appropriate scopes

#### 8. KMP-specific rules
- `MainScope()` for shared UI-layer code
- Injecting `CoroutineDispatcher` for platform-specific implementations
- `Dispatchers.Main.immediate` availability per platform

#### 9. Common pitfalls *(before/after examples)*
- Swallowing `CancellationException`
- Using `runBlocking` on the main thread
- Leaking coroutines with unstructured concurrency
- Mixing `withContext` and blocking calls incorrectly
- Not injecting dispatchers (untestable code)
- Catching `Exception`/`Throwable` instead of specific types

#### 10. Testing
- Ask user before writing tests
- `runTest` as the standard test builder
- **Test dispatcher choice prompt:** explain and let user pick:
  - `StandardTestDispatcher` — coroutines queued, not run until explicitly advanced (`advanceUntilIdle()`, `advanceTimeBy()`). Better for time-sensitive tests and precise execution order. Requires more explicit control.
  - `UnconfinedTestDispatcher` — coroutines run eagerly on launch. Simpler for basic tests but can hide ordering bugs and does not support time control.
  - Recommendation: `StandardTestDispatcher` for most cases; `UnconfinedTestDispatcher` for simple state observation tests
- Injecting `TestDispatcherProvider` via the `DispatcherProvider` interface
- Testing cancellation and exception scenarios

---

## Skill 2: `kotlin-flows`

**Trigger:** Use when working with Flow, StateFlow, SharedFlow, or Channel in Kotlin — including cold vs hot stream decisions, operator chains, lifecycle-safe collection, UI state management, or Channel → Flow migration in Android or KMP projects.

### Sections

#### 1. Project context check *(always runs first)*
- Scan existing flow usage: which flow types, how they are collected, how state is managed
- Match the project's approach if it is sound
- If the approach is bad practice: explain why and recommend what to do instead — let the user decide

#### 2. Channel audit *(runs during project context check)*
- Identify `Channel`, `BroadcastChannel`, `ConflatedBroadcastChannel` usages
- Migration rules:
  - `BroadcastChannel` → `SharedFlow` (always — deprecated)
  - `ConflatedBroadcastChannel` → `StateFlow` (always — deprecated)
  - `Channel` used as event bus → `SharedFlow` (recommended; explain trade-offs; prompt user)
  - `Channel` as producer-consumer queue → keep as Channel (correct use case)
- Always prompt user before migrating anything

#### 3. Cold vs hot — choosing the right type
- `Flow` — cold, one consumer, no retained state
- `StateFlow` — hot, always has a value, replays last, for UI state
- `SharedFlow` — hot, configurable replay, multi-consumer events
- Decision rules with examples for each case

#### 4. Creating flows
- `flow {}` — standard cold flow
- `callbackFlow` — bridging callback APIs
- `channelFlow` — concurrent emissions
- Rules: when to use each; common mistakes in `callbackFlow` (not calling `awaitClose`)

#### 4b. Callback bridging
- **Single-value callbacks → suspend function:**
  - `suspendCancellableCoroutine` — preferred; supports cancellation
  - `suspendCoroutine` — simpler, no cancellation; explain when this matters
  - Rule: always prefer `suspendCancellableCoroutine` unless the API has no cancellation concept
- **Multi-value / stream callbacks → Flow:**
  - `callbackFlow` — registers callback on collection start, unregisters on cancel
  - `channelFlow` — for concurrent emissions from multiple sources
  - Rule: `awaitClose {}` is mandatory in `callbackFlow`; always clean up callback registration there
  - Pitfall: forgetting `awaitClose` leaks the callback and prevents flow completion
- **Android-specific callback APIs:**
  - Examples: `LocationManager`, sensor listeners, `TextWatcher`, `OnScrollChangeListener`
  - Before/after: raw callback registration → `callbackFlow` wrapper
- **Third-party SDK callbacks:**
  - Pattern for wrapping SDK listeners that are not lifecycle-aware
  - How to handle SDKs that do not support deregistration cleanly

#### 5. Operator rules
- `map`, `filter`, `onEach` — basics
- `flatMapLatest` vs `flatMapMerge` vs `flatMapConcat` — rules and use cases for each
- `debounce` — search queries, UI input
- `distinctUntilChanged` — avoiding redundant emissions
- `buffer`, `conflate` — backpressure handling
- `stateIn`, `shareIn` — converting cold to hot

#### 6. StateFlow patterns
- Initialisation with `MutableStateFlow`
- **Immutable exposure rule:**
  - Always expose `StateFlow` (immutable) publicly; back it with a private `MutableStateFlow`
  - Same applies to `SharedFlow` / `MutableSharedFlow`
  - Before/after: exposing `MutableStateFlow` directly vs. private backing field pattern
- Updating with `update {}` (thread-safe); rule: never use `value =` in concurrent contexts
- `stateIn` with `SharingStarted` strategies

#### 7. SharedFlow patterns
- `replay` and `extraBufferCapacity` — when to configure each
- One-shot events debate — `SharedFlow` vs `Channel`; present both sides
- `onBufferOverflow` strategies

#### 8. Lifecycle-safe collection (Android)
- `collectAsStateWithLifecycle` in Compose — preferred
- `repeatOnLifecycle` in non-Compose code
- Pitfall: `lifecycleScope.launch { flow.collect {} }` without `repeatOnLifecycle`

#### 9. KMP patterns
- Exposing flows from shared code to iOS via `kotlinx-coroutines-core` wrappers
- Avoiding platform-specific collection patterns in shared code

#### 10. Common pitfalls *(before/after examples)*
- Collecting in `lifecycleScope` without `repeatOnLifecycle`
- Using `StateFlow` where `SharedFlow` is needed and vice versa
- Missing `awaitClose` in `callbackFlow`
- Triggering side effects in `map` instead of `onEach`
- Hot flow leaks (forgetting `SharingStarted.WhileSubscribed`)
- Exposing `MutableStateFlow` or `MutableSharedFlow` publicly

#### 11. Testing
- Ask user before writing tests
- Turbine for flow testing (`test {}`, `awaitItem()`, `awaitComplete()`)
- Testing StateFlow and SharedFlow
- Testing operators and transformations

---

## Skill 3: `rxjava-migration`

**Trigger:** Use only when the user explicitly requests migration from RxJava to Kotlin coroutines and/or flows.

### Sections

#### 1. Complexity assessment *(always runs first)*
- Classify the RxJava code:
  - **Simple:** single-type usage, straightforward chains (≤3 operators, no custom schedulers, no complex error handling)
  - **Complex:** nested chains, custom schedulers, complex error recovery, multi-source merging, hot observables with backpressure
- Simple → apply type and operator mapping directly
- Complex → follow migration strategy; prompt user for key decisions

#### 2. Type mapping (simple cases)
- `Observable<T>` → `Flow<T>`
- `Single<T>` → `suspend fun` returning `T`
- `Maybe<T>` → `suspend fun` returning `T?`
- `Completable` → `suspend fun` returning `Unit`
- `Subject<T>` → `MutableSharedFlow<T>`
- `BehaviorSubject<T>` → `MutableStateFlow<T>`
- Full operator mapping table → `migration-map.md`

#### 3. Interop patterns *(for incremental migration)*
- `rxjava3-coroutines-interop` library
- `Observable.asFlow()`, `Flow.asObservable()`
- `Single.await()`, `Completable.await()`
- Scheduler → Dispatcher mapping
- Rule: prefer boundary-level interop; do not mix RxJava and coroutines deep in business logic

#### 4. Migration strategy (complex cases)
- Incremental approach: migrate leaf dependencies first, work inward
- Identify natural boundaries (repository layer, use cases) for clean cuts
- Where to prompt user: custom operator equivalents, backpressure strategy choices, threading model decisions
- How to handle complex error recovery chains

#### 5. Common pitfalls when migrating
- Losing backpressure handling when going from `Flowable` to `Flow`
- Scheduler assumptions not translating cleanly to dispatchers
- Hot Observable → SharedFlow replay semantics differences
- Missing `CompositeDisposable` equivalent (`CoroutineScope` cancellation)

### Supporting file: `migration-map.md`
Complete RxJava operator → Flow/coroutine equivalent table covering: creation operators, transforming, filtering, combining, error handling, utility operators.
