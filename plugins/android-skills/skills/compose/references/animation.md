# Animation in Jetpack Compose

Reference: `androidx/compose/animation/animation/src/commonMain/kotlin/androidx/compose/animation/`

## State-Based Animations

### animate*AsState

Animate individual properties by targeting a value. The animation starts when the value changes.

```kotlin
val size by animateDpAsState(
    targetValue = if (isExpanded) 200.dp else 100.dp,
    animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy),
    label = "size"
)

Box(modifier = Modifier.size(size))
```

Common variants:

```kotlin
animateColorAsState(targetValue = Color.Blue)
animateFloatAsState(targetValue = 1f)
animateIntAsState(targetValue = 100)
animateOffsetAsState(targetValue = Offset(10f, 20f))
```

Each automatically handles coroutines and recomposition. Use the `label` parameter for debugging.

## AnimatedVisibility

Controls appear/disappear animations with enter and exit transitions.

```kotlin
var visible by remember { mutableStateOf(true) }

AnimatedVisibility(visible = visible) {
    Text("Hello!")
}

// Trigger
Button(onClick = { visible = !visible }) { Text("Toggle") }
```

### Enter/Exit Transitions

```kotlin
AnimatedVisibility(
    visible = visible,
    enter = slideInHorizontally(initialOffsetX = { -it }) + fadeIn(),
    exit = slideOutHorizontally(targetOffsetX = { -it }) + fadeOut()
) {
    Text("Animated!")
}
```

Built-in transitions:
- `slideInVertically`, `slideOutVertically`
- `slideInHorizontally`, `slideOutHorizontally`
- `expandVertically`, `shrinkVertically`
- `expandHorizontally`, `shrinkHorizontally`
- `fadeIn`, `fadeOut`
- `scaleIn`, `scaleOut`
- Combine with `+`: `slideInVertically() + fadeIn()`

### Advanced: Custom animation specs

```kotlin
AnimatedVisibility(
    visible = visible,
    enter = slideInVertically(
        initialOffsetY = { fullHeight -> fullHeight },
        animationSpec = spring()
    ),
    exit = slideOutVertically(
        targetOffsetY = { fullHeight -> fullHeight },
        animationSpec = tween(durationMillis = 300)
    )
) {
    Box(Modifier.fillMaxWidth().height(100.dp).background(Color.Blue))
}
```

## AnimatedContent

Replace content with smooth transitions.

```kotlin
var count by remember { mutableStateOf(0) }

AnimatedContent(targetState = count) { target ->
    Text(text = "Count: $target")
}

Button(onClick = { count++ }) { Text("Increment") }
```

### Custom transitionSpec

```kotlin
AnimatedContent(
    targetState = count,
    transitionSpec = {
        slideInVertically(initialOffsetY = { it }) with slideOutVertically(targetOffsetY = { -it })
    }
) { target ->
    Text("$target")
}
```

Use `with` to specify exit and enter together. This runs exits and entries simultaneously.

### Sequencing transitions

```kotlin
AnimatedContent(
    targetState = count,
    transitionSpec = {
        slideInVertically(initialOffsetY = { it }) with slideOutVertically(targetOffsetY = { -it }) using SizeTransform(clip = false)
    }
) { target ->
    Text(
        "Count: $target",
        modifier = Modifier.fillMaxWidth()
    )
}
```

`SizeTransform` animates container size smoothly during content changes.

### contentKey for sealed UiState / Result wrappers

**For sealed wrappers like `UiState` or `Result<T>`, key `AnimatedContent` on shape, not payload.** `AnimatedContent` re-triggers transitions on every `targetState` change — but payload changes within the same shape (e.g., `Success(items=[1,2,3])` → `Success(items=[1,2,3,4])`) shouldn't cause cross-fades.

```kotlin
AnimatedContent(
    targetState = uiState,
    contentKey = { state ->
        when (state) {
            is UiState.Loading -> "loading"
            is UiState.Success -> "success"  // every Success state shares the key
            is UiState.Error -> "error"
        }
    },
    label = "uiState",
) { state ->
    when (state) {
        is UiState.Loading -> LoadingScreen()
        is UiState.Success -> SuccessScreen(state.data)
        is UiState.Error -> ErrorScreen(state.message)
    }
}
```

