# Performance Optimization Reference

## Two Axes: Stability and Phase

Recomposition perf issues split into two independent axes — **parameter stability** (does Compose skip this composable?) and **state-read phase** (when does a state read trigger recomposition?). Decide which axis fits the evidence before applying fixes:

- **Stability axis** — composable runs even though inputs didn't change. Diagnose with compiler reports (`*_composables.txt`, `*_classes.txt`) and the strong-skipping rules below. Fixes: stable types, `@Immutable`/`@Stable`, `stabilityConfigurationFiles`, immutable collections.
- **Phase axis** — composable runs because a state read happened in composition that could have happened in layout or draw. Diagnose with Layout Inspector recomposition counts. Fixes: provider lambdas, `Modifier.offset { }`, `Modifier.graphicsLayer { }`, `derivedStateOf`.

**Don't apply this skill when** recomposition tracks real data changes (correctness, not cost) or when no profiler/compiler signal suggests a problem. Premature stability annotations and `remember` wrapping cost more than they save.

---

## Three Phases: Composition, Layout, Drawing

Every frame consists of three phases. Understanding state reads in each phase prevents unnecessary recompositions.

### Composition Phase
- Executes composable functions, evaluates state reads
- Generates lambda and instance allocations
- **State reads here trigger recomposition** of the entire scope

### Layout Phase
- Calculates size and position, runs `measure` and `layout` blocks
- Can read state without triggering composition recomposition
- Mutable state reads OK; prefer `Modifier.offset { }` over `Modifier.offset()`

### Drawing Phase
- Emits draw operations, runs `Canvas` and custom `DrawScope`
- Cannot read mutable state without stability warnings

**Source**: `androidx/compose/runtime/Composer.kt`

---

## Recomposition Skipping with Compiler Reports

The Compose compiler generates `$changed` bitmasks to detect state changes. Enable compiler reports **on demand** (opt-in via a Gradle property) so they don't generate on every build:

```kotlin
// build.gradle.kts
composeCompiler {
    if (project.findProperty("composeReports") == "true") {
        reportsDestination = layout.buildDirectory.dir("compose_reports")
        metricsDestination = layout.buildDirectory.dir("compose_metrics")
    }
}
```

Run with `./gradlew assembleRelease -PcomposeReports=true` when you actually want a report. WHY: report generation slows incremental builds and pollutes `build/` for every developer; gating it keeps the default path fast.

For one-off audits — especially against a repo you don't own — use Gradle's `--init-script` flag to inject the reports configuration without touching the target project's build files:

```kotlin
// compose-reports.init.gradle.kts
allprojects {
    afterEvaluate {
        extensions.findByType(org.jetbrains.kotlin.compose.compiler.gradle.ComposeCompilerGradlePluginExtension::class.java)?.apply {
            reportsDestination.set(layout.buildDirectory.dir("compose_reports"))
            metricsDestination.set(layout.buildDirectory.dir("compose_metrics"))
        }
    }
}
```

Run with `./gradlew --init-script compose-reports.init.gradle.kts :app:assembleRelease`. Reports land in each module's `build/compose_reports/`. No project-side changes; nothing to revert.

After building, check the generated files in `build/compose_reports/`:

- **`*_composables.txt`** — shows each composable's restartability and skippability:
  ```
  restartable skippable fun MyComponent(name: String, onClick: Function0<Unit>)
  restartable fun UnstableComponent(items: List<Item>)  // NOT skippable — unstable param
  ```

- **`*_classes.txt`** — shows stability inference for each class:
  ```
  stable class User { stable val name: String }
  unstable class ScreenState { unstable val items: List<Item> }
  ```

- **`*-composables.csv`** — programmatic view of skippability. **When reading the module-wide `skippable%`, filter out rows where `isLambda == "1"`** before computing the percentage. Zero-argument lambdas can't skip structurally (they have nothing to compare), so they pull the module-wide number down even when every *named* composable is skippable. Named-only `skippable%` is the metric that maps to caller behaviour.

With Kotlin 2.0.20+ and strong skipping on by default, the legacy "missing skippable means not skippable" reading is wrong — almost everything is skippable now. The diagnostic question is no longer "is this composable skippable at all?" but **"will these parameters compare the way I expect, and are callers creating new unstable instances every frame?"**

Under strong skipping:
- **Stable parameters** compare with `equals()` — value equality decides whether to skip.
- **Unstable parameters** compare with `===` (instance equality) — the same instance skips, a new instance recomposes.
- **Lambdas inside composables** are automatically remembered based on their captures — they no longer break skipping just by existing.

So when the report shows a composable as skippable but Layout Inspector shows it recomposing constantly, look at the call site: a caller probably allocates a new unstable instance every frame (`listOf(...)`, `Modifier.X.Y()`, an ad-hoc data class). Fixing instability still matters — but now mostly to turn `===` comparisons back into `equals()`:

