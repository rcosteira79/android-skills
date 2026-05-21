# Jetpack Compose State Management Reference

## State Fundamentals

State in Compose is observable data that triggers recomposition when changed.

### Creating State

Use type-specific state holders for efficiency:

```kotlin
// General-purpose state (Any type)
val name = mutableStateOf("Alice")

// Primitive specializations (avoid boxing)
val count = mutableIntStateOf(0)
val progress = mutableFloatStateOf(0.5f)
val enabled = mutableStateOf(true)  // Boolean has no specialization
```

**Pitfall:** Using `mutableStateOf<Int>()` instead of `mutableIntStateOf()` causes unnecessary boxing on every read/write. Primitive specializations are located in `androidx.compose.runtime` (source: `State.kt`).

## remember vs rememberSaveable

Both associate state with a composition key, but differ in persistence scope.

### remember
- Lives for the composition's lifetime
- Lost on process death, configuration changes, back navigation
- Best for UI state: selection, expanded/collapsed, scroll position

```kotlin
@Composable
fun Counter() {
    var count by remember { mutableIntStateOf(0) }
    Button(onClick = { count++ }) {
        Text("Count: $count")
    }
}
```

### rememberSaveable
- Survives process death and configuration changes
- Uses `Bundle`-compatible types by default (String, Int, Boolean, etc.)
- For custom types, provide a `Saver` or use `@Parcelize`
- Best for data that represents user input or navigation state

```kotlin
@Composable
fun SearchScreen() {
    var query by rememberSaveable { mutableStateOf("") }
    // survives configuration change
}

// Custom type requires explicit Saver
data class User(val id: Int, val name: String)
val userSaver = Saver<User, String>(
    save = { "${it.id}:${it.name}" },
    restore = { parts -> User(parts.split(":")[0].toInt(), parts.split(":")[1]) }
)
var user by rememberSaveable(stateSaver = userSaver) { mutableStateOf(User(1, "Alice")) }
```

**Pitfall:** Assuming `rememberSaveable` works with all types. Custom classes need explicit `Saver` or `@Parcelize`. See `SaveableStateRegistry` in `androidx.compose.runtime.saveable`.

**DON'T try to save runtime objects with `rememberSaveable`** — `LazyListState`, `FocusRequester`, `CoroutineScope`, callbacks, lambdas. Savers serialize data; runtime references don't survive process death and shouldn't try. If you need scroll position after process death, persist the *index* (an `Int`) and re-create the `LazyListState` from it, or hoist that piece of data to a ViewModel / `SavedStateHandle`.

```kotlin
// WRONG — runtime object, no meaningful serialization
val listState = rememberSaveable { LazyListState() }
val focusRequester = rememberSaveable { FocusRequester() }

// RIGHT — save the data, recreate the runtime object
var savedIndex by rememberSaveable { mutableIntStateOf(0) }
val listState = rememberLazyListState(initialFirstVisibleItemIndex = savedIndex)
LaunchedEffect(listState) {
    snapshotFlow { listState.firstVisibleItemIndex }
        .collect { savedIndex = it }
}
```

### The Unified Keying Rule

`remember`, `LaunchedEffect`, `DisposableEffect`, `produceState`, and the surrounding `remember { ... }` block around `derivedStateOf` all share one rule: **any changing value the body reads must either appear in the key list, be a constant, be a call-site-owned stable object, or be read through `rememberUpdatedState`**.

The three legitimate carve-outs:

1. **Constants** — `MAX_RETRY = 3`, `Color.Red`, a string literal. Compile-time constant, can't change.
2. **Call-site-owned stable objects that the call site never replaces** — `val scope = rememberCoroutineScope()`, `val animatable = remember { Animatable(0f) }`, a state holder created with `remember { ... }` higher up. The key argument would be redundant because the reference is already stable for the composition's lifetime.
3. **Initial-only capture is the goal** — `val firstSeenAt = remember { Clock.System.now() }`. Capturing the value at first composition is exactly what the author wants. Mark these with a `// initial-only` comment so future readers don't read the missing key as a bug.

```kotlin
@Composable
fun SessionTimer() {
    val firstSeenAt = remember { Clock.System.now() }  // initial-only — intentional
    val elapsed = remember(firstSeenAt) {
        Clock.System.now() - firstSeenAt  // keyed correctly so this recomputes when firstSeenAt does
    }
    // ...
}
```

