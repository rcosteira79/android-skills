---
name: kotlin-coroutines
description: Use when writing, reviewing, or debugging coroutine code in Kotlin — including dispatcher selection, scope management, structured concurrency, cancellation, exception handling, or async patterns in Android or KMP projects.
---

# Kotlin Coroutines

## Overview

Kotlin coroutines are built on **structured concurrency**: every coroutine runs within a scope, and cancellation/errors propagate through the parent-child hierarchy automatically.

**Core principle:** Suspend functions must always be main-safe. The function doing blocking work owns the `withContext` call — callers should never need to switch dispatchers.

## Diagnosing Coroutine Issues

When reviewing or debugging coroutine code, triage the symptom first:

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| ANR / UI freeze | Blocking call on main thread | `withContext(Dispatchers.IO)` inside suspend fun |
| Memory leak / zombie coroutine | `GlobalScope` or unbound scope | Replace with `viewModelScope`, `lifecycleScope`, or injected scope |
| Incorrect lifecycle collection | `launchWhenStarted` (deprecated) | `repeatOnLifecycle(Lifecycle.State.STARTED)` |
| Cancellation silently broken | `catch (e: Exception)` swallows `CancellationException` | Catch specific types; rethrow `CancellationException` |
| Non-cancellable tight loop | No cancellation checkpoint | Add `ensureActive()` at loop start |
| Hard to test dispatchers | Hardcoded `Dispatchers.IO` | Inject `CoroutineDispatcher` via constructor |
| Race condition / wrong state | State exposed as `MutableStateFlow` | Encapsulate; expose read-only `StateFlow` |
| Callback never cleaned up | No `awaitClose` in `callbackFlow` | Always add `awaitClose { removeListener() }` |

## Step 1: Project Context Check

Before writing or modifying any coroutine code:

1. Search for `Dispatchers`, `CoroutineScope`, `GlobalScope`, `viewModelScope`, `lifecycleScope`
2. Identify how dispatchers are injected (or not)
3. Identify exception handling patterns in use
4. **If approach is sound:** match it
5. **If approach violates rules below:** explain why to the user, recommend the correct approach, and let them decide before changing anything — do NOT produce code that follows the bad pattern
6. **Beyond violations:** also look for places where the patterns in this skill could simplify existing code — manual scope management that structured concurrency could clean up, unnecessary coroutine overhead, etc.

## Dispatcher Selection

| Dispatcher | Use for |
|---|---|
| `Dispatchers.Main` | UI updates only |
| `Dispatchers.IO` | Blocking I/O: network, disk, database |
| `Dispatchers.Default` | CPU-intensive: parsing, sorting, computation |
| `Dispatchers.Unconfined` | Never use in production (unpredictable thread resumption) |

**Rule: Inject dispatchers — never hardcode them.**

```kotlin
// DO
class NewsRepository(private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO) {
    suspend fun fetchNews(): List<Article> = withContext(ioDispatcher) { /* ... */ }
}

// DO NOT
class NewsRepository {
    suspend fun fetchNews(): List<Article> = withContext(Dispatchers.IO) { /* ... */ }
}
```

### Main-Safety Rule

Every suspend function must be callable from the main thread. The class doing blocking work owns the `withContext` — callers must never switch dispatchers before calling a suspend function.

```kotlin
// DO: self-contained, main-safe
class NewsRepository(private val ioDispatcher: CoroutineDispatcher) {
    suspend fun fetchLatestNews(): List<Article> = withContext(ioDispatcher) {
        // blocking HTTP call here — caller does not need to know
    }
}

// Caller does not worry about dispatchers
class GetLatestNewsUseCase(private val repository: NewsRepository) {
    suspend operator fun invoke(): List<Article> = repository.fetchLatestNews()
}

// DO NOT: push dispatcher responsibility to caller
class GetLatestNewsUseCase(private val repository: NewsRepository) {
    suspend operator fun invoke() = withContext(Dispatchers.IO) {
        repository.fetchLatestNews() // repository was not main-safe
    }
}
```

