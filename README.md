# Android Skills

Skills for Android and KMP development — covering architecture, data layer, networking, testing, debugging, Jetpack Compose, coroutines, flows, Gradle, and RxJava migration. Works as a plugin for Claude Code and Copilot CLI.

Several skills in this collection were inspired by or built on top of work from the community — specifically [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills), [compose-skill](https://github.com/aldefy/compose-skill), and [chrisbanes/skills](https://github.com/chrisbanes/skills). Skills with no attribution tag are original work.

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

For semantic navigation of your project's code via the IDE's symbol index, install [jetbrains-index-mcp-plugin](https://github.com/hechtcarmel/jetbrains-index-mcp-plugin) in Android Studio or IntelliJ. The agent uses it for type-hierarchy queries — finding implementations, overrides, callers, references through typealiases — with much higher recall than text search alone. Particularly valuable for the `compose`, `android-debugging`, `android-tdd`, and `rxjava-migration` skills. Requires the IDE running with the project indexed.

#### Android CLI

Several skills — notably [`compose`](plugins/android-skills/skills/compose/SKILL.md) and [`android-debugging`](plugins/android-skills/skills/android-debugging/SKILL.md) — have CLI-native shortcuts when Google's `android` CLI is installed: documentation search over the Android Knowledge Base (`android docs`), runtime UI layout inspection (`android layout`), device/emulator orchestration, and SDK management. The skills still work without it, but recommend installing it for the best experience.

Follow Google's installation instructions: <https://developer.android.com/tools/agents/android-cli>

## Skills

Skills are invoked automatically based on context (e.g. working on Compose code activates the `compose` skill).

### `android-dev`
Senior Android engineering knowledge and best practices for Android and KMP projects. Covers architecture, code quality, and platform-specific patterns.

### `android-tdd`
Test-driven development for Android/KMP — extends TDD with Android's three-tier test model, fake-first strategy, coroutine testing, Compose UI testing, and Roborazzi screenshot testing.

> Inspired by [chrisbanes/skills](https://github.com/chrisbanes/skills)

### `android-ux`
Material Design 3 UX principles for Android — touch targets (48×48dp), 8dp spacing grid, navigation patterns (Bottom Bar, Rail, Drawer), canonical layouts (Feed, List-Detail, Supporting Pane), foldable postures (tabletop, book mode), M3 contrast levels, safe area handling, accessibility, animation timing, keyboard input types, and an M3 compliance audit that scores screens across 10 categories.

> Inspired by [material-3-skill](https://github.com/hamen/material-3-skill)

### `android-debugging`
Debugging Android and KMP issues — Logcat, ADB, ANR traces, R8 stack trace decoding, memory leaks, Gradle build failures, and Compose recomposition bugs.

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
Jetpack Compose expert guidance — state management (`@Composable`, `remember`, `mutableStateOf`, `derivedStateOf`, state hoisting), Modifier chains, lazy lists, navigation, animation, side effects, theming, accessibility, performance optimization, and focus/key-event navigation (`FocusRequester`, `focusable`, `focusProperties`, D-pad/TV/ChromeOS, lazy-list focus restoration, dialog focus traps, predictive-back, and testing with `performKeyInput` + `assertIsFocused`).

> Forked from [compose-skill](https://github.com/aldefy/compose-skill) — reference docs rebased on live source verification instead of the upstream's bundled AndroidX snapshots.

> Incorporates patterns from [chrisbanes/skills](https://github.com/chrisbanes/skills)

### `rxjava-migration`
Triggered only when you explicitly ask to migrate. Assesses complexity, maps RxJava types and operators to coroutines equivalents, and provides interop patterns for incremental migration.

> Incorporates material from [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `android-retrofit`
Retrofit setup for Android — service interface patterns (`@GET`, `@POST`, `@Path`, `@Query`, `@Body`), coroutines integration, OkHttp configuration, Hilt module, and error handling in the repository layer.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `kmp-ktor`
Ktor client setup for KMP and Android — per-platform engine selection (OkHttp/Darwin/CIO), `kotlinx.serialization` configuration, bearer token auth with refresh via the `Auth` plugin, `MockEngine` testing, and error mapping at the repository boundary.

> Inspired by [compose-skill](https://github.com/Meet-Miyani/compose-skill) (Meet-Miyani)

### `kmp-boundaries`
Designing Kotlin Multiplatform boundaries — choosing between `expect`/`actual`, common interfaces with platform bindings, or separate platform screens. Covers capability granularity (split by capability, not one `Platform` object), the thin-actuals rule, source-set hierarchies (`skikoMain`, `appleMain`), and Compose Multiplatform leaf positioning.

> Inspired by [chrisbanes/skills](https://github.com/chrisbanes/skills)

### `android-data-layer`
Data layer implementation — Repository pattern as single source of truth, Room DAOs with `Flow`, offline-first strategies (stale-while-revalidate, outbox pattern), and model mapping between DTO/entity/domain types.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `coil-compose`
Image loading in Compose with Coil — `AsyncImage` vs `SubcomposeAsyncImage` vs `rememberAsyncImagePainter`, `ImageRequest` configuration, performance in lazy lists, and Hilt setup for a shared `ImageLoader`.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `android-gradle-logic`
Scalable Gradle build logic — Convention Plugins, composite builds, shared `compileSdk`/`minSdk`/Compose configuration across modules, and clean per-module `build.gradle.kts` files.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

### `gradle-build-performance`
Gradle build optimisation — Build Scans, configuration cache, build cache, kapt→KSP migration, parallel execution, lazy task configuration, and a recommended `gradle.properties` baseline.

> Inspired by [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills)

## Removed skills

- **`xml-to-compose-migration`** — dropped in favour of Google's actively-maintained [`migrate-xml-views-to-jetpack-compose`](https://github.com/android/skills/tree/main/jetpack-compose/migration), available via the [`android/skills`](https://github.com/android/skills) repo.

## Related Projects

- [android/skills](https://github.com/android/skills) — Google's official Android agent skills covering AGP 9 migration (pure-Android; KMP is out of scope), XML-to-Compose migration, Navigation 3, R8 analysis, Play Billing upgrades, and edge-to-edge support
- [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills) — JetBrains' official agent skills for Kotlin. Includes `kotlin-tooling-agp9-migration` (the KMP-focused complement to Google's `agp-9-upgrade`, covering Paths A/B/C, the new `com.android.kotlin.multiplatform.library` plugin, built-in Kotlin, source-set restructure, and the JetBrains default project layout), `kotlin-tooling-cocoapods-spm-migration` (CocoaPods → SwiftPM for KMP iOS interop, requires Kotlin 2.4.0+), `kotlin-tooling-java-to-kotlin` (framework-aware J2K conversion with reference guides for Spring, Dagger/Hilt, Retrofit, Mockito, RxJava, JUnit, Lombok, Hibernate, Jackson, Micronaut, Quarkus, and Guice), and `kotlin-backend-jpa-entity-mapping` (Kotlin + Spring/JPA — not Android, but the authoritative source for Kotlin-on-backend entity design)
- [awesome-android-agent-skills](https://github.com/new-silvermoon/awesome-android-agent-skills) — curated list of Android agent skills that inspired many of the skills in this repo
- [compose-skill](https://github.com/aldefy/compose-skill) — alternative Compose skill that bundles a static AndroidX snapshot
- [android-source-explorer-mcp](https://github.com/mrmike/android-source-explorer-mcp) — MCP server for navigating Android source code (optional, used by `android-source-search` skill)
- [material-3-skill](https://github.com/hamen/material-3-skill) — comprehensive Material Design 3 reference covering 30+ components, design tokens, theming, responsive layout, and dynamic color across platforms
- [compose_skill](https://github.com/hamen/compose_skill) — strict, evidence-based Compose audit skill that scores repos on performance, state management, side effects, and API quality using automated Compose Compiler reports
- [compose-skill (Meet-Miyani)](https://github.com/Meet-Miyani/compose-skill) — broad Compose + KMP skill covering MVI/MVVM, Navigation 2 & 3, Ktor, Koin/Hilt, Room, DataStore, Paging, and iOS interop; inspired the `kmp-ktor` skill in this repo
- [chrisbanes/skills](https://github.com/chrisbanes/skills) — Chris Banes' narrow, opinionated Compose and Kotlin skills covering state authoring, side effects, recomposition performance, stability diagnostics, focus navigation, UI testing patterns, structured concurrency, flow primitive selection, and KMP expect/actual boundaries; informed the `kmp-boundaries` and `focus-navigation` references and authoring rules across several existing skills
- [android-reverse-engineering-skill](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) — Claude Code plugin for decompiling APKs, extracting API endpoints, and tracing call flows
- [skydoves/android-testing-skills](https://github.com/skydoves/android-testing-skills) — 50+ source-grounded testing skills spanning Compose UI tests, JVM unit tests, instrumentation (Espresso/UiAutomator), ADB-driven E2E, and test doubles. Complements our `android-tdd`. Apache-2.0.
- [skydoves/compose-performance-skills](https://github.com/skydoves/compose-performance-skills) — sister repo covering the *performance* side of Compose (stability, recomposition, lazy layouts, baseline profiles, R8, hot reload). Same authoring spec; install both for full testing + performance coverage.

## License

MIT
