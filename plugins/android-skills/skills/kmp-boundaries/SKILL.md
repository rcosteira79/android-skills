---
name: kmp-boundaries
description: Use when designing Kotlin Multiplatform boundaries — choosing between expect/actual, common interfaces with platform bindings, or separate platform screens. Covers platform services (clipboard, share, haptics, permissions, files, settings, sensors, biometrics), native SDKs, source-set hierarchies (commonMain, skikoMain, appleMain, androidMain), Compose Multiplatform interop, and capability granularity. Use whenever common code needs to reach a platform API and you're picking the boundary shape.
---

# Kotlin Multiplatform Boundary Design

Designing the boundary between shared code and platform code is the central craft of KMP. Get it right and `commonMain` reads like product code that happens to compile everywhere. Get it wrong and `commonMain` is full of `Context`, `UIViewController`, and `actual` implementations that quietly grow domain logic.

This skill covers **boundary design**: when to reach for `expect`/`actual`, when to use a common interface with platform bindings, when to drop to separate platform screens, and the granularity rules that keep all three from collapsing into a god object.

**Related skills:**
- `android-skills:kmp-ktor` — Ktor client for network APIs (one concrete platform boundary done right).
- `android-skills:compose` — `references/multiplatform.md` covers Compose Multiplatform mechanics (resources, source-set wiring, migration table).
- `android-skills:kotlin-coroutines` — scope ownership rules that apply to platform-bound work.

---

## Core Principle

**Keep `commonMain` semantic and stable. Push platform mechanics behind small, named boundaries. Actuals translate — they don't decide.**

Three rules govern every boundary decision in this skill:

1. **Common code describes *what* the product needs; actuals describe *how* a platform delivers it.** `currentRegion()` belongs in common; `localeFromAndroidContext(context)` does not.
2. **Split by capability, never one giant `Platform` object.** `Clipboard`, `ShareSheet`, `Haptics`, `Biometrics` are five interfaces, not one. Five small boundaries are independently testable, mockable, and replaceable.
3. **An `actual` that knows product state or domain rules is a leak.** Translation only — if the actual is making decisions, move the decision back to common code.

---

## When To Use This Skill

Use this skill when common code needs to:

- Reach a platform service: clipboard, share sheet, intents, deep links, haptics, biometrics, notifications.
- Touch platform OS surfaces: files, paths, clocks, locale, network reachability, sensors, crypto, media, camera, maps.
- Wrap a native SDK that only exists on one platform.
- Embed native views, controllers, or platform widgets inside Compose Multiplatform.
- Make a runtime decision that varies per platform (engine selection, capability detection).
- Decide between `expect`/`actual`, a common interface bound per-platform, dependency injection, or splitting into separate platform screens.

If you're picking the *mechanism* (HTTP client, image loader, navigation library) and there's an existing recipe (Ktor, Coil 3, Navigation Compose) — use the recipe. If you're picking the *boundary shape* for a platform call that doesn't have a recipe — use this skill.

---

## The Boundary Decision

There are four boundary shapes. Pick by the situation:

| Situation | Boundary | Why |
|-----------|----------|-----|
| Simple compile-time platform specialization (one function, one value, one leaf composable) | `expect`/`actual` function, value, typealias, or composable | Smallest possible surface; compiler enforces every platform has an actual |
| Implementation needs injected dependencies, lifecycle ownership, runtime choice, or test fakes | Common interface + platform binding | Interface is trivially fakeable; DI controls construction |
| UI is mostly shared, one leaf differs visibly per platform | Common composable calling an `expect` leaf | Keep the layout in common; isolate the platform-specific node |
| Entire screen differs per platform (Android settings vs iOS settings) | Separate platform screens behind a common navigation contract | Don't `expect` an entire screen — design two screens, share the route |
| Only constants/resources differ | Common API exposing semantic values, actual values per platform | `app.iconSize`, not `R.dimen.icon_size` |

