# Kotlin Coroutines & Flows Skills Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create three focused Claude skills — `kotlin-coroutines`, `kotlin-flows`, and `rxjava-migration` — that guide best-practice coroutine and flow code in Android and KMP projects.

**Architecture:** Three independent skills in `~/.claude/skills/`, each with its own `SKILL.md`. The TDD process from `superpowers:writing-skills` applies: run baseline scenarios first (RED), write the skill (GREEN), verify, then refactor (REFACTOR). Each skill is tested and committed independently.

**Tech Stack:** Kotlin, Kotlin Coroutines, Kotlin Flow, Turbine (testing), kotlinx-coroutines-rx3 (migration interop)

---

## Task 1: RED — Baseline scenarios for `kotlin-coroutines`

Run these scenarios using a subagent **without** the skill loaded. Document exact responses and rationalizations.

**Files:**
- No files to create. Document findings in notes before proceeding to Task 2.

**Step 1: Run Scenario A — Application scenario**

Prompt the subagent:

> "Write a repository class called `NewsRepository` that fetches a list of news articles from a REST API using Retrofit. The repository should use coroutines, handle errors gracefully, and be unit testable. Use Kotlin."

Document: Does it inject dispatchers? Does it use `withContext`? Does it make the function main-safe? Does it catch `Exception` or specific types?

**Step 2: Run Scenario B — Pressure: legacy codebase with GlobalScope**

Prompt the subagent:

> "I'm working on a legacy Android codebase. The entire app uses `GlobalScope.launch` and hardcoded `Dispatchers.IO`. The team values consistency with existing patterns. Please add a `UserRepository` that fetches a user profile and a `UserViewModel` that calls it and updates UI state."

Document: Does it follow the bad pattern? Does it warn the user? Does it explain why GlobalScope is harmful?

**Step 3: Run Scenario C — Pressure: exception handling shortcut**

Prompt the subagent:

> "This is urgent. I just need you to wrap this `GlobalScope.launch` block with a try/catch to handle exceptions quickly. Don't refactor anything."

```kotlin
class ProfileViewModel : ViewModel() {
    fun loadProfile() {
        GlobalScope.launch(Dispatchers.IO) {
            val profile = profileRepository.fetchProfile()
            withContext(Dispatchers.Main) { updateUi(profile) }
        }
    }
}
```

Document: Does it comply blindly? Does it catch `Exception`? Does it flag the underlying issues?

**Step 4: Document findings**

Write down exact rationalizations used. These inform what the skill must address.

---

## Task 2: GREEN — Write `kotlin-coroutines/SKILL.md`

**Files:**
- Create: `~/.claude/skills/kotlin-coroutines/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p ~/.claude/skills/kotlin-coroutines
```

**Step 2: Write SKILL.md**

Create `~/.claude/skills/kotlin-coroutines/SKILL.md` with this exact content:

```markdown
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
5. **If approach violates rules below:** explain why to the user, recommend the correct approach, and let them decide before changing anything

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
    private val testDispatcher: TestCoroutineDispatcher = StandardTestDispatcher()
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

**Rule: Never use `GlobalScope`.** It creates unstructured, untestable, leak-prone coroutines.

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
- `launch` — fire-and-observe within a structured scope
- `coroutineScope` — one child failure cancels all siblings
- `supervisorScope` — children fail independently

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

// DO NOT: catch Exception or Throwable — swallows CancellationException
viewModelScope.launch {
    try {
        loginRepository.login(username, token)
    } catch (e: Exception) { } // breaks cooperative cancellation silently
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
| `runBlocking` on main thread | Never — blocks UI thread |
| `GlobalScope.launch {}` | Inject a `CoroutineScope` |
| Hardcoded `Dispatchers.IO` in production | Inject via `DispatcherProvider` |
| `try/catch` around `launch {}` | Put try/catch inside the coroutine body |
| `catch (e: Exception)` | Catch specific types only |
| No cancellation check in long loop | Add `ensureActive()` at start of each iteration |

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
```

**Step 3: Verify file was created**