- **Unstable collection types** (`List`, `Set`, `Map`) — replace with `kotlinx.collections.immutable` equivalents (`ImmutableList`, `ImmutableSet`, `ImmutableMap`) so equality is meaningful.
- **All properties are stable but the class itself is not annotated** — add `@Stable` or `@Immutable` (only if the contract genuinely holds — `@Stable` on a class with deeply unstable inner types is a lie that causes skipped recompositions and stale UI).
- **Inner types are themselves unstable** — fix the inner types first, then the outer type becomes stable. This can cascade several levels deep.
- **Cross-module boundary** — the compiler can't infer stability across module boundaries. Use `stabilityConfigurationFiles` (see below) to declare these types stable globally.
- **Pragmatic opt-out** — `@Suppress("ComposeUnstableCollections")` per-function when the instability is harmless and the refactoring cost is not justified.

### Stability — @Stable and @Immutable

A type is **stable** if:
- Its public properties are stable
- Overrides to `equals()` and `hashCode()` are based on stable properties
- Recomposition is skipped when the same instance is passed

Mark stable types explicitly:

```kotlin
@Immutable
data class Person(val name: String, val age: Int)

@Stable
class UserViewModel : ViewModel {
    private val _state = MutableState(UserState())
    val state: State<UserState> = _state
}

// Composable receiving stable types can skip recomposition
@Composable
fun PersonCard(person: Person) {
    Text(person.name)  // Skips if person unchanged
}
```

**Avoid**: `@Stable` on data classes with mutable fields or non-final properties.

### `@Immutable` vs `@Stable` — the boundary

- **`@Immutable`** — use when every property is effectively immutable and `equals()` describes all observable state. The compiler is then free to skip recomposition whenever the previous and current values are `equals`-equal.
- **`@Stable`** — use for types whose mutable state is observable to Compose, typically via `MutableState`. You're promising that *any* state change a consumer can observe will be flagged through a Compose snapshot, so the compiler can compare by identity and still get correct results.

WHY the distinction matters: `@Immutable` is a stricter promise (no mutation at all) and lets the compiler skip more aggressively. `@Stable` is the right call for things like ViewModels and snapshot-backed holders — anything where state mutates but the mutation routes through `MutableState`/snapshots.

**Don't annotate to silence a report.** A false stability promise produces *skipped recompositions and stale UI* — the worst failure mode, because the bug is silent and hard to reproduce. If the contract doesn't hold, fix the underlying type or live with the recomposition.

### Cross-module stability via `stabilityConfigurationFiles`

The Compose compiler can't infer stability for types from other modules or third-party libraries (`java.time.*`, `java.math.BigDecimal`, `kotlinx.datetime.*`, etc.). Declare them stable globally with `stabilityConfigurationFiles`:

```kotlin
// build.gradle.kts
composeCompiler {
    stabilityConfigurationFiles.add(
        rootProject.layout.projectDirectory.file("compose_stability.conf")
    )
}
```

Sample `compose_stability.conf`:

```
java.math.BigDecimal
java.time.LocalDate
java.time.LocalDateTime
java.time.Instant
kotlinx.datetime.Instant
kotlinx.datetime.LocalDate
```

WHY this is safer than `@Suppress` or wrapping the type: the promise lives in one config file you can review, not scattered across composables. WHY this is more dangerous than annotations: there's no compile-time check that the listed type actually is immutable.

**Only list types you're willing to promise are immutable.** Do NOT list mutable types like `java.util.Date`, `java.util.Calendar`, or anything backed by mutable internal state — listing them lies to the compiler and causes stale UI for the same reason a wrong `@Immutable` does.

### The Five Stability Types in Compiler Reports

When reading `*_classes.txt` or the Compose compiler's stability inference output, the compiler emits one of five classifications. The mental model "stable vs unstable" is too coarse; `runtime stable` in particular is **not a bug**.

| Type | Meaning | Skipping behaviour |
|---|---|---|
| **Certain (stable)** | All properties are known-stable at compile time | `equals()` comparison; skips when equal |
| **Runtime (stable)** | Stability depends on an inner type that the compiler defers — a per-instance `$stable: Int` field is generated and checked at runtime | `equals()` comparison if the runtime check passes; otherwise falls back to `===` |
| **Unknown** | Interface-typed parameter where the compiler can't see the concrete implementation | `===` comparison (instance equality) — same instance skips |
| **Parameter** | A generic type parameter — stability depends on the call-site type argument | Resolved per-call-site against the concrete type |
| **Unstable** | Proven unstable (mutable field outside Compose snapshots, etc.) | Strong skipping disabled outright; the composable runs every time |