**Default to interfaces with DI for anything more complex than "a single value or pure function."** `expect class` is the easiest pattern to overuse — it looks lightweight but it's hard to fake, hard to extend, and hard to test without a real platform runtime.

---

## Keep Common APIs Semantic

`commonMain` should describe what the product needs, not how the platform does it.

```kotlin
// GOOD — common API is semantic; how Android/iOS resolve it is invisible
expect fun currentRegion(): Region

// BAD — common API leaks Android implementation
expect fun currentRegionFromAndroidLocale(context: Context): Region
```

The Android actual uses `Locale` APIs. The iOS actual uses Foundation. Callers know neither.

### Symptoms that an API isn't semantic

- A parameter type is Android-only (`Context`, `Activity`, `Uri`, `Bundle`, `Drawable`) or iOS-only (`UIViewController`, `NSBundle`, `NSURL`).
- A parameter is only used on one platform — the other actual ignores it.
- The function name contains a platform mechanism (`fromAndroidIntent`, `toIosNSString`, `withCgImage`).
- Adding a third platform would force every caller in `commonMain` to change.

### Fix it before the actual is written

If the API isn't semantic, the actual has nowhere to put its details — they leak into common code. Get the common signature right first; the actuals follow trivially.

---

## Keep Actuals Thin

Actuals translate, they don't decide. If an actual starts accumulating product rules, business logic, or domain decisions, those rules belong in `commonMain`.

```kotlin
// commonMain
interface ShareSheet {
    suspend fun shareText(text: String)
}

// androidMain — thin: builds the intent and launches it
class AndroidShareSheet(private val activity: Activity) : ShareSheet {
    override suspend fun shareText(text: String) {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        activity.startActivity(Intent.createChooser(intent, null))
    }
}
```

### Activity-owned, not Context-owned

The Android `ShareSheet` is explicitly `Activity`-owned. A generic `Context` would need `Intent.FLAG_ACTIVITY_NEW_TASK` to launch the chooser — and that flag is a smell: it hides the fact that this is a UI operation requiring a foreground task. The right design is "the platform binding holds an `Activity`," not "the actual silently launches into whatever task the OS picks."

This is the single most common Android boundary mistake: passing `applicationContext` (or `LocalContext.current`) into a class that actually needs an Activity, then papering over the lifecycle gap with `FLAG_ACTIVITY_NEW_TASK`. The cost is invisible until you need to know whether `shareText` returned because the sheet opened or because the user finished.

### Define what `suspend` means

For platform UI actions, "the function returned" usually means **the action was launched**, not **the user completed it**. The share sheet opened — not "the user picked an app and tapped Send." Document this in the interface KDoc; otherwise callers will write incorrect retry/confirmation logic.

```kotlin
interface ShareSheet {
    /**
     * Launches the system share sheet for the given text. Returns when the sheet is
     * presented — **not** when the user completes or cancels the share.
     */
    suspend fun shareText(text: String)
}
```

### Anti-pattern: business rules in the actual

```kotlin
// WRONG — Android actual decides what counts as "shareable"
class AndroidShareSheet(private val activity: Activity) : ShareSheet {
    override suspend fun shareText(text: String) {
        if (text.length > 1000) return  // policy in the actual
        if (text.startsWith("debug:")) return  // policy in the actual
        // ...
    }
}

// RIGHT — common decides, actual translates
class ShareUseCase(private val shareSheet: ShareSheet) {
    suspend operator fun invoke(text: String): ShareResult {
        if (text.length > 1000) return ShareResult.TooLong
        if (text.startsWith("debug:")) return ShareResult.Blocked
        shareSheet.shareText(text)
        return ShareResult.Launched
    }
}
```

If you find an `if`, a `when`, or a domain validation inside an actual, that logic belongs in `commonMain`.

---

## Prefer Interfaces When Tests Or DI Matter

