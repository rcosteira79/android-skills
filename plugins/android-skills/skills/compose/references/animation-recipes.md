# Animation Recipes in Jetpack Compose

Recipe cookbook and choreography helpers for Compose animations. For primitives, specs, and the animation decision tree, see [animation.md](animation.md). For shared-element transitions, gesture-driven animations, predictive back, and `graphicsLayer` performance work, see [animation-advanced.md](animation-advanced.md).

## Animation Recipes

### Shimmer / Skeleton Loading

```kotlin
fun Modifier.shimmerEffect(): Modifier = composed {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val translateAnim by transition.animateFloat(
        initialValue = -1000f,
        targetValue = 1000f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "shimmer_translate"
    )

    val shimmerBrush = Brush.linearGradient(
        colors = listOf(
            Color.LightGray.copy(alpha = 0.6f),
            Color.LightGray.copy(alpha = 0.2f),
            Color.LightGray.copy(alpha = 0.6f)
        ),
        start = Offset(translateAnim, 0f),
        end = Offset(translateAnim + 500f, 0f)
    )

    background(shimmerBrush)
}

@Composable
fun SkeletonCard() {
    Column(modifier = Modifier.padding(16.dp)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .clip(RoundedCornerShape(12.dp))
                .shimmerEffect()
        )
        Spacer(modifier = Modifier.height(8.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth(0.7f)
                .height(20.dp)
                .clip(RoundedCornerShape(4.dp))
                .shimmerEffect()
        )
    }
}

@Composable
fun ContentWithLoading(isLoading: Boolean, content: @Composable () -> Unit) {
    Crossfade(targetState = isLoading, label = "loading_crossfade") { loading ->
        if (loading) {
            SkeletonCard()
        } else {
            content()
        }
    }
}
```

### Staggered List Entrance

```kotlin
@Composable
fun StaggeredListEntrance(items: List<String>) {
    Column {
        items.forEachIndexed { index, item ->
            val animatable = remember { Animatable(0f) }
            LaunchedEffect(Unit) {
                delay(index * 100L)
                animatable.animateTo(
                    targetValue = 1f,
                    animationSpec = spring(
                        dampingRatio = Spring.DampingRatioLowBouncy,
                        stiffness = Spring.StiffnessMediumLow
                    )
                )
            }
            Text(
                text = item,
                modifier = Modifier
                    .graphicsLayer {
                        alpha = animatable.value
                        translationX = (1f - animatable.value) * 100f
                    }
                    .padding(8.dp)
            )
        }
    }
}
```

### Swipe-to-Dismiss (Material 3)

```kotlin
@Composable
fun SwipeToDismissItem(
    onDismiss: () -> Unit,
    content: @Composable () -> Unit
) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value != SwipeToDismissBoxValue.Settled) {
                onDismiss()
                true
            } else false
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val color by animateColorAsState(
                targetValue = when (dismissState.targetValue) {
                    SwipeToDismissBoxValue.StartToEnd -> Color.Green
                    SwipeToDismissBoxValue.EndToStart -> Color.Red
                    SwipeToDismissBoxValue.Settled -> Color.Transparent
                },
                label = "dismiss_bg"
            )
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(color)
                    .padding(horizontal = 20.dp),
                contentAlignment = when (dismissState.targetValue) {
                    SwipeToDismissBoxValue.StartToEnd -> Alignment.CenterStart
                    else -> Alignment.CenterEnd
                }
            ) {
                Icon(
                    imageVector = when (dismissState.targetValue) {
                        SwipeToDismissBoxValue.StartToEnd -> Icons.Default.Done
                        else -> Icons.Default.Delete
                    },
                    contentDescription = null,
                    tint = Color.White
                )
            }
        }
    ) {
        content()
    }
}
```

### Expandable Card

```kotlin
@Composable
fun ExpandableCard(title: String, description: String) {
    var expanded by remember { mutableStateOf(false) }
    val arrowRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        label = "arrow_rotation"
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .animateContentSize(animationSpec = spring(stiffness = Spring.StiffnessMediumLow))
            .clickable { expanded = !expanded }
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(text = title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Icon(
                    imageVector = Icons.Default.KeyboardArrowDown,
                    contentDescription = if (expanded) "Collapse" else "Expand",
                    modifier = Modifier.graphicsLayer { rotationZ = arrowRotation }
                )
            }
            AnimatedVisibility(visible = expanded) {
                Text(
                    text = description,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
    }
}
```

### Pull-to-Refresh Custom

```kotlin
@Composable
fun CustomPullToRefresh(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    content: @Composable () -> Unit
) {
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = onRefresh,
        indicator = { state ->
            val distanceFraction = state.distanceFraction.coerceIn(0f, 1f)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp),
                contentAlignment = Alignment.TopCenter
            ) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = "Refreshing",
                    modifier = Modifier
                        .size(32.dp)
                        .graphicsLayer {
                            scaleX = distanceFraction
                            scaleY = distanceFraction
                            rotationZ = distanceFraction * 360f
                        }
                )
            }
        }
    ) {
        content()
    }
}
```

### FAB Morph

**Pattern 1: ExtendedFloatingActionButton with scroll-driven expand/collapse**

```kotlin
@Composable
fun CollapsibleFab(listState: LazyListState) {
    val expandedFab by remember {
        derivedStateOf { listState.firstVisibleItemIndex == 0 }
    }

    ExtendedFloatingActionButton(
        onClick = { /* action */ },
        expanded = expandedFab,
        icon = { Icon(Icons.Default.Add, contentDescription = "Add") },
        text = { Text("New Item") }
    )
}
```

**Pattern 2: Exploding FAB with updateTransition**

