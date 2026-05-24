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

The convention plugin examples above target AGP 8. AGP 9 changes several things that hit build logic directly: it drops the standalone `org.jetbrains.kotlin.android` plugin (Kotlin is built into `com.android.application` / `com.android.library`), removes `BaseExtension` and the old variant APIs (`applicationVariants` → `androidComponents { onVariants { … } }`), moves `kotlinOptions {}` to a top-level `kotlin { compilerOptions { … } }`, and makes `kapt` incompatible (migrate to KSP). Any convention plugin that touches these needs updating.

Defer to the dedicated migration skills for the mechanics rather than duplicating the steps here: Google's [`agp-9-upgrade`](https://github.com/android/skills/tree/main/agp-9-upgrade) for pure-Android projects, JetBrains' [`kotlin-tooling-agp9-migration`](https://github.com/Kotlin/kotlin-agent-skills/tree/main/skills/kotlin-tooling-agp9-migration) for KMP, and this repo's `gradle-build-performance` skill for the kapt → KSP step.

---

## Checklist

- [ ] `build-logic` included as a composite build in root `settings.gradle.kts`
- [ ] Convention plugins registered with stable IDs and declared in version catalog
- [ ] `compileSdk`, `minSdk`, Java toolchain defined once in plugins — not in each module
- [ ] Compose plugin applied via convention — not copy-pasted into each feature module
- [ ] `build-logic` itself resolves dependencies from the root version catalog
