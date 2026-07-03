---
name: gradle-build-performance
description: Use when Android/Gradle builds are slow — diagnosing bottlenecks with build scans, enabling configuration cache, migrating kapt to KSP, fixing cache misses, and optimizing CI/CD build times.
---

# Gradle Build Performance

This reference covers the workflow discipline plus the patterns that move the needle and are easy to get wrong, not the standard knobs (`org.gradle.caching`, `org.gradle.parallel`, `org.gradle.jvmargs`, `android.nonTransitiveRClass`, `kapt` → `ksp`).

**Workflow:** measure a baseline (clean + incremental) → `./gradlew assembleDebug --scan` (or `--profile` for a no-upload report) → find the slow phase (configuration / execution / dependency resolution) in the Build Scan timeline → apply **one** optimization at a time → measure again. Batching changes means you never learn what helped.

## Configuration phase — the cheapest wins

- **Configuration cache** (`org.gradle.configuration-cache=true`, AGP 8+) skips the entire configuration phase when inputs are unchanged. Start with `org.gradle.configuration-cache.problems=warn`, move to `fail` once clean.
- **No I/O during configuration.** A `file("version.txt").readText()`, a network call, or `exec {}` at configuration time breaks the configuration cache and slows every build — defer it to execution: `providers.fileContents(layout.projectDirectory.file("version.txt")).asText`.
- **Lazy task registration** — `tasks.register("x") { … }` (configured only if it's in the execution graph), never `tasks.create("x") { … }` (eager).
- **Convention plugins, not `subprojects {}` / `allprojects {}`** — those root-build blocks eagerly evaluate every subproject. Move shared config into convention plugins (see `android-skills:android-gradle-logic`).

## kapt → KSP (mandatory on AGP 9)

KSP is ~2× faster than kapt, and **AGP 9 makes the migration mandatory** — it has built-in Kotlin support and `org.jetbrains.kotlin.kapt` is incompatible with it. Migrate to KSP (requires KSP 2.3.1+ on AGP 9; Hilt / Room / Moshi all support it), or fall back to `com.android.legacy-kapt` (same version as AGP) for annotation processors with no KSP equivalent. See JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) skill for the broader AGP 9 mechanics.

## Dependency resolution

- **Pin versions** — a dynamic `1.0.+` or `-SNAPSHOT` forces a network resolution check on every build. Pin `1.2.3`.
- **Repository order** — Gradle checks repositories in declaration order; put the most-used first (`google()` then `mavenCentral()`, third-party last).

## A reasonable `gradle.properties` baseline

```properties
org.gradle.configuration-cache=true
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC
android.nonTransitiveRClass=true
```