Now cross-fade fires only on Loading↔Success↔Error transitions, never on Success-payload updates.

## Crossfade

Simple content swap with fade effect.

```kotlin
var showFirst by remember { mutableStateOf(true) }

Crossfade(targetState = showFirst) { state ->
    if (state) {
        Text("First")
    } else {
        Text("Second")
    }
}
```

Lightweight alternative to `AnimatedContent` for simple visibility toggles.

## updateTransition

**Prefer `rememberTransition` over `updateTransition` for new code.** Both coordinate multiple animated values from one state, but `rememberTransition` is the preferred API in current Compose — it accepts a `MutableTransitionState` for fine-grained start/end control and reuses transition state across navigation. `updateTransition` is retained for source compatibility.

```kotlin
// PREFERRED — rememberTransition with explicit MutableTransitionState
val transitionState = remember { MutableTransitionState(false) }.apply {
    targetState = expanded
}
val transition = rememberTransition(transitionState, label = "expand")
val size by transition.animateDp(label = "size") { if (it) 200.dp else 100.dp }
val color by transition.animateColor(label = "color") { if (it) Color.Blue else Color.Red }
```

Legacy form, still works:

```kotlin
var expanded by remember { mutableStateOf(false) }
val transition = updateTransition(targetState = expanded)

val size by transition.animateDp { if (it) 200.dp else 100.dp }
val color by transition.animateColor { if (it) Color.Blue else Color.Red }

Box(
    modifier = Modifier
        .size(size)
        .background(color)
        .clickable { expanded = !expanded }
)
```

All animations run in sync, controlled by a single state change. Useful for complex components with multiple animated properties.

## rememberInfiniteTransition

Create looping animations.

```kotlin
val infiniteTransition = rememberInfiniteTransition(label = "infinite")

val alpha by infiniteTransition.animateFloat(
    initialValue = 0f,
    targetValue = 1f,
    animationSpec = infiniteRepeatable(
        animation = tween(1000),
        repeatMode = RepeatMode.Reverse
    ),
    label = "alpha"
)

Text("Pulsing", modifier = Modifier.alpha(alpha))
```

Runs continuously until the composable is removed. Perfect for loading states, pulsing indicators.

## Animatable

Imperative animation control in coroutines. Use for fine-grained control.

```kotlin
val animatable = remember { Animatable(0f) }

LaunchedEffect(trigger) {
    animatable.animateTo(
        targetValue = 100f,
        animationSpec = spring()
    )
}

Box(Modifier.graphicsLayer(translationX = animatable.value))
```

Useful for responding to gestures or complex conditions:

```kotlin
val animatable = remember { Animatable(0f) }

LaunchedEffect(Unit) {
    animatable.animateTo(targetValue = 360f, animationSpec = tween(2000))
}

Box(
    Modifier
        .size(100.dp)
        .background(Color.Blue)
        .graphicsLayer(rotationZ = animatable.value)
)
```

## Animation Specifications

### spring — Realistic, physics-based

```kotlin
val size by animateDpAsState(
    targetValue = 200.dp,
    animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow)
)
```

- `dampingRatio`: `NoBouncy` (1f), `LowBouncy` (0.75f), `MediumBouncy` (0.5f), `HighBouncy` (0.2f)
- `stiffness`: `Low`, `Medium`, `High`

Use for interactive feedback, familiar to users.

### tween — Time-based

```kotlin
val color by animateColorAsState(
    targetValue = Color.Blue,
    animationSpec = tween(durationMillis = 500, easing = EaseInOutCubic)
)
```

Easing functions: `EaseInQuad`, `EaseOutQuad`, `EaseInOutQuad`, `LinearEasing`, `FastOutSlowInEasing`.

Predictable timing, good for sequential animations.

### keyframes — Frame-by-frame control