```bash
cat ~/.claude/skills/kotlin-coroutines/SKILL.md | head -5
```

Expected: frontmatter with `name: kotlin-coroutines`

---

## Task 3: GREEN Verify + REFACTOR — Test `kotlin-coroutines` skill

**Step 1: Run Scenario A again with skill**

Repeat the same prompt from Task 1 Step 1 — this time with the skill loaded. Verify the response:
- Injects dispatchers via `DispatcherProvider` or constructor
- Uses `withContext` inside the repository (main-safe)
- Catches specific exception types, not `Exception`

**Step 2: Run Scenario B again with skill**

Repeat the GlobalScope legacy codebase scenario. Verify:
- Flags GlobalScope as bad practice with explanation
- Recommends injecting `CoroutineScope` instead
- Asks user how to proceed before changing existing patterns

**Step 3: Run Scenario C again with skill**

Repeat the urgent exception handling scenario. Verify:
- Does not blindly catch `Exception`
- Flags the underlying issues (GlobalScope, hardcoded dispatcher)
- Explains `CancellationException` risk

**Step 4: Identify new rationalizations**

If any new bad patterns appear that the skill did not prevent, add explicit rules to the SKILL.md.

**Step 5: Commit**

```bash
git -C ~/.claude add skills/kotlin-coroutines/SKILL.md
git -C ~/.claude commit -m "feat: add kotlin-coroutines skill"
```

(If `~/.claude` is not a git repo, skip the commit step and note it.)

---

## Task 4: RED — Baseline scenarios for `kotlin-flows`

Run these scenarios using a subagent **without** `kotlin-flows` skill loaded.

**Step 1: Run Scenario A — Callback bridging**

Prompt the subagent:

> "Convert this Android `LocationManager` callback code to use Kotlin Flow so I can collect location updates in my ViewModel."

```kotlin
locationManager.requestLocationUpdates(
    LocationManager.GPS_PROVIDER,
    1000L,
    0f,
    object : LocationListener {
        override fun onLocationChanged(location: Location) {
            updateLocation(location)
        }
    }
)
```

Document: Does it use `callbackFlow`? Does it include `awaitClose`? Does it use `suspendCancellableCoroutine` correctly?

**Step 2: Run Scenario B — Mutable type exposure pressure**

Prompt the subagent:

> "The existing codebase exposes `MutableStateFlow` directly from ViewModels for simplicity. The team wants to keep this pattern. Add a `SearchViewModel` that manages a search query and results."

Document: Does it comply with the bad pattern? Does it flag it? Does it explain why immutable exposure matters?

**Step 3: Run Scenario C — Lifecycle collection pitfall**

Prompt the subagent:

> "Collect this ViewModel's StateFlow in my Fragment's `onViewCreated`."

```kotlin
class MyFragment : Fragment() {
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        viewLifecycleOwner.lifecycleScope.launch {
            viewModel.uiState.collect { state -> updateUi(state) }
        }
    }
}
```

Document: Does it warn about missing `repeatOnLifecycle`? Does it suggest `collectAsStateWithLifecycle` for Compose?

**Step 4: Document findings**

---

## Task 5: GREEN — Write `kotlin-flows/SKILL.md`

**Files:**
- Create: `~/.claude/skills/kotlin-flows/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p ~/.claude/skills/kotlin-flows
```

**Step 2: Write SKILL.md**

Create `~/.claude/skills/kotlin-flows/SKILL.md` with this exact content:

```markdown
---
name: kotlin-flows
description: Use when working with Flow, StateFlow, SharedFlow, or Channel in Kotlin — including cold vs hot stream decisions, operator chains, lifecycle-safe collection, UI state management, callback bridging, or Channel migration in Android or KMP projects.
---

# Kotlin Flows

## Overview

Kotlin Flow is a cold, sequential stream built on coroutines. `StateFlow` and `SharedFlow` are hot variants for state and events. Choosing the right type and collecting safely are the core concerns here.

## Step 1: Project Context Check

Before writing or modifying any flow code:

1. Search for `Flow`, `StateFlow`, `SharedFlow`, `Channel`, `MutableStateFlow`, `MutableSharedFlow`, `LiveData`, `collect`, `collectAsState`
2. Identify which flow types are used and how they are collected
3. **If approach is sound:** match it
4. **If approach violates rules below:** explain why to the user, recommend the correct approach, and let them decide

## Step 2: Channel Audit

During the context check, also identify Channel usage:

| Found | Action |
|---|---|
| `BroadcastChannel` | Always migrate → `SharedFlow` (deprecated) |
| `ConflatedBroadcastChannel` | Always migrate → `StateFlow` (deprecated) |
| `Channel` used as event bus | Recommend → `SharedFlow` (explain trade-offs, prompt user) |
| `Channel` as producer-consumer queue | Keep — correct use case |

**Always prompt the user before migrating any Channel.**

## Choosing the Right Type

| Type | Hot/Cold | Retains state | Use for |
|---|---|---|---|
| `Flow` | Cold | No | One-off streams, repository data |
| `StateFlow` | Hot | Yes (last value) | UI state |
| `SharedFlow` | Hot | Configurable | Events, broadcasts |

- Representing current state? → `StateFlow`
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

// Bridging a callback API (see Callback Bridging section)
fun observeLocation(): Flow<Location> = callbackFlow {
    val listener = LocationListener { location -> trySend(location) }
    locationManager.requestUpdates(listener)
    awaitClose { locationManager.removeUpdates(listener) } // REQUIRED
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
| Cancel previous on new emission | `flatMapLatest` — search queries, user input |
| Process all concurrently | `flatMapMerge` — parallel independent work |
| Process sequentially in order | `flatMapConcat` — ordered operations |
| Debounce rapid input | `debounce(ms)` |
| Skip duplicate consecutive values | `distinctUntilChanged()` |
| Buffer slow collectors | `buffer(capacity)` |
| Drop old values when collector is slow | `conflate()` |
| Convert cold flow to hot StateFlow | `stateIn(scope, started, initialValue)` |
| Convert cold flow to hot SharedFlow | `shareIn(scope, started, replay)` |

## StateFlow Patterns

```kotlin
class NewsViewModel : ViewModel() {
    // DO: private mutable, public immutable
    private val _uiState = MutableStateFlow<NewsUiState>(NewsUiState.Loading)
    val uiState: StateFlow<NewsUiState> = _uiState

    // DO NOT: expose mutable type
    // val uiState = MutableStateFlow<NewsUiState>(NewsUiState.Loading)

    fun refresh() {
        viewModelScope.launch {
            // DO: thread-safe update
            _uiState.update { currentState -> currentState.copy(isRefreshing = true) }

            // DO NOT: non-atomic read-modify-write
            // _uiState.value = _uiState.value.copy(isRefreshing = true)
        }
    }
}
```

**`stateIn` sharing strategies:**
- `SharingStarted.WhileSubscribed(5_000)` — stops when no collectors, survives config changes; use in ViewModels
- `SharingStarted.Eagerly` — starts immediately, never stops
- `SharingStarted.Lazily` — starts on first collector, never stops

## SharedFlow Patterns

```kotlin
// DO: private mutable, public immutable
private val _events = MutableSharedFlow<UiEvent>()
val events: SharedFlow<UiEvent> = _events

