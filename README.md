<div align="center">

# Android Skills

**Android & KMP development skills for Claude Code and Copilot CLI** — architecture, Compose, coroutines, flows, networking, persistence, dependency injection, testing, debugging, and Gradle.

![version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Frcosteira79%2Fandroid-skills%2Fmain%2F.claude-plugin%2Fmarketplace.json&query=%24.metadata.version&label=version&color=3b82f6&prefix=v)
![skills](https://img.shields.io/badge/skills-22-8b5cf6)
![license](https://img.shields.io/badge/license-MIT-2f9e6f)
![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-d97757)
![Copilot CLI](https://img.shields.io/badge/Copilot_CLI-plugin-24292e)

</div>

Skills are invoked automatically based on context — working on Compose code activates the `compose` skill, a coroutine bug pulls in `kotlin-coroutines`, and so on. Each `SKILL.md` is plain, self-contained markdown, so the collection also works outside the plugin format.

## Contents

- [Installation](#installation)
- [Skills](#skills)
- [Companion tools](#companion-tools)
- [Related projects](#related-projects)
- [Attribution](#attribution)
- [License](#license)

## Installation

### Claude Code (plugin)

```
/plugin marketplace add rcosteira79/android-skills
/plugin install android-skills@android-skills
```

Updates are picked up automatically when the plugin version is bumped.

### Copilot CLI (plugin)

Copilot CLI detects the same plugin format automatically:

```bash
copilot plugin install rcosteira79/android-skills
```

### Manual / other agents

Copy the skill directories into your agent's skills folder:

```bash
git clone https://github.com/rcosteira79/android-skills.git
cp -r android-skills/plugins/android-skills/skills/* ~/.claude/skills/
```

The `SKILL.md` files are plain markdown, so they can be adapted to any editor that supports custom instructions.

## Skills

### Foundation & architecture

- **`android-dev`** — the baseline for Android and KMP work: house defaults (DI, async, JSON, images, networking, module boundaries), routing to the specialised skills, the greenfield MVVM state/effect UI convention, four-bucket `UiState` modeling, and `Channel(BUFFERED)` over `SharedFlow(replay = 0)` for one-shot effects.
- **`modularization`** — visibility discipline for multi-module projects: declare everything at the lowest visibility that still compiles (`private` → `internal` → `public`), keep DI-bound implementation classes `internal` behind `public` interfaces, and treat widening to `public` as a decision that requires a real cross-module consumer.
- **`android-data-layer`** — data-layer implementation: the layered error-propagation model (repository as the error boundary, sealed `DataError`, `Result` placement with and without a domain layer) and KMP Room setup (`@ConstructedBy`, `BundledSQLiteDriver`, per-target KSP).
- **`android-domain-layer`** — where behaviour goes in the domain layer: business *rules* on the model (invariants at construction, derived values as properties, value objects, `require` vs `Result`) and business *logic* in use cases (orchestration, the `Result` boundary, when a use case is pure overhead), plus the placement test, the restraint clause for tickets that state no rule at all, the three obligations of relocating a rule (identical behaviour, the old call site moves, the helpers travel), what never enters the domain module, and review smells in both directions.

### UI — Compose & design

- **`compose`** — Jetpack Compose expert guidance: state management (`remember`, `derivedStateOf`, hoisting, the unified keying rule, cross-phase back-writing), Modifier chains, lazy lists (`LazyLayoutCacheWindow` prefetch tuning), navigation (Nav 2 + Nav 3 guardrails), animation, side effects (`LifecycleStartEffect`/`LifecycleResumeEffect`), theming, accessibility, performance (Argument Change Reasons, the five compiler stability types, escape-hatch annotations, baseline profiles), focus/key-event navigation (D-pad/TV/ChromeOS, focus restoration, dialog focus traps, predictive-back), and a production-crash playbook with CMP equivalents.
- **`android-ux`** — Material Design 3 UX principles: foldable postures (tabletop, book mode), M3 contrast levels (`Hct`/`SchemeContent`), motion duration tokens and reduced motion, and an M3 compliance audit scoring screens across 10 categories with grep-based quick checks.
- **`coil-compose`** — image loading in Compose and CMP with Coil 3: the KMP specifics (`LocalPlatformContext`, `SingletonImageLoader.setSafe`, `coil-compose` vs `coil-compose-core`) and two lazy-list performance guardrails (never `SubcomposeAsyncImage` in lists; `rememberAsyncImagePainter` needs an explicit size).

### Async — Kotlin

- **`kotlin-coroutines`** — scope management, structured concurrency, cancellation, and exception handling, centered on scope ownership (prefer `suspend fun`, let the caller own the scope) and exception discipline that doesn't break cancellation.
- **`kotlin-flows`** — Flow traps and semantic edge cases: `Channel` vs `SharedFlow` one-shot event semantics, callback bridging (`callbackFlow` + `awaitClose`), retry attempt guards, `.catch` scope and the `CancellationException` trap, side effects outside transforms, and explicit backing fields (Kotlin 2.4+).

### Networking

- **`android-retrofit`** — Retrofit setup: `suspend` service functions returning the body directly (`Response<T>` only when you need status/headers/error body), the auth-interceptor throw-vs-proceed decision, loose-JSON `kotlinx.serialization` config, and error mapping at the repository boundary.
- **`kmp-ktor`** — Ktor client configuration traps for KMP and Android: plugin install order (`HttpRequestRetry` before `HttpTimeout`), `encodeDefaults = true` and the vanishing-constant-field trap, `expectSuccess` consistency, bearer refresh with `markAsRefreshTokenRequest()`, WebSocket/SSE via the serialization converter, `MockEngine` testing, and error mapping at the repository boundary.

### Persistence & lists

- **`datastore`** — Jetpack DataStore for Android and KMP: Preferences vs Typed vs Room selection, the two error traps (`IOException`-specific `.catch`; `CorruptionException` + `ReplaceFileCorruptionHandler` for typed stores), and the KMP factory with per-platform file paths.
- **`paging`** — Paging 3 for Android and Compose: `PagingSource`, `Pager`/`PagingConfig`, the critical "PagingData must be a separate Flow, never inside UiState" rule, dynamic filters via `flatMapLatest` + `debounce`, `cachedIn` placement, `LazyColumn` integration (`itemKey`/`itemContentType`/load-state handling), `RemoteMediator` for offline-first lists with Room, and unit tests with `TestPager` + `asSnapshot`.

### Dependency injection

- **`koin`** — Koin for Android and KMP: Classic DSL vs KSP annotations, `expect val platformModule: Module` for per-target wiring, `koinViewModel` in Compose, scopes, Nav 3 entry providers via `koinEntryProvider()`, compile-time verification with `verify()`, and a clear Koin-vs-Hilt positioning.

### Multiplatform

- **`kmp-boundaries`** — designing Kotlin Multiplatform boundaries: choosing between `expect`/`actual`, common interfaces with platform bindings, or separate platform screens; capability granularity, the thin-actuals rule, source-set hierarchies (`skikoMain`, `appleMain`), Compose Multiplatform leaf positioning, AGP 9 KMP library plugin constraints, and a dedicated iOS Swift interop reference.

### Build & Gradle

- **`android-gradle-logic`** — scalable Gradle build logic: Convention Plugins, composite builds, shared `compileSdk`/`minSdk`/Compose configuration across modules, and clean per-module `build.gradle.kts` files.
- **`gradle-build-performance`** — Gradle build optimisation: Build Scans, configuration cache, build cache, kapt→KSP migration, parallel execution, lazy task configuration, and a recommended `gradle.properties` baseline.

### Testing & debugging

- **`android-testing`** — test-first discipline plus the Android test traps: Compose-test dispatching (`StandardTestDispatcher` default, the two-schedulers trap), semantics-first selectors, choosing the smallest test shape, test-clock vs wall-clock, and animation/screenshot determinism.
- **`android-debugging`** — debugging Android and KMP issues: Logcat, ADB, ANR traces, R8 stack trace decoding (forward and inverse-mapping), Perfetto trace investigation escalation, memory leaks, Gradle build failures, and Compose recomposition bugs.

### Platform APIs

- **`pdf-annotations`** — editing PDF annotations (highlight, free-text, stamp) and page objects with Android's platform PDF APIs: the API 36.1 / SDK-extension-18 editing surface (`android.graphics.pdf.component`), the version gate between `PdfRenderer.Page` and `PdfRendererPreV.Page`, the open→edit→write workflow, and the id/render-flag/save contracts.

### Source access & migration

- **`android-source-search`** — fetch and verify Android source: AOSP platform internals (`@hide` APIs, framework classes, system services via Gitiles) and AndroidX/Jetpack library source and samples (via GitHub). A zero-setup fallback; upgrade with [android-source-explorer-mcp](https://github.com/mrmike/android-source-explorer-mcp).
- **`rxjava-migration`** — triggered only when you explicitly ask to migrate: assesses complexity, maps RxJava types and operators to coroutines equivalents, and provides interop patterns for incremental migration.

### Removed

- **`xml-to-compose-migration`** — dropped in favour of Google's actively-maintained [`migrate-xml-views-to-jetpack-compose`](https://github.com/android/skills/tree/main/jetpack-compose/migration).

## Companion tools

The skills work standalone, but several integrate with external tools for enhanced capabilities. These are independent of the plugin install — use them alongside whichever agent you choose.

- **[android-source-explorer-mcp](https://github.com/mrmike/android-source-explorer-mcp)** — local source sync, Tree-sitter parsing, class hierarchy, and LSP for Android source navigation. The `android-source-search` and `compose` skills use it automatically when present, and fall back to Gitiles/GitHub otherwise.

  ```bash
  uv tool install git+https://github.com/mrmike/android-source-explorer-mcp
  ```

- **[jetbrains-index-mcp-plugin](https://github.com/hechtcarmel/jetbrains-index-mcp-plugin)** — semantic navigation via the IDE's symbol index (implementations, overrides, callers, references through typealiases) with much higher recall than text search. Particularly valuable for `compose`, `android-debugging`, `android-testing`, and `rxjava-migration`. Requires Android Studio / IntelliJ running with the project indexed.

- **Google's `android` CLI** — CLI-native shortcuts for `compose` and `android-debugging`: Android Knowledge Base search (`android docs`), runtime UI layout inspection (`android layout`), device/emulator orchestration, and SDK management. Skills work without it, but it's recommended for the best experience. [Install instructions](https://developer.android.com/tools/agents/android-cli).

## Related projects

- [android/skills](https://github.com/android/skills) — Google's official Android agent skills: AGP 9 migration (pure-Android), XML-to-Compose migration, Navigation 3, R8 analysis, Play Billing upgrades, and edge-to-edge support.
- [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills) — JetBrains' official Kotlin skills: AGP 9 migration for KMP, CocoaPods → SwiftPM migration, framework-aware Java-to-Kotlin conversion, and Kotlin backend/JPA entity mapping.
- [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills) — curated list of Android agent skills.
- [chrisbanes/skills](https://github.com/chrisbanes/skills) — narrow, opinionated Compose and Kotlin skills covering state authoring, side effects, recomposition performance, stability diagnostics, focus navigation, UI testing, structured concurrency, and KMP `expect`/`actual` boundaries.
- [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill) — broad Compose + KMP skill covering MVI/MVVM, Navigation 2 & 3, Ktor, Koin/Hilt, Room, DataStore, Paging, and iOS interop.
- [compose-skill (aldefy)](https://github.com/aldefy/compose-skill) — alternative Compose skill that bundles a static AndroidX snapshot.
- [compose_skill (hamen)](https://github.com/hamen/compose_skill) — ships `jetpack-compose-audit` (evidence-based repo scoring via Compose Compiler reports) and `compose-agent` (a teaching/authoring skill with 13 reference files). Install directly for the full audit+score workflow.
- [material-3-skill](https://github.com/hamen/material-3-skill) — comprehensive Material Design 3 reference: 30+ components, design tokens, theming, responsive layout, and dynamic color.
- [skydoves/android-testing-skills](https://github.com/skydoves/android-testing-skills) — 54 source-grounded testing skills as a 7-set catalog to cherry-pick from. The `jvm-tests`, `instrumentation`, and `kotlin` sets fit cleanly alongside `android-testing` without overlap. Apache-2.0.
- [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills) — the performance side of Compose (stability, recomposition, lazy layouts, baseline profiles, R8, hot reload).
- [android-reverse-engineering-skill](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) — decompiling APKs, extracting API endpoints, and tracing call flows.

## Attribution

These skills are my own work — most written from scratch, then sharpened over many audit passes. Where one drew inspiration, adapted a specific section, or (only in `compose`'s case) started from an existing skill, the credit is below. Anything not listed is fully original.

| Skill(s) | Inspiration / adapted material |
|---|---|
| `android-dev`, `kmp-ktor`, `datastore`, `paging`, `koin` | [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill) |
| `android-retrofit`, `coil-compose`, `rxjava-migration`, `android-gradle-logic`, `gradle-build-performance` | [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills) |
| `android-data-layer` | [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills); Room KMP section from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill) |
| `kotlin-coroutines` | [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills) + [chrisbanes/skills](https://github.com/chrisbanes/skills) |
| `android-testing`, `kotlin-flows` | [chrisbanes/skills](https://github.com/chrisbanes/skills) |
| `kmp-boundaries` | [chrisbanes/skills](https://github.com/chrisbanes/skills); iOS Swift interop from [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill) |
| `android-ux` | [material-3-skill](https://github.com/hamen/material-3-skill) |
| `compose` | forked from [aldefy/compose-skill](https://github.com/aldefy/compose-skill), then rebased on live source verification, with patterns from [chrisbanes/skills](https://github.com/chrisbanes/skills), [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills), and [compose_skill (hamen)](https://github.com/hamen/compose_skill) |

## License

MIT