```kotlin
val position by animateFloatAsState(
    targetValue = 100f,
    animationSpec = keyframes {
        0f at 0 using EaseInQuad
        50f at 150 using EaseOutQuad
        100f at 300
    }
)
```

Define exact values at specific timestamps. Use for complex choreography.

## Automatic Size Animation

### animateContentSize

Smoothly animate Box size when content changes.

```kotlin
var expanded by remember { mutableStateOf(false) }

Box(
    modifier = Modifier
        .animateContentSize()
        .background(Color.Blue)
        .clickable { expanded = !expanded }
) {
    Column {
        Text("Header")
        if (expanded) {
            Text("Expanded content...")
        }
    }
}
```

No need for explicit `AnimatedVisibility` or layout transitions. Handles the container automatically.

## Layout Animation in LazyLists

### animateItem — Replaces animateItemPlacement

Animate item appearance, removal, and reordering.

```kotlin
LazyColumn {
    items(items, key = { it.id }) { item ->
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .animateItem()
                .padding(8.dp)
                .background(Color.Gray)
        ) {
            Text(item.name)
        }
    }
}
```

Automatically animates:
- New items sliding in
- Removed items sliding out
- Reordered items moving to new positions

Called on items in Lazy layouts (LazyColumn, LazyRow, LazyVerticalGrid).

## Anti-Patterns

### Don't: Animate visibility with if

```kotlin
// ❌ Anti-pattern
@Composable
fun MyScreen() {
    if (visible) {
        Text("Content") // Jumps in/out without animation
    }
}

// ✅ Correct
@Composable
fun MyScreen() {
    AnimatedVisibility(visible = visible) {
        Text("Content")
    }
}
```

### Don't: Create Animatable in composition

```kotlin
// ❌ Anti-pattern
@Composable
fun MyScreen() {
    val animatable = Animatable(0f) // Recreated every recomposition!

    LaunchedEffect(Unit) {
        animatable.animateTo(100f)
    }
}

// ✅ Correct
@Composable
fun MyScreen() {
    val animatable = remember { Animatable(0f) } // Preserved across recompositions

    LaunchedEffect(Unit) {
        animatable.animateTo(100f)
    }
}
```

### Don't: Animate in composition phase

```kotlin
// ❌ Anti-pattern
@Composable
fun MyScreen() {
    var position by remember { mutableStateOf(0f) }
    position = position + 10f // Infinite recomposition loop!
}

// ✅ Correct
@Composable
fun MyScreen() {
    var position by remember { mutableStateOf(0f) }

    LaunchedEffect(Unit) {
        repeat(10) {
            position += 10f
            delay(16)
        }
    }
}
```

### Don't: Forget label parameter

```kotlin
// ❌ Anti-pattern (harder to debug)
val size by animateDpAsState(targetValue = 100.dp)

// ✅ Correct
val size by animateDpAsState(
    targetValue = 100.dp,
    label = "box_size"
)
```

Labels help with debugging layout inspector and animation inspection tools.

---

## Animation Decision Tree

### When to Use Which API

| API | Use When |
|---|---|
| `animate*AsState` | Animating a single property (size, color, alpha) driven by state |
| `AnimatedVisibility` | Showing or hiding a composable with enter/exit transitions |
| `AnimatedContent` / `Crossfade` | Switching between different composables (content swap) |
| `updateTransition` | Multiple properties that must animate in sync from the same state |
| `Animatable` | Gesture-driven or imperative control (coroutine-based, supports `snapTo`, `animateDecay`) |
| `rememberInfiniteTransition` | Infinite looping animations (pulsing, rotating, shimmer) |
| `animateContentSize` | Smoothly animating a container's size when its content changes |
| `animateItem` | List item appearance, disappearance, and reordering in Lazy layouts |

### Which Phase Each Animation Affects

Compose rendering has three phases: **Composition** (what to show), **Layout** (where to place), **Draw** (how to render). Animations should read state in the latest possible phase to minimize work.

