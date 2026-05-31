# CompositionLocals: Implicit Data Passing in Jetpack Compose

CompositionLocals provide a way to pass data implicitly down the composition tree without threading it through every function parameter. They're analogous to SwiftUI's `@Environment`.

## What Are CompositionLocals?

A CompositionLocal is a slot in the composition that holds a value accessible to any descendant composable without explicit parameter passing. Values are provided using `CompositionLocalProvider` and accessed via `current`.

```kotlin
val localAppTheme = compositionLocalOf { "Light" }

@Composable
fun MyScreen() {
  CompositionLocalProvider(localAppTheme provides "Dark") {
    DescendantComposable() // Can access "Dark" via localAppTheme.current
  }
}

@Composable
fun DescendantComposable() {
  Text(localAppTheme.current) // Reads "Dark"
}
```

**Source:** `androidx/compose/runtime/runtime/src/commonMain/kotlin/androidx/compose/runtime/CompositionLocal.kt`

## compositionLocalOf vs staticCompositionLocalOf

The key difference is the **recomposition scope** when a value changes.

### compositionLocalOf
Tracks reads. When the value changes, only composables that **actually read** `.current` are invalidated. More efficient when the value changes; modest bookkeeping overhead per read.

```kotlin
val LocalUserPreferences = compositionLocalOf { UserPreferences() }
```

Use for values that may change during composition: user session, locale, scroll-driven state.

### staticCompositionLocalOf
Does NOT track reads. When the value changes, the **entire subtree** below the `CompositionLocalProvider` is invalidated and recomposed. Cheaper per read, but a single change blows away everything in scope.

```kotlin
val LocalAppVersion = staticCompositionLocalOf { "1.0.0" }
```

Use only for values that truly never change during composition: theme, spacing, DI-provided dependencies. If the value flips, the cost is recomposing the whole subtree — which is fine when "the whole subtree" is the right unit of update for a theme switch, but a bug for anything finer-grained.

### compositionLocalWithComputedDefaultOf
Introduced for computed default values. The lambda is called each time the value is read when no provider is active.

```kotlin
val LocalResources = compositionLocalWithComputedDefaultOf { context.resources }
```

This is more efficient than `compositionLocalOf { lazy { ... } }` because it avoids capturing state unnecessarily.

## Built-In CompositionLocals

The Compose runtime and UI libraries provide standard locals:

| Local | Type | Purpose |
|-------|------|---------|
| `LocalContext` | `Context` | Android Context (requires AndroidCompositionLocals) |
| `LocalConfiguration` | `Configuration` | Screen size, orientation, density |
| `LocalDensity` | `Density` | Pixel density for dp/px conversion |
| `LocalLayoutDirection` | `LayoutDirection` | LTR/RTL directionality |
| `LocalView` | `View` | Underlying Android View (if available) |
| `LocalLifecycleOwner` | `LifecycleOwner` | Activity/Fragment lifecycle |
| `LocalSavedStateRegistryOwner` | `SavedStateRegistryOwner` | For state persistence |

**Source:** `androidx/compose/ui/ui/src/androidMain/kotlin/androidx/compose/ui/platform/AndroidCompositionLocals.android.kt`

```kotlin
@Composable
fun MyComposable() {
  val context = LocalContext.current
  val density = LocalDensity.current
  val config = LocalConfiguration.current

  Text("Screen width: ${config.screenWidthDp}dp")
}
```

## Providing Values with CompositionLocalProvider

Provide one or multiple local values:

```kotlin
// Single local
CompositionLocalProvider(LocalUserPreferences provides user) {
  Content()
}

// Multiple locals
CompositionLocalProvider(
  LocalUserPreferences provides user,
  LocalTheme provides darkTheme,
  LocalLanguage provides "en"
) {
  Content()
}
```

Values are **scoped** to descendants only:

```kotlin
CompositionLocalProvider(LocalUserPreferences provides userA) {
  ComponentA() // Sees userA
  CompositionLocalProvider(LocalUserPreferences provides userB) {
    ComponentB() // Sees userB (overrides)
  }
  ComponentC() // Sees userA (original)
}
```

## Creating Custom CompositionLocals

Create locals at top level, outside composable functions:

```kotlin
data class AppTheme(val isDark: Boolean, val colors: Colors)

val LocalAppTheme = compositionLocalOf<AppTheme> {
  error("AppTheme not provided")
}

// For nullable defaults
val LocalOptionalUser = compositionLocalOf<User?> { null }
```

**When to create a CompositionLocal:**
- Value is needed by many descendants
- Threading it as a parameter creates "prop drilling"
- Value is configuration-like (theme, locale, permissions)

**When NOT to use CompositionLocal:**
- Only 1–2 levels of composables need it → use parameters
- Value changes frequently and children need precise control → use State/ViewModel
- It's a dependency that should be testable → prefer parameters or dependency injection

## Testing with CompositionLocals

Provide test doubles to avoid real implementations:

```kotlin
@Composable
fun MyScreen() {
  val user = LocalUserRepository.current
  Text(user.name)
}

// In test
@Test
fun testMyScreen() {
  composeRule.setContent {
    CompositionLocalProvider(
      LocalUserRepository provides FakeUserRepository(User("Test User"))
    ) {
      MyScreen()
    }
  }
  composeRule.onNodeWithText("Test User").assertExists()
}
```

## Anti-Patterns

### ✗ Using CompositionLocal as Generic Dependency Injection
```kotlin
// Bad: obscures dependencies, hard to test
val LocalEverything = compositionLocalOf { AppContainer() }

@Composable
fun MyScreen() {
  val container = LocalEverything.current
  val repo = container.userRepo
  val cache = container.cache
}
```

**Better:** Provide specific locals or pass dependencies as parameters.

### ✗ Reading LocalContext Repeatedly
```kotlin
// Inefficient: reads on every recomposition
@Composable
fun MyComposable() {
  val context = LocalContext.current // Reading repeatedly
  // ...
}
```

**Better:** Read once outside the lambda or cache in remember:

```kotlin
@Composable
fun MyComposable() {
  val context = LocalContext.current
  val effect = remember(context) { /* use context */ }
}
```

### ✗ Storing Mutable State in CompositionLocal
```kotlin
// Bad: state changes won't trigger recomposition properly
val LocalCounter = compositionLocalOf { mutableStateOf(0) }
```

**Better:** Store the State in a parent composable and provide the value, not the State:

```kotlin
val LocalCount = compositionLocalOf { 0 }

@Composable
fun Parent() {
  var count by remember { mutableStateOf(0) }
  CompositionLocalProvider(LocalCount provides count) {
    Child()
  }
}
```

## Key Takeaways

1. Use `compositionLocalOf` for values that children read and depend on updates
2. Use `staticCompositionLocalOf` only for truly static values
3. Prefer parameters over CompositionLocals unless you have significant nesting
4. Always provide a sensible error default or nullable type
5. Test by providing fake implementations via `CompositionLocalProvider`
6. CompositionLocals are not a replacement for proper architecture — use them for configuration and environment data, not general dependency injection
