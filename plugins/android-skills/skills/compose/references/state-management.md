# Jetpack Compose State Management Reference

## Creating State

```kotlin
val name = mutableStateOf("Alice")        // general-purpose (Any type)
val count = mutableIntStateOf(0)          // primitive specialization — avoids boxing
val progress = mutableFloatStateOf(0.5f)
val enabled = mutableStateOf(true)        // Boolean has no specialization
```

**Pitfall:** `mutableStateOf<Int>()` instead of `mutableIntStateOf()` boxes on every read/write. Primitive specializations live in `androidx.compose.runtime` (`State.kt`).

## remember vs rememberSaveable

- **`remember`** — lives for the composition; lost on process death, config change, back nav. UI state: selection, expanded/collapsed, scroll position.
- **`rememberSaveable`** — survives process death and config change via `Bundle`-compatible types; custom types need a `Saver` or `@Parcelize`. User input, navigation state.

```kotlin
var query by rememberSaveable { mutableStateOf("") }   // survives config change

data class User(val id: Int, val name: String)
val userSaver = Saver<User, String>(
    save = { "${it.id}:${it.name}" },
    restore = { User(it.split(":")[0].toInt(), it.split(":")[1]) }
)
var user by rememberSaveable(stateSaver = userSaver) { mutableStateOf(User(1, "Alice")) }
```

**DON'T try to save runtime objects** with `rememberSaveable` — `LazyListState`, `FocusRequester`, `CoroutineScope`, callbacks. Savers serialize data; runtime references don't survive process death. Persist the *data* and recreate the object:

```kotlin
// WRONG — runtime object, no meaningful serialization
val listState = rememberSaveable { LazyListState() }

// RIGHT — save the index, recreate the state
var savedIndex by rememberSaveable { mutableIntStateOf(0) }
val listState = rememberLazyListState(initialFirstVisibleItemIndex = savedIndex)
LaunchedEffect(listState) {
    snapshotFlow { listState.firstVisibleItemIndex }.collect { savedIndex = it }
}
```

### The Unified Keying Rule

`remember`, `LaunchedEffect`, `DisposableEffect`, `produceState`, and the `remember { ... }` block around `derivedStateOf` share one rule: **any changing value the body reads must either appear in the key list, be a constant, be a call-site-owned stable object, or be read through `rememberUpdatedState`**. The three legitimate carve-outs:

1. **Constants** — `MAX_RETRY = 3`, `Color.Red`. Can't change.
2. **Call-site-owned stable objects the call site never replaces** — `rememberCoroutineScope()`, `remember { Animatable(0f) }`. The key would be redundant; the reference is already stable for the composition.
3. **Initial-only capture is the goal** — `val firstSeenAt = remember { Clock.System.now() }`. Mark with a `// initial-only` comment so the missing key doesn't read as a bug.

For values that should keep an effect *running* across changes but invoke the *latest* callback (e.g. `onComplete`), wrap with `rememberUpdatedState(value)` and read inside the effect — it tracks the latest value without restarting.

## State Hoisting

Stateless content + a stateful wrapper makes UI reusable and testable:

```kotlin
// Stateless — reusable, testable
@Composable
fun Counter(count: Int, onCountChange: (Int) -> Unit) {
    Button(onClick = { onCountChange(count + 1) }) { Text(count.toString()) }
}

// Stateful wrapper — provides the state
@Composable
fun StatefulCounter() {
    var count by remember { mutableIntStateOf(0) }
    Counter(count = count, onCountChange = { count = it })
}
```

**Push state as high as needed, but no higher.** See `compose/references/view-composition.md` for the composable-shape side (stateful wrapper vs stateless content).

### Where State Belongs

Four tiers, lowest to highest — each tier costs scope, ceremony, and lifecycle assumptions, so hoist only as far as the logic needs:

| Tier | Location | Use when |
|---|---|---|
| 1 | Local `remember` | State read/written only inside this composable |
| 2 | Lowest common composable ancestor | Multiple siblings need it; no business logic depends on it |
| 3 | Plain state holder class (composition-scoped) | Operations cluster (`clear`/`submit`/`jumpToTop`); derived flags scatter; children receive mechanics they don't own; scope-bound objects cluster |
| 4 | Screen-level state holder / ViewModel | State drives or is driven by business logic — repository, navigation, validation |

