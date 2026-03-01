---
name: rxjava-migration
description: Use only when the user explicitly requests migration from RxJava to Kotlin coroutines and/or flows.
---

# RxJava Migration

## Overview

Migrate RxJava code to Kotlin coroutines and flows incrementally. Simple cases map directly. Complex cases require a strategy and user input before any code is written.

**Only invoke this skill when the user explicitly asks to migrate RxJava code.**

## Step 1: Complexity Assessment

Before writing a single line of migrated code, classify what you are looking at:

**Simple — apply type and operator mapping directly:**
- Single RxJava type (`Single`, `Observable`, `Completable`, `Maybe`)
- ≤3 operators in the chain
- Standard schedulers (`Schedulers.io()`, `AndroidSchedulers.mainThread()`)
- No complex error recovery (`retryWhen`, `onErrorResumeNext` with fallback flows)
- No hot observables with backpressure (`Flowable`)

**Complex — follow migration strategy and prompt user for key decisions:**
- Nested chains (`flatMap` / `switchMap` with inner `Single` or `Observable`)
- Custom `Scheduler` implementations
- Complex error recovery: `retryWhen`, exponential backoff, retry counts
- Multi-source merging: `zip`, `combineLatest` with 3+ sources
- `Flowable` with explicit backpressure strategies
- `Subject` shared across multiple classes
- Unclear return type of called APIs (still RxJava or already suspend?)

**Classification rule: ANY Complex criterion makes the whole chain Complex**, regardless of how many Simple criteria it also meets. A two-operator chain with `retryWhen` is Complex. A chain with all standard schedulers but an unclear API return type is Complex.

**Always ask the developer to confirm what each called API returns before migrating. Do not assume.**

## Type Mapping (Simple Cases)

State the mapping explicitly — do not silently transform types.

| RxJava | Coroutines/Flow | Notes |
|---|---|---|
| `Observable<T>` | `Flow<T>` | Cold by default |
| `Flowable<T>` | `Flow<T>` | Handle backpressure explicitly — see below |
| `Single<T>` | `suspend fun`: `T` | One-shot async value |
| `Maybe<T>` | `suspend fun`: `T?` | Returns null if empty |
| `Completable` | `suspend fun`: `Unit` | No return value |
| `Subject<T>` | `MutableSharedFlow<T>` | |
| `BehaviorSubject<T>` | `MutableStateFlow<T>` or `MutableSharedFlow<T>(replay = 1)` | Ask user — see below |
| `PublishSubject<T>` | `MutableSharedFlow<T>(replay = 0)` | |
| `ReplaySubject<T>` | `MutableSharedFlow<T>(replay = n)` | |

**`BehaviorSubject` — ask the user before mapping:**

> "`BehaviorSubject` can map to either `MutableStateFlow` or `MutableSharedFlow(replay = 1)`. `StateFlow` always has a current value (requires an initial value, exposes `.value`) and replays it to new collectors. `SharedFlow(replay = 1)` also replays the last emission but has no `.value` property and no requirement for an initial value. Which semantic fits your use case — do you always have an initial value and need `.value` access, or is the stream sometimes empty at start?"

- **Always has a value, need `.value` access** → `MutableStateFlow(initialValue)`
- **May start empty, no need for `.value`** → `MutableSharedFlow<T>(replay = 1, extraBufferCapacity = 1)`

### Scheduler → Dispatcher Mapping

Always state this mapping explicitly when migrating — do not drop it silently.

| RxJava Scheduler | Coroutine Dispatcher |
|---|---|
| `Schedulers.io()` | `Dispatchers.IO` |
| `Schedulers.computation()` | `Dispatchers.Default` |
| `AndroidSchedulers.mainThread()` | `Dispatchers.Main` |
| `Schedulers.single()` | `newSingleThreadContext("name")` |
| `Schedulers.newThread()` | `Dispatchers.IO` | IO pool is preferred; per-task thread spawning is not idiomatic in coroutines |

**Important:** `observeOn(AndroidSchedulers.mainThread())` does not translate to a dispatcher switch in the repository or use case — it means the **caller** collects on `Dispatchers.Main`. In the coroutines model, this is the ViewModel's responsibility (via `viewModelScope`, which runs on `Dispatchers.Main`). Always explain this shift to the developer.

**When the called API is already a `suspend fun`:** it manages its own dispatcher internally via `withContext`. In this case, `subscribeOn` has no equivalent and simply disappears — do not add a `withContext` wrapper on top of an already main-safe suspend function.