The common reading mistake is treating **runtime stable** as a defect to annotate away. It isn't. The `$stable: Int` field is a valid compile-time-deferred classification: when the inner type's actual runtime stability matches the outer type's expected stability, the comparison is `equals()` and the composable skips. Adding `@Stable` on top of a `runtime stable` class only matters when the runtime check is producing too many false negatives — and the right diagnostic for that is to look at the inner type, not the wrapper.

**Source verification:** these five types are defined in `androidx/compose/compiler/plugins/kotlin/analysis/Stability.kt`. The runtime `$stable: Int` field is generated by `ClassStabilityTransformer.kt`. The configuration file format is parsed by `StabilityConfigParser.kt`. The inference algorithm itself is in `StabilityInferencer.kt`.

---

## Strong Skipping Mode (Default in Kotlin 2.0.20+)

Strong skipping is the default with the Compose compiler shipped in Kotlin 2.0.20+. Drop the old "missing skippable means not skippable" mental model — under strong skipping, the rules are:

- **Stable parameters** compare with `equals()`. Two equal instances skip.
- **Unstable parameters** compare with `===` (instance equality). The same instance skips; a new instance recomposes — even if `equals()` would have returned `true`.
- **Lambdas inside composables** are automatically remembered based on their captures. You don't need `remember { { ... } }` to keep an `onClick` stable across recompositions; the compiler does it for you.

```kotlin
// Strong skipping in action
@Composable
fun Counter(count: Int, onClick: () -> Unit) {
    // 'onClick' is auto-remembered; stable across recompositions of the caller
    Button(onClick = onClick) {
        Text("Count: $count")
    }
}
```

WHY this matters for diagnosis: the right question shifts from "is this composable skippable?" (almost always yes) to **"will my parameters compare the way I expect, and are callers creating new unstable instances every frame?"** A skippable composable that still recomposes is almost always a call-site problem — a fresh `List`, `Modifier` chain, or ad-hoc object on each parent recomposition — not a missing annotation on the callee.

Verify the toolchain is recent enough to get strong skipping:

```kotlin
// libs.versions.toml
[versions]
kotlin = "2.0.20"  // or newer
```

If you're stuck on an older Kotlin, the legacy "missing skippable" diagnosis from older guides still applies — but plan the upgrade rather than papering over it.

### Disabling Strong Skipping

If a specific module depends on the old comparison semantics during a migration, the modern way to opt out is via the compiler feature flag DSL — not the deprecated `enableStrongSkippingMode` Gradle property:

```kotlin
// build.gradle.kts (the module that needs the opt-out)
composeCompiler {
    featureFlags.add(ComposeFeatureFlag.StrongSkipping.disabled())
}
```

Treat this as a transitional escape hatch, not a default. Re-enable strong skipping as soon as the offending call sites are fixed.

### Strong Skipping Doesn't Reach Non-`@Composable` Scopes

Automatic lambda memoization happens inside `@Composable` functions only. Lambdas allocated in **non-composable scopes** still produce a fresh instance on every parent recomposition:

| Scope | Why it's not memoized |
|---|---|
| `LazyListScope.items { … }` and its item lambdas | `items {}` is a regular Kotlin extension on `LazyListScope`, not a composable function |
| `Modifier.pointerInput(key) { … }` block | `PointerInputScope.() -> Unit` is a suspend lambda — not composable |
| `object : Foo { override fun bar() = { … } }` | Anonymous object literals — Kotlin object scope |
| `Modifier.drawBehind { }`, `drawWithCache { }`, `drawWithContent { }` | `DrawScope.() -> Unit` is a regular lambda over `DrawScope` |

For these, hoist the lambda to a stable reference at the composable level — usually a method reference (`vm::onClick`) or a `remember { ... }` of a custom callback object that holds the method references:

```kotlin
@Composable
fun ItemList(items: List<Item>, vm: ItemViewModel) {
    val onItemClick: (Item) -> Unit = vm::onItemClick  // stable method reference
    LazyColumn {
        items(items, key = { it.id }) { item ->
            ItemRow(item, onClick = { onItemClick(item) })  // lambda OK — inside @Composable item block
        }
    }
}
```

### Compose Inline Layouts Aren't Skippable

`Row`, `Column`, `Box`, and other inline-marked composables are **not restartable or skippable**. Wrapping a `Row` in another composable "to make it skip" is a no-op; the compiler still inlines the body into the parent's recomposition scope.

The fix for a wasteful `Row` body isn't a wrapper — it's making the *parent* skippable so the inline body doesn't get re-executed in the first place.

### Escape Hatches: `@DontMemoize`, `@NonSkippableComposable`, `@NonRestartableComposable`

Strong skipping ships with three opt-out annotations. Reach for them rarely, with a justifying comment at the call site:

| Annotation | Target | Use when |
|---|---|---|
| `@DontMemoize` | A specific lambda literal (target is `EXPRESSION`) | The lambda must allocate every call — typically a fresh `MutableState` initializer or capture of a constructor that mutates on equality |
| `@NonSkippableComposable` | A composable function | The body must run every recomposition — telemetry composables, custom inspectors that observe parent recomposition counts |
| `@NonRestartableComposable` | A composable function | The function should be inlined into the parent's restart scope — typically used by library authors to keep an effect from spawning its own scope |
| `@ReadOnlyComposable` | A composable function | The composable only reads `CompositionLocal`s and `CurrentRecomposeScope` — never invalidates and never invalidates its callers (for example, `MaterialTheme.colorScheme`) |

The `@DontMemoize` annotation in particular is `@Target(EXPRESSION)` — it applies to the lambda literal at the call site, not the lambda type. Putting it on the parameter type does nothing.

---

## Defer State Reads to Layout/Draw Phase

Reading state in composition triggers recomposition. Push reads to later phases:

### Bad: Recomposition on Every Offset Change
```kotlin
@Composable
fun Box(offsetX: State<Float>) {
    val x = offsetX.value  // Reads in composition, triggers recomposition
    Box(modifier = Modifier.offset(x.dp, 0.dp))
}
```

### Good: Deferred Read in Layout Phase
```kotlin
@Composable
fun Box(offsetX: State<Float>) {
    Box(
        modifier = Modifier.offset {
            IntOffset(offsetX.value.toInt(), 0)  // Read in layout phase
        }
    )
}
```

Use `Modifier.offset { }` (lambda) instead of `Modifier.offset()` (parameter) for state-dependent positioning.

### Provider Lambdas Across Composable Boundaries

When state needs to cross a composable boundary, pass a **provider lambda** — not a snapshot value. Reading the value at the call site triggers recomposition of the parent every time the value changes; reading inside the consumer's layout/draw block defers it.

```kotlin
// WRONG — snapshot value crosses boundary, parent recomposes every frame
@Composable
fun HomeScreen(scrollOffset: Int) {
    HeroImage(scrollOffset = scrollOffset)
}

// RIGHT — provider lambda; HeroImage reads inside graphicsLayer's block
@Composable
fun HomeScreen(scrollOffsetProvider: () -> Int) {
    HeroImage(scrollOffsetProvider = scrollOffsetProvider)
}

@Composable
fun HeroImage(scrollOffsetProvider: () -> Int) {
    Image(
        painter = painterResource(R.drawable.hero),
        contentDescription = null,
        modifier = Modifier.graphicsLayer { translationY = -scrollOffsetProvider() / 2f },
    )
}
```

WHY this works: the value read happens inside `graphicsLayer { ... }`, which runs in the draw phase. The state read is recorded against the draw scope, not the composition, so changes invalidate only the layer — not `HeroImage`, not `HomeScreen`.

**The `by` delegate is the smell.** When you write `val offset by scrollOffsetState`, you've unwrapped the snapshot at the read site. Keep the value as `State<T>` (or expose `() -> T`) so it can survive crossing the boundary as a provider. By the time you've unwrapped it, the only way to defer is to re-wrap it — usually clunkier than just not unwrapping in the first place.

**Deferral sites** (where state reads stay out of composition):
- `Modifier.offset { }` — layout phase
- `Modifier.graphicsLayer { }` — draw phase, the cheapest of all
- `Modifier.layout { }` — layout phase, custom measure/place
- Custom `Alignment.align(...)` — layout phase
- `drawWithContent`, `drawBehind`, `drawWithCache` — draw phase

Pick the latest phase your transformation tolerates: `graphicsLayer` for translation/rotation/alpha (no relayout needed), `offset { }`/`layout { }` when child position affects siblings, `drawBehind` for raw drawing.

---

## derivedStateOf — Reducing Recomposition Frequency

When deriving expensive computations from state, wrap in `derivedStateOf` to dedup recompositions:

```kotlin
// Bad: recomposes on every items change
@Composable
fun SearchResults(items: List<Item>, query: String) {
    val filtered = items.filter { query in it.title }  // Composition phase
    LazyColumn {
        items(filtered) { /* ... */ }
    }
}

// Good: only recomposes if filtered result actually changes
@Composable
fun SearchResults(items: List<Item>, query: String) {
    val filtered = remember(items, query) {
        derivedStateOf { items.filter { query in it.title } }
    }
    LazyColumn {
        items(filtered.value) { /* ... */ }
    }
}
```

`derivedStateOf` deduplicates downstream recompositions — two different filters yielding the same list trigger only one downstream recomposition.

---

## remember with Keys

Avoid unnecessary recalculation:

```kotlin
// Recalculates on every recomposition
@Composable
fun ExpensiveItem(id: Int) {
    val metadata = computeMetadata(id)  // Called every time
    Text(metadata)
}

// Recalculates only when id changes
@Composable
fun ExpensiveItem(id: Int) {
    val metadata = remember(id) { computeMetadata(id) }
    Text(metadata)
}

// Multiple keys
@Composable
fun Item(id: Int, userId: Int) {
    val data = remember(id, userId) { fetchData(id, userId) }
    Text(data.toString())
}
```