**Counter-trigger:** don't extract a state holder for one boolean. Ceremony is not separation of concerns.

**If a UI value is an input to business logic, it belongs in the screen state holder (tier 4) — not local.** The boundary isn't "is this UI?" — it's "does my repository or navigation graph depend on this value?" A search query that feeds repository queries is the canonical case:

```kotlin
// WRONG — query is UI-local, but every keystroke hits the repository: can't debounce, restore, or test
@Composable
fun SearchScreen(viewModel: SearchViewModel) {
    var query by remember { mutableStateOf("") }
    LaunchedEffect(query) { viewModel.search(query) }
}

// RIGHT — query lives in the VM, which owns debouncing and the repository call
class SearchViewModel : ViewModel() {
    private val _query = MutableStateFlow("")
    val results = _query
        .debounce(300)
        .flatMapLatest { repository.search(it) }  // assumes search(): Flow<List<Result>>; use mapLatest if it's a suspend fun returning the list directly
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    fun onQueryChange(new: String) { _query.value = new }
}
```

The "State Holder Class Pattern" below is the tier-3 shape; "State in ViewModels" is tier-4.

## derivedStateOf

Computes a value from existing state, recomputing only when dependencies change. Use for expensive derivations (filtering/sorting) or combining state values — not for cheap operations (string concat, simple conditions), where it adds overhead.

```kotlin
val filteredUsers = remember(users, filterText) {
    derivedStateOf { users.filter { it.name.contains(filterText, ignoreCase = true) } }
}
```

**Pitfalls:**
- Accessing `.value` in a lambda passed to a child doesn't create a dependency — use `snapshotFlow` for callbacks.
- The block must read at least one Compose `State<T>` to invalidate. `derivedStateOf { a + b }` where neither is a `State` never re-evaluates — you've paid the overhead for nothing. For a single-shot computation, use `remember { a + b }`.

### `derivedStateOf` and the Surrounding `remember`

`derivedStateOf` tracks **`State<T>` reads inside its lambda**. It does **not** track plain values captured by the lambda — those are captured **once** when the surrounding `remember { ... }` runs, and if they change later without being in the `remember` key list, the derived state silently uses the original value forever.

```kotlin
// WRONG — threshold captured once at first composition; later changes go unnoticed
val isPastThreshold by remember {
    derivedStateOf { listState.firstVisibleItemIndex > threshold }
}

// RIGHT — key the surrounding remember on the captured value
val isPastThreshold by remember(threshold) {
    derivedStateOf { listState.firstVisibleItemIndex > threshold }
}
```

If the lambda captures a `State<T>` indirectly (calls `someState.value` then passes the unwrapped value), the same trap applies — capture the `State` itself, not the snapshot.

## snapshotFlow

Converts Compose state to a Kotlin Flow for side effects and external APIs. Emits the initial value, then only on changes; runs in the composition's coroutine scope (launched via `LaunchedEffect`).

```kotlin
LaunchedEffect(Unit) {
    snapshotFlow { query }.debounce(500).distinctUntilChanged().collect { viewModel.search(it) }
}
```

**Pitfall:** reading state directly in a `LaunchedEffect(Unit)` captures it at launch time and won't re-run on change — either key the effect on the value (`LaunchedEffect(query)`) or read it through `snapshotFlow`.

## SnapshotStateList and SnapshotStateMap

Observable collections that trigger recomposition on **structural** changes — but not on mutation of an element held inside:

```kotlin
val items = remember { mutableStateListOf(Item(1, "First")) }

items[0] = Item(1, "Updated")        // ✅ recomposes (list structure changed)
items[0].name = "Updated"            // ❌ does NOT recompose (object mutated in place)
items[0] = items[0].copy(name = "Updated")  // ✅ correct — replace the reference
```

Source: `androidx.compose.runtime.snapshots`.

## Cross-Phase Back-Writing

**Back-writing** = writing observable state in a phase that invalidates an *earlier* phase. The compiler doesn't flag it and the recomposition counter shows no single hot spot — the symptom is jittery scroll, ghost layouts, or recomposition looping between two states. Three flavors, by frequency:

### 1. Composition → composition (`mutableStateMapOf.clear()/putAll()` in a body)

Rebuilding a `mutableStateMapOf`/`mutableStateListOf` inside a composable body writes observable state *during composition*, invalidating the same scope that's running:

