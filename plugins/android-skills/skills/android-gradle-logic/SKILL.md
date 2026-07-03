---
name: android-gradle-logic
description: Use when setting up or refactoring Android Gradle build logic — convention plugins, composite builds, version catalogs, and shared build configuration across modules.
---

# Android Gradle Build Logic

Centralise build configuration in reusable **Convention Plugins** inside a `build-logic/` composite build, so each module's `build.gradle.kts` collapses to `plugins { alias(libs.plugins.myapp.android.library) }` plus a `namespace`.

The canonical worked example is **[nowinandroid's `build-logic/`](https://github.com/android/nowinandroid/tree/main/build-logic)** — start from it rather than hand-rolling. This skill covers the three wiring details that are easy to get wrong, plus the AGP 9 deltas.

## The wiring gotchas

**1. `build-logic` does NOT inherit the root version catalog — recreate it.** A composite build has its own `settings.gradle.kts`; the root `libs` catalog is invisible inside `build-logic` until you declare it. Without this the convention plugins can't reference `libs.*` and won't compile:

```kotlin
// build-logic/settings.gradle.kts
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") { from(files("../gradle/libs.versions.toml")) }
    }
}
```

**2. Declare the convention-plugin ids in `[plugins]` with `version = "unspecified"`** — otherwise `alias(libs.plugins.myapp.android.library)` in a module file doesn't resolve (Gradle treats it as a versioned external plugin and fails to find it). The `id` here must match the one you `register(...)`:

```toml
# gradle/libs.versions.toml
[plugins]
myapp-android-application = { id = "myapp.android.application", version = "unspecified" }
myapp-android-library     = { id = "myapp.android.library", version = "unspecified" }
myapp-android-compose     = { id = "myapp.android.compose", version = "unspecified" }
```

**3. Set the JVM toolchain via Kotlin's extension, not `JavaPluginExtension`.** AGP's `com.android.application` / `com.android.library` plugins do **not** apply Gradle's `java` plugin, so `configure<JavaPluginExtension> { ... }` throws *"Extension of type JavaPluginExtension does not exist"* and fails configuration in every module. Use the Kotlin extension inside the convention plugin:

```kotlin
extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
    jvmToolchain(21)
}
// equivalently: kotlin { jvmToolchain(21) }
```

## AGP 9 Implications

The convention plugin pattern above targets AGP 8. AGP 9 changes several things that hit build logic directly: it drops the standalone `org.jetbrains.kotlin.android` plugin (Kotlin is built into `com.android.application` / `com.android.library`), removes `BaseExtension` and the old variant APIs (`applicationVariants` → `androidComponents { onVariants { … } }`), moves `kotlinOptions {}` to a top-level `kotlin { compilerOptions { … } }`, and makes `kapt` incompatible (migrate to KSP). Any convention plugin that touches these needs updating.

Defer to the dedicated migration skills for the mechanics rather than duplicating the steps here: Google's [`agp-9-upgrade`](https://github.com/android/skills/tree/main/agp-9-upgrade) for pure-Android projects, JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) for KMP, and this repo's `gradle-build-performance` skill for the kapt → KSP step.

## Checklist

- [ ] `build-logic` included as a composite build (`includeBuild("build-logic")`) in the root `settings.gradle.kts`
- [ ] `build-logic/settings.gradle.kts` recreates the `libs` catalog via `from(files("../gradle/libs.versions.toml"))`
- [ ] Convention plugins `register`-ed with stable ids **and** declared in `[plugins]` with `version = "unspecified"`
- [ ] JVM toolchain set via `KotlinAndroidProjectExtension` / `kotlin { jvmToolchain() }`, never `JavaPluginExtension`
- [ ] `compileSdk` / `minSdk` / Compose set once in the plugins, not per module
