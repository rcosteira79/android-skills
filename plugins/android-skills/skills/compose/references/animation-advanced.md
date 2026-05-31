# Advanced Animation in Jetpack Compose

Advanced patterns: shared element transitions, `graphicsLayer`-based performance optimisations, gesture-driven animations, and predictive-back integration. For primitives, specs, and the decision tree, see [animation.md](animation.md). For recipe cookbook + choreography, see [animation-recipes.md](animation-recipes.md).

## Shared Element Transitions

Animate elements seamlessly across screen boundaries using `SharedTransitionLayout` and Navigation Compose.

### sharedElement() vs sharedBounds()

| Aspect | `sharedElement()` | `sharedBounds()` |
|---|---|---|
| **Content** | Identical on both screens (same image, same icon) | Different content in source and target (e.g., card expands to detail) |
| **Use case** | Hero image, avatar, thumbnail | Container transform, card-to-page |
| **During transition** | Only the target composable is rendered | Both source and target are visible and crossfade |

### Complete Working Example

```kotlin
@Composable
fun App() {
    SharedTransitionLayout {
        NavHost(navController = navController, startDestination = "list") {
            composable("list") {
                ListScreen(
                    onItemClick = { id -> navController.navigate("detail/$id") },
                    sharedTransitionScope = this@SharedTransitionLayout,
                    animatedVisibilityScope = this@composable
                )
            }
            composable("detail/{id}") { backStackEntry ->
                val id = backStackEntry.arguments?.getString("id") ?: return@composable
                DetailScreen(
                    itemId = id,
                    sharedTransitionScope = this@SharedTransitionLayout,
                    animatedVisibilityScope = this@composable
                )
            }
        }
    }
}

@Composable
fun ListScreen(
    onItemClick: (String) -> Unit,
    sharedTransitionScope: SharedTransitionScope,
    animatedVisibilityScope: AnimatedVisibilityScope
) {
    with(sharedTransitionScope) {
        Row(
            modifier = Modifier
                .clickable { onItemClick(item.id) }
                // sharedBounds wraps the entire card container (different content at source/target)
                .sharedBounds(
                    sharedContentState = rememberSharedContentState(key = "card-${item.id}"),
                    animatedVisibilityScope = animatedVisibilityScope,
                    boundsTransform = BoundsTransform { initialBounds, targetBounds ->
                        keyframes {
                            durationMillis = 500
                            initialBounds at 0 using ArcMode.ArcBelow
                            targetBounds at 500
                        }
                    }
                )
        ) {
            Image(
                painter = painterResource(item.imageRes),
                contentDescription = null,
                modifier = Modifier
                    .size(80.dp)
                    // sharedElement for the identical image across screens
                    .sharedElement(
                        state = rememberSharedContentState(key = "image-${item.id}"),
                        animatedVisibilityScope = animatedVisibilityScope
                    )
            )
            Text(
                text = item.title,
                modifier = Modifier
                    .sharedElement(
                        state = rememberSharedContentState(key = "title-${item.id}"),
                        animatedVisibilityScope = animatedVisibilityScope
                    )
                    // Prevent text reflow during transition by snapping to final size
                    .skipToLookaheadSize()
            )
        }
    }
}

@Composable
fun DetailScreen(
    itemId: String,
    sharedTransitionScope: SharedTransitionScope,
    animatedVisibilityScope: AnimatedVisibilityScope
) {
    with(sharedTransitionScope) {
        Column(
            modifier = Modifier
                .sharedBounds(
                    sharedContentState = rememberSharedContentState(key = "card-$itemId"),
                    animatedVisibilityScope = animatedVisibilityScope
                )
        ) {
            Image(
                painter = painterResource(item.imageRes),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp)
                    .sharedElement(
                        state = rememberSharedContentState(key = "image-$itemId"),
                        animatedVisibilityScope = animatedVisibilityScope
                    )
            )
            Text(
                text = item.title,
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier
                    .sharedElement(
                        state = rememberSharedContentState(key = "title-$itemId"),
                        animatedVisibilityScope = animatedVisibilityScope
                    )
                    .skipToLookaheadSize()
            )
            // Non-shared content fades in
            Text(
                text = item.description,
                modifier = Modifier.animateEnterExit(
                    enter = fadeIn() + slideInVertically { it / 3 },
                    exit = fadeOut()
                )
            )
        }
    }
}
```