Omit `remember` if computation is cheap (string formatting, simple objects). Over-wrapping causes memory leaks.

### `remember { ... }` That Reads `LocalConfiguration` / `LocalDensity` / `LocalLayoutDirection`

If the `remember { }` body reads any of these compositional locals, the values **must** appear in the key list. Without keying, the cached value goes stale on rotation, font-scale change, foldable posture transition, RTL flip, or display density change — silently.

```kotlin
// WRONG — caches once at first composition; stays wrong forever after rotation
@Composable
fun ResponsiveColumn(content: @Composable () -> Unit) {
    val columns = remember {
        val width = LocalConfiguration.current.screenWidthDp
        if (width >= 840) 3 else if (width >= 600) 2 else 1
    }
    /* ... */
}

// RIGHT — key on the local that drives the cached computation
@Composable
fun ResponsiveColumn(content: @Composable () -> Unit) {
    val configuration = LocalConfiguration.current
    val columns = remember(configuration) {
        val width = configuration.screenWidthDp
        if (width >= 840) 3 else if (width >= 600) 2 else 1
    }
    /* ... */
}
```

The same applies to `LocalDensity` (font scale, screen density), `LocalLayoutDirection` (RTL changes during a session, e.g., from app-level language switch), and `LocalContext` (configuration-changed context).

---

## LazyList Performance — Keys and ContentType

### Always Provide Keys

Keys enable item reuse and animations:

```kotlin
// Bad: no keys, items recreated on every list change
LazyColumn {
    items(users) { user ->
        UserRow(user)
    }
}

// Good: keys enable reuse
LazyColumn {
    items(users, key = { it.id }) { user ->
        UserRow(user)
    }
}
```

### ContentType for Efficient Reuse

```kotlin
sealed class ListItem {
    data class Header(val title: String) : ListItem()
    data class User(val user: User) : ListItem()
}

LazyColumn {
    items(
        items = items,
        key = { it.hashCode() },
        contentType = { item ->
            when (item) {
                is ListItem.Header -> "header"
                is ListItem.User -> "user"
            }
        }
    ) { item ->
        when (item) {
            is ListItem.Header -> HeaderRow(item.title)
            is ListItem.User -> UserRow(item.user)
        }
    }
}
```

Without `contentType`, all items compete for one ViewHolder pool. With it, items reuse efficiently.

### Avoid Allocations in Item Scope

```kotlin
// Bad: allocates on every recomposition
LazyColumn {
    items(users) { user ->
        val userState = remember { mutableStateOf(user) }
        UserRow(userState.value)
    }
}

// Good: allocates once
LazyColumn {
    items(
        items = users,
        key = { it.id }
    ) { user ->
        UserRow(user)
    }
}
```

### Stabilize Per-Item Lambdas with `remember(item.id)`

When an item lambda captures any value that changes per item (the item itself, an index, a per-item callback), wrap it with `remember(item.id) { ... }` so each row gets a stable instance keyed by its id. Without this, the lambda is allocated fresh on every scroll, defeating the strong-skipping comparison for `ItemRow`.

```kotlin
// WRONG — fresh lambda every scroll; ItemRow re-runs even though `item` didn't change
LazyColumn {
    items(items, key = { it.id }) { item ->
        ItemRow(item, onClick = { onItemClick(item) })
    }
}

// RIGHT — lambda keyed by stable id; remembered per item
LazyColumn {
    items(items, key = { it.id }) { item ->
        val onClick = remember(item.id) { { onItemClick(item) } }
        ItemRow(item, onClick = onClick)
    }
}
```

### Prefetch and Cache Window (Foundation 1.9+ / 1.10+)

Lazy layouts compose items just outside the viewport during scroll to keep frame budget steady. Foundation 1.9+ exposes `LazyLayoutCacheWindow(ahead, behind)` to control how far ahead and behind the viewport prefetch reaches; Foundation 1.10+ makes prefetch pausable (it yields the main thread when frame deadline pressure rises).

```kotlin
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MediaList(items: List<MediaItem>) {
    val state = rememberLazyListState(
        cacheWindow = LazyLayoutCacheWindow(ahead = 2, behind = 1),  // prefetch 2 ahead, 1 behind
    )
    LazyColumn(state = state) {
        items(items, key = { it.id }) { MediaRow(it) }
    }
}
```

Tune `ahead` higher for tall items with slow-to-resolve images; tune it lower (or to 0) when items are cheap and prefetch is bloating memory. The default is sensible for most cases — touch this knob only when a profiler shows item composition spike under scroll.

For nested lazy layouts (a `LazyRow` inside each `LazyColumn` item), `NestedPrefetchScope` lets the outer list trigger inner prefetch ahead of the outer item entering composition. Reach for it when sideways-scrolling carousels show first-frame jank as you scroll vertically.