```kotlin
// WRONG — composition rebuilds the map, which invalidates composition, which rebuilds the map…
@Composable
fun SectionedList(items: List<Item>) {
    val grouped = remember { mutableStateMapOf<String, List<Item>>() }
    grouped.clear(); grouped.putAll(items.groupBy { it.category })  // writes inside composition
    LazyColumn { grouped.forEach { (key, list) -> /* … */ } }
}

// RIGHT — derive, don't rebuild
@Composable
fun SectionedList(items: List<Item>) {
    val grouped = remember(items) { items.groupBy { it.category } }
    LazyColumn { grouped.forEach { (key, list) -> /* … */ } }
}
```

`mutableStateMapOf`/`mutableStateListOf` are for state that **mutates in response to events**, not for caches — for those, plain `remember(key) { computeMap() }`.

### 2. Layout → composition (`onSizeChanged` writing observable state read in composition)

`onSizeChanged` fires *after layout*. Writing `MutableState` from it (or any layout-phase callback) invalidates composition with the new size, which lays out again, which fires the callback again:

```kotlin
// WRONG — onSizeChanged writes state read in composition → feedback loop
var widthPx by remember { mutableIntStateOf(0) }
Box(Modifier.fillMaxWidth().onSizeChanged { widthPx = it.width }) {
    Text(title, Modifier.padding(start = (widthPx / 4).dp))  // composition read of widthPx
}

// RIGHT — defer the read to the layout phase
Box(Modifier.fillMaxWidth().onSizeChanged { widthPx = it.width }) {
    Text(title, Modifier.layout { measurable, constraints ->
        val placeable = measurable.measure(constraints)
        layout(placeable.width, placeable.height) { placeable.place(widthPx / 4, 0) }
    })
}
```

If two siblings must know each other's measured size, use `Modifier.decorateMeasureConstraints` (Foundation 1.10+) instead of round-tripping through composition:

```kotlin
Modifier.decorateMeasureConstraints { measurable, constraints ->
    measurable.measure(constraints.copy(minHeight = anchorHeight))
}
```

### 3. Draw → composition

Vanishingly rare — `Canvas`/`DrawScope` blocks that update a `MutableState`. Same fix: cache the computed value in layout, not draw.

**General rule:** state writes go forward through phases (composition → layout → draw), never backward. When a backward write is the right shape (a sticky header that needs its measured height), the cure is a layout-phase API (`Modifier.layout`, `Modifier.decorateMeasureConstraints`), not a `MutableState` that bridges back into composition.

## Read-Only Composables

Mark composable functions/properties `@ReadOnlyComposable` when they're pure readers — no `Box`/`Text` emit, no `remember`, no effects. Reading them takes a faster runtime path; mis-marking corrupts composition.

**Bidirectional contract — both directions must hold:**
- Add it only when every call inside is itself read-only (`@Composable` getter, `MaterialTheme.colorScheme`, `LocalDensity.current`, property access).
- Remove it the moment you call `Box`, `Text`, `remember`, or any effect — including inside content lambdas.

```kotlin
val MaterialTheme.spacing: Spacing
    @Composable @ReadOnlyComposable get() = LocalSpacing.current
```

WHY: the fast path skips the bookkeeping needed to host child composables or restartable groups. If a `@ReadOnlyComposable` ever emits UI or calls `remember`, the runtime silently corrupts the slot table — the symptom is usually crashes deeper in the tree, not at the call site. It's an opt-in performance contract, not documentation. See `compose/references/side-effects.md` for the side-effect-bearing counterpart.

## Stability Annotations

`@Immutable` / `@Stable` and strong-skipping mechanics are covered canonically in `compose/references/performance.md` (`@Immutable` vs `@Stable` boundary, the five stability classifications, `stabilityConfigurationFiles`, strong skipping). The state-management-relevant rule: under strong skipping (default on Kotlin 2.0.20+), same-module classes with all-stable properties are inferred stable automatically — don't annotate speculatively. Reach for `@Immutable` / `@Stable` only when inference can't see the type (cross-module boundaries, generic wrappers) or when you want to document an intentional stability contract.

## State in ViewModels: StateFlow vs Compose State

- **`StateFlow`** (recommended for ViewModels) — survives recomposition and config change, framework-agnostic, testable, collected with `collectAsStateWithLifecycle()`.
- **Compose `State`** — temporary, UI-local state only; don't hoist to the ViewModel; lost on back navigation.