### BoundsTransform for Arc Motion

Control the animation path between source and target bounds:

```kotlin
val arcBoundsTransform = BoundsTransform { initialBounds, targetBounds ->
    keyframes {
        durationMillis = 500
        initialBounds at 0 using ArcMode.ArcBelow
        targetBounds at 500
    }
}

// Apply to sharedElement or sharedBounds
Modifier.sharedElement(
    state = rememberSharedContentState(key = "hero"),
    animatedVisibilityScope = animatedVisibilityScope,
    boundsTransform = arcBoundsTransform
)
```

### Overlay Rendering

Keep shared elements above all other content during the transition:

```kotlin
Modifier.sharedElement(
    state = rememberSharedContentState(key = "fab"),
    animatedVisibilityScope = animatedVisibilityScope,
    renderInSharedTransitionScopeOverlay = true // Renders above navigation transitions
)
```

### Preventing Text Reflow

Use `skipToLookaheadSize()` so text composables snap to their final size immediately, avoiding awkward line-break changes mid-transition:

```kotlin
Text(
    text = item.title,
    modifier = Modifier
        .sharedElement(
            state = rememberSharedContentState(key = "title-${item.id}"),
            animatedVisibilityScope = animatedVisibilityScope
        )
        .skipToLookaheadSize() // Text uses target size immediately, no reflow
)
```

## Performance: graphicsLayer for Transforms

Animate transforms using `graphicsLayer` instead of layout changes.

```kotlin
// ✅ Correct: Uses GPU-accelerated graphicsLayer
val offset by animateFloatAsState(targetValue = 100f)
Box(modifier = Modifier.graphicsLayer(translationX = offset))

// ❌ Avoid: Causes recomposition and relayout
val offset by animateFloatAsState(targetValue = 100f)
Box(modifier = Modifier.offset(x = offset.dp))
```

Use `graphicsLayer` for:
- Translation (`translationX`, `translationY`)
- Rotation (`rotationX`, `rotationY`, `rotationZ`)
- Scale (`scaleX`, `scaleY`)
- Alpha (opacity)

### drawBehind for Animated Background Colors

**For animated background colors, use `drawBehind { drawRect(...) }` instead of `Modifier.background(color)`.** `Modifier.background(color)` reads `color` during composition — every animated frame triggers recomposition. `drawBehind` reads in the draw phase only.

```kotlin
// SLOWER — animated color forces composition every frame
val color by animateColorAsState(if (selected) Color.Blue else Color.Gray, label = "bg")
Box(modifier = Modifier.background(color))

// FASTER — color read in draw phase only
val color by animateColorAsState(if (selected) Color.Blue else Color.Gray, label = "bg")
Box(modifier = Modifier.drawBehind { drawRect(color) })
```

## Gesture-Driven Animations

### Swipe-to-Dismiss with Animatable

```kotlin
fun Modifier.swipeToDismiss(onDismiss: () -> Unit): Modifier = composed {
    val offsetX = remember { Animatable(0f) }
    val decay = rememberSplineBasedDecay<Float>()

    pointerInput(Unit) {
        coroutineScope {
            while (true) {
                val velocityTracker = VelocityTracker()
                // Wait for touch down
                val pointerId = awaitPointerEventScope {
                    awaitFirstDown().id
                }
                // Cancel any ongoing animation
                offsetX.stop()

                awaitPointerEventScope {
                    horizontalDrag(pointerId) { change ->
                        val horizontalDragOffset = offsetX.value + change.positionChange().x
                        launch { offsetX.snapTo(horizontalDragOffset) }
                        velocityTracker.addPosition(change.uptimeMillis, change.position)
                        change.consume()
                    }
                }

                val velocity = velocityTracker.calculateVelocity().x
                val targetOffsetX = decay.calculateTargetValue(offsetX.value, velocity)

                offsetX.updateBounds(
                    lowerBound = -size.width.toFloat(),
                    upperBound = size.width.toFloat()
                )

                launch {
                    if (abs(targetOffsetX) >= size.width * 0.5f) {
                        // Fling far enough — dismiss
                        offsetX.animateDecay(velocity, decay)
                        onDismiss()
                    } else {
                        // Snap back
                        offsetX.animateTo(
                            targetValue = 0f,
                            initialVelocity = velocity
                        )
                    }
                }
            }
        }
    }.offset { IntOffset(offsetX.value.roundToInt(), 0) }
}
```