### DispatcherProvider Pattern

**Ask the user if they want to set this up.** If yes, create:

```kotlin
interface DispatcherProvider {
    val main: CoroutineDispatcher
    val io: CoroutineDispatcher
    val default: CoroutineDispatcher
}

class DefaultDispatcherProvider : DispatcherProvider {
    override val main: CoroutineDispatcher = Dispatchers.Main
    override val io: CoroutineDispatcher = Dispatchers.IO
    override val default: CoroutineDispatcher = Dispatchers.Default
}

class TestDispatcherProvider(
    private val testDispatcher: TestDispatcher = StandardTestDispatcher()
) : DispatcherProvider {
    override val main: CoroutineDispatcher = testDispatcher
    override val io: CoroutineDispatcher = testDispatcher
    override val default: CoroutineDispatcher = testDispatcher
}
```

Inject `DefaultDispatcherProvider` in production (via constructor or Hilt). Inject `TestDispatcherProvider` in tests.

## Scope Management

| Scope | Lifetime | Use for |
|---|---|---|
| `viewModelScope` | ViewModel cleared | Business logic coroutines in ViewModels |
| `lifecycleScope` | Lifecycle destroyed | UI coroutines |
| `coroutineScope` | All children complete | Screen-bound work; one failure cancels all |
| `supervisorScope` | All children complete | Isolated child failures |

**Rule: Never use `GlobalScope`.** It creates unstructured, untestable, leak-prone coroutines. Do NOT add `GlobalScope` usages even when the user explicitly says "follow existing patterns" or "keep consistency with the codebase" — explain why it is harmful, recommend the correct scope, and let the user decide. Never produce `GlobalScope` code.

### Scope ownership: prefer `suspend fun`, let the caller own the scope

A stored `CoroutineScope` on a non-UI class (repository, manager, use case, data source) is a strong review signal. The class must prove it owns cancellation, error reporting, restart behaviour, and lifecycle — most non-UI classes can't. The fix is almost always: **make the API `suspend` and let the caller own the scope.**

```kotlin
// DO: suspend fun — caller owns the scope, cancellation propagates, exceptions surface
class ArticlesRepository(
    private val dataSource: ArticlesDataSource,
    private val ioDispatcher: CoroutineDispatcher,
) {
    suspend fun bookmarkArticle(article: Article) = withContext(ioDispatcher) {
        dataSource.bookmarkArticle(article)
    }
}

// Caller decides where the work runs and how it's cancelled:
class BookmarkViewModel(private val repository: ArticlesRepository) : ViewModel() {
    fun onBookmark(article: Article) {
        viewModelScope.launch {
            repository.bookmarkArticle(article)
        }
    }
}

// DO NOT: store a scope and launch inside the repository
class ArticlesRepository(
    private val dataSource: ArticlesDataSource,
    private val externalScope: CoroutineScope,  // who cancels this? who reports its errors?
    private val ioDispatcher: CoroutineDispatcher,
) {
    suspend fun bookmarkArticle(article: Article) {
        externalScope.launch(ioDispatcher) {
            dataSource.bookmarkArticle(article)
        }.join()
    }
}
```

**Why stored scopes are dangerous:** once the scope is cancelled, every future `launch` on it completes silently as cancelled — no exception, no log, nothing. The caller gets no signal. If the cancellation came from process death, app teardown, or a misconfigured DI graph, the repository keeps accepting calls and silently doing nothing.

### When work must outlive the caller — fire-and-forget

If a bookmark must survive the user navigating away mid-write, the work doesn't belong to the repository — it belongs to an **application-scoped state holder** (a `WorkManager` job, a navigation-graph `ViewModel`, an Application-scoped class that owns the scope deliberately).