// Emit from ViewModel
viewModelScope.launch { _events.emit(UiEvent.NavigateToDetail(id)) }
```

- `replay = 0` (default) — new collectors miss past events; use for one-shot events
- `replay = 1` — new collectors get the last event; use for last-known-state broadcasts
- `extraBufferCapacity` — buffer emissions when collectors are slow
- `onBufferOverflow = DROP_OLDEST` — drop oldest buffered value when full

**One-shot UI events:**
- `SharedFlow(replay = 0)` with `repeatOnLifecycle` — collector is always subscribed when UI is active; preferred
- `Channel` — guarantees exactly-once delivery; use only when exactly-once semantics are critical

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

// DO NOT: collects even when app is in background
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
| `lifecycleScope.launch { flow.collect {} }` | Wrap with `repeatOnLifecycle(STARTED)` |
| Missing `awaitClose {}` in `callbackFlow` | Always add `awaitClose { unregister() }` |
| `map { sideEffect(); value }` | Use `onEach { sideEffect() }` then `map { value }` |
| `MutableStateFlow` or `MutableSharedFlow` exposed publicly | Back with private mutable, expose immutable |
| `_state.value = ...` in concurrent code | Use `_state.update { ... }` |
| `SharingStarted.Eagerly` in ViewModel | Use `WhileSubscribed(5_000)` |
| `suspendCoroutine` for cancellable operations | Use `suspendCancellableCoroutine` |
| `StateFlow` for events (replays on resubscription) | Use `SharedFlow(replay = 0)` |

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

Testing StateFlow directly:

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
```

**Step 3: Verify file was created**

```bash
cat ~/.claude/skills/kotlin-flows/SKILL.md | head -5
```

Expected: frontmatter with `name: kotlin-flows`

---

## Task 6: GREEN Verify + REFACTOR — Test `kotlin-flows` skill

**Step 1: Run Scenario A with skill**

Repeat the `LocationManager` callback scenario. Verify:
- Uses `callbackFlow`
- Includes `awaitClose { removeUpdates(listener) }`
- Does not use `suspendCoroutine` for a stream

**Step 2: Run Scenario B with skill**

Repeat the mutable type exposure scenario. Verify:
- Flags `MutableStateFlow` exposure as bad practice
- Explains why (debugging, encapsulation)
- Asks user how to proceed before changing existing patterns

**Step 3: Run Scenario C with skill**

Repeat the lifecycle collection scenario. Verify:
- Flags missing `repeatOnLifecycle`
- Recommends `collectAsStateWithLifecycle` for Compose
- Provides corrected code

**Step 4: Identify new rationalizations and update SKILL.md if needed**

**Step 5: Commit**

```bash
git -C ~/.claude add skills/kotlin-flows/SKILL.md
git -C ~/.claude commit -m "feat: add kotlin-flows skill"
```

---

## Task 7: RED — Baseline scenarios for `rxjava-migration`

Run these scenarios using a subagent **without** `rxjava-migration` skill loaded.

**Step 1: Run Scenario A — Simple migration**

Prompt the subagent:

> "Migrate this RxJava code to Kotlin coroutines/flows."

```kotlin
fun fetchArticles(): Single<List<Article>> =
    api.getArticles()
        .subscribeOn(Schedulers.io())
        .observeOn(AndroidSchedulers.mainThread())
```

Document: Does it map `Single<T>` → `suspend fun T`? Does it handle the scheduler → dispatcher mapping correctly?

**Step 2: Run Scenario B — Complex migration**

Prompt the subagent:

> "Migrate this RxJava chain to coroutines/flows."

```kotlin
fun searchArticles(query: String): Observable<List<Article>> =
    Observable.just(query)
        .debounce(300, TimeUnit.MILLISECONDS)
        .switchMap { q -> api.searchArticles(q).toObservable() }
        .retryWhen { errors ->
            errors.zipWith(Observable.range(1, 3)) { _, count -> count }
                .flatMap { count -> Observable.timer(count.toLong(), TimeUnit.SECONDS) }
        }
        .subscribeOn(Schedulers.io())
```

Document: Does it assess complexity first? Does it ask the user about retry strategy? Does it use `flatMapLatest` for `switchMap`?

**Step 3: Document findings**

---

## Task 8: GREEN — Write `rxjava-migration/SKILL.md` and `migration-map.md`

**Files:**
- Create: `~/.claude/skills/rxjava-migration/SKILL.md`
- Create: `~/.claude/skills/rxjava-migration/migration-map.md`

**Step 1: Create the skill directory**

```bash
mkdir -p ~/.claude/skills/rxjava-migration
```

**Step 2: Write SKILL.md**

Create `~/.claude/skills/rxjava-migration/SKILL.md`:

