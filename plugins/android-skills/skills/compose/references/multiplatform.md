# Compose Multiplatform (CMP) Reference

A strong model already knows the CMP shape by default: shared UI in `commonMain` (runtime / foundation / material3 / navigation are all multiplatform, Skia-rendered off-Android), `expect`/`actual` for platform bridges, per-platform entry points (`ComponentActivity.setContent`, `application { Window }`, `ComposeUIViewController`, `ComposeViewport`), and `Res.*` Compose Resources (`Res.drawable`/`Res.string`/`Res.font`, files under `commonMain/composeResources/`, `values-fr/` localization, Android XML vector drawables render on every platform). This reference keeps the migration facts + cross-platform gotchas it gets wrong.

## Android-only APIs (nearly everything else is in commonMain)

`AndroidView`, `BackHandler`, `dynamicColorScheme()`, `LocalContext`, **`collectAsStateWithLifecycle()`**, `hiltViewModel()`, Baseline Profiles / Macrobenchmark. Desktop-only: `Window` / `MenuBar` / `Tray`, `DialogWindow`, scrollbars, `SwingPanel`. iOS-only: `UIKitView` / `UIKitViewController`, `ComposeUIViewController`, `LocalUIViewController`.

## Migration: Android-only → CMP

| Android-only | CMP replacement |
|---|---|
| `hiltViewModel()` | `koinViewModel()` (Koin is first-class KMP) or KMP `viewModel { }` |
| Retrofit | Ktor Client (`android-skills:kmp-ktor`) |
| Room | Room KMP (2.7.0+) or SQLDelight |
| Coil 2.x | Coil 3.x — same API, fully KMP (`android-skills:coil-compose`) |
| **Lottie** | **Kottie / Compottie** — `com.airbnb.lottie:lottie-compose` is Android-only |
| `R.drawable.*` / `R.string.*` | `Res.drawable.*` / `Res.string.*` |
| **`collectAsStateWithLifecycle()`** | **`collectAsState()`** — see gotcha below |
| `LocalContext.current` | a common interface (or `expect`/`actual`) — see gotcha below |
| `rememberSaveable` + `Bundle` + `@Parcelize` | `@Serializable` + a custom `Saver` (Bundle/Parcelize are Android-only) |
| `BackHandler` | `expect`/`actual` per platform |

## The gotchas the default gets wrong

**`collectAsState()`, not `collectAsStateWithLifecycle()`, in `commonMain`** — the lifecycle-aware variant is Android-only, yet all three default models reach for it in shared code. (Desktop/Web don't background like Android; iOS CMP handles lifecycle — unless `lifecycle-runtime-compose:2.10.0+` surfaces the lifecycle-aware variant in commonMain.)

**`@Preview` in commonMain is `org.jetbrains.compose.ui.tooling.preview.Preview`, NOT `androidx.compose.ui.tooling.preview.Preview`** — the androidx one is Android-only and won't compile in commonMain. Add `compose.components.uiToolingPreview`. Android Studio renders androidMain previews; IntelliJ/Fleet render commonMain ones.

**`LocalContext` has no KMP replacement** — abstract platform needs behind a common interface. A share sheet specifically is a UI op needing a foreground `Activity`: use a common `ShareSheet` interface with an **Activity-owned** Android binding (not `applicationContext + FLAG_ACTIVITY_NEW_TASK`), not an `expect fun` (which can't be faked in tests or hold an Activity). Full bindings in `android-skills:kmp-boundaries`.

**Compose-compiler stability inference can be wrong on non-JVM targets** — the compiler may mark classes unstable on iOS/WASM (→ excessive recomposition). Check the stability report for *all* targets, not just Android, and `@Immutable`-annotate shared data classes when inference misses them.

**Version lockstep** — Kotlin / `org.jetbrains.compose` / `org.jetbrains.kotlin.plugin.compose` / AGP have strict compatibility; mismatches produce cryptic compiler errors. Check the JetBrains compatibility-and-versioning table.

**Don't migrate bottom-up** — migrating leaf modules first leaves a broken build for weeks. Add the KMP plugin to the app module, move composables to `commonMain` one screen at a time with `expect`/`actual` stubs, then migrate feature modules once the app module compiles.

## Navigation

`androidx.navigation:navigation-compose` is fully multiplatform as of 2.8.0+ (`@Serializable` type-safe routes work in commonMain). Deep links integrate with `Intent` / manifest on Android but must be wired manually elsewhere (iOS URL scheme, Web URL). Navigation 3's `navigation3-common` is multiplatform but `navigation3-ui` isn't fully KMP yet — wait for stable before relying on it. (Voyager and Decompose are third-party KMP alternatives.)
