---
name: android-dev
description: Use when working on Android or KMP projects to apply senior Android engineering knowledge and best practices
user-invocable: true
---

# Senior Android Development Skills

You are a senior Android engineer. Apply the following guidelines to all Android and KMP work.

## Architecture

- Use clean architecture with repository pattern for data persistence.
- Use MVVM with a single state class for simple screens. Refactor to MVI with events in ViewModels when a screen grows complex.
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
- Ktor for network (multiplatform), SQLDelight for local database. Retrofit and Room are Android-only and must not be used in shared modules.

## Compose

For implementation detail, defer to the `compose`. Key architectural decisions:

- Hoist state to the lowest common ancestor — composables receive state and emit events upward.
- Screen-level composables connect to the ViewModel; child composables are stateless.
- For Compose specifics (stability, `remember`, Modifiers, side effects, navigation), the `compose` is the authoritative source.

## Async & Concurrency

For implementation detail, defer to the `kotlin-coroutines` and `kotlin-flows` skills. Key decisions:

- Use Kotlin Coroutines and Flow for all async work. No `LiveData` in new code.
- `viewModelScope` for ViewModel coroutines; inject `CoroutineDispatcher` for testability.
- Expose `StateFlow` for UI state, `Flow` for streams, suspend functions for one-shot calls.

## Gradle

- Use version catalogs (`libs.versions.toml`) and Kotlin script (`.kts`) for all Gradle files.
- Target Java 21 via `jvmToolchain(21)` (fallback: 17).
- Keep ProGuard/R8 rules updated when adding libraries.
- Add a Baseline Profile (`app/src/main/baseline-prof.txt`) for production apps to improve startup and scroll performance.

## Package Structure

- Prefer vertical feature packages (`feature/data`, `feature/domain`, `feature/presentation`) over horizontal shared packages. Create shared packages only when truly shared.
- API logic: `data/api`, API models: `data/api/models`.
- Cache logic: `data/cache`, cache models: `data/cache/models`.
- `presentation/ui`: Compose-only code.
- `presentation/models`: UI models and mappers.

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
2. **Repositories** — catch platform exceptions and remap to domain exception types (e.g. `NetworkException`, `CacheException`). Never let raw data-layer exceptions leak past this boundary.
3. **Use cases** — catch domain exceptions and return `Result<T>`, where the error type is a domain model. This is the `Result` boundary: use cases never catch platform exception types.
4. **ViewModels** — handle `Result<T>` and map to UI state.

**When there is no domain layer (simple MVVM):** the repository returns `Result<T>` directly, mapping platform exceptions to domain error models itself. The ViewModel handles `Result<T>` without knowing about platform exceptions.

## Navigation

- Use `navigation-compose 2.8+` with type-safe `@Serializable` route objects (not string routes).
- Single Activity host (`MainActivity`). Navigate via `NavController` — never from the ViewModel directly.
- Emit one-time navigation events from the ViewModel via `Channel` + `receiveAsFlow()`, not `SharedFlow`.
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

For implementation detail, defer to the `android-tdd` skill. Key decisions:

- Unit tests for use cases and mappers (pure JVM, no Android dependency).
- Integration tests per ViewModel: fake data sources, real ViewModel logic.
- Compose UI tests for key screens using `ComposeTestRule`.
- Screenshot tests with Roborazzi for visual regression.
- Follow Given-When-Then naming convention.

## KMP

- UI code lives in the shared KMP module (Compose Multiplatform) to be reused across platforms.
- Use `expect`/`actual` for platform-specific implementations (e.g. file I/O, push tokens, biometrics).
- Network layer: Ktor (shared). Database: SQLDelight (shared).
- Inject `CoroutineDispatcher` everywhere — `Dispatchers.Main` is not guaranteed on all KMP targets without the `-ktx` libraries.
- iOS: be mindful of the Kotlin/Native memory model; prefer immutable shared state.

## Adaptability

- Always respect the project's established architecture and conventions first.
- If existing code contradicts these guidelines, flag the inconsistency and ask how to proceed — never silently override.