`expect`/`actual` is right for **compile-time platform specialization of a single function or value**. The moment you need fakes, multiple implementations, runtime selection, or lifecycle ownership, switch to a common interface bound per-platform.

```kotlin
// expect class — hard to fake, hard to extend, requires platform runtime in tests
expect class Clipboard() {
    suspend fun setText(text: String)
}

// Common interface — trivially fakeable; DI binds the platform implementation
interface Clipboard {
    suspend fun setText(text: String)
}

class FakeClipboard : Clipboard {
    val writes = mutableListOf<String>()
    override suspend fun setText(text: String) { writes += text }
}
```

### Decision rule

| Need | Use |
|------|-----|
| Pure function or constant | `expect fun` / `expect val` |
| Object the product injects, fakes in tests, or selects at runtime | Common `interface` + platform binding |
| Native type alias for interop only (`expect typealias`) | `expect typealias` |
| Lifecycle ownership (Activity, ViewController) | Interface; bind in platform DI layer |
| Multiple implementations on the same platform (real vs offline vs debug) | Interface |

`expect class` exists, but it's the boundary shape most often used incorrectly. Prefer interfaces unless there's no DI in the project.

---

## Granularity — Split By Capability

The single biggest boundary mistake in KMP projects: one giant `Platform` object holding clipboard, share, haptics, biometrics, notifications, and the kitchen sink.

```kotlin
// WRONG — monolithic boundary, untestable in isolation
expect class Platform {
    suspend fun copyToClipboard(text: String)
    suspend fun shareText(text: String)
    fun vibrate(ms: Long)
    suspend fun authenticate(): BiometricResult
    fun showNotification(title: String, body: String)
    // ...and 15 more
}
```

Problems with the monolith:
- A test that only needs `Clipboard` must fake every other method.
- Changing one capability invalidates the entire boundary.
- Capabilities have different lifecycle owners (Activity for share, Application for notifications, secure context for biometrics) — one class can't honour all of them.
- Adding a platform forces every method to have an actual, even ones that don't apply.

### Split by capability

```kotlin
// RIGHT — one interface per capability
interface Clipboard { suspend fun setText(text: String) }
interface ShareSheet { suspend fun shareText(text: String) }
interface Haptics { fun perform(feedback: HapticFeedback) }
interface Biometrics { suspend fun authenticate(prompt: BiometricPrompt): BiometricResult }
interface Notifications { suspend fun show(notification: AppNotification) }
```

Five small interfaces, five independent platform bindings, five independently fakeable test surfaces. This is the granularity rule that Banes captures as *"never one Platform object — split by capability."*

### How small is too small?

If two capabilities are *always* used together and never independently, they can share an interface. `LocaleProvider` exposing `currentRegion()`, `currentLanguage()`, and `currentCalendar()` is fine — they're one platform service viewed three ways. But the moment one method has a different lifecycle owner, different fake, or different testability concern from another, split them.

---

## Source-Set Hierarchy Strategy

KMP source sets form a tree. Default tree:

```
commonMain
├── androidMain
├── iosMain
├── desktopMain (jvmMain on KMP without Compose)
└── wasmJsMain
```

But shared `actual` implementations between non-Android targets often belong in intermediate source sets — `skikoMain` (everything that renders via Skia: desktop + iOS + web) or `appleMain` (iOS + macOS + tvOS). Use them when two platforms can genuinely share an `actual`:

```
commonMain
├── androidMain
└── skikoMain                ← shared by all non-Android Compose targets
    ├── desktopMain
    ├── nonAndroidMain       ← shared by iOS + Web only
    │   ├── iosMain
    │   └── wasmJsMain
```

### When to introduce an intermediate source set

Add one only when **at least two** platforms can share an actual:

- `skikoMain` — the Compose Multiplatform `Font` actual for desktop+iOS+web shares Skia.
- `appleMain` — iOS+macOS share Foundation and UIKit/AppKit overlap.