For values that should keep an effect *running* across changes but invoke the *latest* version of a callback (typically `onComplete`-style continuations), wrap with `rememberUpdatedState(value)` and read inside the effect — it intentionally tracks the latest value without restarting the effect on changes.

## State Hoisting

Move state up to a parent composable to enable reusability and testing.

### Stateful vs Stateless Pattern

```kotlin
// ❌ Stateful version (tightly coupled)
@Composable
fun Counter() {
    var count by remember { mutableIntStateOf(0) }
    Button(onClick = { count++ }) { Text(count.toString()) }
}

// ✅ Stateless version (reusable, testable)
@Composable
fun Counter(
    count: Int,
    onCountChange: (Int) -> Unit
) {
    Button(onClick = { onCountChange(count + 1) }) { Text(count.toString()) }
}

// ✅ Wrapper composable (provides state, uses stateless child)
@Composable
fun StatefulCounter() {
    var count by remember { mutableIntStateOf(0) }
    Counter(count = count, onCountChange = { count = it })
}
```

**Rule:** Push state as high as needed, but no higher. If only one child needs state, keep it there. If multiple children or parents need it, hoist up.

### Where State Belongs

**Hoist only as far as the logic needs.** Four tiers from lowest to highest:

| Tier | Location | Use when |
|---|---|---|
| 1 | Local `remember` in the composable | State read/written only inside this composable |
| 2 | Hoisted to lowest common composable ancestor | Multiple siblings need it; no business logic depends on it |
| 3 | Plain state holder class (composition-scoped) | Operations cluster (clear/submit/jumpToTop); derived flags scatter; children receive mechanics they don't own |
| 4 | Screen-level state holder / ViewModel | State drives or is driven by business logic — repository, navigation, validation |

**Triggers for extracting a plain state holder (tier 3, >=2 of these):**
- Named operations cluster (`clear()`, `submit()`, `jumpToTop()`)
- Derived flags scattered across composables
- Children receive mechanics they don't own
- Scope-bound objects (`LazyListState`, `FocusRequester`, `CoroutineScope`) cluster together

**Counter-trigger:** don't extract for one boolean. Ceremony is not separation of concerns.

WHY: each tier costs something — scope, ceremony, lifecycle assumptions. Hoisting too high couples local UI to business logic and pollutes the ViewModel; hoisting too low blocks reuse and forces duplicate logic in siblings. The "State Holder Class Pattern" below shows the tier-3 shape; the "State in ViewModels" section shows the tier-4 shape.

**If UI element state is an input to business logic, it may need to live in the screen state holder (tier 4) — not local.** Example: a search query that feeds repository queries belongs in the ViewModel, not in a local `remember { mutableStateOf("") }`. Even if it 'feels like UI state,' the moment it drives a network/database call, hoist it. The boundary isn't "is this UI?" — it's "does my repository or navigation graph depend on this value?"

```kotlin
// WRONG — search query is UI-local, but every keystroke needs to hit the repository
@Composable
fun SearchScreen(viewModel: SearchViewModel) {
    var query by remember { mutableStateOf("") }  // hidden from VM; can't debounce, can't restore, can't test
    LaunchedEffect(query) { viewModel.search(query) }
}

// RIGHT — query lives in the VM, which owns debouncing and the repository call
class SearchViewModel : ViewModel() {
    private val _query = MutableStateFlow("")
    val query = _query.asStateFlow()
    val results = _query
        .debounce(300)
        .flatMapLatest { repository.search(it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun onQueryChange(new: String) { _query.value = new }
}
```

See `compose/references/view-composition.md` for the composable-shape side of this split (stateful wrapper vs stateless content).

## derivedStateOf

Computes a value from existing state, recomputing only when dependencies change.

```kotlin
// ❌ Wrong: recomputes on every recomposition
val isEven = count % 2 == 0

// ✅ Correct: recomputes only when count changes
val isEven = derivedStateOf { count % 2 == 0 }
```

**When to use:**
- Expensive computations from state (e.g., filtering, sorting lists)
- Combining multiple state values
- Creating intermediate state for conditional logic

```kotlin
@Composable
fun UserList(users: List<User>, filterText: String) {
    val filteredUsers = derivedStateOf {
        users.filter { it.name.contains(filterText, ignoreCase = true) }
    }

    LazyColumn {
        items(filteredUsers.value.size) { index ->
            UserRow(filteredUsers.value[index])
        }
    }
}
```

