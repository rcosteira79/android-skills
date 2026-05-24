---
name: gradle-build-performance
description: Use when Android/Gradle builds are slow — diagnosing bottlenecks with build scans, enabling configuration cache, migrating kapt to KSP, fixing cache misses, and optimizing CI/CD build times.
---

# Gradle Build Performance

## Workflow

1. **Measure baseline** — clean build + incremental build times
2. **Generate a Build Scan** — `./gradlew assembleDebug --scan`
3. **Identify the slow phase** — Configuration? Execution? Dependency resolution?
4. **Apply one optimization at a time** — don't batch changes; you won't know what helped
5. **Measure again** — confirm improvement before moving on

---

## Quick Diagnostics

```bash
# Generate a Build Scan (uploads to scans.gradle.com)
./gradlew assembleDebug --scan

# Local profile report (no upload)
./gradlew assembleDebug --profile
# Opens report in build/reports/profile/
```

In the Build Scan, go to **Performance → Build timeline** to identify which phase is slow.

---

## Build Phases

| Phase | What Happens | Common Issues |
|-------|-------------|---------------|
| **Initialization** | `settings.gradle.kts` evaluated | Too many `include()` calls |
| **Configuration** | All `build.gradle.kts` files evaluated | Expensive plugins, eager task creation, I/O |
| **Execution** | Tasks run | Cache misses, non-incremental tasks, insufficient parallelism |

---

## 12 Optimization Patterns

### 1. Enable Configuration Cache

Skips the configuration phase on subsequent builds when inputs haven't changed (AGP 8.0+):

```properties
# gradle.properties
org.gradle.configuration-cache=true
org.gradle.configuration-cache.problems=warn  # start with warn, move to fail once clean
```

### 2. Enable Build Cache

Reuses task outputs from previous builds (including on CI):

```properties
# gradle.properties
org.gradle.caching=true
```

### 3. Enable Parallel Execution

Builds independent modules simultaneously:

```properties
# gradle.properties
org.gradle.parallel=true
```

### 4. Increase JVM Heap

```properties
# gradle.properties
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC
```

### 5. Migrate kapt → KSP

KSP is ~2× faster than kapt. Migrate when the library supports it (Hilt, Room, Moshi all support KSP):

```kotlin
// Before
kapt("com.google.dagger:hilt-compiler:2.51.1")
kapt("androidx.room:room-compiler:2.6.1")

// After
ksp("com.google.dagger:hilt-compiler:2.51.1")
ksp("androidx.room:room-compiler:2.6.1")
```

Also replace the `kotlin-kapt` plugin with `com.google.devtools.ksp`.

**AGP 9 makes this mandatory.** AGP 9 has built-in Kotlin support, and `org.jetbrains.kotlin.kapt` is incompatible with it. The path forward is KSP (requires KSP 2.3.1+ on AGP 9) or, for annotation processors with no KSP equivalent, the `com.android.legacy-kapt` plugin (same version as AGP) as a transitional fallback. See JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) skill for the broader AGP 9 migration mechanics.

### 6. Enable Non-Transitive R Classes

Reduces R class size and recompilation scope (default in AGP 8.0+):

```properties
# gradle.properties
android.nonTransitiveRClass=true
```

### 7. Pin Dependency Versions

Dynamic versions force resolution on every build:

```kotlin
// Bad — forces network check every build
implementation("com.example:lib:1.0.+")

// Good
implementation("com.example:lib:1.2.3")
```

### 8. Optimise Repository Order

Gradle checks repositories in order — put the most-used ones first:

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()       // Android artifacts
        mavenCentral() // Everything else
        // Third-party repos last
    }
}
```

### 9. Lazy Task Configuration

```kotlin
// Bad — eagerly configures and instantiates the task
tasks.create("generateVersion") { ... }

// Good — configured only if the task is in the execution graph
tasks.register("generateVersion") { ... }
```

### 10. No I/O During Configuration

File reads, network calls, and `exec {}` during configuration phase break the configuration cache and slow every build:

```kotlin
// Bad — reads file during configuration
val version = file("version.txt").readText()

// Good — defers read to execution
val version = providers.fileContents(layout.projectDirectory.file("version.txt")).asText
```

### 11. Composite Builds for Shared Libraries

If you have a multi-repo setup, `includeBuild` is faster than publishing snapshots:

```kotlin
// settings.gradle.kts
includeBuild("../shared-library") {
    dependencySubstitution {
        substitute(module("com.example:shared")).using(project(":"))
    }
}
```

### 12. Use Convention Plugins (not subproject blocks)

`subprojects { }` and `allprojects { }` in the root `build.gradle.kts` eagerly evaluate all subprojects. Replace with Convention Plugins (see `android-gradle-logic` skill).

---

## Common Bottleneck Analysis

### Slow configuration phase

| Cause | Fix |
|-------|-----|
| Eager task creation | Use `tasks.register()` |
| File/network I/O in config | Defer to execution phase with `providers` |
| Many plugins applied unconditionally | Move to convention plugins; apply only where needed |
| `subprojects {}` / `allprojects {}` blocks | Replace with convention plugins |

### Slow execution phase

| Cause | Fix |
|-------|-----|
| kapt annotation processing | Migrate to KSP |
| Build cache misses | Enable `org.gradle.caching=true`; check for non-deterministic task inputs |
| Sequential module builds | Enable `org.gradle.parallel=true` |
| Insufficient memory | Increase `org.gradle.jvmargs` heap |

### Slow dependency resolution

| Cause | Fix |
|-------|-----|
| Dynamic versions (`1.+`) | Pin exact versions |
| Slow or unnecessary repositories | Reorder; remove unused repos |
| No local cache | Enable build cache |

---

## Recommended `gradle.properties` Baseline

```properties
# Performance
org.gradle.configuration-cache=true
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.jvmargs=-Xmx4g -XX:+UseParallelGC

# Android
android.useAndroidX=true
android.nonTransitiveRClass=true
android.defaults.buildfeatures.buildconfig=false
android.defaults.buildfeatures.aidl=false
android.defaults.buildfeatures.renderscript=false
```

---

## Checklist

- [ ] Build Scan generated and reviewed before optimising
- [ ] Configuration Cache enabled (`org.gradle.configuration-cache=true`)
- [ ] Build Cache enabled (`org.gradle.caching=true`)
- [ ] All dependency versions pinned (no `+` or `-SNAPSHOT` in production)
- [ ] kapt migrated to KSP where libraries support it
- [ ] Parallel execution enabled
- [ ] No file/network I/O during configuration phase
- [ ] Lazy task registration (`register` not `create`)
- [ ] Non-transitive R classes enabled
