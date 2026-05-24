---
name: kmp-boundaries
description: Use when designing Kotlin Multiplatform boundaries — choosing between expect/actual, common interfaces with platform bindings, or separate platform screens. Covers platform services (clipboard, share, haptics, permissions, files, settings, sensors, biometrics), native SDKs, source-set hierarchies (commonMain, skikoMain, appleMain, androidMain), Compose Multiplatform interop, and capability granularity. Use whenever common code needs to reach a platform API and you're picking the boundary shape.
---

# Kotlin Multiplatform Boundary Design

Designing the boundary between shared and platform code is the central craft of KMP: keep `commonMain` reading like product code, and push `Context`/`UIViewController`/`actual` mechanics behind small named boundaries before they grow domain logic. This skill covers boundary **shape** — `expect`/`actual` vs a common interface with platform bindings vs separate platform screens — and the granularity rules that keep all three from collapsing into a god object.

Use it when common code must reach a platform API (clipboard, share, haptics, biometrics, files, sensors, native SDKs, Compose interop) and there's no existing recipe. If you're picking a *mechanism* that has a recipe (Ktor, Coil 3, Navigation Compose), use the recipe instead.

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

Get the common signature right first; the actuals follow trivially. If the API isn't semantic, the actual has nowhere to put its details — they leak into common code.

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

The Android `ShareSheet` is explicitly `Activity`-owned. A generic `Context` would need `Intent.FLAG_ACTIVITY_NEW_TASK` to launch the chooser — and that flag is a smell: it hides the fact that this is a UI operation requiring a foreground task. The right design is "the platform binding holds an `Activity`," not "the actual silently launches into whatever task the OS picks." This is the single most common Android boundary mistake: passing `applicationContext` (or `LocalContext.current`) into a class that actually needs an Activity, then papering over the lifecycle gap with `FLAG_ACTIVITY_NEW_TASK`.

**How the Activity reaches the constructor.** You don't app-wide-inject an `Activity` — it's framework-created and lifecycle-bound. Construct the binding in an **activity scope** in the Android app module, where the current Activity is available:

```kotlin
// androidApp — Hilt, activity-scoped (Activity is a default binding in ActivityComponent)
@Module
@InstallIn(ActivityComponent::class)
object ShareModule {
    @Provides fun shareSheet(activity: Activity): ShareSheet = AndroidShareSheet(activity)
}
```

Koin's equivalent is an activity-scoped definition (`scope` / `scoped`). `commonMain` only ever sees the `ShareSheet` interface — the `Activity` never leaves the app module. If a longer-lived (app-scoped) object needs the binding, don't capture the Activity directly; hold it behind a lifecycle-aware provider (set in `onResume`, cleared in `onPause`) so a destroyed Activity can't leak.

### Define what `suspend` means

For platform UI actions, "the function returned" usually means **the action was launched**, not **the user completed it**. Document this in the interface KDoc; otherwise callers will write incorrect retry/confirmation logic.

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

If you find an `if`, a `when`, or a domain validation inside an actual, that logic belongs in `commonMain` — where it's testable with a fake `ShareSheet` instead of a real platform runtime.

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
| Native type alias for interop only | `expect typealias` |
| Lifecycle ownership (Activity, ViewController) | Interface; bind in platform DI layer |
| Multiple implementations on the same platform (real vs offline vs debug) | Interface |

`expect class` exists, but it's the boundary shape most often used incorrectly. Prefer interfaces unless there's no DI in the project. A common test then runs on the JVM with a fake — no Android/iOS runtime required.

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

```kotlin
// RIGHT — one interface per capability
interface Clipboard { suspend fun setText(text: String) }
interface ShareSheet { suspend fun shareText(text: String) }
interface Haptics { fun perform(feedback: HapticFeedback) }
interface Biometrics { suspend fun authenticate(prompt: BiometricPrompt): BiometricResult }
interface Notifications { suspend fun show(notification: AppNotification) }
```

### How small is too small?

If two capabilities are *always* used together and never independently, they can share an interface. `LocaleProvider` exposing `currentRegion()`, `currentLanguage()`, and `currentCalendar()` is fine — they're one platform service viewed three ways. But the moment one method has a different lifecycle owner, different fake, or different testability concern from another, split them.

---

## Source-Set Hierarchy Strategy

KMP source sets form a tree. Shared `actual` implementations between non-Android targets often belong in intermediate source sets — `skikoMain` (everything that renders via Skia: desktop + iOS + web) or `appleMain` (iOS + macOS + tvOS). Use them when two platforms can genuinely share an `actual`:

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

AGP 9 replaces `com.android.library` with `com.android.kotlin.multiplatform.library` for the Android side of a KMP module, and rejects the `com.android.application` + `kotlin.multiplatform` combination outright. The new plugin enforces a single-variant architecture and removes several Android-library features that previously bled into boundary design. These constraints are *structural* — they shape what can live in shared code vs. what must move to a platform app module.

