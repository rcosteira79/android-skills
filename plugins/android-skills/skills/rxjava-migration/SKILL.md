---
name: rxjava-migration
description: Use only when the user explicitly requests migration from RxJava to Kotlin coroutines and/or flows.
---

# RxJava Migration

Migrate RxJava to Kotlin coroutines/flows incrementally. **Only invoke this skill when the user explicitly asks to migrate RxJava code.** Simple cases map directly; complex cases need a strategy and user input *before* any code is written.

## Step 1: Complexity gate

Classify before writing any migrated code. A chain is **Complex** if ANY of: nested `flatMap`/`switchMap` with an inner `Single`/`Observable`; a custom `Scheduler`; complex error recovery (`retryWhen`, backoff, retry counts); multi-source `zip`/`combineLatest` (3+ sources); `Flowable` with an explicit backpressure strategy; a `Subject` shared across classes; or an unclear API return type. **Any single Complex criterion makes the whole chain Complex** — a two-operator chain with `retryWhen` is Complex.

**Always confirm what each called API returns before migrating — do not assume.** A leaf you think is migrated may still return `Single`/`Observable`.

## Type mapping (state it explicitly — don't silently transform)

| RxJava | Coroutines/Flow |
|---|---|
| `Observable<T>` / `Flowable<T>` | `Flow<T>` (Flowable: match the original backpressure with `buffer()` / `conflate()`) |
| `Single<T>` / `Maybe<T>` / `Completable` | `suspend fun`: `T` / `T?` / `Unit` |
| `PublishSubject` / `ReplaySubject(n)` | `MutableSharedFlow(replay = 0 / n)` |
| `BehaviorSubject<T>` | **ask** — `MutableStateFlow` vs `MutableSharedFlow(replay = 1)` |

**`BehaviorSubject` — ask first:** `StateFlow` always has a current value (needs an initial, exposes `.value`, replays it to new collectors); `SharedFlow(replay = 1)` also replays the last emission but has no `.value` and no initial-value requirement. *"Do you always have an initial value and need `.value` access, or is the stream sometimes empty at start?"*

### Schedulers and the `observeOn` shift

`Schedulers.io()` → `Dispatchers.IO`, `computation()` → `Default`, `mainThread()` → `Main`, `single()` → `newSingleThreadContext(...)`, `newThread()` → `IO` (per-task thread spawning isn't idiomatic in coroutines).

- **`observeOn(AndroidSchedulers.mainThread())` does NOT become a dispatcher switch** in the repository/use case — it means the **caller** collects on `Main`, which in the coroutines model is the ViewModel's job (`viewModelScope` runs on `Main`). Explain this shift to the developer.
- **When the called API is already a `suspend fun`**, it manages its own dispatcher via `withContext` — `subscribeOn` has no equivalent and simply disappears. **Do not wrap an already-main-safe suspend function in another `withContext`.**
- `subscribeOn` + `observeOn` → `flowOn` applies **upstream only**; restructure accordingly.

For the full operator mapping, see `migration-map.md`.

## Retry — the accuracy trap

RxJava's `retryWhen` is stateful; Flow's `retry` predicate receives the **`Throwable`**, not an index.

```kotlin
// WRONG — 'attempt' is a Throwable, not a Long; this does not compile
flow.retry(3) { attempt -> delay(attempt * 1000L); true }

// CORRECT — retry(n)'s predicate gets the cause
flow.retry(3) { cause -> cause is IOException }

// CORRECT — stateful backoff: attempt IS the 0-based index here
flow.retryWhen { cause, attempt ->
    if (cause is IOException && attempt < 3) { delay((attempt + 1) * 1000L); true } else false
}
```

Use `retryWhen { cause, attempt -> }` for any policy that depends on the attempt count.

## Interop during incremental migration

Add `kotlinx-coroutines-rx3` (or `rx2`); keep interop **at layer boundaries only**, never mixing RxJava and coroutines inside one function body.

```kotlin
observable.asFlow(); single.await(); maybe.awaitSingleOrNull(); completable.await()   // Rx → coroutines
flow.asObservable(); flow.asSingle()   // coroutines → Rx (asSingle throws if the flow emits 0 or 2+ elements)
```

Migrate leaf-up (data source → repository → use case → ViewModel), remove each bridge once its layer is fully migrated, and commit per layer.

## Complex cases — stop and ask before migrating

`retryWhen` (count? linear vs exponential? which error types? what after exhaustion?); a custom `Scheduler` (which `CoroutineDispatcher`?); `Flowable` backpressure (`buffer` / `conflate` / `DROP_OLDEST`?); `flatMap`/`switchMap` over **writes** — `switchMap` → `flatMapLatest` is safe for reads (search/live data) but cancels in-flight work, so it's dangerous for writes; a `Subject` shared across classes (state → `StateFlow`, event → `SharedFlow`?). For `onErrorResumeNext` → `catch`, rethrow cancellation: `catch { e -> if (e is CancellationException) throw e else emit(fallback) }`.

(`compositeDisposable.clear()` in `onCleared()` → delete it entirely: `viewModelScope` is cancelled automatically when the ViewModel is cleared.)