### AnchoredDraggable Snap Points

```kotlin
enum class DragValue { Start, Center, End }

@Composable
fun AnchoredDraggableExample() {
    val density = LocalDensity.current
    val anchors = with(density) {
        DraggableAnchors {
            DragValue.Start at -200.dp.toPx()
            DragValue.Center at 0f
            DragValue.End at 200.dp.toPx()
        }
    }

    val state = remember {
        AnchoredDraggableState(
            initialValue = DragValue.Center,
            anchors = anchors,
            positionalThreshold = { totalDistance -> totalDistance * 0.5f },
            velocityThreshold = { with(density) { 125.dp.toPx() } },
            animationSpec = spring()
        )
    }

    Box(
        modifier = Modifier
            .offset { IntOffset(state.requireOffset().roundToInt(), 0) }
            .anchoredDraggable(state, Orientation.Horizontal)
            .size(80.dp)
            .background(Color.Blue, RoundedCornerShape(16.dp))
    )
}
```

### Transformable: Pinch, Zoom, Rotate

```kotlin
@Composable
fun TransformableExample() {
    var scale by remember { mutableFloatStateOf(1f) }
    var rotation by remember { mutableFloatStateOf(0f) }
    var offset by remember { mutableStateOf(Offset.Zero) }

    val transformableState = rememberTransformableState { zoomChange, offsetChange, rotationChange ->
        scale = (scale * zoomChange).coerceIn(0.5f, 5f)
        rotation += rotationChange
        offset += offsetChange
    }

    Box(
        modifier = Modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                rotationZ = rotation
                translationX = offset.x
                translationY = offset.y
            }
            .transformable(state = transformableState)
            .size(200.dp)
            .background(Color.Blue)
    )
}
```

---

## Predictive Back Gesture Animation (Android 14+)

### NavHost Transitions

```kotlin
NavHost(
    navController = navController,
    startDestination = "home",
    enterTransition = {
        slideInHorizontally(initialOffsetX = { it }) + fadeIn(animationSpec = tween(300))
    },
    exitTransition = {
        slideOutHorizontally(targetOffsetX = { -it / 3 }) + fadeOut(animationSpec = tween(300))
    },
    popEnterTransition = {
        slideInHorizontally(initialOffsetX = { -it / 3 }) + fadeIn(animationSpec = tween(300))
    },
    popExitTransition = {
        slideOutHorizontally(targetOffsetX = { it }) + fadeOut(animationSpec = tween(300))
    }
) {
    composable("home") { HomeScreen() }
    composable("detail") { DetailScreen() }
}
```

### PredictiveBackHandler

```kotlin
@Composable
fun PredictiveBackExample(onBack: () -> Unit) {
    var boxScale by remember { mutableFloatStateOf(1f) }

    PredictiveBackHandler(enabled = true) { progress: Flow<BackEventCompat> ->
        try {
            progress.collect { backEvent ->
                boxScale = 1f - (0.3f * backEvent.progress)
            }
            onBack()
        } catch (e: CancellationException) {
            boxScale = 1f
            throw e
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer {
                scaleX = boxScale
                scaleY = boxScale
            }
    ) {
        Text("Swipe back to see scale animation")
    }
}
```

### M3 Automatic Predictive Back

These Material 3 components animate with predictive back gestures out of the box (no extra code needed):

- `SearchBar` — collapses back on swipe
- `ModalBottomSheet` — slides down with gesture progress
- `ModalNavigationDrawer` — slides closed with gesture progress

---