For full operator mapping, see `migration-map.md`.

## Interop Patterns (Incremental Migration)

Add `kotlinx-coroutines-rx3` (or `rx2`) to bridge during migration. Keep interop at layer boundaries only.

```kotlin
// Add to build.gradle.kts
// implementation("org.jetbrains.kotlinx:kotlinx-coroutines-rx3:<version>")

// RxJava → Coroutines/Flow
observable.asFlow()              // Observable<T> → Flow<T>
single.await()                   // Single<T> → suspend T
maybe.awaitSingleOrNull()        // Maybe<T> → suspend T?
completable.await()              // Completable → suspend Unit

// Coroutines/Flow → RxJava (when bridging into legacy callers)
flow.asObservable()              // Flow<T> → Observable<T>
flow.asSingle()                  // Flow<T> (single value) → Single<T> — throws if flow emits 0 or 2+ elements
```

**Rule:** Do not mix RxJava and coroutines within the same function body. Keep interop at layer boundaries.

**Incremental migration order:**
1. Migrate leaf nodes first (API clients, data sources) — bridge with `await()` / `asFlow()`
2. Work upward: data source → repository → use case → ViewModel
3. Remove interop bridges after each layer is fully migrated
4. Commit after each layer

## Migration Strategy (Complex Cases)

**Stop and prompt the user before migrating any of these:**

- **Custom retry policy (`retryWhen`):** Ask the developer to confirm — retry count, delay schedule (linear vs exponential), whether to retry on all errors or specific types, what to do after retries are exhausted.
- **Custom `Scheduler`:** Ask which `CoroutineDispatcher` it maps to.
- **`Flowable` with backpressure:** Ask which Flow strategy fits — `buffer`, `conflate`, or `DROP_OLDEST`.
- **`flatMap`/`switchMap` with write operations:** `flatMapLatest` (equivalent of `switchMap`) cancels in-flight work — dangerous for writes. Ask if cancellation is safe for the operation.
- **Unclear API return type:** Ask whether the API being called has been migrated to suspend or still returns RxJava types.
- **`Subject` shared across classes:** Ask whether `StateFlow` or `SharedFlow` better fits the semantics (state vs event).

### Retry API — Critical Accuracy Note

RxJava's `retryWhen` is stateful. The Kotlin Flow `retry` operator works differently:

```kotlin
// WRONG — common mistake: naming the parameter 'attempt' expecting an index
flow.retry(3) { attempt ->
    delay(attempt * 1000L)  // Does not compile — attempt is a Throwable, not Long
    true
}

// CORRECT: retry(n) with a predicate receives the cause as a Throwable, not an index
flow.retry(3) { cause -> cause is IOException }

// CORRECT: for exponential backoff, track attempts manually
flow.retryWhen { cause, attempt ->
    if (cause is IOException && attempt < 3) {
        delay((attempt + 1) * 1000L)
        true  // retry
    } else {
        false  // give up
    }
}
```

`retryWhen { cause, attempt -> }` is the correct Flow operator for stateful retry — `attempt` here is the 0-based attempt index, `cause` is the exception. Always use this for policies that depend on attempt count.

### `switchMap` → `flatMapLatest`

`switchMap` in RxJava is equivalent to `flatMapLatest` in Flow — both cancel the previous inner stream when a new upstream value arrives. Safe for read operations (search queries, live data). **Dangerous for write operations** — ask the developer before using it.

## Common Pitfalls When Migrating

| Pitfall | Fix |
|---|---|
| `Flowable` → `Flow` without backpressure | Add `buffer()` or `conflate()` to match original strategy |
| `BehaviorSubject` → `SharedFlow` (loses initial value) | Use `MutableStateFlow` with initial value instead |
| Hot `Observable` → `Flow` (now cold) | Use `SharedFlow` or `StateFlow` to maintain hot semantics |
| Missing `CompositeDisposable` replacement | Use `CoroutineScope` — cancellation is automatic |
| `onErrorResumeNext` → `catch {}` swallowing `CancellationException` | `catch { e -> if (e is CancellationException) throw e else emit(fallback) }` |
| `subscribeOn` + `observeOn` both become `flowOn` | `flowOn` applies upstream only — restructure accordingly; `observeOn(main)` becomes caller responsibility |
| `retry(n) { attempt -> }` treating attempt as an index | `attempt` in the predicate is the `Throwable`, not a count — use `retryWhen { cause, attempt -> }` |
| Migrating without confirming API return types | Always ask — a called API may still return `Single`/`Observable` |
