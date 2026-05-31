# Android Skills

Skills for Android and KMP development — covering architecture, data layer, networking (Retrofit, Ktor), persistent storage (Room, DataStore), pagination, dependency injection (Hilt, Koin), testing, debugging, Jetpack Compose, coroutines, flows, Gradle, and RxJava migration. Works as a plugin for Claude Code and Copilot CLI.

Several skills in this collection were inspired by or built on top of work from the community — specifically [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills), [compose-skill (aldefy)](https://github.com/aldefy/compose-skill), [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill), [chrisbanes/skills](https://github.com/chrisbanes/skills), [material-3-skill](https://github.com/hamen/material-3-skill), [compose_skill](https://github.com/hamen/compose_skill), and [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills). Skills with no attribution tag are original work.

## Installation

### Claude Code (plugin)

Install as a plugin to get all skills:

```
/plugin marketplace add rcosteira79/android-skills
/plugin install android-skills@android-skills
```

Updates are picked up automatically when the plugin version is bumped.

### Claude Code (manual)

Alternatively, copy the skill directories into your Claude Code skills folder:

```bash
git clone https://github.com/rcosteira79/android-skills.git
cp -r android-skills/plugins/android-skills/skills/* ~/.claude/skills/
```

### Copilot CLI (plugin)

Copilot CLI detects the same plugin format automatically:

```bash
copilot plugin install rcosteira79/android-skills
```

### Other agentic editors

Each skill is self-contained — the `SKILL.md` files are plain markdown, so they can be adapted to other editors that support custom instructions.

### Recommended companion tools

The skills work standalone, but several integrate with external tools for enhanced capabilities. These are independent of the plugin install — use them alongside whichever agent you choose.

#### android-source-explorer MCP

For enhanced source code navigation (local source sync, Tree-sitter parsing, class hierarchy, LSP), install [android-source-explorer-mcp](https://github.com/mrmike/android-source-explorer-mcp):

```bash
uv tool install git+https://github.com/mrmike/android-source-explorer-mcp
```

The `android-source-search` and `compose` skills automatically use the MCP tools when available, and fall back to Gitiles/GitHub otherwise.

#### IntelliJ Index MCP

For semantic navigation of your project's code via the IDE's symbol index, install [jetbrains-index-mcp-plugin](https://github.com/hechtcarmel/jetbrains-index-mcp-plugin) in Android Studio or IntelliJ. The agent uses it for type-hierarchy queries — finding implementations, overrides, callers, references through typealiases — with much higher recall than text search alone. Particularly valuable for the `compose`, `android-debugging`, `android-testing`, and `rxjava-migration` skills. Requires the IDE running with the project indexed.

#### Android CLI

Several skills — notably [`compose`](plugins/android-skills/skills/compose/SKILL.md) and [`android-debugging`](plugins/android-skills/skills/android-debugging/SKILL.md) — have CLI-native shortcuts when Google's `android` CLI is installed: documentation search over the Android Knowledge Base (`android docs`), runtime UI layout inspection (`android layout`), device/emulator orchestration, and SDK management. The skills still work without it, but recommend installing it for the best experience.

Follow Google's installation instructions: <https://developer.android.com/tools/agents/android-cli>

## Skills

Skills are invoked automatically based on context (e.g. working on Compose code activates the `compose` skill).

### `android-dev`
Senior Android engineering knowledge and best practices for Android and KMP projects — architecture, code quality, MVI event naming, four-bucket UiState modeling, and `Channel(BUFFERED)` vs `SharedFlow(replay = 0)` rationale for one-shot effects.

> Inspired by [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill)

### `android-testing`
Test-driven development for Android/KMP — extends TDD with Android's three-tier test model, fake-first strategy, coroutine testing, Compose UI testing, and Roborazzi screenshot testing.

> Inspired by [chrisbanes/skills](https://github.com/chrisbanes/skills)

> Granular tool references (Mockito, MockK, `runTest`, Turbine, Robolectric, Espresso, UiAutomator, Gradle Managed Devices, `kotlin.test`) cross-reference the `jvm-tests`, `instrumentation`, and `kotlin` sets of [skydoves/android-testing-skills](https://github.com/skydoves/android-testing-skills).

### `android-ux`
Material Design 3 UX principles for Android — touch targets (48×48dp), 8dp spacing grid, navigation patterns (Bottom Bar, Rail, Drawer), canonical layouts (Feed, List-Detail, Supporting Pane), foldable postures (tabletop, book mode), M3 contrast levels, safe area handling, accessibility, animation timing, M3 motion duration tokens, keyboard input types, and an M3 compliance audit that scores screens across 10 categories with grep-based quick checks.

> Inspired by [material-3-skill](https://github.com/hamen/material-3-skill)

### `android-debugging`
Debugging Android and KMP issues — Logcat, ADB, ANR traces, R8 stack trace decoding (forward and inverse-mapping), Perfetto trace investigation escalation, memory leaks, Gradle build failures, and Compose recomposition bugs.

> Inverse-mapping (reading obfuscated third-party code via `jadx --deobf`) cross-references the [`android-reverse-engineering`](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) plugin. Deep performance trace investigation cross-references Google's [`perfetto-sql`](https://github.com/android/skills/tree/main/profilers/perfetto-sql) and [`perfetto-trace-analysis`](https://github.com/android/skills/tree/main/profilers/perfetto-trace-analysis) skills.

### `android-source-search`
Fetch and verify Android source code — AOSP platform internals (`@hide` APIs, framework classes, system services via Gitiles) and AndroidX/Jetpack library source and samples (via GitHub). Also useful when public docs are insufficient to complete a task.

> This skill is a zero-setup fallback. For enhanced capabilities (local source sync, sub-10ms Tree-sitter parsing, method-level extraction, class hierarchy, LSP), install [android-source-explorer-mcp](https://github.com/mrmike/android-source-explorer-mcp) separately — the skill will use it automatically when available.

### `kotlin-coroutines`
Dispatcher selection, scope management, structured concurrency, cancellation, exception handling, and Android/KMP async patterns. Includes the DispatcherProvider pattern for testable dispatcher injection.

> Incorporates material from [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

> Inspired by [chrisbanes/skills](https://github.com/chrisbanes/skills)

### `kotlin-flows`
Flow type selection (`Flow`/`StateFlow`/`SharedFlow`), operator chains, callback bridging, lifecycle-safe collection, Channel migration, and UI state management.

> Inspired by [chrisbanes/skills](https://github.com/chrisbanes/skills)

### `compose`
Jetpack Compose expert guidance — state management (`@Composable`, `remember`, `mutableStateOf`, `derivedStateOf`, state hoisting, unified keying rule, cross-phase back-writing), Modifier chains, lazy lists (including `LazyLayoutCacheWindow` prefetch tuning), navigation (Nav 2 + Nav 3 Compose-shape guardrails), animation, side effects (`LifecycleStartEffect`/`LifecycleResumeEffect`), theming, accessibility, performance optimization (Argument Change Reasons, the five compiler stability types including `runtime stable`, subcomposition pitfalls, escape-hatch annotations, baseline profile `Require` vs `UseIfAvailable`), focus/key-event navigation (`FocusRequester`, `focusable`, `focusProperties`, D-pad/TV/ChromeOS, lazy-list focus restoration, dialog focus traps, predictive-back, testing with `performKeyInput` + `assertIsFocused`), and a production-crash playbook with CMP equivalents for `LocalConfiguration` and `rememberSaveable`.

> Forked from [compose-skill](https://github.com/aldefy/compose-skill) — reference docs rebased on live source verification instead of the upstream's bundled AndroidX snapshots.

> Incorporates patterns from [chrisbanes/skills](https://github.com/chrisbanes/skills), [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills), and [compose_skill (hamen)](https://github.com/hamen/compose_skill)

### `rxjava-migration`
Triggered only when you explicitly ask to migrate. Assesses complexity, maps RxJava types and operators to coroutines equivalents, and provides interop patterns for incremental migration.

> Incorporates material from [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `android-retrofit`
Retrofit setup for Android — service interface patterns (`@GET`, `@POST`, `@Path`, `@Query`, `@Body`), coroutines integration, OkHttp configuration, Hilt module, and error handling in the repository layer.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `kmp-ktor`
Ktor client setup for KMP and Android — per-platform engine selection (OkHttp/Darwin/CIO), `kotlinx.serialization` configuration, bearer token auth with refresh via the `Auth` plugin, plugin install order, `MockEngine` testing, error mapping at the repository boundary, the advanced `safeRequest` + sealed `ApiResult<T>` pattern, and WebSocket/SSE support.

> Inspired by [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill). The plugin install order rule (`ContentNegotiation → Auth → HttpRequestRetry → HttpTimeout → ContentEncoding`), `expectSuccess` decision table, sealed `ApiResult<T>` advanced alternative with `safeRequest`, and WebSockets/SSE sections absorbed from the upstream.

### `kmp-boundaries`
Designing Kotlin Multiplatform boundaries — choosing between `expect`/`actual`, common interfaces with platform bindings, or separate platform screens. Covers capability granularity (split by capability, not one `Platform` object), the thin-actuals rule, source-set hierarchies (`skikoMain`, `appleMain`), Compose Multiplatform leaf positioning, AGP 9 KMP library plugin constraints, and a dedicated iOS Swift interop reference (Kotlin↔Swift naming, type bridging, SKIE, sealed-class exhaustiveness, `UIHostingController` embedding).

> Inspired by [chrisbanes/skills](https://github.com/chrisbanes/skills)

> The iOS Swift interop reference (Kotlin → Swift naming, type bridging, SKIE async/AsyncSequence, exhaustive sealed-class switches with `onEnum(of:)`, `ComposeUIViewController` / `UIKitViewController` with `UIHostingController` for embedding SwiftUI in Compose, and iOS API design rules like `@HiddenFromObjC` and `isStatic`) adapted from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill)

### `android-data-layer`
Data layer implementation — Repository pattern as single source of truth, Room DAOs with `Flow`, KMP Room setup (`@ConstructedBy`, `BundledSQLiteDriver`, per-target KSP), offline-first strategies (stale-while-revalidate, outbox pattern), and model mapping between DTO/entity/domain types.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills). Room KMP setup section (`@ConstructedBy` + `expect object`, `BundledSQLiteDriver`, `setQueryCoroutineContext`, per-target KSP wiring) adapted from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill).

### `coil-compose`
Image loading in Compose with Coil — `AsyncImage` vs `SubcomposeAsyncImage` vs `rememberAsyncImagePainter`, `ImageRequest` configuration, performance in lazy lists, and Hilt setup for a shared `ImageLoader`.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `android-gradle-logic`
Scalable Gradle build logic — Convention Plugins, composite builds, shared `compileSdk`/`minSdk`/Compose configuration across modules, and clean per-module `build.gradle.kts` files.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `gradle-build-performance`
Gradle build optimisation — Build Scans, configuration cache, build cache, kapt→KSP migration, parallel execution, lazy task configuration, and a recommended `gradle.properties` baseline.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `datastore`
Jetpack DataStore for Android and KMP — Preferences vs Typed selection, KMP factory with per-platform file paths (Android `filesDir`, iOS `NSFileManager`, JVM `~/.appname/`), all preference key types, `SharedPreferences` migration, `Serializer<T>` with `corruptionHandler` for typed stores, DI singletons (Koin + Hilt), and repository / MVI integration.

> Adapted from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill)'s DataStore reference

### `paging`
Paging 3 for Android and Compose — `PagingSource`, `Pager` / `PagingConfig`, the critical "PagingData must be a separate Flow, never inside UiState" rule, dynamic filters via `flatMapLatest` + `debounce`, `cachedIn` placement, `LazyColumn` integration with `itemKey` / `itemContentType` / load-state handling, `RemoteMediator` for offline-first lists with Room, and unit tests with `TestPager` + `asSnapshot`.

> Adapted from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill)'s Paging 3 references

### `koin`
Koin dependency injection for Android and KMP — Classic DSL vs KSP annotations decision, `expect val platformModule: Module` for per-target engine wiring, `koinViewModel` in Compose, scopes (`scope<T>`, `activityRetainedScope`), Nav 3 entry providers via `koinEntryProvider()`, compile-time module verification with `verify()`, and a clear Koin-vs-Hilt positioning (Koin for KMP and `verify()`, Hilt for Android-only and codegen-enforced graph validation).

> Adapted from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill)'s Koin reference

## Removed skills

- **`xml-to-compose-migration`** — dropped in favour of Google's actively-maintained [`migrate-xml-views-to-jetpack-compose`](https://github.com/android/skills/tree/main/jetpack-compose/migration), available via the [`android/skills`](https://github.com/android/skills) repo.

## Related Projects

- [android/skills](https://github.com/android/skills) — Google's official Android agent skills covering AGP 9 migration (pure-Android; KMP is out of scope), XML-to-Compose migration, Navigation 3, R8 analysis, Play Billing upgrades, and edge-to-edge support
- [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills) — JetBrains' official agent skills for Kotlin, covering AGP 9 migration for KMP (the complement to Google's pure-Android `agp-9-upgrade`), CocoaPods → SwiftPM migration, framework-aware Java-to-Kotlin conversion, and Kotlin backend/JPA entity mapping
- [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills) — curated list of Android agent skills that inspired many of the skills in this repo
- [compose-skill](https://github.com/aldefy/compose-skill) — alternative Compose skill that bundles a static AndroidX snapshot
- [android-source-explorer-mcp](https://github.com/mrmike/android-source-explorer-mcp) — MCP server for navigating Android source code (optional, used by `android-source-search` skill)
- [material-3-skill](https://github.com/hamen/material-3-skill) — comprehensive Material Design 3 reference covering 30+ components, design tokens, theming, responsive layout, and dynamic color across platforms
- [compose_skill](https://github.com/hamen/compose_skill) — ships two complementary skills: `jetpack-compose-audit` (a strict, evidence-based audit skill that scores repos 0–100 on performance, state, side effects, and API quality using automated Compose Compiler reports + an `--init-script` for project-edit-free auditing) and `compose-agent` (a teaching/authoring skill with 13 reference files covering state, effects, performance, modifiers, navigation, concurrency, flows, component API, testing, focus, KMP, kotlin style, and API migrations). We've absorbed targeted rules from both into our `compose` skill; install hamen's directly for the full audit+score workflow.
- [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill) — broad Compose + KMP skill covering MVI/MVVM, Navigation 2 & 3, Ktor, Koin/Hilt, Room, DataStore, Paging, and iOS interop; inspired the `kmp-ktor` skill in this repo
- [chrisbanes/skills](https://github.com/chrisbanes/skills) — Chris Banes' narrow, opinionated Compose and Kotlin skills covering state authoring, side effects, recomposition performance, stability diagnostics, focus navigation, UI testing patterns, structured concurrency, flow primitive selection, and KMP expect/actual boundaries; informed the `kmp-boundaries` and `focus-navigation` references and authoring rules across several existing skills
- [android-reverse-engineering-skill](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) — Claude Code plugin for decompiling APKs, extracting API endpoints, and tracing call flows
- [skydoves/android-testing-skills](https://github.com/skydoves/android-testing-skills) — 54 source-grounded testing skills organized as a 7-set catalog the author says to cherry-pick from: `compose` (25), `fundamentals` (5), `kotlin` (1), `jvm-tests` (6), `instrumentation` (6), `platform` (1), `adb` (10). Complements our `android-testing`: the `jvm-tests`, `instrumentation`, and `kotlin` sets fit cleanly alongside it without overlap; the `compose` and `fundamentals` sets overlap our `compose` and `android-testing` coverage. Apache-2.0.
- [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills) — sister repo covering the *performance* side of Compose (stability, recomposition, lazy layouts, baseline profiles, R8, hot reload). Same authoring spec; install both for full testing + performance coverage.

## License

MIT