### When NOT to

- "I might share this later" — add the intermediate set when there's a second platform implementation, not before.
- "Almost the same on iOS and desktop" — `almost` is the cue to keep two actuals. Sharing an actual that has subtle per-platform branches is worse than two clear actuals.

### Source-set wiring example

```kotlin
// build.gradle.kts (KMP module)
kotlin {
    androidTarget()
    jvm("desktop")
    iosX64(); iosArm64(); iosSimulatorArm64()
    wasmJs { browser() }

    sourceSets {
        val commonMain by getting
        val androidMain by getting
        val skikoMain by creating { dependsOn(commonMain) }
        val desktopMain by getting { dependsOn(skikoMain) }
        val iosMain by creating { dependsOn(skikoMain) }
        val iosX64Main by getting { dependsOn(iosMain) }
        val iosArm64Main by getting { dependsOn(iosMain) }
        val iosSimulatorArm64Main by getting { dependsOn(iosMain) }
        val wasmJsMain by getting { dependsOn(skikoMain) }
    }
}
```

---

## KMP Library Plugin Constraints (AGP 9)

AGP 9 replaces `com.android.library` with `com.android.kotlin.multiplatform.library` for the Android side of a KMP module, and rejects the `com.android.application` + `kotlin.multiplatform` combination outright. The new plugin enforces a single-variant architecture and removes several Android-library features that previously bled into boundary design.

These constraints are *structural* — they shape what can live in shared code vs. what must move to a platform app module. Knowing them up front saves a class of "this should be easy" mistakes where you design a `commonMain` API around a feature that no longer exists in a KMP library module.

- **`BuildConfig` is unavailable.** Compile-time constants come from [BuildKonfig](https://github.com/yshrsmz/BuildKonfig) / [gradle-buildconfig-plugin](https://github.com/gmazzo/gradle-buildconfig-plugin), or — more often — from DI (`AppConfiguration` interface bound per-platform). Don't design `commonMain` APIs that assume `BuildConfig.X` exists.
- **No build variants.** Variant-specific dependencies, resources, and signing belong in the app module, not the shared library. A `debug` vs `release` decision can still surface as a runtime configuration value injected into common code — just not as a build-variant split inside the KMP module.
- **No NDK / JNI.** If common code needs to call into native (C/C++) libraries on Android, extract that into a separate `com.android.library` module and wrap it behind a common interface the KMP module consumes.
- **Compose Multiplatform resources need explicit enable.** Add `androidResources { enable = true }` inside `kotlin { android { ... } }` or `Res.string.*` / `Res.drawable.*` crash at runtime on Android. Easy to miss — the build succeeds.
- **Consumer ProGuard rules need explicit migration.** `consumerProguardFiles("rules.pro")` from the old `android {}` block is silently dropped; use `consumerProguardFiles.add(file("rules.pro"))` in the new DSL.
- **KMP module cannot also be `com.android.application`.** The Android entry point (Activity, Application class, launcher manifest, `applicationId`, `targetSdk`, `versionCode`, `versionName`) must live in a separate `androidApp` module that depends on the shared KMP library. Anything that previously lived in `androidMain` of a `composeApp`-style monolith — `MainActivity`, app-level Hilt setup, navigation host wiring — now belongs in the app module, not the shared library.
- **kapt is incompatible with built-in Kotlin.** AGP 9 has Kotlin support built into `com.android.application` and `com.android.library`, and `org.jetbrains.kotlin.kapt` no longer applies. Migrate annotation processors to KSP (requires KSP 2.3.1+) or fall back to `com.android.legacy-kapt` for processors with no KSP equivalent.

### Where does this code live?

The "shared library or app module?" decision becomes clear-cut for several categories that used to be ambiguous in monolithic `composeApp` modules:

| Concern | Pre-AGP-9 (monolithic) | AGP 9 KMP library |
|---|---|---|
| `MainActivity`, Application class, launcher manifest | `androidMain` of shared module | Separate `androidApp` module |
| `applicationId`, `versionCode`, `targetSdk` | Shared module's `android {}` | `androidApp` only |
| Compile-time constants (env, feature flags) | `BuildConfig` field | `BuildKonfig` in common, or runtime DI |
| Debug vs release variants | `buildTypes {}` in shared module | App module; runtime config in shared |
| NDK / JNI native code | `androidMain` (any module) | Separate `com.android.library`, wrapped behind a common interface |
| App-level resources (launcher icon, theme) | Shared module's `androidMain/res` | `androidApp` module |

If you're starting a new KMP project on AGP 9, design with these constraints from day one — they're not migration steps, they're the new shape of a KMP library. If you're migrating an existing project, see JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) skill for the full migration mechanics (Paths A/B/C, DSL migration, plugin compatibility, Gradle property defaults).