**Pitfall:** Using `derivedStateOf` for cheap operations (String concatenation, simple conditions) adds overhead. Only use when the computation is non-trivial.

**Pitfall:** Accessing `.value` in a lambda passed to a child composable doesn't create a dependency. Use `snapshotFlow` for callbacks.

**Pitfall:** The block must read at least one Compose `State<T>` to invalidate. `derivedStateOf { a + b }` where neither `a` nor `b` is a `State` will never re-evaluate after the first run, and you've paid the overhead for nothing — the wrapper does no work that a plain `val` wouldn't do. If you intentionally want a single-shot computation, use `remember { a + b }` instead.

### `derivedStateOf` and the Surrounding `remember`

`derivedStateOf` tracks **`State<T>` reads inside its lambda**. It does **not** track plain values captured by the lambda. Those plain values are captured **once** when the surrounding `remember { ... }` runs — and if they change later without being in the `remember` key list, the derived state silently uses the original value forever.

```kotlin
// WRONG — threshold captured once; threshold changes later go unnoticed
@Composable
fun ScrollFlag(listState: LazyListState, threshold: Int) {
    val isPastThreshold by remember {
        derivedStateOf { listState.firstVisibleItemIndex > threshold }  // threshold captured at first composition
    }
    // ... isPastThreshold uses the original threshold even if the parameter changes
}

// RIGHT — key the surrounding remember on the captured value
@Composable
fun ScrollFlag(listState: LazyListState, threshold: Int) {
    val isPastThreshold by remember(threshold) {
        derivedStateOf { listState.firstVisibleItemIndex > threshold }
    }
}
```

If the surrounding lambda also captures a `State<T>` indirectly (e.g., calling `someState.value` then passing the unwrapped value), the same trap applies — capture the `State` itself, not the unwrapped snapshot, so changes propagate.

## snapshotFlow

Converts Compose state to Kotlin Flow for side effects and external APIs.

```kotlin
@Composable
fun SearchScreen(viewModel: SearchViewModel) {
    var query by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        snapshotFlow { query }
            .debounce(500)
            .distinctUntilChanged()
            .collect { viewModel.search(it) }
    }
}
```

**Key behaviors:**
- Emits initial value, then only on changes
- Works with derivedStateOf, collections, and nested state
- Runs in the composition's coroutine scope (launched via `LaunchedEffect`)

**Pitfall:** Accessing state directly in a `LaunchedEffect` doesn't track changes:
```kotlin
// ❌ Won't re-run when query changes
LaunchedEffect(Unit) {
    viewModel.search(query)  // Capture at launch time only
}

// ✅ Re-runs when query changes
LaunchedEffect(query) {
    viewModel.search(query)
}
```

## SnapshotStateList and SnapshotStateMap

Observable collections that trigger recomposition on structural changes.

```kotlin
val items = remember { mutableStateListOf<Item>() }
items.add(Item(1, "First"))
items[0] = Item(1, "Updated")
items.removeAt(0)

val map = remember { mutableStateMapOf<String, String>() }
map["key"] = "value"  // Triggers recomposition
```