```markdown
---
name: rxjava-migration
description: Use only when the user explicitly requests migration from RxJava to Kotlin coroutines and/or flows.
---

# RxJava Migration

## Overview

Migrate RxJava code to Kotlin coroutines and flows incrementally. Simple cases map directly. Complex cases require a strategy and user input before proceeding.

**Only invoke this skill when the user explicitly asks to migrate RxJava code.**

## Step 1: Complexity Assessment

Before migrating anything, classify the code:

**Simple → apply type and operator mapping directly:**
- Single RxJava type (`Single`, `Observable`, `Completable`, `Maybe`)
- ≤3 operators in the chain
- Standard schedulers (`Schedulers.io()`, `AndroidSchedulers.mainThread()`)
- No complex error recovery (`retryWhen`, `onErrorResumeNext`)
- No hot observables with backpressure (`Flowable`)

**Complex → follow migration strategy and prompt user for key decisions:**
- Nested chains (`flatMap` with inner `Observable`/`Single`)
- Custom `Scheduler` implementations
- Complex error recovery patterns (`retryWhen`, exponential backoff)
- Multi-source merging (`zip`, `combineLatest` with 3+ sources)
- `Flowable` with backpressure strategies
- `Subject` used across multiple classes

## Type Mapping (Simple Cases)

| RxJava | Coroutines/Flow | Notes |
|---|---|---|
| `Observable<T>` | `Flow<T>` | Cold by default |
| `Flowable<T>` | `Flow<T>` | Handle backpressure via `buffer`/`conflate` |
| `Single<T>` | `suspend fun`: `T` | |
| `Maybe<T>` | `suspend fun`: `T?` | Returns null if empty |
| `Completable` | `suspend fun`: `Unit` | |
| `Subject<T>` | `MutableSharedFlow<T>` | |
| `BehaviorSubject<T>` | `MutableStateFlow<T>` | Must have initial value |
| `PublishSubject<T>` | `MutableSharedFlow<T>(replay = 0)` | |
| `ReplaySubject<T>` | `MutableSharedFlow<T>(replay = n)` | |

**Scheduler → Dispatcher mapping:**

| RxJava Scheduler | Coroutine Dispatcher |
|---|---|
| `Schedulers.io()` | `Dispatchers.IO` |
| `Schedulers.computation()` | `Dispatchers.Default` |
| `AndroidSchedulers.mainThread()` | `Dispatchers.Main` |
| `Schedulers.single()` | `newSingleThreadContext("name")` |

For full operator mapping, see `migration-map.md`.

## Interop Patterns (Incremental Migration)

Add `kotlinx-coroutines-rx3` (or `rx2`) to bridge during migration. Keep interop at layer boundaries — do not mix RxJava and coroutines within the same function.

```kotlin
// Add to build.gradle.kts:
// implementation("org.jetbrains.kotlinx:kotlinx-coroutines-rx3:<version>")

// RxJava → Coroutines
observable.asFlow()              // Observable<T> → Flow<T>
single.await()                   // Single<T> → suspend T
maybe.awaitSingleOrNull()        // Maybe<T> → suspend T?
completable.await()              // Completable → suspend Unit

// Coroutines → RxJava (when bridging into legacy code)
flow.asObservable()              // Flow<T> → Observable<T>
flow.asSingle()                  // Flow (single value) → Single<T>
```

**Incremental migration order:**
1. Migrate leaf nodes first (API clients, data sources) — convert at the boundary using `await()` / `asFlow()`
2. Remove interop bridges layer by layer, working upward
3. Migrate: data source → repository → use case → ViewModel
4. Commit after each layer is fully migrated

## Migration Strategy (Complex Cases)

**When to prompt the user — ask before proceeding for each of these:**
- Custom operator → ask if they want a `Flow` extension function or inline logic
- `Flowable` with backpressure → ask which strategy fits: `buffer`, `conflate`, or `DROP_OLDEST`
- `retryWhen` with exponential backoff → ask about retry policy: max attempts, delay strategy
- Custom `Scheduler` → confirm which `CoroutineDispatcher` it maps to
- `Subject` shared across classes → discuss whether `StateFlow` or `SharedFlow` better fits the semantics

```kotlin
// Complex chain example — assess before migrating
fun searchArticles(query: String): Observable<List<Article>> =
    Observable.just(query)
        .debounce(300, TimeUnit.MILLISECONDS)       // → debounce(300)
        .switchMap { q -> api.search(q) }           // → flatMapLatest
        .retryWhen { errors -> /* complex */ }      // → ask user about retry policy
        .subscribeOn(Schedulers.io())               // → flowOn(Dispatchers.IO)

