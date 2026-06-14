# Design-to-Compose

This reference covers the easy-to-miss parts of translating a Figma mockup into Compose: fine-grained shadows and custom spacing/elevation scales.

## Shadows: `dropShadow` / `innerShadow` (Compose UI 1.9+)

1.9 added `Modifier.dropShadow()` and `Modifier.innerShadow()` (in `androidx.compose.ui.draw`) for fine-grained shadows that map directly to Figma's drop/inner-shadow fields — superseding the single-parameter `Modifier.shadow(elevation, shape)` for anything beyond a plain elevation shadow. Two things to get right: the properties go in a **`Shadow` object** (there is no flat `blur`/`offsetX`/`offsetY` parameter list), and **chain placement** matters — a drop shadow comes *before* the background, an inner shadow *after* it.

```kotlin
import androidx.compose.ui.graphics.shadow.Shadow   // NOT androidx.compose.ui.graphics.Shadow (the text-shadow class)
import androidx.compose.ui.unit.DpOffset

// Drop shadow — BEFORE background
Box(
    Modifier
        .dropShadow(
            shape = RoundedCornerShape(12.dp),
            shadow = Shadow(
                radius = 8.dp,                          // Figma "Blur"
                color = Color.Black.copy(alpha = 0.15f),
                offset = DpOffset(0.dp, 4.dp),          // Figma X / Y offset
            ),
        )
        .background(Color.White, RoundedCornerShape(12.dp))
)

// Inner shadow — AFTER background
Box(
    Modifier
        .background(Color.White, RoundedCornerShape(12.dp))
        .innerShadow(
            shape = RoundedCornerShape(12.dp),
            shadow = Shadow(radius = 4.dp, color = Color.Black.copy(alpha = 0.1f), offset = DpOffset(0.dp, 2.dp)),
        )
)
```

Figma shadow fields map onto `Shadow(...)`: Blur → `radius`, X/Y offset → `offset = DpOffset(x, y)`, Spread → `spread`, Color+opacity → `color = Color(hex).copy(alpha = …)`. For an animated shadow, the `dropShadow(shape) { … }` lambda form exposes the same fields as mutable `ShadowScope` properties (`radius`/`spread` as px `Float`, `offset` as `Offset`) without allocating a new `Shadow` each frame. `Modifier.shadow(elevation, shape)` is still fine for a simple elevation shadow.

## Spacing & elevation scales — a custom CompositionLocal

M3 ships `colorScheme`, `typography`, and `shapes` — but **no spacing or elevation scale**. Define your design system's scale once and provide it alongside `MaterialTheme`, so call sites read named tokens (`spacing.md`) instead of scattering raw `dp` literals:

```kotlin
@Immutable
data class AppSpacing(
    val xs: Dp = 4.dp, val sm: Dp = 8.dp, val md: Dp = 16.dp,
    val lg: Dp = 24.dp, val xl: Dp = 32.dp,
)
val LocalAppSpacing = staticCompositionLocalOf { AppSpacing() }

@Immutable
data class AppElevation(val sm: Dp = 2.dp, val md: Dp = 4.dp, val lg: Dp = 8.dp)
val LocalAppElevation = staticCompositionLocalOf { AppElevation() }

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppSpacing provides AppSpacing()) {
        MaterialTheme { content() }
    }
}

// call site
val spacing = LocalAppSpacing.current
Column(
    verticalArrangement = Arrangement.spacedBy(spacing.sm),
    modifier = Modifier.padding(spacing.md),
) { /* … */ }
```

Use `staticCompositionLocalOf` — these tokens don't change after the theme is set (see `compose/references/composition-locals.md` for the static-vs-dynamic rule). This is the same custom-token mechanism `compose/references/theming-material3.md` uses for brand colours.

## Modifier ordering

Modifier order is load-bearing (sizing/layout → decoration → interaction, outer to inner). The full rules and common mistakes live in `compose/references/modifiers.md`.
