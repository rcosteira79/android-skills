# Material 3 Theming Reference

This reference covers extending the theme beyond M3's three slots, not the basics of `MaterialTheme`/`lightColorScheme`/`darkColorScheme`/dynamic color.

## Extending the theme with a CompositionLocal

Material 3 ships three theme slots — `colorScheme`, `typography`, `shapes`. For design tokens beyond those (brand colours, a spacing scale, elevation tiers), provide your own through a `CompositionLocal` alongside `MaterialTheme`:

```kotlin
data class AppColors(
    val brandPrimary: Color = Color(0xFF6200EE),
    val brandSecondary: Color = Color(0xFF03DAC6),
    val neutral: Color = Color.Gray,
)

val LocalAppColors = staticCompositionLocalOf { AppColors() }

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppColors provides AppColors()) {
        MaterialTheme { content() }
    }
}

// at the call site
Button(
    colors = ButtonDefaults.buttonColors(containerColor = LocalAppColors.current.brandPrimary),
) { /* ... */ }
```

Use `staticCompositionLocalOf` for tokens that don't change after the theme is set (the common case) — it avoids tracking reads. Reach for `compositionLocalOf` only when the value updates at runtime (e.g. a user-toggled brand). See `compose/references/composition-locals.md` for the static-vs-dynamic choice and pitfalls, and `compose/references/design-to-compose.md` for ready-made spacing/elevation token scales.

## Related

**M3 contrast levels** (Standard / Medium / High) and in-app contrast control via `Hct` / `SchemeContent` — see `android-skills:android-ux`. Compose's `dynamicLightColorScheme` / `dynamicDarkColorScheme` read the system contrast setting automatically (SDK 34+) and do not expose a contrast parameter.