```kotlin
// Option 1: WorkManager for guaranteed-completion background work
class BookmarkViewModel(
    private val workManager: WorkManager,
) : ViewModel() {
    fun onBookmark(article: Article) {
        val request = OneTimeWorkRequestBuilder<BookmarkWorker>()
            .setInputData(workDataOf("articleId" to article.id))
            .build()
        workManager.enqueue(request)
    }
}

// Option 2: Application-scoped class that explicitly owns its scope and lifecycle
@Singleton
class OfflineBookmarkQueue @Inject constructor(
    private val applicationScope: CoroutineScope,  // Application-bound, cancelled on process death only
    private val repository: ArticlesRepository,
) {
    fun enqueue(article: Article) {
        applicationScope.launch {
            repository.bookmarkArticle(article)
        }
    }
}
```

The named class `OfflineBookmarkQueue` makes the lifetime explicit — and it's testable, cancellable, and observable. Compare against burying `externalScope.launch` inside a repository where no one knows the work is happening.

### State-holder carve-out — when `launch` from a non-suspending method is correct

A UI state holder (ViewModel, Compose-scoped state holder) is allowed to launch from non-suspending event callbacks under all three of:

1. **It is a state holder for a UI surface.** Not "feels like a state holder" — actually owns UI state that the view layer collects.
2. **It uses a lifecycle-bound scope** — `viewModelScope`, `rememberCoroutineScope`, or equivalent. The scope's cancellation is tied to a UI lifecycle the framework manages.
3. **The trigger is a UI event** — a click, swipe, key press, lifecycle event. Not a repository call, not a background timer, not a DI hook.

```kotlin
// DO — three conditions met: state holder, lifecycle-bound scope, UI event trigger
class BookmarkViewModel(private val repository: ArticlesRepository) : ViewModel() {
    fun onBookmarkClicked(article: Article) {
        viewModelScope.launch {
            repository.bookmarkArticle(article)
        }
    }
}
```

If any condition fails, refactor: expose a `suspend fun` and let the actual UI state holder own the scope.

### Anti-pattern: `init { viewModelScope.launch { } }` for non-restartable loops

Launching from `init` makes the work invisible — there's no named trigger, no clear restart path, and a navigation back/forward cycle silently re-launches.

```kotlin
// WRONG — init launches; no observable lifecycle
class FeedViewModel : ViewModel() {
    init {
        viewModelScope.launch {
            while (isActive) {
                refreshFeed()
                delay(30_000)
            }
        }
    }
}

// RIGHT — expose state, let the UI drive collection lifetime
class FeedViewModel(repository: FeedRepository) : ViewModel() {
    val feed: StateFlow<Feed> = repository.feedFlow
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Feed.Empty)
}
```

### DI-bound singleton anti-pattern — `Initializer.initialize()` must not `launch`

`@Singleton` classes that `launch` from their constructor (or from a Hilt `Initializer.initialize()` body) start coroutines at a moment the consumer can't observe or control. "Where does this work start?" → "wherever DI realizes me." "Who can observe whether it's running?" → "no one."

```kotlin
// WRONG — singleton launches in init; no consumer ever asked for this
@Singleton
class AnalyticsUploader @Inject constructor(
    private val applicationScope: CoroutineScope,
    private val api: AnalyticsApi,
) {
    init {
        applicationScope.launch {
            while (true) {
                api.uploadPending()
                delay(60_000)
            }
        }
    }
}

// WRONG — Hilt Initializer launches; misuse of the registration hook
class AnalyticsInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        applicationScope.launch { /* background loop */ }
    }
    override fun dependencies() = emptyList<Class<out Initializer<*>>>()
}

// RIGHT — scheduled work with explicit lifecycle and observable state
class AnalyticsSchedulingInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            "analytics-upload",
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<AnalyticsUploadWorker>(15, TimeUnit.MINUTES).build(),
        )
    }
    override fun dependencies() = emptyList<Class<out Initializer<*>>>()
}
```

Diagnostic for DI-bound coroutine launches:
- "Where is the start moment defined?" If "wherever DI realizes me," bad.
- "Who can observe whether the work is running?" If "no one," bad.
- "Can the work be restarted independently?" If "no, only by restarting the process," bad.