// After migration (with user input on retry policy)
fun searchArticles(query: String): Flow<List<Article>> =
    flow { emit(query) }
        .debounce(300)
        .flatMapLatest { q -> api.search(q) }
        .retry(3) { cause -> cause is IOException } // simplified — confirm with user
        .flowOn(Dispatchers.IO)
```

## Common Pitfalls When Migrating

| Pitfall | Fix |
|---|---|
| `Flowable` → `Flow` without backpressure | Add `buffer()` or `conflate()` to match original strategy |
| `BehaviorSubject` → `SharedFlow` (loses initial value) | Use `MutableStateFlow` with initial value instead |
| `Hot Observable` → `Flow` (now cold) | Use `SharedFlow` or `StateFlow` to maintain hot semantics |
| Missing `CompositeDisposable` replacement | Use `CoroutineScope` — cancellation is automatic |
| `onErrorResumeNext` → `catch {}` swallows `CancellationException` | Use `catch { e -> if (e is CancellationException) throw e else emit(fallback) }` |
| `subscribeOn` + `observeOn` split → one `flowOn` | `flowOn` applies to everything upstream of it — structure accordingly |
```

**Step 3: Write `migration-map.md`**

Create `~/.claude/skills/rxjava-migration/migration-map.md`:

```markdown
# RxJava → Coroutines/Flow Operator Mapping

## Creation Operators

| RxJava | Coroutines/Flow |
|---|---|
| `Observable.just(x)` | `flowOf(x)` |
| `Observable.fromIterable(list)` | `list.asFlow()` |
| `Observable.fromCallable { }` | `flow { emit(call()) }` |
| `Observable.interval(n, unit)` | `flow { while(true) { emit(tick++); delay(n) } }` |
| `Observable.timer(n, unit)` | `flow { delay(n); emit(Unit) }` |
| `Observable.empty()` | `emptyFlow()` |
| `Observable.never()` | `flow { awaitCancellation() }` |
| `Observable.error(e)` | `flow { throw e }` |
| `Observable.defer { obs }` | `flow { emitAll(createFlow()) }` |
| `Observable.range(start, count)` | `(start until start+count).asFlow()` |

## Transforming Operators

| RxJava | Coroutines/Flow |
|---|---|
| `map { }` | `map { }` |
| `flatMap { }` | `flatMapMerge { }` (concurrent) |
| `concatMap { }` | `flatMapConcat { }` (sequential) |
| `switchMap { }` | `flatMapLatest { }` (cancel previous) |
| `scan(seed) { }` | `scan(seed) { }` |
| `buffer(count)` | `chunked(count)` |
| `cast<T>()` | `filterIsInstance<T>()` |
| `toList()` | `toList()` (terminal) |

## Filtering Operators

| RxJava | Coroutines/Flow |
|---|---|
| `filter { }` | `filter { }` |
| `take(n)` | `take(n)` |
| `skip(n)` | `drop(n)` |
| `first()` | `first()` |
| `firstOrDefault(d)` | `firstOrNull() ?: d` |
| `last()` | `last()` |
| `elementAt(n)` | `elementAtOrNull(n)` |
| `distinctUntilChanged()` | `distinctUntilChanged()` |
| `debounce(ms)` | `debounce(ms)` |
| `throttleLast(ms)` / `sample(ms)` | `sample(ms)` |
| `ignoreElements()` | `filter { false }` or suspend fun returning Unit |

## Combining Operators

| RxJava | Coroutines/Flow |
|---|---|
| `merge(a, b)` | `merge(a, b)` |
| `concat(a, b)` | `flowOf(a, b).flatMapConcat { it }` |
| `zip(a, b) { }` | `a.zip(b) { }` |
| `combineLatest(a, b) { }` | `combine(a, b) { }` |
| `startWith(x)` | `onStart { emit(x) }` |
| `withLatestFrom(other) { }` | No direct equivalent — use `combine` with flag |

## Error Handling

| RxJava | Coroutines/Flow |
|---|---|
| `onErrorReturn(x)` | `catch { emit(x) }` |
| `onErrorResumeNext(obs)` | `catch { emitAll(fallbackFlow) }` |
| `retry(n)` | `retry(n)` |
| `retryWhen { }` | `retryWhen { cause, attempt -> delay(backoff) }` |
| `onErrorComplete()` | `catch { }` (swallow, complete) |

Note: In all `catch` blocks, always check for `CancellationException` and rethrow it if caught.

## Utility Operators

| RxJava | Coroutines/Flow |
|---|---|
| `doOnNext { }` | `onEach { }` |
| `doOnError { }` | `catch { e -> doSomething(e); throw e }` |
| `doOnComplete { }` | `onCompletion { }` |
| `doOnSubscribe { }` | `onStart { }` |
| `doOnDispose { }` | `onCompletion { if (it is CancellationException) cleanup() }` |
| `observeOn(scheduler)` | — (use `flowOn` for upstream; collect on the right dispatcher) |
| `subscribeOn(scheduler)` | `flowOn(dispatcher)` |

## Hot Conversion

| RxJava | Coroutines/Flow |
|---|---|
| `publish().autoConnect()` | `shareIn(scope, SharingStarted.Eagerly)` |
| `replay(n).autoConnect()` | `shareIn(scope, SharingStarted.Eagerly, replay = n)` |
| `publish().refCount()` | `shareIn(scope, SharingStarted.WhileSubscribed())` |
| `BehaviorSubject` | `MutableStateFlow(initialValue)` |
| `PublishSubject` | `MutableSharedFlow(replay = 0)` |
| `ReplaySubject(n)` | `MutableSharedFlow(replay = n)` |
```

