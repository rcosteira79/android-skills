---
name: android-gradle-logic
description: Use when setting up or refactoring Android Gradle build logic — convention plugins, composite builds, version catalogs, and shared build configuration across modules.
---

# Android Gradle Build Logic

Centralise build logic in reusable Convention Plugins instead of copy-pasting `build.gradle.kts` configuration across modules.

## Project Structure

```
root/
├── build-logic/
│   ├── convention/
│   │   ├── src/main/kotlin/
│   │   │   ├── AndroidApplicationConventionPlugin.kt
│   │   │   ├── AndroidLibraryConventionPlugin.kt
│   │   │   └── AndroidComposeConventionPlugin.kt
│   │   └── build.gradle.kts
│   └── settings.gradle.kts
├── gradle/
│   └── libs.versions.toml
├── app/
│   └── build.gradle.kts          ← just: plugins { alias(libs.plugins.myapp.android.application) }
├── feature/home/
│   └── build.gradle.kts          ← just: plugins { alias(libs.plugins.myapp.android.library) }
└── settings.gradle.kts
```

---

## Step 1: Include `build-logic` as a Composite Build

```kotlin
// settings.gradle.kts
pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
```

---

## Step 2: Configure `build-logic/settings.gradle.kts`

```kotlin
// build-logic/settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "build-logic"
include(":convention")
```

---

## Step 3: Configure `build-logic/convention/build.gradle.kts`

```kotlin
plugins {
    `kotlin-dsl`
}

dependencies {
    compileOnly(libs.android.gradlePlugin)
    compileOnly(libs.kotlin.gradlePlugin)
    compileOnly(libs.ksp.gradlePlugin)
}

gradlePlugin {
    plugins {
        register("androidApplication") {
            id = "myapp.android.application"
            implementationClass = "AndroidApplicationConventionPlugin"
        }
        register("androidLibrary") {
            id = "myapp.android.library"
            implementationClass = "AndroidLibraryConventionPlugin"
        }
        register("androidCompose") {
            id = "myapp.android.compose"
            implementationClass = "AndroidComposeConventionPlugin"
        }
    }
}
```

---

## Step 4: Write Convention Plugins

### Application Plugin

```kotlin
// AndroidApplicationConventionPlugin.kt
import com.android.build.api.dsl.ApplicationExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.configure

class AndroidApplicationConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("com.android.application")
            pluginManager.apply("org.jetbrains.kotlin.android")

            extensions.configure<ApplicationExtension> {
                compileSdk = 35
                defaultConfig {
                    minSdk = 26
                    targetSdk = 35
                }
            }

            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                jvmToolchain(21)
            }
        }
    }
}
```

### Library Plugin

```kotlin
// AndroidLibraryConventionPlugin.kt
import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.configure

class AndroidLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("com.android.library")
            pluginManager.apply("org.jetbrains.kotlin.android")

            extensions.configure<LibraryExtension> {
                compileSdk = 35
                defaultConfig.minSdk = 26
            }

            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                jvmToolchain(21)
            }
        }
    }
}
```

### Compose Plugin

```kotlin
// AndroidComposeConventionPlugin.kt
import com.android.build.api.dsl.CommonExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.kotlin.dsl.getByType

class AndroidComposeConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("org.jetbrains.kotlin.plugin.compose")

            val extension = extensions.getByType<CommonExtension<*, *, *, *, *, *>>()
            extension.buildFeatures.compose = true
        }
    }
}
```

---

## Step 5: Declare Custom Plugins in Version Catalog

```toml
# gradle/libs.versions.toml
[plugins]
myapp-android-application = { id = "myapp.android.application", version = "unspecified" }
myapp-android-library     = { id = "myapp.android.library", version = "unspecified" }
myapp-android-compose     = { id = "myapp.android.compose", version = "unspecified" }
```

---

## Step 6: Use in Module Build Files

```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.myapp.android.application)
    alias(libs.plugins.myapp.android.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.example.app"
    defaultConfig.applicationId = "com.example.app"
    defaultConfig.versionCode = 1
    defaultConfig.versionName = "1.0"
}

dependencies {
    implementation(projects.feature.home)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
}
```

```kotlin
// feature/home/build.gradle.kts
plugins {
    alias(libs.plugins.myapp.android.library)
    alias(libs.plugins.myapp.android.compose)
}

android.namespace = "com.example.feature.home"
```

The feature module's build file is now just 5 lines. All common configuration lives in the convention plugins.

---

## AGP 9 Implications

The convention plugin examples above target AGP 8. AGP 9 requires several adjustments:

- **Drop `org.jetbrains.kotlin.android`.** AGP 9 ships built-in Kotlin support for `com.android.application` and `com.android.library`. The standalone plugin conflicts when applied alongside — remove it from convention plugins *and* from the version catalog. KMP modules are unaffected: they keep `org.jetbrains.kotlin.multiplatform` and switch from `com.android.library` to `com.android.kotlin.multiplatform.library`.
- **`BaseExtension` is removed.** Use `CommonExtension<*, *, *, *, *, *>` (already the case in the Compose plugin example above) or one of the typed `ApplicationExtension` / `LibraryExtension` interfaces. Convention plugins that referenced `BaseExtension` won't compile.
- **Variant APIs are removed.** `applicationVariants`, `libraryVariants`, `variantFilter`, and `BaseVariant` are gone. The replacement is `androidComponents { onVariants { variant -> ... } }` — the lazy variant-aware API. If a convention plugin reads or mutates variants (BuildConfig fields, manifest placeholders, source-set tweaks), it needs to move to `androidComponents`.
- **`kotlinOptions {}` → `compilerOptions {}`.** Inside `android {}`, `kotlinOptions { jvmTarget = "11" }` becomes top-level `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_11) } }`. Convention plugins that configured Kotlin via the Android extension need to use the Kotlin extension instead.
- **kapt → KSP (or `com.android.legacy-kapt`).** `kapt` is incompatible with built-in Kotlin on AGP 9. See the `gradle-build-performance` skill's "Migrate kapt → KSP" section.

For full AGP 9 migration mechanics, see Google's [`agp-9-upgrade`](https://github.com/android/skills/tree/main/agp-9-upgrade) for pure-Android projects and JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) for KMP projects.

---

## Checklist

- [ ] `build-logic` included as a composite build in root `settings.gradle.kts`
- [ ] Convention plugins registered with stable IDs and declared in version catalog
- [ ] `compileSdk`, `minSdk`, Java toolchain defined once in plugins — not in each module
- [ ] Compose plugin applied via convention — not copy-pasted into each feature module
- [ ] `build-logic` itself resolves dependencies from the root version catalog