---

## Subcomposition Pitfalls

`SubcomposeLayout`, `BoxWithConstraints`, and `Scaffold` use the **subcomposition** mechanism — they run a composition pass *during the measure phase*, with a slot that depends on layout constraints. Powerful when needed; expensive when stacked.

### `BoxWithConstraints` inside a `LazyColumn` item

This is the highest-cost shape. Every visible item runs its own subcomposition pass during measurement on every scroll:

```kotlin
// WRONG — subcomposition per visible item, on every scroll
LazyColumn {
    items(items, key = { it.id }) { item ->
        BoxWithConstraints {
            if (maxWidth < 320.dp) CompactRow(item) else WideRow(item)
        }
    }
}

// RIGHT — hoist the constraint decision to the screen level, pass a flag in
@Composable
fun ItemList(items: List<Item>) {
    BoxWithConstraints {
        val compact = maxWidth < 320.dp  // subcomposed ONCE per screen size
        LazyColumn {
            items(items, key = { it.id }) { item ->
                if (compact) CompactRow(item) else WideRow(item)  // plain conditional, no subcomposition
            }
        }
    }
}
```

The same logic applies anywhere subcomposition is nested inside a high-frequency parent (carousel inside a paged feed, etc.).

### Nested `Scaffold`

`Scaffold` is a `SubcomposeLayout` under the hood — it subcomposes top bar, bottom bar, FAB, and content slots independently to measure inner padding. Nesting one `Scaffold` inside another's content slot doubles the work and produces inset/padding bugs that look like spacing arithmetic errors.

Use one screen-level `Scaffold` per route. For nested-section layouts that need top/bottom-bar-like ergonomics, build the section out of plain `Column` + `TopAppBar` instead of reaching for `Scaffold` again.

### Reuse with `SubcomposeSlotReusePolicy`

When you author a custom `SubcomposeLayout`, cap the reuse pool so old slot composition state isn't held indefinitely:

```kotlin
SubcomposeLayout(
    modifier = modifier,
    slotReusePolicy = SubcomposeSlotReusePolicy(maxSlotsToRetainForReuse = 4),
) { constraints ->
    val placeable = subcompose(slotId = "primary") { content() }.first().measure(constraints)
    // ...
}
```

For latency-sensitive content (a heavy section that appears on a tab switch), use `state.precompose(slotId, content)` to compose the slot ahead of time outside the measure phase. Both APIs are available in `SubcomposeLayoutState` (Foundation 1.6+).

**Lint signal:** AndroidX has an internal `ComposableLambdaInMeasurePolicy` lint that flags fresh composable lambdas allocated inside `subcompose(slotId)` blocks. Public APIs suppress it; app code should not reproduce the pattern. If a `subcompose(slotId) { /* fresh lambda */ }` is in the hot path, hoist the lambda out so the slot identity stays stable.

**Source verification:** `SubcomposeLayout.kt`, `BoxWithConstraints.kt`, and `Scaffold.kt` in `androidx.compose.foundation` / `androidx.compose.material3`.

---

## Baseline Profiles

Baseline profiles instruct R8 to pre-compile hot code paths, reducing startup time and jank.

### Generating Profiles

Use Jetpack Macrobenchmark to record profiles:

```kotlin
@RunWith(AndroidBenchmarkRunner::class)
class StartupBenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun startupCompilation() = benchmarkRule.measureRepeated(
        packageName = "com.example.app",
        metrics = listOf(StartupTimings.FIRST_FRAME),
        iterations = 10,
        setupBlock = {
            pressHome()
            startActivityAndWait()
        }
    ) {
        // Interact with app
    }
}
```

Profiles are generated in `baseline-prof.txt`:
```
androidx/compose/runtime/Recomposer;startRecomposition()V
com/example/MyScreen;ComposableFunctionName(ILandroidx/compose/runtime/Composer;I)V
```

### `BaselineProfileMode.Require` vs `UseIfAvailable`

When running a `MacrobenchmarkRule` measurement that assumes a baseline profile is installed, set `CompilationMode.Partial(baselineProfileMode = BaselineProfileMode.Require)`. The default `UseIfAvailable` silently falls back to measuring an *unprofiled* build when no profile is detected — producing benchmark numbers that look fine in CI and lie about what your users will see.

```kotlin
@Test
fun scrollWithProfile() = benchmarkRule.measureRepeated(
    packageName = "com.example.app",
    metrics = listOf(FrameTimingMetric()),
    iterations = 10,
    compilationMode = CompilationMode.Partial(
        baselineProfileMode = BaselineProfileMode.Require,  // fail loudly if profile is missing
    ),
) {
    // Interact: scroll, click, etc.
}
```

In CI, `Require` turns a missing-profile bug into a loud test failure — exactly what you want when reviewing a baseline-profile PR.