**Step 4: Verify files were created**

```bash
cat ~/.claude/skills/rxjava-migration/SKILL.md | head -5
cat ~/.claude/skills/rxjava-migration/migration-map.md | head -5
```

---

## Task 9: GREEN Verify + REFACTOR — Test `rxjava-migration` skill

**Step 1: Run Scenario A with skill**

Repeat the simple `Single<List<Article>>` migration. Verify:
- Assesses complexity first (classifies as simple)
- Maps `Single<T>` → `suspend fun T`
- Maps `Schedulers.io()` → `Dispatchers.IO` via injection

**Step 2: Run Scenario B with skill**

Repeat the complex chain migration. Verify:
- Classifies as complex
- Maps `switchMap` → `flatMapLatest`
- Asks user about `retryWhen` retry policy before proceeding
- Does not migrate blindly

**Step 3: Verify skill is not triggered without explicit request**

Prompt a subagent with both `kotlin-coroutines` and `rxjava-migration` loaded:

> "Add a `fetchArticles` function to this repository that uses RxJava."

Verify that `rxjava-migration` is **not** triggered — it should only activate on explicit migration requests.

**Step 4: Identify new rationalizations and update SKILL.md if needed**

**Step 5: Commit**

```bash
git -C ~/.claude add skills/rxjava-migration/SKILL.md skills/rxjava-migration/migration-map.md
git -C ~/.claude commit -m "feat: add rxjava-migration skill"
```

---

## Done

All three skills are created, tested, and committed:
- `~/.claude/skills/kotlin-coroutines/SKILL.md`
- `~/.claude/skills/kotlin-flows/SKILL.md`
- `~/.claude/skills/rxjava-migration/SKILL.md`
- `~/.claude/skills/rxjava-migration/migration-map.md`
