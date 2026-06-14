---
name: kmp-boundaries
description: Use when designing Kotlin Multiplatform boundaries — choosing between expect/actual, common interfaces with platform bindings, or separate platform screens. Covers platform services (clipboard, share, haptics, permissions, files, settings, sensors, biometrics), native SDKs, source-set hierarchies (commonMain, skikoMain, appleMain, androidMain), Compose Multiplatform interop, and capability granularity. Use whenever common code needs to reach a platform API and you're picking the boundary shape.
---

# Kotlin Multiplatform Boundary Design

Core rules for any KMP boundary:

- **Keep `commonMain` semantic** — describe *what* the product needs, not Android/iOS mechanics: `currentRegion()`, never `currentRegionFromAndroidLocale(context)`.
- **Split by capability** — `Clipboard`, `ShareSheet`, `Haptics`, `Biometrics` as separate interfaces, not one `Platform` god object.
- **Keep actuals thin** — they translate, they don't decide; a business `if`/`when` inside an actual belongs in common, tested with a fake.
- **Prefer a common `interface` + per-platform binding over `expect class`** whenever you need fakes / DI / lifecycle / runtime selection.
- **Introduce an intermediate source set** (`skikoMain`, `appleMain`) only when two platforms genuinely share an actual.

Two boundaries get the most detail below: the **Activity-owned** platform-UI boundary, and the **AGP-9 KMP-library** constraints.

**Related:** `android-skills:kmp-ktor` (network boundary), `compose/references/multiplatform.md` (Compose-MP mechanics), `android-skills:kotlin-coroutines` (scope ownership). For the iOS↔Swift bridge — Kotlin→Swift naming, type widths (`Int` is 32-bit), SKIE `suspend`→`async` / `Flow`→`AsyncSequence`, sealed-class exhaustiveness, SwiftUI embedding — load `references/ios-interop.md` when authoring the iOS-side actual.

## Platform-UI bindings are Activity-owned, not Context-owned

The single most common Android boundary mistake: passing `applicationContext` / `LocalContext.current` into a binding that actually needs an `Activity`, then papering over the lifecycle gap with `Intent.FLAG_ACTIVITY_NEW_TASK`. That flag is a smell — it hides that this is a foreground-UI operation. Hold an `Activity` instead.

```kotlin
// commonMain — semantic interface; DOCUMENT what `suspend` means
interface ShareSheet {
    /** Launches the system share sheet. Returns when the sheet is PRESENTED — not when the user
     *  completes or cancels. (Otherwise callers write incorrect retry/confirmation logic.) */
    suspend fun shareText(text: String)
}

// androidMain — thin: build the intent and launch it. Activity-owned.
class AndroidShareSheet(private val activity: Activity) : ShareSheet {
    override suspend fun shareText(text: String) {
        activity.startActivity(Intent.createChooser(
            Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null,
        ))
    }
}
```

You don't app-wide-inject an `Activity` (it's framework-created and lifecycle-bound) — construct the binding in an **activity scope** in the Android app module (Hilt `@InstallIn(ActivityComponent::class)`, where `Activity` is a default binding; Koin `scoped`). `commonMain` only ever sees the interface; the `Activity` never leaves the app module. If a longer-lived (app-scoped) object needs it, hold it behind a lifecycle-aware provider (set in `onResume`, cleared in `onPause`) so a destroyed Activity can't leak.

## AGP-9 KMP-library constraints (structural — they shape what can live in shared code)

AGP 9 replaces `com.android.library` with **`com.android.kotlin.multiplatform.library`** for the Android side of a KMP module, and rejects `com.android.application` + `kotlin.multiplatform` outright. The new plugin enforces a single-variant architecture:

- **`BuildConfig` is unavailable** — compile-time constants come from [BuildKonfig](https://github.com/yshrsmz/BuildKonfig) or an injected `AppConfiguration` interface. Don't design `commonMain` APIs that assume `BuildConfig.X` exists.
- **No build variants** — variant-specific deps/resources/signing live in the app module; a debug/release decision surfaces as a runtime config value injected into common code, not a build-variant split inside the KMP module.
- **No NDK / JNI** — extract native (C/C++) into a separate `com.android.library` module, wrapped behind a common interface the KMP module consumes.
- **Compose-MP resources need explicit enable** — add `androidResources { enable = true }` inside `kotlin { android { … } }`, or `Res.string.*` / `Res.drawable.*` crash at runtime on Android (the build still succeeds — easy to miss).
- **Consumer ProGuard rules need migration** — `consumerProguardFiles("rules.pro")` from the old `android {}` block is silently dropped; use `consumerProguardFiles.add(file("rules.pro"))` in the new DSL.
- **The KMP module can't also be `com.android.application`** — the Android entry point (`MainActivity`, Application class, launcher manifest, `applicationId` / `targetSdk` / `versionCode` / `versionName`) moves to a separate `androidApp` module that depends on the shared library. `MainActivity`, app-level Hilt setup, and nav-host wiring all move out of the shared `androidMain`.
- **kapt is incompatible** with AGP 9's built-in Kotlin — migrate annotation processors to KSP (2.3.1+), or fall back to `com.android.legacy-kapt` for processors with no KSP equivalent.

| Concern | Pre-AGP-9 (monolithic) | AGP 9 KMP library |
|---|---|---|
| `MainActivity`, Application class, launcher manifest | `androidMain` of shared module | Separate `androidApp` module |
| `applicationId`, `versionCode`, `targetSdk` | Shared module's `android {}` | `androidApp` only |
| Compile-time constants (env, flags) | `BuildConfig` field | `BuildKonfig` in common, or runtime DI |
| NDK / JNI native code | `androidMain` (any module) | Separate `com.android.library`, behind a common interface |

For migrating an existing project, see JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) skill for the full mechanics.
