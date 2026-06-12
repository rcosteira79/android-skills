---
name: android-dev
description: Use this skill as the baseline for ALL Android and Kotlin Multiplatform (KMP) work — whenever the user mentions Android, Kotlin (in an Android context), KMP, CMP, commonMain, androidMain, iosMain, AndroidManifest, Gradle, build.gradle, Hilt, Dagger, Room, Retrofit, Ktor, ViewModel, LiveData, StateFlow, SharedFlow, Compose, Activity, Fragment, Intent, ADB, Logcat, MVVM, MVI, repository pattern, or any Android SDK / Jetpack / AndroidX API. Always load this skill alongside the more specific skills (android-skills:compose, android-skills:kotlin-flows, android-skills:kmp-ktor, android-skills:android-retrofit, etc.): it routes to them and adds the few baseline rules a strong model otherwise gets wrong. Casual mentions like "fix this bug in my Android app," "refactor this ViewModel," "my KMP project," or any work inside an Android project directory should trigger this skill.
---

# Android / KMP baseline

You are a senior Android and KMP engineer. A strong model already produces correct modern architecture by default, so this skill does **not** re-teach it. Treat the project's stack picks below as assumed — apply them, don't expect reminders or re-derive them:

- Clean architecture with a repository boundary; `ViewModel` exposing `StateFlow<UiState>`, observed via `collectAsStateWithLifecycle`; Compose + Material 3 for UI.
- **Hilt + KSP** for DI (or `android-skills:koin` when the project uses Koin); Coroutines/Flow for async (no `LiveData` in new code); `kotlinx.serialization` for JSON; Coil for images.
- Android: Room + Retrofit/OkHttp. KMP shared: Ktor for network; Room or SQLDelight for local. Retrofit is Android-only and never goes in a shared module.
- Feature-vertical packages and modules; `:core:model` has zero Android deps; `:feature:*` modules never depend on each other.
- Errors mapped to a domain type at the repository boundary — platform exceptions never leak past it; UI state explicitly models loading / success / error. (Hierarchy: `android-skills:android-data-layer`.)

The rest of this skill is only the parts a strong model gets wrong by default.

## Skill routing

Load the specific skill for the task, always with the **fully-qualified `android-skills:` prefix** — never the short name (`compose`, `koin`, …).

| For | Load |
|---|---|
| Compose detail — stability, `remember`, modifiers, side effects, lists, animation, navigation | `android-skills:compose` |
| M3 UX — touch targets, adaptive/foldable layouts, accessibility & M3-compliance audit | `android-skills:android-ux` |
| Coroutines & Flow — operators, `Channel` vs `SharedFlow`, structured concurrency | `android-skills:kotlin-coroutines`, `android-skills:kotlin-flows` |
| Repository / data layer + the `DataError` taxonomy | `android-skills:android-data-layer` |
| Networking | `android-skills:android-retrofit` (Android) · `android-skills:kmp-ktor` (KMP) |
| Paging | `android-skills:paging` |
| Testing | `android-skills:android-testing` |
| Build logic / convention plugins | `android-skills:android-gradle-logic` |
| DI with Koin | `android-skills:koin` |

## Four-bucket state modeling

Screens with rich interactions (forms, calculators, multi-step wizards) get unmanageable when state is one flat `data class`. Slice `UiState` into four explicit buckets, and **derive computed values as class properties, not constructor parameters**:

```kotlin
data class CheckoutUiState(
    // 1. Editable input — what the user types
    val email: String = "",
    val cardNumber: String = "",
    // 3. Persisted snapshot — last value read from the repository / stored cross-screen
    val savedShippingAddress: Address? = null,
    // 4. Transient UI-only — flags that must NOT survive the screen
    val isSubmitting: Boolean = false,
    val showCardScannerOverlay: Boolean = false,
) {
    // 2. Derived — getters, NOT constructor params, so no caller can copy() into an
    //    inconsistent state (e.g. emailValid = false next to a valid email).
    val emailValid: Boolean get() = email.isValidEmail()
    val canSubmit: Boolean get() = emailValid && cardNumber.passesLuhn() && !isSubmitting
}
```

The bucket dictates lifecycle and persistence, not the field. Persisting `isSubmitting` keeps the spinner forever after process death; computing `canSubmit` outside the class lets it drift from the inputs; persisting `cardNumber` cross-screen leaks PII. Mixing the buckets produces bugs that look architectural.

## Reuse the project's existing mechanism

Before adding any new mechanism — an event dispatcher, an effects `Channel`/`SharedFlow`, a use-case layer, or a parallel state field — open a sibling ViewModel in the same feature and reuse what's already there. A strong model usually matches local conventions on its own; the miss it doesn't always catch is **duplicating** an existing mechanism instead of widening it — adding a second `shouldDisplayUndoX` flag beside the existing one rather than generalizing the one that's there. If existing code contradicts a "best practice," follow the code and flag the inconsistency; never silently override the project's architecture.

## KMP

Inject a `CoroutineDispatcher` everywhere rather than calling `Dispatchers.Main` / `Dispatchers.IO` directly: `Dispatchers.Main` isn't guaranteed on every KMP target without the `-ktx` artifacts, and injection is also what makes dispatcher-swapped tests possible. Use `expect`/`actual` for platform specifics (file I/O, push tokens, biometrics); on iOS prefer immutable shared state.