Three named replacement patterns:
1. **Invert into the consumer** — delete the background-loop class; let the consumer collect or call directly.
2. **Scheduled work** — use `WorkManager` with `enqueueUniquePeriodicWork` so the system owns lifecycle.
3. **Explicit named launch site** — if the work really must run, put it in a named class with a named method (`OfflineBookmarkQueue.startSyncing()`) so the start moment is grep-able.

**Layer responsibilities:**
- Work tied to current screen → `coroutineScope` or `supervisorScope` inside a `suspend fun`
- Work that genuinely outlives the screen → `WorkManager`, navigation-graph `ViewModel`, or a named Application-scoped class with explicit start/stop methods
- Never: stored `CoroutineScope` on a repository/manager/use case to "make `launch` available"

## Structured Concurrency

```kotlin
// Parallel work — both fail together
suspend fun getBookAndAuthors(): BookAndAuthors = coroutineScope {
    val books = async { booksRepository.getAllBooks() }
    val authors = async { authorsRepository.getAllAuthors() }
    BookAndAuthors(books.await(), authors.await())
}

// Parallel work — failures are independent
suspend fun loadDashboard() = supervisorScope {
    launch { loadNews() }
    launch { loadWeather() }
}
```

- `async`/`await` — parallel work returning a value
- `launch` — fire-and-forget within a structured scope; no result returned
- `coroutineScope` — one child failure cancels all siblings
- `supervisorScope` — children fail independently

**Mixed case — ask the user:**

When some operations should cancel together on failure (e.g. a required data fetch) but others should be independent (e.g. an optional analytics call), the right shape isn't obvious. Ask:

> "If [critical operation] fails, should [other operation] be cancelled too, or should it continue independently?"

Based on the answer, use `supervisorScope` for the outer scope and `coroutineScope` for the group that must cancel together:

```kotlin
suspend fun loadScreen() = supervisorScope {
    // analytics failure must NOT cancel the data fetch
    launch { trackScreenView() }

    // both data fetches must succeed or both should cancel
    launch {
        coroutineScope {
            val user = async { fetchUser() }
            val feed = async { fetchFeed() }
            displayData(user.await(), feed.await())
        }
    }
}
```

## Cancellation

Cancellation is cooperative — coroutines must check for it explicitly in long operations.

```kotlin
launch {
    for (file in files) {
        ensureActive() // throws CancellationException if job is cancelled
        readFile(file)
    }
}
```

- `ensureActive()` — throws `CancellationException` if cancelled; use at the top of loops and long operations
- `isActive` — check without throwing; use when you need to clean up before returning
- `yield()` — suspends, checks cancellation, and lets other coroutines run
- All `kotlinx.coroutines` suspend functions (`delay`, `withContext`) are already cancellable — no extra check needed

**Cleanup that must survive cancellation** — use `withContext(NonCancellable)`:

```kotlin
launch {
    try {
        doWork()
    } finally {
        // This block runs even if the coroutine was cancelled,
        // but without NonCancellable it cannot call suspend functions
        withContext(NonCancellable) {
            db.saveCheckpoint() // suspend call safe here
        }
    }
}
```

Use `NonCancellable` only in `finally` blocks for cleanup. Never use it as a general escape hatch from cancellation.

## Timeouts

**Only use `withTimeout`/`withTimeoutOrNull` when:**
- The codebase already uses them — match the pattern, or
- The user explicitly asks to short-circuit an operation and return a default after a time limit

**Do not** suggest them for network timeouts — network libraries (OkHttp, Retrofit, Ktor) expose their own timeout configuration, which is the right place for that.

```kotlin
// withTimeout — throws TimeoutCancellationException if the block exceeds the limit
val config = withTimeout(5_000) {
    remoteConfig.fetchAndActivate()
}

// withTimeoutOrNull — returns null instead of throwing; use when a missing result is acceptable
val config = withTimeoutOrNull(5_000) {
    remoteConfig.fetchAndActivate()
} ?: defaultConfig
```

`TimeoutCancellationException` is a `CancellationException` — never catch it without rethrowing, and never wrap a `withTimeout` block in `catch (e: Exception)`.