---

## Compose-Specific Boundary Rules

Compose Multiplatform UI built on top of these boundaries follows three additional rules.

### 1. Keep platform-specific composables at leaf nodes

```kotlin
// commonMain — layout is shared
@Composable
fun MapScreen(state: MapState, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Header(state.title)
        // ↓ platform-specific leaf — UIKitView on iOS, AndroidView on Android
        NativeMapView(coords = state.center, modifier = Modifier.weight(1f))
        Controls(onZoomIn = state.onZoomIn, onZoomOut = state.onZoomOut)
    }
}

// commonMain
@Composable
expect fun NativeMapView(coords: Coords, modifier: Modifier = Modifier)
```

The layout, header, and controls are shared. Only the map widget — which genuinely is a native view — is `expect`. Don't expect the whole screen.

### 2. Pass `Modifier` through every expected composable that emits UI

```kotlin
// WRONG — caller can't size or place the leaf
@Composable expect fun NativeMapView(coords: Coords)

// RIGHT — leaf participates in the shared layout
@Composable expect fun NativeMapView(coords: Coords, modifier: Modifier = Modifier)
```

See `compose/references/modifiers.md` for the broader modifier-as-API-contract rule.

### 3. Effect discipline inside actuals

`LaunchedEffect`, `DisposableEffect`, `rememberUpdatedState`, and stable keys apply *inside* actual composables exactly as they would in common Compose code. An actual that calls `UIKitView { ... }` or `AndroidView { ... }` and forgets to clean up listeners on dispose has the same bug as any other Compose code that does that.

```kotlin
// iosMain
@Composable
actual fun NativeMapView(coords: Coords, modifier: Modifier) {
    val view = remember { MKMapView() }

    LaunchedEffect(coords) {
        view.setCenterCoordinate(coords.toCLLocation(), animated = true)
    }

    DisposableEffect(view) {
        val delegate = MapDelegate()
        view.delegate = delegate
        onDispose {
            view.delegate = null
        }
    }

    UIKitView(
        factory = { view },
        modifier = modifier,
    )
}
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `commonMain` API exposes Android/iOS types | Replace with semantic common types |
| `expect` function has parameters used by only one platform | Move those details into the actual |
| Business branching duplicated across actuals | Move business rules to `commonMain`; actuals translate only |
| One huge `Platform` `expect` object | Split by capability: `Clipboard`, `ShareSheet`, `Haptics`, etc. |
| `expect class` for something the project needs to fake | Use a common `interface` bound per-platform |
| Android actual uses `applicationContext` + `FLAG_ACTIVITY_NEW_TASK` for UI launch | Make the binding Activity-owned |
| `suspend` actual returns "when the sheet was launched" with no doc — caller treats it as completion | Document the `suspend` contract in the interface |
| Platform UI leaks high in the composable tree | Push the platform composable to a leaf; share the rest |
| Intermediate source set (`skikoMain`) created with only one platform under it | Don't introduce hierarchy until a second platform shares the actual |
| Native view embedded with no `DisposableEffect` cleanup | Add `onDispose { view.delegate = null }` (or equivalent) |

---

## Red Flags During Review

- **Common code imports `android.*` or `platform.*`.** That's a leak — the import is the proof.
- **An actual contains an `if`/`when` that depends on product state.** Domain logic in the actual; move it back to common.
- **A platform API name appears in a common function name.** `currentRegionFromAndroidLocale` is the giveaway.
- **Adding a third platform would force changes in `commonMain`.** The boundary isn't semantic — it leaks the existing two platforms.
- **Tests need an Android/iOS runtime to verify common business behaviour.** The boundary should be fakeable in common tests.
- **One `Platform` god object holding more than two capabilities.** Split.
- **`expect class` for anything that needs DI, lifecycle, or fakes.** Switch to an interface.
- **Android actual uses `applicationContext` for a UI operation.** Activity-owned, not Application-owned.
- **`suspend` actual contract is undocumented.** What does "returned" mean — launched, presented, completed?

---

## RIGHT vs WRONG Patterns

### Platform UI service — boundary shape

```kotlin
// WRONG — expect class + applicationContext + FLAG_ACTIVITY_NEW_TASK
// commonMain
expect class ShareSheet() {
    suspend fun shareText(text: String)
}

