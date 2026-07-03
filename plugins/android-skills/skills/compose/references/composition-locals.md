# CompositionLocals

CompositionLocals pass data implicitly down the composition tree (`compositionLocalOf` / `staticCompositionLocalOf`, provided via `CompositionLocalProvider`, read through `.current`). This reference covers the recomposition-scope and mutable-state traps, not the basics of the built-in locals or providing values.

## `compositionLocalOf` vs `staticCompositionLocalOf` — the recomposition-scope trap

The choice is not stylistic; it changes **what recomposes when the value changes**.

- **`compositionLocalOf`** tracks reads — when the value changes, only composables that actually read `.current` recompose. Pay the per-read bookkeeping when the value *changes during composition*: user session, locale, a scroll-driven value.
- **`staticCompositionLocalOf`** does NOT track reads — changing the value invalidates the **entire subtree** under the provider. Cheaper per read, but one flip recomposes everything in scope. Use it only for values that effectively never change after they're set: theme, a spacing scale, DI-provided singletons.

Picking `staticCompositionLocalOf` for a value that updates at runtime is a performance bug — every change recomposes the whole subtree. Picking `compositionLocalOf` for a truly-static theme token just adds read-tracking overhead for nothing. This is the same decision `compose/references/theming-material3.md` and `compose/references/design-to-compose.md` route here for when extending the theme with custom tokens.

For a default that must be **computed** lazily from the environment when no provider is active, use `compositionLocalWithComputedDefaultOf { … }` — the lambda runs per read, which avoids capturing state the way `compositionLocalOf { lazy { … } }` would.

## Never store mutable State in a CompositionLocal

Providing a `MutableState` (or any mutable holder) through a local breaks recomposition: descendants capture the container once and don't re-run when its contents change.

```kotlin
// ✗ state changes won't propagate correctly
val LocalCounter = staticCompositionLocalOf { mutableStateOf(0) }

// ✓ hold the State in a parent; provide the VALUE, not the holder
val LocalCount = compositionLocalOf { 0 }

@Composable
fun Parent() {
    var count by remember { mutableStateOf(0) }
    CompositionLocalProvider(LocalCount provides count) { Child() }
}
```

Provide an immutable snapshot of the value and let the normal provide-on-change flow drive recomposition.