- **`BuildConfig` is unavailable.** Compile-time constants come from [BuildKonfig](https://github.com/yshrsmz/BuildKonfig) / [gradle-buildconfig-plugin](https://github.com/gmazzo/gradle-buildconfig-plugin), or — more often — from DI (`AppConfiguration` interface bound per-platform). Don't design `commonMain` APIs that assume `BuildConfig.X` exists.
- **No build variants.** Variant-specific dependencies, resources, and signing belong in the app module, not the shared library. A `debug` vs `release` decision can still surface as a runtime configuration value injected into common code — just not as a build-variant split inside the KMP module.
- **No NDK / JNI.** If common code needs to call into native (C/C++) libraries on Android, extract that into a separate `com.android.library` module and wrap it behind a common interface the KMP module consumes.
- **Compose Multiplatform resources need explicit enable.** Add `androidResources { enable = true }` inside `kotlin { android { ... } }` or `Res.string.*` / `Res.drawable.*` crash at runtime on Android. Easy to miss — the build succeeds.
- **Consumer ProGuard rules need explicit migration.** `consumerProguardFiles("rules.pro")` from the old `android {}` block is silently dropped; use `consumerProguardFiles.add(file("rules.pro"))` in the new DSL.
- **KMP module cannot also be `com.android.application`.** The Android entry point (Activity, Application class, launcher manifest, `applicationId`, `targetSdk`, `versionCode`, `versionName`) must live in a separate `androidApp` module that depends on the shared KMP library. Anything that previously lived in `androidMain` of a `composeApp`-style monolith — `MainActivity`, app-level Hilt setup, navigation host wiring — now belongs in the app module, not the shared library.
- **kapt is incompatible with built-in Kotlin.** AGP 9 has Kotlin support built into `com.android.application` and `com.android.library`, and `org.jetbrains.kotlin.kapt` no longer applies. Migrate annotation processors to KSP (requires KSP 2.3.1+) or fall back to `com.android.legacy-kapt` for processors with no KSP equivalent.

### Where does this code live?

| Concern | Pre-AGP-9 (monolithic) | AGP 9 KMP library |
|---|---|---|
| `MainActivity`, Application class, launcher manifest | `androidMain` of shared module | Separate `androidApp` module |
| `applicationId`, `versionCode`, `targetSdk` | Shared module's `android {}` | `androidApp` only |
| Compile-time constants (env, feature flags) | `BuildConfig` field | `BuildKonfig` in common, or runtime DI |
| Debug vs release variants | `buildTypes {}` in shared module | App module; runtime config in shared |
| NDK / JNI native code | `androidMain` (any module) | Separate `com.android.library`, wrapped behind a common interface |
| App-level resources (launcher icon, theme) | Shared module's `androidMain/res` | `androidApp` module |

If you're starting a new KMP project on AGP 9, design with these constraints from day one — they're not migration steps, they're the new shape of a KMP library. If you're migrating an existing project, see JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) skill for the full migration mechanics.

---

## Compose-Specific Boundary Rules

### 1. Keep platform-specific composables at leaf nodes

```kotlin
// commonMain — layout is shared; only the map widget is platform-specific
@Composable
fun MapScreen(state: MapState, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Header(state.title)
        NativeMapView(coords = state.center, modifier = Modifier.weight(1f))  // UIKitView on iOS, AndroidView on Android
        Controls(onZoomIn = state.onZoomIn, onZoomOut = state.onZoomOut)
    }
}

@Composable expect fun NativeMapView(coords: Coords, modifier: Modifier = Modifier)
```

Don't `expect` the whole screen — duplicating the layout per platform means every UI change happens twice and Compose Preview can't render it.

### 2. Pass `Modifier` through every expected composable that emits UI

```kotlin
// WRONG — caller can't size or place the leaf
@Composable expect fun NativeMapView(coords: Coords)
// RIGHT — leaf participates in the shared layout
@Composable expect fun NativeMapView(coords: Coords, modifier: Modifier = Modifier)
```

See `compose/references/modifiers.md` for the broader modifier-as-API-contract rule.

### 3. Effect discipline inside actuals

`LaunchedEffect`, `DisposableEffect`, `rememberUpdatedState`, and stable keys apply *inside* actual composables exactly as in common Compose code. An actual that wraps a native view and forgets to clean up on dispose has the same bug as any other Compose code.

```kotlin
// iosMain
@Composable
actual fun NativeMapView(coords: Coords, modifier: Modifier) {
    val view = remember { MKMapView() }
    LaunchedEffect(coords) { view.setCenterCoordinate(coords.toCLLocation(), animated = true) }
    DisposableEffect(view) {
        val delegate = MapDelegate()
        view.delegate = delegate
        onDispose { view.delegate = null }
    }
    UIKitView(factory = { view }, modifier = modifier)
}
```

---

## Swift Interop at the Boundary

Code exposed to iOS — whether through `expect`/`actual`, an interface implementation, or a `ComposeUIViewController` factory — ends up on the Kotlin↔Swift bridge, which has its own naming, type-width, and exhaustiveness rules that catch projects out at integration time.

See `references/ios-interop.md` for:
- Kotlin → Swift naming (`fileNameKt.foo()`, `object.shared`, companion access)
- Type bridging (`Int` is 32-bit Kotlin / `Int32` Swift, `Unit` becomes `KotlinUnit`, `List<T>` is copied not shared)
- `suspend` → `async` and `Flow` → `AsyncSequence` via SKIE
- Sealed-class exhaustiveness with SKIE `onEnum(of:)`
- Embedding SwiftUI in Compose via `UIHostingController` + `UIKitViewController`
- iOS API design rules (`@HiddenFromObjC`, `isStatic`, batch-don't-iterate)

Load it when authoring the iOS-side actual or the SwiftUI bridge, not for every KMP boundary decision.

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
| `suspend` actual returns "when launched" with no doc — caller treats it as completion | Document the `suspend` contract in the interface |
| Platform UI leaks high in the composable tree | Push the platform composable to a leaf; share the rest |
| Intermediate source set (`skikoMain`) created with only one platform under it | Don't introduce hierarchy until a second platform shares the actual |
| Native view embedded with no `DisposableEffect` cleanup | Add `onDispose { view.delegate = null }` (or equivalent) |
| `commonMain` test needs an Android/iOS runtime to verify business behaviour | The boundary should be fakeable in common tests |
| Designing a `commonMain` API around `BuildConfig` in an AGP-9 KMP library | Use `BuildKonfig` or inject an `AppConfiguration` |