// androidMain
actual class ShareSheet {
    actual suspend fun shareText(text: String) {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        applicationContext.startActivity(
            Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}

// RIGHT — interface + Activity-owned binding + explicit suspend contract
// commonMain
interface ShareSheet {
    /** Launches the share sheet. Returns when the sheet is presented, not when the user completes the share. */
    suspend fun shareText(text: String)
}

// androidMain
class AndroidShareSheet(private val activity: Activity) : ShareSheet {
    override suspend fun shareText(text: String) {
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        activity.startActivity(Intent.createChooser(intent, null))
    }
}

// iosMain
class IosShareSheet : ShareSheet {
    override suspend fun shareText(text: String) {
        val activityVc = UIActivityViewController(
            activityItems = listOf(text),
            applicationActivities = null,
        )
        UIApplication.sharedApplication.keyWindow?.rootViewController
            ?.presentViewController(activityVc, animated = true, completion = null)
    }
}
```

**WRONG because** `applicationContext` cannot launch a chooser without `FLAG_ACTIVITY_NEW_TASK`, which papers over the fact that share is a UI operation requiring a foreground task. The interface is also not fakeable for tests, and the suspend contract is undocumented — callers will assume it means "user finished sharing."

### Granularity

```kotlin
// WRONG — god object
expect class Platform {
    fun copyToClipboard(text: String)
    suspend fun shareText(text: String)
    fun vibrate(ms: Long)
    suspend fun authenticate(): Boolean
}

// RIGHT — one interface per capability
interface Clipboard { fun setText(text: String) }
interface ShareSheet { suspend fun shareText(text: String) }
interface Haptics { fun perform(feedback: HapticFeedback) }
interface Biometrics { suspend fun authenticate(prompt: BiometricPrompt): BiometricResult }
```

**WRONG because** the monolith forces every test fake to implement every method, couples capabilities with different lifecycle owners, and produces a boundary that grows linearly with every new platform feature.

### Domain logic in actuals

```kotlin
// WRONG — Android actual decides what's shareable
class AndroidShareSheet(private val activity: Activity) : ShareSheet {
    override suspend fun shareText(text: String) {
        if (text.isBlank()) return
        if (text.length > 5000) return
        if (text.contains("@debug")) return
        activity.startActivity(...)
    }
}

// RIGHT — domain rules in common; actual translates
class ShareUseCase(
    private val shareSheet: ShareSheet,
    private val policy: SharePolicy,
) {
    suspend operator fun invoke(text: String): ShareResult {
        when (val verdict = policy.evaluate(text)) {
            is SharePolicy.Verdict.Allowed -> {
                shareSheet.shareText(text)
                return ShareResult.Launched
            }
            is SharePolicy.Verdict.Blocked -> return ShareResult.Blocked(verdict.reason)
        }
    }
}
```

**WRONG because** every platform actual would duplicate the same rules, the rules would drift, and a test of `ShareUseCase` would need a real Android runtime to verify behaviour that's pure logic. Domain rules belong in `commonMain` where they're testable with a fake `ShareSheet`.

### Expect class vs interface for testable services

```kotlin
// WRONG — expect class; test on JVM needs an Android-or-iOS runtime to instantiate
expect class Clipboard() {
    suspend fun setText(text: String)
}

@Test
fun `copy button writes URL to clipboard`() = runTest {
    val clipboard = Clipboard()  // explodes on JVM — no actual for jvmTest
    val viewModel = ShareViewModel(clipboard)
    viewModel.onCopyClicked("https://example.com")
    // can't assert anything — clipboard has no inspection API
}

// RIGHT — interface; common test uses a fake
interface Clipboard { suspend fun setText(text: String) }

class FakeClipboard : Clipboard {
    val writes = mutableListOf<String>()
    override suspend fun setText(text: String) { writes += text }
}

@Test
fun `copy button writes URL to clipboard`() = runTest {
    val clipboard = FakeClipboard()
    val viewModel = ShareViewModel(clipboard)
    viewModel.onCopyClicked("https://example.com")
    assertEquals(listOf("https://example.com"), clipboard.writes)
}
```

**WRONG because** `expect class` requires a real platform actual to exist at the test site, and the resulting platform clipboard usually has no inspection API. An interface is fakeable in common tests with no platform runtime, and the fake exposes exactly the inspection the test needs.

### Compose leaf positioning

```kotlin
// WRONG — entire screen is expect; layout duplicated per platform
// commonMain
@Composable expect fun MapScreen(state: MapState)

// androidMain
@Composable actual fun MapScreen(state: MapState) {
    Column { Header(state.title); AndroidView({ MapView(it) }); Controls(...) }
}

// iosMain
@Composable actual fun MapScreen(state: MapState) {
    Column { Header(state.title); UIKitView({ MKMapView() }); Controls(...) }
}

// RIGHT — common layout, platform leaf
// commonMain
@Composable
fun MapScreen(state: MapState, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Header(state.title)
        NativeMapView(coords = state.center, modifier = Modifier.weight(1f))
        Controls(state.onZoomIn, state.onZoomOut)
    }
}

@Composable expect fun NativeMapView(coords: Coords, modifier: Modifier = Modifier)
```

**WRONG because** the layout is identical and the only real platform difference is the map widget. Duplicating the layout means every UI change happens twice, every spacing tweak happens twice, and Compose Preview can't render the screen at all.

---

## Checklist

- [ ] Common API is semantic — function name and signature don't mention any platform mechanism
- [ ] No Android/iOS types in `commonMain` signatures (`Context`, `UIViewController`, etc.)
- [ ] Boundary granularity: one interface per capability, never one `Platform` god object
- [ ] `expect`/`actual` only for pure functions, values, typealiases, or genuine leaf composables
- [ ] Interfaces with DI for anything that needs fakes, lifecycle, or runtime selection
- [ ] Android bindings hold an `Activity` (not `applicationContext`) when launching UI
- [ ] `suspend` contract in interface KDoc explains what "returned" means
- [ ] No domain rules, `if`s, or `when`s inside actuals — actuals translate only
- [ ] Intermediate source sets (`skikoMain`, `appleMain`) only when ≥2 platforms share the actual
- [ ] Native views embedded with `DisposableEffect` cleanup
- [ ] Compose `expect` composables accept `modifier: Modifier = Modifier`
- [ ] Common tests run on JVM without needing Android/iOS runtime
