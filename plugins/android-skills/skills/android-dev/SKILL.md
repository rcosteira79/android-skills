---
name: android-dev
description: Use this skill as the baseline for ALL Android and Kotlin Multiplatform (KMP) work — whenever the user mentions Android, Kotlin (in an Android context), KMP, CMP, commonMain, androidMain, iosMain, AndroidManifest, Gradle, build.gradle, Hilt, Dagger, Room, Retrofit, Ktor, ViewModel, LiveData, StateFlow, SharedFlow, Compose, Activity, Fragment, Intent, ADB, Logcat, MVVM, MVI, repository pattern, or any Android SDK / Jetpack / AndroidX API. Always load this skill alongside more specific skills (android-skills:compose, android-skills:kotlin-flows, android-skills:kmp-ktor, android-skills:android-retrofit, etc.) — it provides the architectural baseline, existing-pattern audit, and project-adaptability rules those skills defer to. Casual mentions like "fix this bug in my Android app," "refactor this ViewModel," "my KMP project," or any work inside an Android project directory should trigger this skill.
---

# Senior Android Development Skills

You are a senior Android engineer. Apply the following guidelines to all Android and KMP work.

## Skill Invocation Rule

**Always use fully qualified names when invoking skills from this plugin.** Use the `android-skills:` prefix — e.g., `android-skills:compose`, `android-skills:kotlin-coroutines`, `android-skills:android-testing`. Never use short names like `compose` or `kotlin-coroutines` alone.

## Architecture

- Use clean architecture with repository pattern for data persistence.
- Ask the user whether they prefer MVVM or MVI. If they have no preference, default to MVVM for simpler screens (few state-changing interactions) and MVI for screens with many interactions that change state.
- Use Compose for all new UI. For legacy interop use `AndroidView` / `ComposeView`.
- Use `collectAsStateWithLifecycle` to observe state from ViewModels in composables.
- Use `StateFlow` / `State` to manage UI state.
- Use Material 3 for the UI.
- Use Hilt for DI with KSP.
- Use Coil for image loading.
- Use `kotlinx.serialization` for network model serialization.

**Android-only projects:**
- Room for local caching, Retrofit + OkHttp for network.

**KMP shared code:**
- Ktor for network (multiplatform). For local database, ask the user whether they prefer Room (KMP) or SQLDelight. If they have no preference, default to Room. Retrofit is Android-only and must not be used in shared modules.

## Existing-pattern check (before designing new mechanisms)

Before adding any new mechanism — events, flows, navigation triggers, or state shape — in an existing project, check how the surrounding code already handles it. The failure mode is inventing new mechanisms when existing ones should be reused, then dressing the shortcut in architectural language so it sounds principled.

### Audit procedure

Open a sibling ViewModel in the same feature module — or `Grep` the feature for the terms below — **before writing any new code**:

| Concern | What to look for |
|---|---|
| How actions reach the ViewModel | Sealed `Event` / `Intent` / `Action` interface, `onEvent()` dispatcher, and a Handler interface the ViewModel implements — check all three, not just one |
| How one-shot effects are emitted | Existing `SharedFlow` / `Channel` of sealed effect classes (see `android-skills:kotlin-flows`) |
| How navigation is triggered | Nav callbacks, `NavController` (Nav 2) or `NavDisplay` (Nav 3) use, or navigation effects in the effects stream |
| How the ViewModel exposes new behaviour | Event class entries + handler methods, or direct `fun` — match whichever the existing ViewModels use |
| How state is structured | `UiState` sealed classes, `StateFlow<State>` shape, field granularity |

### Red flags