---

## R8/ProGuard Compose Rules

Compose includes default ProGuard rules. Ensure `shrinkResources true` and `minifyEnabled true`:

```gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

Custom rules to preserve stability:

```proguard
-keep @androidx.compose.runtime.Stable class **
-keep @androidx.compose.runtime.Immutable class **
-keepclassmembers class * {
    @androidx.compose.runtime.Stable <methods>;
}
```

---

## Measuring Performance

### Layout Inspector — Recomposition Counts

In Android Studio:
1. Run app on device
2. Open **Layout Inspector** (Tools > Layout Inspector)
3. Select target process
4. Check **Show Composition Counts** (toggle in inspector)

Recomposition counts display how many times each composable was recomposed since inspection started.

#### Argument Change Reasons (Android Studio Hedgehog+)

When a composable shows a high recomposition count, the **Composition state** column in Layout Inspector classifies each parameter into one of five statuses. Map the status to the fix instead of guessing:

| Status | What it means | Likely fix |
|---|---|---|
| **Changed** | Parameter actually has a new value | Correct — this is the cause; check whether the upstream value should be changing this often |
| **Unchanged** | Parameter value equal, no recomposition contribution | Skip — not the source |
| **Uncertain** | Compose couldn't determine equality (unstable type, instance-equality fallback) | Stabilize the type (`@Stable`/`@Immutable`/`stabilityConfigurationFiles`) so equality is meaningful |
| **Static** | Compile-time constant — never causes recomposition | Skip |
| **Unknown** | Interface-typed parameter where the concrete type is hidden | Either expose a stable concrete type at the boundary, or rely on `===` and ensure callers reuse instances |

Most "why is this recomposing?" investigations resolve at the **Uncertain** row: an unstable parameter type forces instance-equality comparison, callers create new instances every parent recomposition, the composable runs every time. Fix the type — don't memoize the caller.

For headless/CLI workflows (no IDE), use `android layout --diff --pretty` between two app states to get a JSON tree of which nodes changed. Combine with `SideEffect { Log.d(...) }` counters to correlate tree diffs with recomposition hot paths.

### Macrobenchmark — Frame Timing

```kotlin
benchmarkRule.measureRepeated(
    packageName = "com.example.app",
    metrics = listOf(FrameTimingMetric()),
    iterations = 10
) {
    // Interact: scroll, click, etc.
}
```

Reports frame times (ms), jank, jitter. Target <16.67ms for 60 fps.

---

## Common Hot Paths

### String Formatting in Composition
```kotlin
// Bad: allocates string every recomposition
@Composable
fun Counter(count: Int) {
    Text("Count: ${count}")  // String.format called
}

// Still composed, but optimized
@Composable
fun Counter(count: Int) {
    Text(buildString { append("Count: "); append(count) })
}
```

### List Filtering Without derivedStateOf
```kotlin
// Bad: filters every recomposition
@Composable
fun FilteredList(items: List<Item>, predicate: (Item) -> Boolean) {
    LazyColumn {
        items(items.filter(predicate)) { /* ... */ }
    }
}

// Good
@Composable
fun FilteredList(items: List<Item>, predicate: (Item) -> Boolean) {
    val filtered = remember(items, predicate) {
        derivedStateOf { items.filter(predicate) }
    }
    LazyColumn {
        items(filtered.value) { /* ... */ }
    }
}
```

### Creating Objects in Lambdas
```kotlin
// Bad
Button(
    colors = ButtonDefaults.buttonColors(
        containerColor = if (isPressed) Color.Red else Color.Blue
    )
) { }

// Good: compute once
val buttonColors = remember(isPressed) {
    ButtonDefaults.buttonColors(
        containerColor = if (isPressed) Color.Red else Color.Blue
    )
}
Button(colors = buttonColors) { }
```

---

## Anti-Patterns

### Wrapping Everything in remember
```kotlin
// Unnecessary
val text = remember { "Hello" }
val size = remember { 12.sp }
val color = remember { Color.Black }
```

`remember` only for mutable state or expensive calculations.

### Premature Optimization
Profile first. Don't add `derivedStateOf` or `remember` without Layout Inspector data.

### @Stable on Mutable Data Classes
```kotlin
// DON'T
@Stable
data class MutableUser(val name: String, val age: MutableState<Int>)

