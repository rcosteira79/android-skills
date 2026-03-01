---
name: kotlin-coroutines
description: Use when writing, reviewing, or debugging coroutine code in Kotlin — including dispatcher selection, scope management, structured concurrency, cancellation, exception handling, or async patterns in Android or KMP projects.
---

# Kotlin Coroutines

## Overview

Kotlin coroutines are built on **structured concurrency**: every coroutine runs within a scope, and cancellation/errors propagate through the parent-child hierarchy automatically.

**Core principle:** Suspend functions must always be main-safe. The function doing blocking work owns the `withContext` call — callers should never need to switch dispatchers.

## Step 1: Project Context Check

Before writing or modifying any coroutine code:

1. Search for `Dispatchers`, `CoroutineScope`, `GlobalScope`, `viewModelScope`, `lifecycleScope`
2. Identify how dispatchers are injected (or not)
3. Identify exception handling patterns in use
4. **If approach is sound:** match it
5. **If approach violates rules below:** explain why to the user, recommend the correct approach, and let them decide before changing anything — do NOT produce code that follows the bad pattern

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

If work must outlive the current screen, inject an external `CoroutineScope`:

```kotlin
// DO: inject external scope for work that must survive navigation
class ArticlesRepository(
    private val dataSource: ArticlesDataSource,
    private val externalScope: CoroutineScope,
    private val ioDispatcher: CoroutineDispatcher
) {
    suspend fun bookmarkArticle(article: Article) {
        externalScope.launch(ioDispatcher) {
            dataSource.bookmarkArticle(article)
        }.join()
    }
}

// DO NOT: use GlobalScope
class ArticlesRepository(private val dataSource: ArticlesDataSource) {
    suspend fun bookmarkArticle(article: Article) {
        GlobalScope.launch { dataSource.bookmarkArticle(article) }.join()
    }
}
```

**Layer responsibilities:**
- Work tied to current screen → `coroutineScope` or `supervisorScope`
- Work that must outlive the screen → inject external `CoroutineScope` managed by `Application` or a navigation-graph-scoped `ViewModel`

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
- `try/catch` does **not** work around `launch {}` — always put it inside the coroutine body
- `CoroutineExceptionHandler` — last-resort handler for uncaught exceptions in `launch`; does not catch in `async`
- `SupervisorJob` — child failures do not cancel siblings; pair with per-child `try/catch` or `CoroutineExceptionHandler`

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

## KMP-Specific Rules

- Use `MainScope()` for shared UI-layer coroutine scope in common code
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
| `suspend fun` for business logic in ViewModel | ViewModel should use `viewModelScope.launch` and expose `StateFlow` |

## Testing

**Always ask the user before writing tests.**

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
