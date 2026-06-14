# Compose State Management

This reference covers the state traps and boundaries, not the basics of `mutableStateOf` / `remember` / hoisting / `derivedStateOf`.

## The unified keying rule

`remember`, `LaunchedEffect`, `DisposableEffect`, `produceState`, and the `remember { }` around `derivedStateOf` share one rule: **any changing value the body reads must either be in the key list, be a constant, be a call-site-owned stable object, or be read through `rememberUpdatedState`.** The three legitimate carve-outs:

1. **Constants** — `MAX_RETRY = 3`, `Color.Red`.
2. **Call-site-owned stable objects the call site never replaces** — `rememberCoroutineScope()`, `remember { Animatable(0f) }`; the key would be redundant.
3. **Initial-only capture is the goal** — `val firstSeenAt = remember { Clock.System.now() }`; mark it `// initial-only` so the missing key doesn't read as a bug.

For a value that should keep an effect *running* across changes but invoke the *latest* callback (e.g. `onComplete`), wrap it with `rememberUpdatedState(value)` and read inside the effect — it tracks the latest without restarting.

## Don't `rememberSaveable` a runtime object

`rememberSaveable` serializes *data*; runtime references (`LazyListState`, `FocusRequester`, `CoroutineScope`, callbacks) don't survive process death. Persist the data and recreate the object:

```kotlin
// WRONG — runtime object, no meaningful serialization
val listState = rememberSaveable { LazyListState() }

// RIGHT — save the index, recreate the state
var savedIndex by rememberSaveable { mutableIntStateOf(0) }
val listState = rememberLazyListState(initialFirstVisibleItemIndex = savedIndex)
LaunchedEffect(listState) { snapshotFlow { listState.firstVisibleItemIndex }.collect { savedIndex = it } }
```

## A UI value that drives business logic belongs in the ViewModel

The hoisting boundary isn't "is this UI?" — it's "does my repository or navigation graph depend on this value?" A search query that feeds repository queries is the canonical case:

```kotlin
// WRONG — query is UI-local, but every keystroke hits the repo: can't debounce, restore, or test
var query by remember { mutableStateOf("") }
LaunchedEffect(query) { viewModel.search(query) }

// RIGHT — query lives in the VM, which owns debouncing + the repository call
class SearchViewModel : ViewModel() {
    private val _query = MutableStateFlow("")
    val results = _query.debounce(300)
        .flatMapLatest { repository.search(it) }   // mapLatest if search() is a suspend fun returning the list
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    fun onQueryChange(new: String) { _query.value = new }
}
```

## `derivedStateOf` + the surrounding `remember` capture trap

`derivedStateOf` tracks **`State<T>` reads inside its lambda**. Plain values captured by the lambda are captured **once** when the surrounding `remember { }` runs; if they change later without being in the `remember` key list, the derived state silently uses the original forever.

```kotlin
// WRONG — threshold captured once at first composition; later changes go unnoticed
val isPast by remember { derivedStateOf { listState.firstVisibleItemIndex > threshold } }

// RIGHT — key the surrounding remember on the captured value
val isPast by remember(threshold) { derivedStateOf { listState.firstVisibleItemIndex > threshold } }
```

(Also: the block must read at least one Compose `State` to ever re-evaluate — `derivedStateOf { a + b }` over two plain values pays overhead for nothing; use `remember { a + b }`.)

`SnapshotStateList` / `Map` recompose on **structural** change, not on mutation of a contained element: `items[0].name = "x"` does NOT recompose; `items[0] = items[0].copy(name = "x")` does.

## Cross-Phase Back-Writing

**Back-writing** = writing observable state in a phase that invalidates an *earlier* phase. The compiler doesn't flag it; the symptom is jittery scroll, ghost layouts, or recomposition looping between two states.

**1. Composition → composition** — rebuilding a `mutableStateMapOf`/`mutableStateListOf` inside a composable body writes observable state *during composition*, invalidating the scope that's running:

```kotlin
// WRONG — composition rebuilds the map → invalidates composition → rebuilds the map…
val grouped = remember { mutableStateMapOf<String, List<Item>>() }
grouped.clear(); grouped.putAll(items.groupBy { it.category })

// RIGHT — derive, don't rebuild
val grouped = remember(items) { items.groupBy { it.category } }
```

`mutableStateMapOf`/`mutableStateListOf` are for state that **mutates in response to events**, not for caches — for caches use plain `remember(key) { computeMap() }`.

**2. Layout → composition** — `onSizeChanged` fires *after* layout; writing a `MutableState` from it that's read in composition invalidates composition with the new size → lays out again → fires again:

