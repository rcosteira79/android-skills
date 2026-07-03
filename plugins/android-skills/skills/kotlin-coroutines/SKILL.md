---
name: kotlin-coroutines
description: Use when writing, reviewing, or debugging coroutine code in Kotlin — including dispatcher selection, scope management, structured concurrency, cancellation, exception handling, or async patterns in Android or KMP projects.
---

# Kotlin Coroutines

Built on **structured concurrency**: every coroutine runs in a scope; cancellation and errors propagate through the parent–child hierarchy. This reference focuses on the two disciplines most often gotten wrong: **who owns the scope**, and **exception handling that doesn't break cancellation**.

**Main-safety:** the function doing blocking work owns the `withContext(ioDispatcher)`; callers never switch dispatchers before calling a suspend function.

## Scope ownership — prefer `suspend fun`, let the caller own the scope

A stored `CoroutineScope` on a non-UI class (repository, manager, use case, data source) is a strong review signal: the class would have to prove it owns cancellation, error reporting, restart, and lifecycle — most can't. The fix is almost always **make the API `suspend` and let the caller own the scope.**

```kotlin
// DO — suspend fun; the caller owns the scope, cancellation propagates, exceptions surface
class ArticlesRepository(private val dataSource: ArticlesDataSource, private val io: CoroutineDispatcher) {
    suspend fun bookmark(article: Article) = withContext(io) { dataSource.bookmark(article) }
}
class BookmarkViewModel(private val repo: ArticlesRepository) : ViewModel() {
    fun onBookmark(a: Article) { viewModelScope.launch { repo.bookmark(a) } }
}

// DO NOT — store a scope and launch inside the repository
class ArticlesRepository(private val externalScope: CoroutineScope, /* ... */) {
    suspend fun bookmark(a: Article) { externalScope.launch { dataSource.bookmark(a) }.join() }
}
```

**Why stored scopes are dangerous:** once that scope is cancelled, every future `launch` on it completes silently as cancelled — no exception, no log. If the cancellation came from process death or a misconfigured DI graph, the class keeps accepting calls and silently does nothing.

### When work must outlive the caller

A write that must survive the user navigating away doesn't belong to the repository — it belongs to a `WorkManager` job, or a **named** application-scoped class that deliberately owns its scope (an `OfflineBookmarkQueue` with an injected `applicationScope`, cancelled only on process death). The named class makes the lifetime explicit, testable, and observable — unlike a buried `externalScope.launch`.

### State-holder carve-out — when `launch` from a non-suspending method is OK

A UI state holder may launch from a non-suspending event callback only under **all three**: (1) it actually owns UI state the view layer collects; (2) it uses a lifecycle-bound scope (`viewModelScope` / `rememberCoroutineScope`); (3) the trigger is a UI event (click, swipe, lifecycle) — not a repository call, background timer, or DI hook. If any fails, expose a `suspend fun` and let the real state holder own the scope.

### Anti-patterns: `init { launch }` and DI-singleton `launch`

`init { viewModelScope.launch { while (isActive) { … } } }` makes the work invisible — no named trigger, no restart path, and a nav back/forward silently re-launches it. Expose a `StateFlow` via `stateIn` instead. Likewise a `@Singleton` (or a Hilt `Initializer`) that launches from its constructor starts coroutines "wherever DI realizes me," observable by no one — use `WorkManager.enqueueUniquePeriodicWork`, invert the work into the consumer, or put it in a named class with an explicit `startX()` method.

**Diagnostic** for any DI-bound or stored-scope launch: *where is the start moment defined? who can observe whether it's running? can it be restarted without restarting the process?* Answers of *"wherever / no one / no"* mean refactor.

## Cancellation

Cooperative: `ensureActive()` at the top of long loops (throws if cancelled), `isActive` to check without throwing, `yield()` to also yield the thread. `delay` / `withContext` are already cancellable. Cleanup that must run after cancellation goes in `finally { withContext(NonCancellable) { … } }` — `NonCancellable` only there, never as a general escape hatch. `TimeoutCancellationException` (from `withTimeout`) **is** a `CancellationException` — never catch it without rethrowing. (Don't reach for `withTimeout` for network timeouts — OkHttp/Retrofit/Ktor own those.)

## Exception handling — don't break cancellation

```kotlin
// DO — specific types
try { repo.login(u, p) } catch (e: IOException) { _state.value = Error("Network") }

// DO NOT — catch (e: Exception) / Throwable swallows CancellationException and breaks structured cancellation
```

- Catch **specific** types (`IOException`, `HttpException`), never `Exception` / `Throwable`.
- **Never** catch `CancellationException` without rethrowing it.
- **Never** `runCatching` in a suspend function — it catches `CancellationException`. Use a `suspendRunCatching` that rethrows it:

```kotlin
suspend inline fun <R> suspendRunCatching(block: () -> R): Result<R> = try {
    Result.success(block())
} catch (e: CancellationException) { throw e } catch (e: Throwable) { Result.failure(e) }
```

- `try/catch` doesn't wrap `launch {}` — put it inside the coroutine body.
- An unawaited `async {}` in a `supervisorScope` swallows its exception — use `launch` if you don't need the result.
- `viewModelScope` already uses `SupervisorJob` — don't add another alongside it.

## KMP

Don't use `MainScope()` — it's unstructured (`Dispatchers.Main + SupervisorJob()`), with the same problems as `GlobalScope`. Inject a lifecycle-bound `CoroutineScope` from the platform layer (`viewModelScope` on Android; a view-controller-bound scope on iOS). Inject `CoroutineDispatcher` for platform implementations; `expect`/`actual` `Dispatchers.Main.immediate` if a target lacks it.

## Testing

Coroutine and dispatcher testing lives in `android-skills:android-testing` — notably the two-schedulers trap (`runTest` + `MainDispatcherRule` must share one scheduler) and the `StandardTestDispatcher` default in Compose tests.