- **Adding a public `fun foo()` on the ViewModel for the UI to call** when the project has a sealed `Event` + `onEvent()` pattern → add an Event data object and a handler method instead.
- **Creating a new `SharedFlow` or `Channel`** → check whether an existing effects stream already carries this kind of signal.
- **New composable parameter that bypasses existing state/event wiring** → look at how sibling screens wire the same ViewModel.
- **Justifying a direct approach with phrases like "natural extension of X," "the ViewModel delegates to Y," or "this is architecturally sound" — *without having first opened a sibling ViewModel***. Rationalization dressing up a shortcut is itself a signal to stop and audit, not a signal you're on the right track.
- **Adding a ViewModel delegate, a repository wrapper, or a use-case pass-through** → mentally delete it first. If the surrounding code gets no simpler with it gone, it's pass-through indirection — inline it. Such a layer earns its keep only when removing it would scatter the same logic across several call sites. (The deliberate single-implementation repository interface that marks a clean-architecture layer boundary is *not* pass-through indirection — that one stays; it's a seam for testing and dependency inversion, not a wrapper.)

### Rule

**If the project has an established pattern for X, use it — even if a simpler direct approach would also work.** Simplicity is not a valid reason to diverge from the architecture. The cost of one extra `Event` data object and handler method is trivial; the cost of an architectural inconsistency is cumulative and paid by every future reader.

## State and Events

### Where state lives

| Scope | Owner | When |
|---|---|---|
| Single composable | `remember { mutableStateOf(...) }` | Transient UI state that resets on screen leave (expanded card, tooltip visibility, animation triggers) |
| Single composable, must survive rotation / low-memory kill | `rememberSaveable { mutableStateOf(...) }` | UI-local state that needs to outlive config change / process death without involving a ViewModel (tab index, expanded panel, scroll position, form field text) |
| Several composables in one screen | Plain state holder class with `mutableStateOf` | UI orchestration that crosses composables but never outlives the screen (form coordinator, list selection mode) |
| Survives recomposition AND configuration change | `ViewModel` exposing `StateFlow<UiState>` | App state — anything the user can return to, anything tied to a domain action |
| Survives process death | `ViewModel.savedStateHandle` or a real persistence layer | User-input drafts that shouldn't be lost on low-memory kill |

Don't escalate without reason. A bottom-sheet expansion flag in a ViewModel adds noise for the rest of the screen; a draft email in local state silently disappears when the user backgrounds the app. Match the scope to the lifetime of the data.

### Event naming (MVI)

When a sealed `Event` / `Intent` / `Action` interface drives the ViewModel, name entries by **what happened in the UI**, not what the ViewModel should do about it.

```kotlin
// RIGHT — describes the UI event
sealed interface CategoryEvent {
    data object OnSaveClick : CategoryEvent
    data class OnNameChange(val value: String) : CategoryEvent
    data object OnDeleteConfirm : CategoryEvent
}

// WRONG — describes the ViewModel's reaction
sealed interface CategoryEvent {
    data object SaveCategory : CategoryEvent
    data class UpdateName(val value: String) : CategoryEvent
    data object DeleteCategory : CategoryEvent
}
```

UI-centric names (`OnSaveClick`) survive ViewModel refactors. ViewModel-centric names (`SaveCategory`) describe an implementation that may change — and they read awkwardly when the same event triggers multiple reactions: a `SaveCategory` event that *also* dismisses a dialog and refreshes a list is poorly named for two of its three effects.

### Four-bucket state modeling

Screens with rich interactions (forms, calculators, multi-step wizards) get unmanageable fast when state is a single flat `data class`. Slice `UiState` into four explicit buckets:

```kotlin
data class CheckoutUiState(
    // 1. Editable input — what the user types
    val email: String = "",
    val cardNumber: String = "",
    val shippingNotes: String = "",

    // 3. Persisted snapshot — last value read from the repository or stored cross-screen
    val savedShippingAddress: Address? = null,
    val savedPaymentMethod: PaymentMethod? = null,

    // 4. Transient UI-only — flags that shouldn't survive the screen
    val isSubmitting: Boolean = false,
    val showCardScannerOverlay: Boolean = false,
) {
    // 2. Derived/computed — class properties, NOT constructor parameters. A caller
    //    must not be able to instantiate (or `copy()` to) an inconsistent state by
    //    passing `emailValid = false` alongside a valid email; deriving on read
    //    guarantees the projection always reflects bucket 1.
    val emailValid: Boolean get() = email.isValidEmail()
    val cardValid: Boolean get() = cardNumber.passesLuhn()
    val canSubmit: Boolean get() = emailValid && cardValid && shippingNotes.length < 500
}
```