**Important:** Changes to list contents trigger recomposition, but changes to list *elements* (if they're mutable objects) do not.

```kotlin
data class Item(val id: Int, var name: String)

val items = remember { mutableStateListOf(Item(1, "First")) }

// ✅ Triggers recomposition (list structure changed)
items[0] = Item(1, "Updated")

// ❌ Does NOT trigger recomposition (object mutated in-place)
items[0].name = "Updated"  // Mutated but list reference unchanged

// ✅ Correct: use copy() or mutableStateOf for nested state
items[0] = items[0].copy(name = "Updated")
```

See source: `androidx.compose.runtime.snapshots` for collection implementation.

## Cross-Phase Back-Writing

**Back-writing** = writing observable state in a phase that invalidates an *earlier* phase. The compiler doesn't flag it, the recomposition counter doesn't show a single hot spot — the symptom is jittery scroll, ghost layouts, or recomposition that loops between two states.

Three flavors, ordered by frequency:

### 1. Composition → composition (`mutableStateMapOf.clear()/putAll()` in a body)

Rebuilding a `mutableStateMapOf` or `mutableStateListOf` inside a composable body writes observable state *during composition*. That write invalidates the same scope that's running, queuing another composition pass that does the same thing on the next frame.

```kotlin
// WRONG — composition rebuilds the map, which invalidates composition, which rebuilds the map…
@Composable
fun SectionedList(items: List<Item>) {
    val grouped = remember { mutableStateMapOf<String, List<Item>>() }
    grouped.clear()                         // write inside composition
    grouped.putAll(items.groupBy { it.category })  // another write inside composition
    LazyColumn { grouped.forEach { (key, list) -> /* … */ } }
}

// RIGHT — derive, don't rebuild
@Composable
fun SectionedList(items: List<Item>) {
    val grouped = remember(items) { items.groupBy { it.category } }
    LazyColumn { grouped.forEach { (key, list) -> /* … */ } }
}
```

`mutableStateMapOf` and `mutableStateListOf` are for state that **mutates in response to events**, not for caches you happen to want recomposition observability on. For the latter, plain `remember(key) { computeMap() }` is the right tool.

### 2. Layout → composition (`onSizeChanged` writing observable state read in composition)

The `onSizeChanged` callback fires *after layout*. Writing `MutableState` from inside it (or any other layout-phase callback) invalidates composition with the new size, which lays out again, which fires the callback again. The loop only stops if the value happens to stabilize.

```kotlin
// WRONG — onSizeChanged writes observable state read in composition; layout invalidates composition
@Composable
fun MeasuredHeader(title: String) {
    var widthPx by remember { mutableIntStateOf(0) }
    Box(modifier = Modifier
        .fillMaxWidth()
        .onSizeChanged { widthPx = it.width }  // layout-phase write
    ) {
        // composition read of widthPx — feedback loop
        Text(title, modifier = Modifier.padding(start = (widthPx / 4).dp))
    }
}

// RIGHT — defer the read to layout/draw via a provider lambda
@Composable
fun MeasuredHeader(title: String) {
    var widthPx by remember { mutableIntStateOf(0) }
    Box(modifier = Modifier
        .fillMaxWidth()
        .onSizeChanged { widthPx = it.width }
    ) {
        Text(
            title,
            modifier = Modifier.layout { measurable, constraints ->
                // read widthPx in the layout phase, not composition
                val placeable = measurable.measure(constraints)
                val start = widthPx / 4
                layout(placeable.width, placeable.height) {
                    placeable.place(start, 0)
                }
            },
        )
    }
}
```

If two siblings need to know each other's measured size (a row where one item should match another's height, for example), reach for `Modifier.decorateMeasureConstraints` (Foundation 1.10+) instead of round-tripping through composition:

```kotlin
// RIGHT — measure-phase decoration, no composition cascade
Modifier.decorateMeasureConstraints { measurable, constraints ->
    measurable.measure(constraints.copy(minHeight = anchorHeight))
}
```

### 3. Draw → composition

Vanishingly rare in app code — the draw phase doesn't usually write Compose state — but `Canvas` and custom `DrawScope` blocks that update a `MutableState` produce the same loop. The fix is the same: cache the computed value in layout, not draw.

The general rule: **state writes go forward through phases (composition → layout → draw), never backward**. When a backward write is the right shape (a sticky-header that needs to know its measured height, for example), the cure is a layout-phase API (`Modifier.layout`, `Modifier.decorateMeasureConstraints`), not a `MutableState` that bridges back into composition.

## Read-Only Composables

Mark composable functions and properties as `@ReadOnlyComposable` when they're pure readers — no `Box`/`Text` emit, no `remember`, no effects, no recompose-triggering writes. Reading them takes a faster runtime path; mis-marking breaks composition.

**Bidirectional contract — both directions must hold:**
- Add `@ReadOnlyComposable` only when every call inside is itself read-only (`@Composable` getter, `MaterialTheme.colorScheme`, `LocalDensity.current`, simple property access).
- Remove it the moment you call `Box`, `Text`, `remember`, or any effect — including inside content lambdas.

**Common case — design token accessors:**
```kotlin
val MaterialTheme.spacing: Spacing
    @Composable
    @ReadOnlyComposable
    get() = LocalSpacing.current
```

**When it doesn't apply:**
- Inside `remember { ... }` producer blocks
- Inside non-composable lambdas (`onClick = { ... }`)
- In plain helper functions (not `@Composable`)

WHY: the read-only fast path skips the bookkeeping needed to host child composables or restartable groups. If a `@ReadOnlyComposable` function ever emits UI or calls `remember`, the runtime silently corrupts the composition slot table — the symptom is usually crashes deeper in the tree, not at the call site. The annotation is an opt-in performance contract, not documentation.