// DO
@Immutable
data class User(val name: String, val age: Int)
```

---

## Symptom → Diagnosis → Fix

Use this table to route from observed behavior to the right axis (stability vs phase) before reaching for a fix:

| Symptom | Diagnosis | Fix |
|---|---|---|
| Composable skips poorly despite strong skipping | New unstable instance each recomposition | Remember, hoist, or make the type stable |
| Draw block recomposes every frame | Value read before draw block | Move `State.value` read inside draw block; use provider lambda for cross-boundary state |
| Regression after adding type to a data class | Cross-module type is unstable | Add to `stabilityConfigurationFiles` or annotate `@Immutable` |
| LazyColumn item recomposes on every scroll | Lambda captured from parent | Cache the lambda with `remember` or hoist the source out of the item |
| Animation triggers recomposition per frame | Animated state read in composition | Read inside `graphicsLayer { }` or `offset { }` block |

WHY a table here: the same surface symptom ("too many recompositions") routes to wildly different fixes depending on axis. Reach for the table before guessing whether the cause is stability or phase.

---

## Resources

- **Compose Compiler Reports**: https://developer.android.com/develop/ui/compose/performance/stability-report
- **Macrobenchmark**: https://developer.android.com/develop/ui/compose/performance/measurement
- **Baseline Profiles**: https://developer.android.com/develop/ui/compose/performance/baseline-profiles
- **Strong Skipping Mode**: https://developer.android.com/develop/ui/compose/performance/stability/strongskipping
- **Compose Stability Configuration**: https://developer.android.com/develop/ui/compose/performance/stability/fix#configuration-file

---

## Zero-Size DrawScope Guard

During initial composition, a composable's size can be zero. This causes crashes in calculations like `size.minDimension / 2`.

```kotlin
// BAD: crashes when size is zero
Canvas(modifier = Modifier.fillMaxSize()) {
    val radius = size.minDimension / 2  // NaN or divide-by-zero
    drawCircle(color = Color.Blue, radius = radius)
}

// GOOD: always guard
Canvas(modifier = Modifier.fillMaxSize()) {
    if (size.minDimension <= 0f) return@Canvas
    val radius = size.minDimension / 2
    drawCircle(color = Color.Blue, radius = radius)
}
```

Rule: Never use `fillMaxSize()` on Canvas without an explicit height constraint. Always guard DrawScope operations.

---

## Composition Tracing

Use `trace()` for Perfetto/systrace integration:

```kotlin
@Composable
fun ExpensiveScreen() {
    trace("ExpensiveScreen") {
        // composable body — visible in system traces
    }
}
```

Enables identifying slow composables in production profiling without adding logging.

---

## movableContentOf

Avoid recomposition when moving content between layout positions:

```kotlin
val movableContent = remember {
    movableContentOf {
        ExpensiveChild() // Only composed once, moved without recomposition
    }
}

if (isExpanded) {
    ExpandedLayout { movableContent() }
} else {
    CollapsedLayout { movableContent() }
}
```

Without `movableContentOf`, switching between layouts would dispose and recompose `ExpensiveChild`. With it, the content is moved, preserving state and avoiding recomposition.

---

## Production Performance Rules

1. **R8: strip previews + semantics in release** — add to `proguard-rules.pro`:
```
-assumenosideeffects class androidx.compose.ui.tooling.preview.** { *; }
```

2. **`@Suppress("ComposeUnstableCollections")`** — pragmatic skipping when stability isn't worth the complexity:
```kotlin
@Suppress("ComposeUnstableCollections")
@Composable
fun ItemList(items: List<Item>) { // List is unstable but acceptable here
    // ...
}
```

3. **Immutable collections for stability** — `kotlinx.collections.immutable` (`ImmutableList`, `ImmutableSet`, `ImmutableMap`):
```kotlin
// Makes the parameter stable, enabling recomposition skipping
@Composable
fun StableList(items: ImmutableList<Item>) { ... }
```

4. **ReportDrawnWhen** for startup performance:
```kotlin
ReportDrawnWhen { items.isNotEmpty() }
```

5. **Canvas always explicitly sized** — never `fillMaxSize()` without a height constraint:
```kotlin
// BAD
Canvas(Modifier.fillMaxSize()) { ... }

// GOOD
Canvas(Modifier.fillMaxWidth().height(200.dp)) { ... }
```

---

## Compose Multiplatform Performance

Performance tooling differs across platforms:

| Tool | Android | Desktop | iOS | Web |
|------|---------|---------|-----|-----|
| Baseline Profiles | Yes | No | No | No |
| Macrobenchmark | Yes | No | No | No |
| Layout Inspector | Yes (AS) | No | No | No |
| Profiling | Android Studio | JMH | Instruments | Browser DevTools |
| R8/ProGuard | Yes | ProGuard separately | N/A (Kotlin/Native) | N/A |

iOS-specific:
- Kotlin/Native has different GC behavior than Android ART
- Enable ProMotion with `CADisableMinimumFrameDurationOnPhone = true` in Info.plist
- Use configurable frame rate API: increase for animations, decrease for static content

Desktop JVM:
- Different GC characteristics (G1GC vs ART)
- JIT compilation warms up differently

Web/WASM:
- Renders entire canvas per frame (unlike DOM partial repaints)
- WASM GC behavior differs from JVM
- Bundle size impacts initial load time