```kotlin
class UserViewModel : ViewModel() {
    private val _uiState = MutableStateFlow<UiState>(UiState.Loading)
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
}

@Composable
fun UserScreen(viewModel: UserViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showFilters by remember { mutableStateOf(false) }  // UI-only — stays local
    // ...
}
```

`collectAsStateWithLifecycle()` (in `androidx.lifecycle:lifecycle-runtime-compose`) collects only when the composable is STARTED, avoiding leaks.

## Common Anti-Patterns

### Bare `var` resets — and the rule is positional, not lexical

```kotlin
// WRONG — content lambdas inside layouts are themselves @Composable; var resets every recomposition
Row {
    var count = 0
    Button(onClick = { count++ }) { Text("Count: $count") }
}

// RIGHT — remember inside the content lambda
Row {
    var count by remember { mutableIntStateOf(0) }
    Button(onClick = { count++ }) { Text("Count: $count") }
}
```

Every `Row { }`, `Column { }`, `Box { }`, `LazyColumn { items { } }` body is its own `@Composable` block — anything declared there without `remember` runs on every recomposition. **If the code is `@Composable`, plain `var` resets.**

### Mutating a List Held by `mutableStateOf`

```kotlin
// WRONG — mutating a MutableList held by mutableStateOf bypasses the State setter; no recomposition
val items = remember { mutableStateOf(mutableListOf<Item>()) }
items.value.add(Item(...))

// RIGHT — mutableStateListOf for observable list state
val items = remember { mutableStateListOf<Item>() }
items.add(Item(...))

// OR — replace the reference for mutableStateOf<List<T>>
val items = remember { mutableStateOf<List<Item>>(emptyList()) }
items.value = items.value + Item(...)
```

`mutableStateOf` observes assignments to `.value`, not mutations of the object behind it.

### Animation Suspend From `viewModelScope`

```kotlin
// WRONG — animation suspend launched from viewModelScope
viewModelScope.launch { listState.animateScrollToItem(0) }

// RIGHT — animation runs in a composition-scoped coroutine; VM emits an intent
@Composable
fun FeedScreen(viewModel: FeedViewModel = hiltViewModel()) {
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    LaunchedEffect(viewModel.events) {
        viewModel.events.collect { if (it is ScrollToTop) scope.launch { listState.animateScrollToItem(0) } }
    }
}
```

WHY: animation suspend functions (`animateScrollToItem`, `Animatable.animateTo`) require a composition-scoped coroutine. `viewModelScope` outlives the composition — the animation keeps running against a `LazyListState` whose UI no longer exists, producing stale state writes, leaked `MonotonicFrameClock` subscriptions, and broken animations after a config change. The ViewModel emits *intents*; the composition decides *how* to render them. See `android-skills:kotlin-coroutines`.

## produceState, rememberUpdatedState, Sealed UiState

```kotlin
// produceState — bridge a suspend function / flow to State; coroutine scoped to composition
@Composable
fun userProfile(userId: String): State<User?> =
    produceState<User?>(initialValue = null, userId) { value = repository.getUser(userId) }

// rememberUpdatedState — call the latest callback in a long-running effect without restarting it
@Composable
fun Timer(onTimeout: () -> Unit) {
    val current by rememberUpdatedState(onTimeout)
    LaunchedEffect(Unit) { delay(5000L); current() }  // always the latest onTimeout
}
```

Sealed `UiState` — `val`-capture in `when` for safe smart-casts:

```kotlin
when (val state = uiState) {
    is UiState.Loading -> LoadingIndicator()
    is UiState.Success -> Content(state.data)   // safe smart cast via val
    is UiState.Error -> ErrorMessage(state.message)
}
```

## State Holder Class Pattern (tier 3)

For complex screens with interrelated state, group it into a `@Stable` holder (the pattern behind `rememberScrollState`, `rememberDrawerState`):

```kotlin
@Composable
fun rememberSearchState(
    listState: LazyListState = rememberLazyListState(),
    scope: CoroutineScope = rememberCoroutineScope(),
): SearchState = remember(listState, scope) { SearchState(listState, scope) }

@Stable
class SearchState(val listState: LazyListState, private val scope: CoroutineScope) {
    var query by mutableStateOf(""); private set
    val isScrolled: Boolean get() = listState.firstVisibleItemIndex > 0
    fun updateQuery(new: String) { query = new }
    fun scrollToTop() { scope.launch { listState.animateScrollToItem(0) } }
}
```