```kotlin
// WRONG — onSizeChanged writes state read in composition → feedback loop
var widthPx by remember { mutableIntStateOf(0) }
Box(Modifier.fillMaxWidth().onSizeChanged { widthPx = it.width }) {
    Text(title, Modifier.padding(start = (widthPx / 4).dp))   // composition read of widthPx
}

// RIGHT — defer the read to the layout phase
Box(Modifier.fillMaxWidth().onSizeChanged { widthPx = it.width }) {
    Text(title, Modifier.layout { m, c -> val p = m.measure(c); layout(p.width, p.height) { p.place(widthPx / 4, 0) } })
}
```

If two siblings must know each other's measured size, use `Modifier.decorateMeasureConstraints` (Foundation 1.10+) rather than round-tripping through composition. **3. Draw → composition** is the same shape, vanishingly rare. **General rule:** state writes go forward (composition → layout → draw), never backward; when a backward write is the right shape (a sticky header needing its measured height), the cure is a layout-phase API, not a `MutableState` that bridges back into composition.

## `@ReadOnlyComposable` — the bidirectional contract

Mark a `@Composable` getter `@ReadOnlyComposable` only when it's a pure reader (no `Box`/`Text` emit, no `remember`, no effects) — reading it takes a faster runtime path. **Remove it** the moment it calls `Box`/`Text`/`remember`/any effect (including inside content lambdas): a `@ReadOnlyComposable` that emits UI or calls `remember` silently corrupts the slot table (crashes deeper in the tree, not at the call site).

```kotlin
val MaterialTheme.spacing: Spacing
    @Composable @ReadOnlyComposable get() = LocalSpacing.current
```

## Stability annotations — don't annotate speculatively

Under strong skipping (default on Kotlin 2.0.20+), same-module classes with all-stable properties are inferred stable automatically — don't `@Immutable`/`@Stable` speculatively. Reach for them only when inference can't see the type (cross-module boundaries, generic wrappers) or to document an intentional contract. The full stability model lives in `compose/references/performance.md`.

## Common anti-patterns

**Animation suspend from `viewModelScope`** — `animateScrollToItem` / `Animatable.animateTo` need a composition-scoped coroutine. `viewModelScope` outlives the composition, so the animation runs against a `LazyListState` whose UI no longer exists → stale writes, leaked `MonotonicFrameClock` subscriptions, broken animation after a config change. The VM emits an *intent*; the composition decides how to render it.

```kotlin
// WRONG
viewModelScope.launch { listState.animateScrollToItem(0) }
// RIGHT — composition collects the intent and runs the animation in rememberCoroutineScope()
LaunchedEffect(viewModel.events) {
    viewModel.events.collect { if (it is ScrollToTop) scope.launch { listState.animateScrollToItem(0) } }
}
```

**`var` without `remember` resets — positional, not lexical.** Every `Row { }` / `Column { }` / `Box { }` / `items { }` body is its own `@Composable` block; a plain `var count = 0` declared there runs on every recomposition. If the code is `@Composable`, plain `var` resets — use `remember`.

**Mutating a list held by `mutableStateOf`** bypasses the `.value` setter — no recomposition. Use `mutableStateListOf`, or replace the reference (`items.value = items.value + x`).

## Durable state + acknowledgement (over ephemeral events when the user sees the outcome)

Before reaching for `Channel`/`SharedFlow`, ask: *would losing this signal desynchronize what the user thinks the app did from the underlying state?* If yes, model it as a field on `UiState` the UI clears after consumption — not a one-shot event that drops on a config change or backgrounding (even a buffered `Channel`'s queue dies with the process; `SharedFlow(replay = 0)` drops with no collector; a `UiState` field backed by `SavedStateHandle` survives both).

```kotlin
data class CheckoutUiState(val isPaying: Boolean = false, val pendingResult: PaymentResult? = null)
fun pay() = viewModelScope.launch {
    _state.update { it.copy(isPaying = true) }
    val result = paymentApi.charge()
    _state.update { it.copy(isPaying = false, pendingResult = result) }
}
fun resultAcknowledged() { _state.update { it.copy(pendingResult = null) } }
```

Reserve ephemeral `Channel`/`SharedFlow` for genuinely fire-and-forget commands where dropping is acceptable (a transient snackbar, a haptic tick, scroll-to-top after refresh). Full Channel-vs-SharedFlow trade-off: `android-skills:kotlin-flows`.

## Don't build Flow pipelines inside `@Composable` bodies

`stateIn` / `shareIn` / `combine` / `flatMapLatest` belong in a ViewModel scope. A pipeline built in composition is rebuilt every recomposition, lives in the wrong layer, and tears down on disposal without surviving a config change. When you see `stateIn(rememberCoroutineScope(), …)` inside a composable, move it to the presenter and pass the result through.

## Compose Multiplatform

`rememberSaveable` / `Bundle` / `@Parcelize` are **Android-only** — on CMP use `@Serializable` + a kotlinx-serialization-based `Saver`. `collectAsStateWithLifecycle()` is Android-specific; on CMP `commonMain`, `collectAsState()` does NOT stop collecting in the background unless `lifecycle-runtime-compose:2.10.0+` provides the lifecycle-aware variant in `commonMain`.