Mixing the four buckets produces bugs that look architectural. Storing `isSubmitting` in `savedStateHandle` keeps the spinner forever after process death. Computing `canSubmit` outside the data class lets it drift from the inputs. Persisting `cardNumber` across screens leaks PII. The discipline is that the bucket dictates lifecycle and persistence rules, not the field itself.

### Effects: `Channel(BUFFERED)` vs `SharedFlow(replay = 0)`

For one-shot UI effects from a ViewModel (snack messages, navigation triggers, haptic feedback, scroll-to-top):

| Primitive | When | Behavior |
|---|---|---|
| `Channel<Effect>(BUFFERED).receiveAsFlow()` | Effect must not be missed (one-time toast for a payment outcome; navigation that must happen) | Single-consumer; buffers across collector gaps; values delivered exactly once |
| `SharedFlow<Effect>(replay = 0)` | Effect can be missed if the UI is inactive (transient haptic tick; an analytics-only signal) | Multi-collector; no replay; values dropped if no collector |

If losing the signal would desynchronize what the user thinks the app did from the underlying state, the signal is not ephemeral — promote it to **state plus an acknowledgement** (a `pendingResult: PurchaseResult? = null` field on `UiState`, cleared after the screen consumes it). One-shot effects are for fire-and-forget signals only.

See `android-skills:kotlin-flows` for the full operator-level discussion of `Channel` vs `SharedFlow`.

## Compose

For implementation detail, defer to `android-skills:compose`. Key architectural decisions:

- Hoist state to the lowest common ancestor — composables receive state and emit events upward.
- Screen-level composables connect to the ViewModel; child composables are stateless.
- For Compose specifics (stability, `remember`, Modifiers, side effects, navigation), `android-skills:compose` is the authoritative source.
- For M3 UX patterns (touch targets, canonical layouts, foldable postures, accessibility, M3 compliance audit), see `android-skills:android-ux`.

## Async & Concurrency

For implementation detail, defer to `android-skills:kotlin-coroutines` and `android-skills:kotlin-flows`. Key decisions:

- Use Kotlin Coroutines and Flow for all async work. No `LiveData` in new code.
- `viewModelScope` for ViewModel coroutines; inject `CoroutineDispatcher` for testability.
- Expose `StateFlow` for UI state, `Flow` for streams, suspend functions for one-shot calls.

## Gradle

- Use version catalogs (`libs.versions.toml`) and Kotlin script (`.kts`) for all Gradle files.
- Target Java 21 via `jvmToolchain(21)` (fallback: 17).
- Keep ProGuard/R8 rules updated when adding libraries.
- Add a Baseline Profile (`app/src/main/baseline-prof.txt`) for production apps to improve startup and scroll performance.

## Package Structure

### Single-module apps

- Prefer vertical feature packages (`feature/data`, `feature/domain`, `feature/presentation`) over horizontal shared packages. Create shared packages only when truly shared.
- API logic: `data/api`, API models: `data/api/models`.
- Cache logic: `data/cache`, cache models: `data/cache/models`.
- `presentation/ui`: Compose-only code.
- `presentation/models`: UI models and mappers.

### Multi-module apps

Follow a feature-vertical module structure:

```
:app                    ← entry point, wires features together
:core:model             ← shared domain models (pure Kotlin, no Android deps)
:core:data              ← repositories, data sources, Room DB, Retrofit
:core:domain            ← use cases, repository interfaces
:core:ui                ← shared composables, theme, design system
:feature:<name>         ← self-contained feature: own UI, ViewModel, nav entry point
```

- `:feature:*` modules depend on `:core:domain` and `:core:ui` — never on each other
- Domain models in `:core:model` have zero Android framework dependencies
- See `android-skills:android-gradle-logic` for Convention Plugin setup to share build config across modules