```kotlin
@Composable
fun ExplodingFab(isExpanded: Boolean, onClick: () -> Unit) {
    val transition = updateTransition(targetState = isExpanded, label = "fab_explode")

    val size by transition.animateDp(label = "size") { if (it) 200.dp else 56.dp }
    val cornerRadius by transition.animateDp(label = "corner") { if (it) 16.dp else 28.dp }
    val color by transition.animateColor(label = "color") {
        if (it) MaterialTheme.colorScheme.secondaryContainer
        else MaterialTheme.colorScheme.primaryContainer
    }
    val contentAlpha by transition.animateFloat(label = "alpha") { if (it) 1f else 0f }

    Surface(
        modifier = Modifier.size(size).clickable { onClick() },
        shape = RoundedCornerShape(cornerRadius),
        color = color
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (!isExpanded) {
                Icon(Icons.Default.Add, contentDescription = "Add")
            }
            Column(
                modifier = Modifier.graphicsLayer { alpha = contentAlpha },
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Expanded content
                Text("Option 1")
                Text("Option 2")
                Text("Option 3")
            }
        }
    }
}
```

### Bottom Sheet Drag

```kotlin
enum class SheetValue { Hidden, Collapsed, Expanded }

@Composable
fun DraggableBottomSheet(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val anchors = with(density) {
        DraggableAnchors {
            SheetValue.Hidden at 0f
            SheetValue.Collapsed at -200.dp.toPx()
            SheetValue.Expanded at -600.dp.toPx()
        }
    }

    val state = remember {
        AnchoredDraggableState(
            initialValue = SheetValue.Hidden,
            anchors = anchors,
            positionalThreshold = { totalDistance -> totalDistance * 0.5f },
            velocityThreshold = { with(density) { 125.dp.toPx() } },
            animationSpec = spring(stiffness = Spring.StiffnessMediumLow)
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        content()

        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .offset { IntOffset(0, (state.requireOffset()).roundToInt()) }
                .anchoredDraggable(state, Orientation.Vertical),
            shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
            shadowElevation = 8.dp
        ) {
            Column(modifier = Modifier.fillMaxWidth().height(600.dp).padding(16.dp)) {
                // Drag handle
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .width(40.dp)
                        .height(4.dp)
                        .background(Color.Gray, RoundedCornerShape(2.dp))
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text("Sheet Content")
            }
        }
    }
}
```

### Parallax Scroll Header

```kotlin
@Composable
fun ParallaxHeader(scrollState: ScrollState) {
    val scrollOffset = scrollState.value.toFloat()

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(300.dp)
            .graphicsLayer {
                translationY = scrollOffset * 0.6f // Parallax factor
                scaleX = 1f + (scrollOffset * 0.001f).coerceAtLeast(0f)
                scaleY = 1f + (scrollOffset * 0.001f).coerceAtLeast(0f)
                alpha = (1f - (scrollOffset / 600f)).coerceIn(0f, 1f)
            }
    ) {
        Image(
            painter = painterResource(R.drawable.header),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )
    }
}
```

### Animated Tab Switch

```kotlin
@Composable
fun AnimatedTabContent(selectedTabIndex: Int) {
    AnimatedContent(
        targetState = selectedTabIndex,
        transitionSpec = {
            val direction = if (targetState > initialState) 1 else -1
            slideInHorizontally(
                initialOffsetX = { fullWidth -> direction * fullWidth },
                animationSpec = tween(300)
            ) + fadeIn(animationSpec = tween(300)) togetherWith
            slideOutHorizontally(
                targetOffsetX = { fullWidth -> -direction * fullWidth },
                animationSpec = tween(300)
            ) + fadeOut(animationSpec = tween(300)) using
            SizeTransform(clip = false)
        },
        label = "tab_content"
    ) { tabIndex ->
        when (tabIndex) {
            0 -> TabOneContent()
            1 -> TabTwoContent()
            2 -> TabThreeContent()
        }
    }
}
```

---

## Sequential/Parallel Animation Choreography

### Sequential (Coroutine Chaining)

Each `animateTo` suspends until complete, so chaining them creates sequential animation:

```kotlin
val alpha = remember { Animatable(0f) }
val translateY = remember { Animatable(100f) }
val scale = remember { Animatable(0.5f) }

LaunchedEffect(Unit) {
    alpha.animateTo(1f, animationSpec = tween(300))
    translateY.animateTo(0f, animationSpec = spring())
    scale.animateTo(1f, animationSpec = tween(200))
}
```

### Parallel (Multiple launch blocks)

```kotlin
val alpha = remember { Animatable(0f) }
val translateY = remember { Animatable(100f) }

LaunchedEffect(Unit) {
    coroutineScope {
        launch { alpha.animateTo(1f, animationSpec = tween(300)) }
        launch { translateY.animateTo(0f, animationSpec = spring()) }
    }
    // Code here runs after BOTH animations complete
}
```

### Staggered Delays

```kotlin
val items = remember { List(5) { Animatable(0f) } }

LaunchedEffect(Unit) {
    items.forEachIndexed { index, animatable ->
        launch {
            delay(index * 80L)
            animatable.animateTo(1f, animationSpec = spring())
        }
    }
}
```

### Mixed Sequential + Parallel

```kotlin
LaunchedEffect(Unit) {
    // Phase 1: Sequential — fade in first
    alpha.animateTo(1f, animationSpec = tween(200))

    // Phase 2: Parallel — move and scale at the same time
    coroutineScope {
        launch { translateY.animateTo(0f, animationSpec = spring()) }
        launch { scale.animateTo(1f, animationSpec = spring()) }
    }

    // Phase 3: Sequential — final flourish after Phase 2 completes
    rotation.animateTo(360f, animationSpec = tween(400))
}
```

---