See `compose/references/side-effects.md` for the side-effect-bearing counterpart (`LaunchedEffect`, `DisposableEffect`, etc., which are explicitly *not* read-only).

## @Stable and @Immutable Annotations

These annotations help the compiler optimize recomposition (strong skipping mode).

### @Immutable
- All public fields are read-only primitives or other `@Immutable` types
- Instances never change after construction
- Compiler can skip recomposition if parameter unchanged

```kotlin
@Immutable
data class User(val id: Int, val name: String)
```

### @Stable
- Implements structural equality (`equals`)
- Public properties are read-only or observable
- Changes are always notified to Compose (through state objects)
- Weaker guarantee than `@Immutable`, but suitable for types with observable state

```kotlin
@Stable
class UserViewModel {
    val userName: State<String> = mutableStateOf("")
    val isLoading: State<Boolean> = mutableStateOf(false)

    // Observable state, not direct properties
}
```

**Pitfall:** Not annotating data classes used as parameters. Unannotated types are assumed unstable, triggering unnecessary recompositions.

```kotlin
// ❌ Treated as unstable, causes recomposition
class Config(val title: String, val color: Color)

// ✅ Properly annotated
@Immutable
class Config(val title: String, val color: Color)
```

## Strong Skipping Mode

In Compose 1.6+, strong skipping mode applies stricter recomposition logic.