```kotlin
// BEST: Draw phase only — no relayout, no recomposition
val alpha by animateFloatAsState(targetValue = if (visible) 1f else 0f, label = "alpha")
Box(
    modifier = Modifier.graphicsLayer { this.alpha = alpha }
)

// GOOD: Layout phase only — relayout but no recomposition
val offsetPx by animateIntAsState(targetValue = if (moved) 300 else 0, label = "offset")
Box(
    modifier = Modifier.offset { IntOffset(offsetPx, 0) }
)

// MODERATE: Composition + Layout — triggers recomposition on every frame
val offsetDp by animateDpAsState(targetValue = if (moved) 100.dp else 0.dp, label = "offset")
Box(
    modifier = Modifier.offset(x = offsetDp)
)
```

**Rule:** Defer state reads to the latest possible phase. Use lambda-based modifiers (`graphicsLayer { }`, `offset { }`) instead of parameter-based modifiers (`graphicsLayer(alpha = ...)`, `offset(x = ...)`).

For state that needs to cross composable boundaries (e.g., `scrollOffset` from parent to child), pass a provider lambda (`scrollOffsetProvider: () -> Int`) instead of a snapshot value, and read it inside `graphicsLayer { translationY = ... }`. See `compose/references/performance.md` for the full pattern.

---

## Design-to-Animation Translation

### Figma Easing Curves to Compose

| Figma Easing | Compose Equivalent |
|---|---|
| Linear | `LinearEasing` |
| Ease In | `FastOutLinearInEasing` |
| Ease Out | `LinearOutSlowInEasing` |
| Ease In and Out | `FastOutSlowInEasing` |
| Custom Bezier (x1, y1, x2, y2) | `CubicBezierEasing(x1, y1, x2, y2)` |

### M3 Motion Duration Tokens

| Token | Duration |
|---|---|
| Short1 | 50ms |
| Short2 | 100ms |
| Short3 | 150ms |
| Short4 | 200ms |
| Medium1 | 250ms |
| Medium2 | 300ms |
| Medium3 | 350ms |
| Medium4 | 400ms |
| Long1 | 450ms |
| Long2 | 500ms |
| Long3 | 550ms |
| Long4 | 600ms |
| ExtraLong1 | 700ms |
| ExtraLong2 | 800ms |
| ExtraLong3 | 900ms |
| ExtraLong4 | 1000ms |

### M3 Easing Tokens

| Token | Compose Value |
|---|---|
| Emphasized | `CubicBezierEasing(0.2f, 0f, 0f, 1f)` |
| EmphasizedDecelerate | `CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)` |
| EmphasizedAccelerate | `CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)` |
| Standard | `FastOutSlowInEasing` |
| StandardDecelerate | `LinearOutSlowInEasing` |
| StandardAccelerate | `FastOutLinearInEasing` |

### Spring Parameter Intuition

**Stiffness** (how fast the animation moves toward its target):

| Value | Constant | Feel |
|---|---|---|
| ~26f | — | Slow, heavy, lethargic |
| 200f | `Spring.StiffnessLow` | Gentle, relaxed |
| 400f | `Spring.StiffnessMediumLow` | Casual, comfortable |
| 1500f | `Spring.StiffnessMedium` | Responsive, default |
| 10000f | `Spring.StiffnessHigh` | Snappy, immediate |

**Damping Ratio** (how much bounce):

| Value | Constant | Feel |
|---|---|---|
| 1.0f | `Spring.DampingRatioNoBouncy` | No overshoot, settles directly |
| 0.75f | `Spring.DampingRatioLowBouncy` | Subtle bounce, professional |
| 0.5f | `Spring.DampingRatioMediumBouncy` | Playful, noticeable bounce |
| 0.2f | `Spring.DampingRatioHighBouncy` | Exaggerated, cartoonish bounce |

### Figma Spring to Compose Conversion

```kotlin
fun figmaSpringToCompose(mass: Float, stiffness: Float, damping: Float): SpringSpec<Float> {
    val dampingRatio = damping / (2f * sqrt(stiffness * mass))
    return spring(dampingRatio = dampingRatio, stiffness = stiffness)
}
```