## Exception Handling

```kotlin
// DO: catch specific exception types
viewModelScope.launch {
    try {
        loginRepository.login(username, token)
    } catch (e: IOException) {
        _uiState.value = UiState.Error("Network error")
    }
}

// DO NOT: catch Exception or Throwable — swallows CancellationException and breaks cancellation
viewModelScope.launch {
    try {
        loginRepository.login(username, token)
    } catch (e: Exception) { } // NEVER do this
}
```

- Catch **specific** types only: `IOException`, `HttpException`, etc. Never `Exception` or `Throwable`
- **Never** catch `CancellationException` without rethrowing — it silently breaks structured cancellation
- **Never** use `runCatching` in suspend functions — it catches `CancellationException`. Use `suspendRunCatching` instead (see below)
- `try/catch` does **not** work around `launch {}` — always put it inside the coroutine body
- `CoroutineExceptionHandler` — last-resort handler for uncaught exceptions in `launch`; does not catch in `async`
- `SupervisorJob` — child failures do not cancel siblings; pair with per-child `try/catch` or `CoroutineExceptionHandler`

### `suspendRunCatching`

`runCatching` catches all `Throwable` including `CancellationException`, silently breaking structured concurrency. When you need `Result`-style error handling in suspend functions, suggest this utility:

```kotlin
suspend inline fun <R> suspendRunCatching(block: () -> R): Result<R> = try {
    Result.success(block())
} catch (e: CancellationException) {
    throw e
} catch (e: Throwable) {
    Result.failure(e)
}
```

Usage:

```kotlin
suspend fun refreshNews(): Result<Unit> = withContext(ioDispatcher) {
    suspendRunCatching {
        val remoteNews = newsApi.fetchLatest()
        newsDao.insertAll(remoteNews.map { it.toDomain() })
    }
}
```

If the project already has a similar utility (`safeRunCatching`, `resultOf`, etc.), match the existing name. Otherwise suggest `suspendRunCatching` and let the user decide where to place it.

## Android-Specific Rules

**ViewModel coroutine ownership:**

```kotlin
// DO: ViewModel creates coroutines, exposes immutable StateFlow
class LatestNewsViewModel(
    private val getLatestNews: GetLatestNewsUseCase
) : ViewModel() {
    private val _uiState = MutableStateFlow<NewsUiState>(NewsUiState.Loading)
    val uiState: StateFlow<NewsUiState> = _uiState

    fun loadNews() {
        viewModelScope.launch {
            try {
                _uiState.value = NewsUiState.Success(getLatestNews())
            } catch (e: IOException) {
                _uiState.value = NewsUiState.Error
            }
        }
    }
}

// DO NOT: expose suspend fun for business logic — caller must manage the coroutine lifecycle
class LatestNewsViewModel(private val getLatestNews: GetLatestNewsUseCase) : ViewModel() {
    suspend fun loadNews() = getLatestNews()
}
```

**Layer contracts:**
- Data/business layers expose `suspend fun` for one-shot calls and `Flow` for streams
- Presentation layer (ViewModel) controls execution lifecycle via `viewModelScope`
- Views never trigger business logic coroutines — defer to ViewModel

**Lifecycle safety:**
- `lifecycleScope` + `repeatOnLifecycle` for flow collection in non-Compose UI
- Never launch coroutines in `onStart`/`onResume` without matching cancellation in `onStop`/`onPause`

**viewModelScope in tests:** call `Dispatchers.setMain(testDispatcher)` before each test, `Dispatchers.resetMain()` after.

**Callback-to-Flow conversion** — use `callbackFlow` with `awaitClose`:

```kotlin
fun locationUpdates(): Flow<Location> = callbackFlow {
    val listener = LocationListener { location ->
        trySend(location)
    }
    locationManager.requestLocationUpdates(listener)

    awaitClose { locationManager.removeUpdates(listener) }
}
```

`awaitClose` is mandatory — it runs when the collector cancels or the flow completes, ensuring the listener is always unregistered.

## KMP-Specific Rules