## Production State Rules

1. **`mutableStateOf` only in composables/state holders, never in ViewModels** — Compose state in a ViewModel couples it to the Compose runtime. Use `StateFlow` (framework-agnostic, testable).

2. **Durable state + acknowledgement over ephemeral events when the user can see the outcome.** Before reaching for `Channel`/`SharedFlow`, ask: *would losing this signal desynchronize what the user thinks the app did from the underlying state?* If yes, model it as a field on `UiState` the UI clears after consumption — not a one-shot event that drops on a config change or backgrounding.

```kotlin
// WRONG — outcome the user must see; lost on process death (even a buffered
// Channel's queue dies with the process), and SharedFlow(replay = 0) drops if
// no collector is active. A UiState field backed by SavedStateHandle survives both.
_events.send(CheckoutEvent.PaymentResult(result))

// RIGHT — durable state in UiState; acknowledgement clears it
data class CheckoutUiState(val isPaying: Boolean = false, val pendingResult: PaymentResult? = null)
fun pay() = viewModelScope.launch {
    _state.update { it.copy(isPaying = true) }
    val result = paymentApi.charge()
    _state.update { it.copy(isPaying = false, pendingResult = result) }
}
fun resultAcknowledged() { _state.update { it.copy(pendingResult = null) } }
```

Reserve ephemeral channels for genuinely fire-and-forget UI commands where dropping is acceptable (a transient snackbar, a haptic tick, scroll-to-top after refresh).

3. **Channel vs SharedFlow for one-shot events** — `Channel` guarantees exactly-once delivery (suspends/buffers until consumed); `SharedFlow(replay = 0)` silently drops when no collector exists. Collect events with `collect` in a `LaunchedEffect`, never `collectAsStateWithLifecycle` (which preserves the last emission as state, re-consuming on recomposition). Full trade-off in `android-skills:kotlin-flows`.

4. **`rememberSaveable` at the NavGraph level** — screen-level state (query, tab) at the entry point, not deep in the tree.

5. **`snapshotFlow { … }.distinctUntilChanged()` for reactive scroll**; **`.map { … }.stateIn(viewModelScope, WhileSubscribed(5000), …)` for derived flows.**

6. **Don't build Flow pipelines inside `@Composable` bodies.** `stateIn`, `shareIn`, `combine`, `flatMapLatest` belong in a ViewModel scope — a pipeline built in composition is rebuilt every recomposition, lives in the wrong layer, and tears down on disposal without surviving a config change.

```kotlin
// WRONG — pipeline rebuilt every recomposition, composition-scoped
val profile by remember {
    combine(repo.userStream(userId), repo.preferencesStream()) { u, p -> u to p }
        .stateIn(rememberCoroutineScope(), SharingStarted.Lazily, null)
}

// RIGHT — pipeline in the ViewModel; UI collects the StateFlow
class ProfileViewModel(repo: ProfileRepository, userId: String) : ViewModel() {
    val state = combine(repo.userStream(userId), repo.preferencesStream()) { u, p -> u to p }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
}
```

When you see `stateIn(rememberCoroutineScope(), …)` inside a composable, the fix is "move it to the presenter and pass the result through."

## Compose Multiplatform Notes

`rememberSaveable`, `Bundle`, and `@Parcelize` are **Android-only**. On CMP, use `@Serializable` with kotlinx.serialization-based custom `Saver`s:

```kotlin
@Parcelize data class SearchParams(...) : Parcelable   // Android
@Serializable data class SearchParams(...)             // CMP
```

`collectAsStateWithLifecycle()` is Android-specific (`androidx.lifecycle:lifecycle-runtime-compose`). On CMP `commonMain`, `collectAsState()` collects basically (does NOT stop in background) unless `lifecycle-runtime-compose:2.10.0+` makes the lifecycle-aware variant available in `commonMain` — otherwise flows keep collecting when backgrounded (battery/perf cost).

---

**Source references:** `androidx.compose.runtime.State`, `androidx.compose.runtime.saveable`, `androidx.compose.runtime.snapshots`, `androidx.lifecycle.runtime.compose`.