### Production-Validated Spring Specs

```kotlin
val figmaMatchedSpring = spring<Float>(dampingRatio = 0.444f, stiffness = 26.5f)
val responsiveSpring = spring<Float>(dampingRatio = 0.7f, stiffness = 800f)
val snappySpring = spring<Float>(dampingRatio = 0.6f, stiffness = 1000f)
```

---

## Additional Anti-Patterns

### Don't: Read animated state in composition when draw-phase suffices

```kotlin
// BAD: Reads alpha during composition, triggers recomposition every frame
val alpha by animateFloatAsState(targetValue = 0.5f, label = "alpha")
Box(modifier = Modifier.alpha(alpha))

// GOOD: Reads alpha during draw phase only, skips recomposition
val alpha by animateFloatAsState(targetValue = 0.5f, label = "alpha")
Box(modifier = Modifier.graphicsLayer { this.alpha = alpha })
```

### Don't: Use offset(x, y) for animated movement

```kotlin
// BAD: Parameter-based offset triggers recomposition + relayout
val animatedDp by animateDpAsState(targetValue = 100.dp, label = "x")
Box(modifier = Modifier.offset(x = animatedDp))

// BETTER: Lambda offset — layout phase only, no recomposition
val animatedPx by animateIntAsState(targetValue = 300, label = "x")
Box(modifier = Modifier.offset { IntOffset(animatedPx, 0) })

// BEST: graphicsLayer — draw phase only
val animatedPx by animateFloatAsState(targetValue = 300f, label = "x")
Box(modifier = Modifier.graphicsLayer { translationX = animatedPx })
```

### Don't: Use updateTransition for independent properties

```kotlin
// BAD: Properties don't need synchronization but are coupled
val transition = updateTransition(targetState = state, label = "t")
val alpha by transition.animateFloat(label = "a") { if (it) 1f else 0f }
val size by transition.animateDp(label = "s") { if (it) 200.dp else 100.dp }

// GOOD: Independent properties use separate animate*AsState
val alpha by animateFloatAsState(targetValue = if (state) 1f else 0f, label = "alpha")
val size by animateDpAsState(targetValue = if (state) 200.dp else 100.dp, label = "size")
```

### Don't: Hardcode arbitrary durations

```kotlin
// BAD: Arbitrary duration with no design rationale
val anim by animateFloatAsState(
    targetValue = 1f,
    animationSpec = tween(durationMillis = 347),
    label = "anim"
)

// GOOD: Use M3 motion tokens for consistency
val anim by animateFloatAsState(
    targetValue = 1f,
    animationSpec = tween(durationMillis = MotionTokens.DurationMedium2.toInt()),
    label = "anim"
)

// BETTER: Use spring() for interruptible, natural-feeling animations
val anim by animateFloatAsState(
    targetValue = 1f,
    animationSpec = spring(stiffness = Spring.StiffnessMedium),
    label = "anim"
)
```

### Don't: Bolt AnimatedContent on top of Navigation destination swaps

**Navigation Compose already animates between destinations** (`NavHost.enterTransition` / `exitTransition` / `popEnterTransition` / `popExitTransition`). Wrapping the destination's content in `AnimatedContent` produces double-animations — the destination swaps, then the new content cross-fades on top of the swap.

The same holds for **Navigation 3**: `NavDisplay` owns its destination transitions, so don't wrap a Nav3 destination's whole content in `AnimatedContent` either. See `references/navigation.md`.

```kotlin
// WRONG — double-animate
NavHost(navController, startDestination = "list") {
    composable("list") {
        AnimatedContent(targetState = uiState) { ... }  // animates inside an already-animating destination
    }
}

// RIGHT — let NavHost own destination transitions; use AnimatedContent for intra-destination state only
NavHost(
    navController = navController,
    startDestination = "list",
    enterTransition = { slideInHorizontally { it } + fadeIn() },
    exitTransition = { slideOutHorizontally { -it / 3 } + fadeOut() },
) {
    composable("list") { ListScreen(...) }  // no nested AnimatedContent over the whole screen
}
```
