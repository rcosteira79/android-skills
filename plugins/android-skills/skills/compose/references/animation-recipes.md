# Animation Recipes in Jetpack Compose

For animation primitives, specs, the phase rule, and M3 motion tokens, see `compose/references/animation.md`; for shared-element / gesture-driven / predictive-back / `graphicsLayer` work, see `compose/references/animation-advanced.md`.

This reference covers the loading recipe and the choreography patterns worth having canonically.

## Shimmer / skeleton loading + loading crossfade

```kotlin
fun Modifier.shimmerEffect(): Modifier = composed {
    val transition = rememberInfiniteTransition(label = "shimmer")
    val x by transition.animateFloat(
        initialValue = -1000f, targetValue = 1000f,
        animationSpec = infiniteRepeatable(tween(1200, easing = LinearEasing), RepeatMode.Restart),
        label = "shimmer_x",
    )
    background(Brush.linearGradient(
        colors = listOf(Color.LightGray.copy(alpha = 0.6f), Color.LightGray.copy(alpha = 0.2f), Color.LightGray.copy(alpha = 0.6f)),
        start = Offset(x, 0f), end = Offset(x + 500f, 0f),
    ))
}

@Composable
fun ContentWithLoading(isLoading: Boolean, content: @Composable () -> Unit) {
    Crossfade(targetState = isLoading, label = "loading_crossfade") { loading ->
        if (loading) SkeletonCard() else content()   // SkeletonCard = Boxes with .clip(...).shimmerEffect()
    }
}
```

Crossfading the skeleton ↔ real content (keyed on `isLoading`) avoids a jarring swap when data arrives. For a list, prefer a stable shimmer item over per-item `composed`; the production crash-safe shimmer (zero-size `SubcomposeLayout` guard) lives in `compose/references/production-crash-playbook.md` §7.

## Sequential / parallel / staggered choreography (just coroutines)

`Animatable.animateTo` suspends until complete, so choreography is plain coroutine structure — no special API:

```kotlin
LaunchedEffect(Unit) {
    alpha.animateTo(1f, tween(200))                  // sequential — each awaits the previous
    coroutineScope {                                  // parallel — launch siblings, resume after BOTH
        launch { translateY.animateTo(0f, spring()) }
        launch { scale.animateTo(1f, spring()) }
    }
    rotation.animateTo(360f, tween(400))              // runs after the parallel phase completes
}

// staggered entrance — a per-index delay before each launch
items.forEachIndexed { i, anim -> launch { delay(i * 80L); anim.animateTo(1f, spring()) } }
```