**What changed:**
- Composables skip recomposition if *all* parameters have unchanged identity and value
- Unannotated parameter types are treated as unstable (always recompose)
- `@Stable` and `@Immutable` annotations are now critical for performance
- Lambda parameters always cause recomposition (they're new instances)

**Enable strong skipping:**
```gradle
composeOptions {
    kotlinCompilerExtensionVersion = "1.5.4+"  // enables by default
}
```

**Practical impact:**
```kotlin
// ❌ These create new instances, always recompose child
@Composable
fun Parent() {
    Child(title = buildString { append("Title") })
    Child(config = Config(...))  // Unstable type
}

// ✅ Cache instances
@Composable
fun Parent() {
    val title = remember { "Title" }
    val config = remember { Config(...) }
    Child(title = title)
    Child(config = config)
}
```

## State in ViewModels: StateFlow vs Compose State

### StateFlow (Recommended for ViewModel)
- Survives composition recomposition and configuration changes
- Works with lifecycle (`collectAsStateWithLifecycle`)
- Thread-safe, works across layers

```kotlin
class UserViewModel : ViewModel() {
    private val _uiState = MutableStateFlow<UiState>(UiState.Loading)
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
}

@Composable
fun UserScreen(viewModel: UserViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    when (uiState) {
        is UiState.Loading -> LoadingScreen()
        is UiState.Success -> SuccessScreen((uiState as UiState.Success).data)
        is UiState.Error -> ErrorScreen((uiState as UiState.Error).message)
    }
}
```

### Compose State (For UI-only state)
- Use for temporary, UI-local state
- Don't hoist to ViewModel
- Lost on back navigation

```kotlin
@Composable
fun SearchScreen(viewModel: SearchViewModel) {
    var showFilters by remember { mutableStateOf(false) }  // UI-only
    val searchResults by viewModel.searchResults.collectAsStateWithLifecycle()

    SearchUI(
        results = searchResults,
        showFilters = showFilters,
        onToggleFilters = { showFilters = !showFilters }
    )
}
```

**Key difference:** `collectAsStateWithLifecycle()` (in `androidx.lifecycle:lifecycle-runtime-compose`) collects only when the composable is in a STARTED state, avoiding memory leaks.

## Common Anti-Patterns

### State in Local Variables
```kotlin
// ❌ Lost on recomposition
@Composable
fun Counter() {
    var count = 0  // Reset to 0 on every recomposition
    Button(onClick = { count++ }) { Text(count.toString()) }
}

// ✅ Correct
@Composable
fun Counter() {
    var count by remember { mutableIntStateOf(0) }
    Button(onClick = { count++ }) { Text(count.toString()) }
}
```

### State in `@Composable` Content Lambdas

```kotlin
// WRONG — content lambdas inside layouts are themselves @Composable; var resets every recomposition
Row {
    var count = 0  // resets to 0 on every recomposition of Row
    Button(onClick = { count++ }) { Text("Count: $count") }
}

// RIGHT — remember inside the content lambda
Row {
    var count by remember { mutableIntStateOf(0) }
    Button(onClick = { count++ }) { Text("Count: $count") }
}
```

WHY: the bare-`var` trap fires inside `@Composable` content lambdas too, not just at function scope. Every `Row { ... }`, `Column { ... }`, `Box { ... }`, `LazyColumn { items { ... } }` body is its own `@Composable` block — anything declared there without `remember` runs on every recomposition. The rule is positional, not lexical: *if the code is `@Composable`, plain `var` resets.*

### Mutating a List Held by `mutableStateOf`

```kotlin
// WRONG — mutating a MutableList held by mutableStateOf bypasses the State setter
val items = remember { mutableStateOf(mutableListOf<Item>()) }
items.value.add(Item(...))  // list reference unchanged; no recomposition

// RIGHT — mutableStateListOf for observable list state
val items = remember { mutableStateListOf<Item>() }
items.add(Item(...))  // observable

// OR — replace the reference for mutableStateOf<List<T>>
val items = remember { mutableStateOf<List<Item>>(emptyList()) }
items.value = items.value + Item(...)
```

WHY: mutating the underlying list doesn't change the State's value reference — no recomposition fires. `mutableStateOf` observes assignments to `.value`, not mutations of the object behind it. `mutableStateListOf` is the snapshot-aware collection that observes structural changes; otherwise treat the list as immutable and replace the reference. See "SnapshotStateList and SnapshotStateMap" above for the element-mutation variant of the same trap.

### Animation Suspend From `viewModelScope`

```kotlin
// WRONG — animation suspend launched from viewModelScope
class FeedViewModel : ViewModel() {
    fun scrollToTop(listState: LazyListState) {
        viewModelScope.launch { listState.animateScrollToItem(0) }  // wrong scope
    }
}

// RIGHT — animation runs in a composition-scoped coroutine
@Composable
fun FeedScreen(viewModel: FeedViewModel = hiltViewModel()) {
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    LaunchedEffect(viewModel.events) {
        viewModel.events.collect { event ->
            if (event is ScrollToTop) scope.launch { listState.animateScrollToItem(0) }
        }
    }
}
```

WHY: animation suspend functions (`animateScrollToItem`, `animateTo`, `Animatable.animateTo`) require a composition-scoped coroutine. `viewModelScope` outlives the composition — when the composable leaves the tree, the animation keeps running against a `LazyListState` whose UI no longer exists, producing stale state writes, leaked `MonotonicFrameClock` subscriptions, and broken animations after configuration change. The ViewModel emits *intents* (events); the composition decides *how* to render them. See `android-skills:kotlin-coroutines` for the general rule on scope ownership.

### Reading State in Wrong Scope
```kotlin
// ❌ Reads happen inside lambda; changes don't re-launch effect
var count by remember { mutableIntStateOf(0) }
LaunchedEffect(Unit) {
    while (true) {
        delay(1000)
        println(count)  // Always prints 0
    }
}

// ✅ Pass state to LaunchedEffect key
LaunchedEffect(count) {
    println("Count changed: $count")
}
```

### Creating State in Lambdas
```kotlin
// ❌ Creates new state on every call
val onButtonClick = {
    val newValue = remember { mutableStateOf(0) }  // ERROR: Can't call remember in lambda
}

// ✅ Create state at composition level
var value by remember { mutableIntStateOf(0) }
val onButtonClick = { value++ }
```

---

**Source references:** `androidx.compose.runtime.State`, `androidx.compose.runtime.saveable`, `androidx.lifecycle.runtime.compose`

---

## produceState

Bridge between suspend functions and Compose state:

```kotlin
@Composable
fun UserProfile(userId: String): State<User?> = produceState<User?>(initialValue = null, userId) {
    value = repository.getUser(userId)
}
```

Use when you need to convert a suspend function result into observable State. The coroutine is scoped to the composition and cancelled when the composable leaves.

Can also observe flows:
```kotlin
@Composable
fun NetworkStatus(): State<Boolean> = produceState(initialValue = false) {
    connectivityManager.observeNetworkState().collect { value = it }
}
```

---

## rememberUpdatedState

Capture latest callback value in long-running effects:

```kotlin
@Composable
fun Timer(onTimeout: () -> Unit) {
    val currentOnTimeout by rememberUpdatedState(onTimeout)
    LaunchedEffect(true) {
        delay(5000L)
        currentOnTimeout() // Always calls the latest onTimeout, even if it changed
    }
}
```

Use when: a LaunchedEffect captures a callback that might change, but you don't want to restart the effect. Without `rememberUpdatedState`, the effect would use the stale original callback or need to restart on every callback change.

---

## Sealed UiState Pattern

```kotlin
sealed interface UiState<out T> {
    data object Loading : UiState<Nothing>
    data class Success<T>(val data: T) : UiState<T>
    data class Error(val message: String) : UiState<Nothing>
}
```

Smart-cast safety:
```kotlin
// BAD: smart cast can fail if uiState changes between check and usage
if (uiState is UiState.Success) {
    Content((uiState as UiState.Success).data) // Unsafe cast
}

// GOOD: val capture for safe smart cast
when (val state = uiState) {
    is UiState.Loading -> LoadingIndicator()
    is UiState.Success -> Content(state.data) // Safe smart cast via val
    is UiState.Error -> ErrorMessage(state.message)
}
```

---

## State Holder Class Pattern

For complex screens with multiple interrelated state values, create a state holder:

```kotlin
@Composable
fun rememberSearchState(
    listState: LazyListState = rememberLazyListState(),
    coroutineScope: CoroutineScope = rememberCoroutineScope()
): SearchState = remember(listState, coroutineScope) {
    SearchState(listState, coroutineScope)
}

@Stable
class SearchState(
    val listState: LazyListState,
    private val coroutineScope: CoroutineScope
) {
    var query by mutableStateOf("")
        private set

    val isScrolled: Boolean
        get() = listState.firstVisibleItemIndex > 0

    fun updateQuery(newQuery: String) { query = newQuery }
    fun scrollToTop() { coroutineScope.launch { listState.animateScrollToItem(0) } }
}
```

This pattern (used by `rememberScrollState`, `rememberDrawerState`, etc.) groups related state and logic into a single class, avoiding parameter bloat in composables.

---

## Production State Rules

### 1. mutableStateOf ONLY in composables, never in ViewModels

```kotlin
// BAD: Compose state in ViewModel couples VM to Compose runtime
class MyViewModel : ViewModel() {
    var name by mutableStateOf("") // Don't do this
}

// GOOD: StateFlow in ViewModel — framework-agnostic, testable
class MyViewModel : ViewModel() {
    private val _name = MutableStateFlow("")
    val name = _name.asStateFlow()

    fun updateName(new: String) { _name.value = new }
}
```

### 2. Durable state + acknowledgement over ephemeral events when the user can see the outcome

Before reaching for `Channel` or `SharedFlow`, ask: **would losing this signal desynchronize what the user thinks the app did from the underlying state?** If yes, the signal isn't ephemeral. Model it as **state plus an acknowledgement** — a field on `UiState` that the UI clears after consumption — not as a one-shot event.

```kotlin
// WRONG — one-shot event for an outcome the user must see
class CheckoutViewModel : ViewModel() {
    private val _events = Channel<CheckoutEvent>(BUFFERED)
    val events = _events.receiveAsFlow()

    fun pay() = viewModelScope.launch {
        val result = paymentApi.charge()
        _events.send(CheckoutEvent.PaymentResult(result))  // dropped if collector is gone (config change, backgrounded)
    }
}

// RIGHT — durable state in UiState, acknowledgement clears it
data class CheckoutUiState(
    val isPaying: Boolean = false,
    val pendingResult: PaymentResult? = null,  // outcome lives here
)

class CheckoutViewModel : ViewModel() {
    private val _state = MutableStateFlow(CheckoutUiState())
    val state = _state.asStateFlow()

    fun pay() = viewModelScope.launch {
        _state.update { it.copy(isPaying = true) }
        val result = paymentApi.charge()
        _state.update { it.copy(isPaying = false, pendingResult = result) }
    }

    fun resultAcknowledged() { _state.update { it.copy(pendingResult = null) } }
}
```

Use ephemeral channels (`Channel<Event>(BUFFERED).receiveAsFlow()` or `SharedFlow(replay = 0)`) only for genuinely fire-and-forget UI commands where dropping is acceptable: a transient snackbar acknowledgement, a haptic tick, scroll-to-top after a refresh. Anything that influences what the user thinks the app did — payment outcomes, deletion confirmations, save success, navigation that must happen — belongs in state, with the UI clearing it after consumption.

### 3. Choose Channel or SharedFlow for one-shot events based on delivery guarantees

`Channel` guarantees exactly-once delivery (sender suspends or buffers until consumed). `SharedFlow(replay = 0)` silently drops emissions when no collector exists. Choose based on whether missed events are acceptable — see `android-skills:kotlin-flows` for the full trade-off.

```kotlin
// SharedFlow — collect events with collect in LaunchedEffect, never with collectAsStateWithLifecycle
// (collectAsStateWithLifecycle preserves the last emission as state, causing re-consumption on recomposition)
private val _events = MutableSharedFlow<AppEvent>()
val events = _events.asSharedFlow()

fun onAction() {
    viewModelScope.launch {
        _events.emit(AppEvent.ShowSnackbar("Done"))
    }
}

// Collect in composable
LaunchedEffect(Unit) {
    viewModel.events.collect { event ->
        when (event) {
            is AppEvent.ShowSnackbar -> snackbarHostState.showSnackbar(event.message)
            is AppEvent.Navigate -> onNavigate(event.route)
        }
    }
}
```

### 4. rememberSaveable only at NavGraph level

Use `rememberSaveable` for screen-level state (search query, tab selection) at the NavGraph entry point, not deep inside composable trees where it adds unnecessary persistence overhead.

### 5. snapshotFlow + distinctUntilChanged() for reactive scroll

```kotlin
LaunchedEffect(listState) {
    snapshotFlow { listState.firstVisibleItemIndex }
        .distinctUntilChanged()
        .collect { index -> viewModel.onScrollPositionChanged(index) }
}
```

### 6. .stateIn() with .map() for derived flows

```kotlin
val filteredItems = repository.items
    .map { items -> items.filter { it.isActive } }
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
```

### 7. Don't build Flow pipelines inside `@Composable` bodies

`stateIn`, `shareIn`, `combine`, `flatMapLatest`, and similar Flow operators belong in a presenter / ViewModel scope — not constructed inside a composable's body or `LaunchedEffect`. A pipeline built inside composition is rebuilt every recomposition, lives in the wrong layer, and tears down on disposal without surviving a config change.

```kotlin
// WRONG — pipeline rebuilt every recomposition, ties pipeline lifecycle to composition
@Composable
fun ProfileScreen(repo: ProfileRepository, userId: String) {
    val profile by remember {
        combine(repo.userStream(userId), repo.preferencesStream()) { u, p -> u to p }
            .stateIn(rememberCoroutineScope(), SharingStarted.Lazily, null)  // composition-scoped — wrong
    }
    /* ... */
}

// RIGHT — pipeline lives in ViewModel; UI collects the StateFlow
class ProfileViewModel(repo: ProfileRepository, userId: String) : ViewModel() {
    val state: StateFlow<ProfilePair?> =
        combine(repo.userStream(userId), repo.preferencesStream()) { u, p -> u to p }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
}

@Composable
fun ProfileScreen(vm: ProfileViewModel) {
    val state by vm.state.collectAsStateWithLifecycle()
    /* ... */
}
```

When you see `stateIn(rememberCoroutineScope(), …)` or `combine(…).stateIn(…)` inside a composable body, the fix is almost always "move this to the presenter and pass the result through."

---

## Compose Multiplatform Notes

### rememberSaveable and Bundle

`rememberSaveable`, `Bundle`, and `@Parcelize` are **Android-only**. On CMP targets:

```kotlin
// Android: @Parcelize works
@Parcelize
data class SearchParams(val query: String, val filters: List<String>) : Parcelable

// CMP: use @Serializable instead
@Serializable
data class SearchParams(val query: String, val filters: List<String>)
```

For state persistence across configuration changes in CMP, use kotlinx.serialization-based custom `Saver` implementations.

### collectAsStateWithLifecycle

`collectAsStateWithLifecycle()` is in `androidx.lifecycle:lifecycle-runtime-compose` -- it's Android-specific.

```kotlin
// Android: lifecycle-aware, stops collecting when paused
val state by viewModel.uiState.collectAsStateWithLifecycle()

// CMP commonMain: basic collection, does NOT stop in background
val state by viewModel.uiState.collectAsState()

// CMP with multiplatform lifecycle (lifecycle-runtime-compose:2.10.0+):
// collectAsStateWithLifecycle() available in commonMain
```

On CMP without the multiplatform lifecycle library, flows continue collecting when the app is backgrounded -- be aware of battery and performance implications.