- Do not use `MainScope()` — it creates an unstructured scope (`Dispatchers.Main + SupervisorJob()`) with the same problems as `GlobalScope`: no lifecycle awareness, must be manually cancelled, hard to test. Instead, inject a `CoroutineScope` from the platform layer (e.g. `viewModelScope` on Android, a lifecycle-bound scope on iOS via `CoroutineScope(SupervisorJob() + Dispatchers.Main)` tied to the view controller lifecycle).
- Inject `CoroutineDispatcher` as a dependency for platform-specific implementations
- Use `expect`/`actual` for `Dispatchers.Main.immediate` if not available on all platforms

## Common Pitfalls

| Pitfall | Fix |
|---|---|
| `catch (e: CancellationException) {}` | Rethrow: `catch (e: CancellationException) { throw e }` |
| `catch (e: Exception)` or `catch (e: Throwable)` | Catch specific types only |
| `runBlocking` in coroutine code | Only valid at top level in `main()`; never inside coroutine bodies, on the main thread, or inside `runTest` (deadlocks with `TestDispatcher`) |
| `GlobalScope.launch {}` | Flag to user; inject a `CoroutineScope` instead |
| Hardcoded `Dispatchers.IO` in production | Inject via `DispatcherProvider` |
| `try/catch` around `launch {}` | Put try/catch inside the coroutine body |
| No cancellation check in long loop | Add `ensureActive()` at start of each iteration |
| Calling blocking I/O directly in coroutine body | Wrap with `withContext(ioDispatcher) { ... }` |
| A class has N `suspend fun` methods and only one or two do not use `withContext` while the rest do | The outliers are likely missing `withContext` — flag them as probable oversights |
| `suspend fun` for business logic in ViewModel | ViewModel should use `viewModelScope.launch` and expose `StateFlow`. **Exception:** pure computations returning a value (e.g. generating a bitmap) are fine as `suspend fun` when called from Compose via `LaunchedEffect` or `produceState` — the composition manages the coroutine lifecycle correctly in that case |
| Explicit `SupervisorJob()` added to a ViewModel alongside `viewModelScope` | `viewModelScope` already uses `SupervisorJob` internally — flag to user, the extra `SupervisorJob` is redundant and may create a detached scope |
| `async {}` result never awaited in `supervisorScope` | Exceptions in unawaited `async {}` are silently swallowed — use `launch {}` if you don't need the result |
| `runCatching {}` in suspend functions | Catches `CancellationException`, breaking structured concurrency — use `suspendRunCatching` or `try/catch` with specific exception types |

## Testing

Use `runTest` — automatically skips delays and manages virtual time.

### Test Dispatcher Choice

Explain both options and let the user pick:

**`StandardTestDispatcher` (recommended for most cases):**
- Coroutines are queued and do not run until explicitly advanced
- Control execution with `advanceUntilIdle()` or `advanceTimeBy(ms)`
- Best for: precise execution order, time-based logic, testing `delay`

**`UnconfinedTestDispatcher` (simpler, less control):**
- Coroutines run eagerly as soon as launched — no manual advancing needed
- Best for: simple state observation tests where execution order does not matter
- Risk: can hide ordering bugs in concurrent code

```kotlin
// StandardTestDispatcher example
@Test
fun `loads news correctly`() = runTest {
    val dispatchers = TestDispatcherProvider(StandardTestDispatcher(testScheduler))
    val repository = NewsRepository(dispatchers = dispatchers)

    repository.loadNews()
    advanceUntilIdle()

    assertThat(repository.news).isNotEmpty()
}

// UnconfinedTestDispatcher example
@Test
fun `emits loading state initially`() = runTest {
    val dispatchers = TestDispatcherProvider(UnconfinedTestDispatcher(testScheduler))
    val viewModel = LatestNewsViewModel(dispatchers = dispatchers)

    assertThat(viewModel.uiState.value).isEqualTo(NewsUiState.Loading)
}
```

If `DispatcherProvider` is set up, inject `TestDispatcherProvider` in all tests.
