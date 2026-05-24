# Performance Optimization Reference

## Two Axes: Stability and Phase

Recomposition perf issues split into two independent axes — **parameter stability** (does Compose skip this composable?) and **state-read phase** (when does a state read trigger recomposition?). Decide which axis fits the evidence before applying fixes:

- **Stability axis** — composable runs even though inputs didn't change. Diagnose with compiler reports (`*_composables.txt`, `*_classes.txt`) and the strong-skipping rules below. Fixes: stable types, `@Immutable`/`@Stable`, `stabilityConfigurationFiles`, immutable collections.
- **Phase axis** — composable runs because a state read happened in composition that could have happened in layout or draw. Diagnose with Layout Inspector recomposition counts. Fixes: provider lambdas, `Modifier.offset { }`, `Modifier.graphicsLayer { }`, `derivedStateOf`.

The three frame phases the phase axis refers to: **composition** (runs composables, evaluates state reads — a read here invalidates the whole scope), **layout** (`measure`/`layout`; mutable reads here don't trigger recomposition — prefer `Modifier.offset { }` over `Modifier.offset()`), **draw** (`Canvas`/`DrawScope`).

**Don't apply this skill when** recomposition tracks real data changes (correctness, not cost) or when no profiler/compiler signal suggests a problem. Premature stability annotations and `remember` wrapping cost more than they save.

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

Run with `./gradlew assembleRelease -PcomposeReports=true` when you actually want a report. Gating it keeps the default build fast.

For a one-off audit against a repo you don't own, inject the config via `--init-script` instead of touching the target's build files:

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

Run with `./gradlew --init-script compose-reports.init.gradle.kts :app:assembleRelease`. No project-side changes; nothing to revert.

What the generated files show:

- **`*_composables.txt`** — each composable's restartability/skippability:
  ```
  restartable skippable fun MyComponent(name: String, onClick: Function0<Unit>)
  restartable fun UnstableComponent(items: List<Item>)  // NOT skippable — unstable param
  ```
- **`*_classes.txt`** — stability inference per class:
  ```
  stable class User { stable val name: String }
  unstable class ScreenState { unstable val items: List<Item> }
  ```
- **`*-composables.csv`** — programmatic view of skippability. **When reading the module-wide `skippable%`, filter out rows where `isLambda == "1"`** before computing the percentage. Zero-argument lambdas can't skip structurally (nothing to compare), so they pull the module number down even when every *named* composable is skippable. Named-only `skippable%` is the metric that maps to caller behaviour.

With Kotlin 2.0.20+ and strong skipping on by default, the legacy "missing skippable means not skippable" reading is wrong — almost everything is skippable now. The diagnostic question is no longer "is this skippable at all?" but **"will these parameters compare the way I expect, and are callers creating new unstable instances every frame?"** (mechanics in *Strong Skipping Mode* below).

When the report shows a composable as skippable but Layout Inspector shows it recomposing constantly, look at the **call site** — a caller probably allocates a new unstable instance every frame (`listOf(...)`, `Modifier.X.Y()`, an ad-hoc data class). Fixing instability turns `===` comparisons back into `equals()`:

- **Unstable collection types** (`List`, `Set`, `Map`) — replace with `kotlinx.collections.immutable` equivalents (`ImmutableList`, …) so equality is meaningful.
- **All properties stable but the class isn't annotated** — same-module classes with all-stable properties are inferred stable automatically, so usually no action is needed; annotate `@Stable`/`@Immutable` only when inference can't see the type — and only if the contract genuinely holds, since a false promise causes skipped recompositions and stale UI. Don't annotate speculatively.
- **Inner types are themselves unstable** — fix the inner types first; the outer type then becomes stable. Can cascade several levels.
- **Cross-module boundary** — the compiler can't infer across modules; use `stabilityConfigurationFiles` (below).
- **Pragmatic opt-out** — `@Suppress("ComposeUnstableCollections")` per-function when the instability is harmless and refactoring isn't justified.

### `@Immutable` vs `@Stable` — the boundary

```kotlin
@Immutable data class Person(val name: String, val age: Int)

@Stable
class UserViewModel : ViewModel {
    private val _state = MutableState(UserState())
    val state: State<UserState> = _state
}
```

- **`@Immutable`** — every property is effectively immutable and `equals()` describes all observable state. The compiler skips whenever previous and current values are `equals`-equal. The stricter promise; lets it skip more aggressively.
- **`@Stable`** — for types whose mutable state is observable to Compose (typically via `MutableState`). You promise *any* observable change is flagged through a snapshot. Like every stable type it's compared with `equals()` (see *Strong Skipping Mode*); a holder that doesn't override `equals()` falls back to identity, so passing the same instance skips while observed snapshot changes still recompose. Right for ViewModels and snapshot-backed holders.

**Don't annotate to silence a report.** A false stability promise produces *skipped recompositions and stale UI* — silent and hard to reproduce. If the contract doesn't hold, fix the type or live with the recomposition. (Never `@Stable` on a data class with mutable non-snapshot fields.)

### Cross-module stability via `stabilityConfigurationFiles`

The compiler can't infer stability for types from other modules or libraries (`java.time.*`, `java.math.BigDecimal`, `kotlinx.datetime.*`). Declare them globally:

```kotlin
// build.gradle.kts
composeCompiler {
    stabilityConfigurationFiles.add(
        rootProject.layout.projectDirectory.file("compose_stability.conf")
    )
}
```

```
# compose_stability.conf
java.math.BigDecimal
java.time.LocalDate
java.time.Instant
kotlinx.datetime.Instant
kotlinx.datetime.LocalDate
```

Safer than `@Suppress` or wrapping (the promise lives in one reviewable file); more dangerous than annotations (no compile-time check that the type really is immutable). **Only list types you're willing to promise are immutable** — never `java.util.Date`/`Calendar` or anything backed by mutable state, or you get stale UI for the same reason a wrong `@Immutable` does.

### The Five Stability Types in Compiler Reports

The "stable vs unstable" model is too coarse; the compiler emits five classifications, and `runtime stable` in particular is **not a bug**.

| Type | Meaning | Skipping behaviour |
|---|---|---|
| **Certain (stable)** | All properties known-stable at compile time | `equals()` comparison; skips when equal |
| **Runtime (stable)** | Stability depends on an inner type the compiler defers — a per-instance `$stable: Int` field is generated and checked at runtime | `equals()` if the runtime check passes; otherwise falls back to `===` |
| **Unknown** | Interface-typed parameter; concrete impl not visible | `===` (instance equality) — same instance skips |
| **Parameter** | A generic type parameter — depends on the call-site type argument | Resolved per call site |
| **Unstable** | Proven unstable (mutable field outside snapshots) | Strong skipping disabled; runs every time |

The common mistake is treating **runtime stable** as a defect to annotate away. It isn't — the `$stable: Int` field is a valid compile-time-deferred classification. Adding `@Stable` on top only matters when the runtime check produces too many false negatives, and the right diagnostic for that is the inner type, not the wrapper.

**Source verification:** the five types are defined in `androidx/compose/compiler/plugins/kotlin/analysis/Stability.kt`; the runtime `$stable: Int` field is generated by `ClassStabilityTransformer.kt`; the config format is parsed by `StabilityConfigParser.kt`; inference is in `StabilityInferencer.kt`.

---

## Strong Skipping Mode (Default in Kotlin 2.0.20+)

Strong skipping is the default with the compiler shipped in Kotlin 2.0.20+. Drop the old "missing skippable means not skippable" mental model. The rules:

- **Stable parameters** compare with `equals()`. Two equal instances skip.
- **Unstable parameters** compare with `===` (instance equality). The same instance skips; a new instance recomposes — even if `equals()` would return `true`.
- **Lambdas inside composables** are auto-remembered based on their captures. You don't need `remember { { ... } }` to keep an `onClick` stable.

```kotlin
@Composable
fun Counter(count: Int, onClick: () -> Unit) {
    // 'onClick' is auto-remembered; stable across recompositions of the caller
    Button(onClick = onClick) { Text("Count: $count") }
}
```

So a skippable composable that still recomposes is almost always a call-site problem — a fresh `List`, `Modifier` chain, or ad-hoc object on each parent recomposition — not a missing annotation on the callee. Verify the toolchain is recent enough (`kotlin = "2.0.20"` or newer); on older Kotlin the legacy "missing skippable" diagnosis still applies — plan the upgrade rather than papering over it.

### Disabling Strong Skipping

If a module depends on the old semantics during a migration, opt out via the feature-flag DSL (not the deprecated `enableStrongSkippingMode` property):

```kotlin
composeCompiler {
    featureFlags.add(ComposeFeatureFlag.StrongSkipping.disabled())
}
```

Transitional escape hatch only — re-enable as soon as the offending call sites are fixed.

### Strong Skipping Doesn't Reach Non-`@Composable` Scopes

Automatic lambda memoization happens inside `@Composable` functions only. Lambdas allocated in **non-composable scopes** still produce a fresh instance on every parent recomposition:

| Scope | Why it's not memoized |
|---|---|
| `LazyListScope.items { … }` and its item lambdas | `items {}` is a regular Kotlin extension, not a composable |
| `Modifier.pointerInput(key) { … }` | `PointerInputScope.() -> Unit` is a suspend lambda |
| `object : Foo { override fun bar() = { … } }` | Anonymous object literal — Kotlin object scope |
| `Modifier.drawBehind { }`, `drawWithCache { }`, `drawWithContent { }` | `DrawScope.() -> Unit` is a regular lambda |

Hoist these to a stable reference — usually a method reference (`vm::onClick`) or a `remember { ... }`:

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

### Inline Layouts Aren't Skippable

`Row`, `Column`, `Box`, and other inline-marked composables are **not restartable or skippable**. Wrapping a `Row` "to make it skip" is a no-op — the compiler inlines the body into the parent's recomposition scope. The fix for a wasteful `Row` body is making the *parent* skippable so the inline body isn't re-executed.

### Escape Hatches

Reach for these rarely, with a justifying comment at the call site:

| Annotation | Target | Use when |
|---|---|---|
| `@DontMemoize` | A lambda literal (`@Target(EXPRESSION)` — applies to the literal, not the type) | The lambda must allocate every call (fresh `MutableState` initializer, capture that mutates on equality) |
| `@NonSkippableComposable` | A composable function | The body must run every recomposition (telemetry, custom inspectors) |
| `@NonRestartableComposable` | A composable function | The function should inline into the parent's restart scope (library effect helpers) |
| `@ReadOnlyComposable` | A composable function | It only reads `CompositionLocal`s — never invalidates and never invalidates callers (e.g. `MaterialTheme.colorScheme`) |

---

## Defer State Reads to Layout/Draw Phase

Reading state in composition triggers recomposition. Push reads to later phases:

```kotlin
// BAD — reads in composition, recomposes on every offset change
@Composable
fun Box(offsetX: State<Float>) {
    val x = offsetX.value
    Box(modifier = Modifier.offset(x.dp, 0.dp))
}

// GOOD — deferred read in layout phase
@Composable
fun Box(offsetX: State<Float>) {
    Box(modifier = Modifier.offset { IntOffset(offsetX.value.toInt(), 0) })
}
```

### Provider Lambdas Across Composable Boundaries

When state crosses a composable boundary, pass a **provider lambda**, not a snapshot value. Reading the value at the call site recomposes the parent on every change; reading inside the consumer's layout/draw block defers it.

```kotlin
// WRONG — snapshot value crosses the boundary; parent recomposes every frame
@Composable fun HomeScreen(scrollOffset: Int) { HeroImage(scrollOffset = scrollOffset) }

// RIGHT — provider lambda; HeroImage reads inside graphicsLayer's block
@Composable fun HomeScreen(scrollOffsetProvider: () -> Int) { HeroImage(scrollOffsetProvider) }

@Composable
fun HeroImage(scrollOffsetProvider: () -> Int) {
    Image(
        painter = painterResource(R.drawable.hero), contentDescription = null,
        modifier = Modifier.graphicsLayer { translationY = -scrollOffsetProvider() / 2f },
    )
}
```

The read happens inside `graphicsLayer { ... }` (draw phase), so the state read is recorded against the draw scope — changes invalidate only the layer, not `HeroImage` or `HomeScreen`.

**The `by` delegate is the smell.** `val offset by scrollOffsetState` unwraps the snapshot at the read site. Keep the value as `State<T>` (or `() -> T`) so it can cross the boundary as a provider; once unwrapped, the only fix is re-wrapping.

**Deferral sites** (reads stay out of composition), latest phase first:
- `Modifier.graphicsLayer { }` — draw phase, cheapest (translation/rotation/alpha, no relayout)
- `Modifier.offset { }` / `Modifier.layout { }` — layout phase (when child position affects siblings)
- `drawWithContent` / `drawBehind` / `drawWithCache` — draw phase (raw drawing)
- custom `Alignment.align(...)` — layout phase

---

## derivedStateOf — Reducing Recomposition Frequency

When deriving an expensive computation from state, wrap in `derivedStateOf` to dedup downstream recompositions — two different inputs yielding the same result trigger only one downstream recomposition:

```kotlin
// BAD — filters (and recomposes) on every items/query change
val filtered = items.filter { query in it.title }

// GOOD — recomposes only when the filtered result actually changes
val filtered = remember(items, query) { derivedStateOf { items.filter { query in it.title } } }
LazyColumn { items(filtered.value) { /* ... */ } }
```

---

## remember with Keys — Configuration-Local Gotcha

`remember` only for mutable state or expensive calculations — omit it for cheap work (string formatting, simple objects); over-wrapping costs memory. The non-obvious trap: if a `remember { }` body reads `LocalConfiguration`, `LocalDensity`, `LocalLayoutDirection`, or `LocalContext`, those **must** be in the key list, or the cached value silently goes stale on rotation, font-scale change, foldable posture, RTL flip, or density change.

```kotlin
// WRONG — caches once at first composition; stays wrong forever after rotation
val columns = remember {
    val width = LocalConfiguration.current.screenWidthDp
    if (width >= 840) 3 else if (width >= 600) 2 else 1
}

// RIGHT — key on the local that drives the computation
val configuration = LocalConfiguration.current
val columns = remember(configuration) {
    val width = configuration.screenWidthDp
    if (width >= 840) 3 else if (width >= 600) 2 else 1
}
```

---

## LazyList Performance

Always provide `key` (enables item reuse and animations) and `contentType` for heterogeneous lists (without it, all items compete for one reuse pool):

```kotlin
LazyColumn {
    items(items, key = { it.id }, contentType = { it.type }) { item -> /* ... */ }
}
```

### Stabilize Per-Item Lambdas with `remember(item.id)`

An item lambda that captures a per-item value (the item, an index, a per-item callback) is allocated fresh on every scroll, defeating strong-skipping for the row. Key it by stable id:

```kotlin
// WRONG — fresh lambda every scroll; ItemRow re-runs even though `item` didn't change
items(items, key = { it.id }) { item -> ItemRow(item, onClick = { onItemClick(item) }) }

// RIGHT — lambda keyed by stable id, remembered per item
items(items, key = { it.id }) { item ->
    val onClick = remember(item.id) { { onItemClick(item) } }
    ItemRow(item, onClick = onClick)
}
```

### Prefetch and Cache Window (Foundation 1.9+ / 1.10+)

Lazy layouts compose just outside the viewport during scroll to keep frame budget steady. Foundation 1.9+ exposes `LazyLayoutCacheWindow(ahead, behind)`; 1.10+ makes prefetch pausable under frame-deadline pressure.

```kotlin
@OptIn(ExperimentalFoundationApi::class)
val state = rememberLazyListState(cacheWindow = LazyLayoutCacheWindow(ahead = 2, behind = 1))
```

Tune `ahead` higher for tall items with slow images, lower (or 0) when items are cheap and prefetch bloats memory — touch this only when a profiler shows item composition spiking under scroll. For nested lazy layouts (a `LazyRow` per `LazyColumn` item), `NestedPrefetchScope` lets the outer list trigger inner prefetch ahead of the outer item entering composition.

---

## Subcomposition Pitfalls

`SubcomposeLayout`, `BoxWithConstraints`, and `Scaffold` run a composition pass *during the measure phase* with a slot that depends on layout constraints. Powerful when needed; expensive when stacked.

### `BoxWithConstraints` inside a `LazyColumn` item

The highest-cost shape — every visible item runs its own subcomposition during measurement on every scroll:

```kotlin
// WRONG — subcomposition per visible item, on every scroll
LazyColumn {
    items(items, key = { it.id }) { item ->
        BoxWithConstraints { if (maxWidth < 320.dp) CompactRow(item) else WideRow(item) }
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

### Nested `Scaffold`

`Scaffold` is a `SubcomposeLayout` — it subcomposes top bar, bottom bar, FAB, and content independently to measure inset padding. Nesting one inside another's content slot doubles the work and produces inset/padding bugs that look like spacing-arithmetic errors. Use one screen-level `Scaffold` per route; for nested sections, build from plain `Column` + `TopAppBar`.

### Reuse with `SubcomposeSlotReusePolicy`

When authoring a custom `SubcomposeLayout`, cap the reuse pool so old slot state isn't held indefinitely:

```kotlin
SubcomposeLayout(
    slotReusePolicy = SubcomposeSlotReusePolicy(maxSlotsToRetainForReuse = 4),
) { constraints -> /* subcompose(...).first().measure(constraints) */ }
```

For latency-sensitive content (a heavy section on a tab switch), `state.precompose(slotId, content)` composes ahead of the measure phase (`SubcomposeLayoutState`, Foundation 1.6+). **Lint signal:** AndroidX's internal `ComposableLambdaInMeasurePolicy` flags fresh composable lambdas allocated inside `subcompose(slotId)` blocks — hoist the lambda so the slot identity stays stable.

**Source verification:** `SubcomposeLayout.kt`, `BoxWithConstraints.kt`, `Scaffold.kt` in `androidx.compose.foundation` / `androidx.compose.material3`.

---

## Baseline Profiles

Baseline profiles tell R8 to pre-compile hot paths, cutting startup time and jank. Record with Jetpack Macrobenchmark (`MacrobenchmarkRule` + `measureRepeated`); profiles land in `baseline-prof.txt`.

### `BaselineProfileMode.Require` vs `UseIfAvailable`

When a measurement assumes a profile is installed, set `CompilationMode.Partial(baselineProfileMode = BaselineProfileMode.Require)`. The default `UseIfAvailable` **silently falls back** to measuring an unprofiled build when no profile is detected — producing CI numbers that look fine and lie about what users get.

```kotlin
benchmarkRule.measureRepeated(
    packageName = "com.example.app",
    metrics = listOf(FrameTimingMetric()),
    iterations = 10,
    compilationMode = CompilationMode.Partial(baselineProfileMode = BaselineProfileMode.Require),
) { /* interact */ }
```

In CI, `Require` turns a missing-profile bug into a loud failure — exactly what you want reviewing a baseline-profile PR.

---

## Measuring Performance

**Layout Inspector → Show Composition Counts** (Tools > Layout Inspector, toggle in inspector) displays per-composable recomposition counts.

### Argument Change Reasons (Android Studio Hedgehog+)

The **Composition state** column classifies each parameter — map status to fix instead of guessing:

| Status | Meaning | Likely fix |
|---|---|---|
| **Changed** | Parameter actually has a new value | The cause — check whether the upstream value should change this often |
| **Unchanged** | Equal, no contribution | Skip — not the source |
| **Uncertain** | Couldn't determine equality (unstable type, instance-equality fallback) | Stabilize the type so equality is meaningful |
| **Static** | Compile-time constant | Skip |
| **Unknown** | Interface-typed; concrete type hidden | Expose a stable concrete type, or ensure callers reuse instances |

Most "why is this recomposing?" investigations resolve at **Uncertain** — an unstable type forces instance-equality, callers create new instances every parent recomposition, the composable runs every time. Fix the type; don't memoize the caller.

For headless/CLI workflows, `android layout --diff --pretty` between two app states gives a JSON tree of changed nodes; combine with `SideEffect { Log.d(...) }` counters to correlate diffs with hot paths. **Macrobenchmark** `FrameTimingMetric()` reports frame times — target <16.67 ms for 60 fps.

---

## Symptom → Diagnosis → Fix

The same surface symptom ("too many recompositions") routes to different fixes by axis. Reach for this before guessing stability vs phase:

| Symptom | Diagnosis | Fix |
|---|---|---|
| Composable skips poorly despite strong skipping | New unstable instance each recomposition | Remember, hoist, or make the type stable |
| Draw block recomposes every frame | Value read before draw block | Move `State.value` read inside the draw block; use a provider lambda across boundaries |
| Regression after adding a type to a data class | Cross-module type is unstable | Add to `stabilityConfigurationFiles` or annotate `@Immutable` |
| LazyColumn item recomposes on every scroll | Lambda captured from parent | Cache with `remember(item.id)` or hoist the source out of the item |
| Animation triggers recomposition per frame | Animated state read in composition | Read inside `graphicsLayer { }` or `offset { }` |

**Anti-patterns:** wrapping cheap values in `remember`; adding `derivedStateOf`/`remember` without Layout Inspector data (profile first); `@Stable` on a data class with a `MutableState` field (use `@Immutable` on a fully-immutable type instead).

---

## Other Techniques

**`movableContentOf`** — move content between layout positions without disposing/recomposing it (preserves state):

```kotlin
val movableContent = remember { movableContentOf { ExpensiveChild() } }
if (isExpanded) ExpandedLayout { movableContent() } else CollapsedLayout { movableContent() }
```

**Composition tracing** — `trace("ExpensiveScreen") { /* body */ }` surfaces slow composables in Perfetto/systrace without logging.

**`ReportDrawnWhen { items.isNotEmpty() }`** — marks first meaningful draw for startup metrics.

**R8** — keep `minifyEnabled`/`shrinkResources` on; Compose ships default rules. Strip preview tooling in release: `-assumenosideeffects class androidx.compose.ui.tooling.preview.** { *; }`.

**Zero-size DrawScope guard** — a composable's size can be zero during initial composition; guard divide-by-size math, and never `fillMaxSize()` a `Canvas` without a height constraint:

```kotlin
Canvas(Modifier.fillMaxWidth().height(200.dp)) {
    if (size.minDimension <= 0f) return@Canvas
    drawCircle(color = Color.Blue, radius = size.minDimension / 2)
}
```

---

## Compose Multiplatform Performance

Tooling availability differs by platform:

| Tool | Android | Desktop | iOS | Web |
|------|---------|---------|-----|-----|
| Baseline Profiles / Macrobenchmark / Layout Inspector | Yes | No | No | No |
| Profiling | Android Studio | JMH | Instruments | Browser DevTools |
| R8/ProGuard | Yes | ProGuard separately | N/A (Kotlin/Native) | N/A |

iOS: Kotlin/Native GC differs from ART; enable ProMotion via `CADisableMinimumFrameDurationOnPhone = true` in Info.plist. Web/WASM: the whole canvas redraws per frame (no DOM partial repaint), and bundle size drives initial load.

---

## Resources

- Compiler reports / stability: https://developer.android.com/develop/ui/compose/performance/stability-report
- Measurement: https://developer.android.com/develop/ui/compose/performance/measurement
- Baseline profiles: https://developer.android.com/develop/ui/compose/performance/baseline-profiles
- Strong skipping: https://developer.android.com/develop/ui/compose/performance/stability/strongskipping
- Stability configuration: https://developer.android.com/develop/ui/compose/performance/stability/fix#configuration-file
