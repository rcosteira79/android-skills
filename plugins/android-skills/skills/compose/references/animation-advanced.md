# Advanced Animation in Jetpack Compose

For primitives, specs, and the phase rule, see `compose/references/animation.md`; for the recipe cookbook + choreography, see `compose/references/animation-recipes.md`. This reference covers shared-element transitions and the draw-phase color trap.

## Shared element transitions

`sharedElement()` vs `sharedBounds()`:

| | `sharedElement()` | `sharedBounds()` |
|---|---|---|
| Content | **Identical** on both screens (hero image, avatar, icon) | **Different** content source ↔ target (card → detail page) |
| During transition | Only the target renders | Both source and target are visible, crossfading |

Use `sharedBounds` for a container transform (the card *becomes* the page) and `sharedElement` for the genuinely-identical pieces inside it. Both need a `SharedTransitionLayout` wrapping the `NavHost` and the per-composable `animatedVisibilityScope`.

```kotlin
with(sharedTransitionScope) {
    Row(Modifier.sharedBounds(rememberSharedContentState("card-${item.id}"), animatedVisibilityScope)) {
        Image(…, Modifier.sharedElement(rememberSharedContentState("image-${item.id}"), animatedVisibilityScope))
        Text(item.title, Modifier
            .sharedElement(rememberSharedContentState("title-${item.id}"), animatedVisibilityScope)
            .skipToLookaheadSize())                       // text uses its TARGET size now → no reflow mid-transition
    }
}
```

- **`skipToLookaheadSize()`** on a shared `Text` makes it snap to its final size immediately, avoiding awkward line-break changes during the transition.
- **`renderInSharedTransitionScopeOverlay = true`** keeps a shared element (e.g. a FAB) rendered above other content during the transition.
- **Arc motion:** a `BoundsTransform { initial, target -> keyframes { durationMillis = 500; initial at 0 using ArcMode.ArcBelow; target at 500 } }` curves the path between source and target bounds.
- Non-shared content fades in with `Modifier.animateEnterExit(enter = …, exit = …)`.

## `drawBehind` for animated background colors

`Modifier.background(color)` reads `color` **during composition** — an animated color recomposes every frame. `drawBehind { drawRect(color) }` reads in the **draw phase** only:

```kotlin
val color by animateColorAsState(if (selected) Color.Blue else Color.Gray, label = "bg")
Box(Modifier.drawBehind { drawRect(color) })      // FASTER — not Modifier.background(color)
```

Same family as the phase rule in `animation.md`: animate via draw-/layout-phase reads (`graphicsLayer { }` for transforms/alpha, `drawBehind` for color) rather than composition-phase parameter reads.

## Predictive back (Android 14+)

`SearchBar`, `ModalBottomSheet`, and `ModalNavigationDrawer` animate with the predictive-back gesture out of the box. For custom progress, `PredictiveBackHandler { progress: Flow<BackEventCompat> -> … }` collects the gesture — and **must rethrow `CancellationException`** (the user can cancel the gesture mid-swipe):

```kotlin
PredictiveBackHandler(enabled = true) { progress ->
    try { progress.collect { boxScale = 1f - 0.3f * it.progress }; onBack() }
    catch (e: CancellationException) { boxScale = 1f; throw e }      // reset + rethrow on cancel
}
```

`NavHost` destination transitions (`enterTransition` / `exitTransition` / `popEnterTransition` / `popExitTransition`) integrate with predictive back automatically — don't double-animate the destination content (see `animation.md`).