## Data Flow

Compose → ViewModel → Repository → Data sources

- Repository lives in the `data` layer.
- ViewModel lives in the `presentation` layer.
- Data models are mapped to UI models inside ViewModels.
- UI models contain only what the screen needs to display.

## Domain Layer (only when needed)

Add a domain layer when business logic outgrows the ViewModel or business rules belong to domain models:

- Domain models under `models`, use cases under `usecases`, repository interfaces under `repositories`.
- Domain layer has no dependency on data or UI layers.
- Data → domain → UI model mapping chain.
- Flow: Compose → ViewModel → use cases → repository interfaces ← repository impl → data sources.

## Error Handling

- Model success/error with sealed classes/interfaces (`Result<T>`).
- UI state must explicitly represent loading, success, and error.
- Never swallow exceptions silently in repositories or data sources.

**Error propagation by layer:**

1. **Data sources** — throw platform/library exceptions (`IOException`, `HttpException`, `SQLiteException`, etc.).
2. **Repositories** — catch platform exceptions and remap to domain error types (e.g. `DataError.Network`, `DataError.Local`). Use a single sealed error hierarchy for the data layer — see `android-skills:android-data-layer`. Never let raw data-layer exceptions leak past this boundary.
3. **Use cases** — catch domain exceptions and return `Result<T>`, where the error type is a domain model. This is the `Result` boundary: use cases never catch platform exception types.
4. **ViewModels** — handle `Result<T>` and map to UI state.

**When there is no domain layer (simple MVVM):** the repository returns `Result<T>` directly, mapping platform exceptions to domain error models itself. The ViewModel handles `Result<T>` without knowing about platform exceptions.

## Navigation

- Use `navigation-compose 2.8+` with type-safe `@Serializable` route objects (not string routes).
- Single Activity host (`MainActivity`). Navigate via `NavController` — never from the ViewModel directly.
- For one-time navigation/UI events from the ViewModel, ask the user: if exactly-once delivery is required (event must never be missed), use `Channel` + `receiveAsFlow()`; if events can be missed when UI is inactive, `SharedFlow(replay = 0)` is simpler. See `android-skills:kotlin-flows` for full trade-offs.
- See `compose/references/navigation.md` for full patterns.

## Background Work

- Use **WorkManager** for deferrable background tasks that must survive process death (sync, upload, periodic jobs).
- Use `CoroutineWorker` for suspend-friendly workers.
- Constrain work with `Constraints` (network, charging) rather than implementing retry logic manually.

```kotlin
val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(1, TimeUnit.HOURS)
    .setConstraints(
        Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
    )
    .build()

WorkManager.getInstance(context).enqueueUniquePeriodicWork(
    "sync",
    ExistingPeriodicWorkPolicy.KEEP,
    syncRequest
)
```

## Testing

For implementation detail, defer to `android-skills:android-testing`. Key decisions:

- Unit tests for use cases and mappers (pure JVM, no Android dependency).
- Integration tests per ViewModel: fake data sources, real ViewModel logic.
- Compose UI tests for key screens using `ComposeTestRule`.
- Screenshot tests with Roborazzi for visual regression.
- Follow Given-When-Then naming convention.

## KMP

- UI code lives in the shared KMP module (Compose Multiplatform) to be reused across platforms.
- Use `expect`/`actual` for platform-specific implementations (e.g. file I/O, push tokens, biometrics).
- Network layer: Ktor (shared). Database: ask user preference between Room (KMP) and SQLDelight; default to Room if no preference.
- Inject `CoroutineDispatcher` everywhere — `Dispatchers.Main` is not guaranteed on all KMP targets without the `-ktx` libraries.
- iOS: be mindful of the Kotlin/Native memory model; prefer immutable shared state.

## Adaptability

- Always respect the project's established architecture and conventions first.
- If existing code contradicts these guidelines, flag the inconsistency and ask how to proceed — never silently override.
