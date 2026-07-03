---
name: android-data-layer
description: Use when implementing the data layer in Android or KMP — the Repository pattern's layered error-propagation model (repository as the error boundary, sealed DataError, Result placement with and without a domain layer) and Room in commonMain (@ConstructedBy, BundledSQLiteDriver, per-target KSP).
---

# Android Data Layer

The data layer coordinates data from multiple sources; its public API is repository interfaces, and its internals (DAOs, API services, DTOs) never leak upward. This skill is the canonical home for the **error-propagation model**, plus the KMP-Room setup. **Related:** `android-skills:android-retrofit` (Retrofit service/OkHttp/Hilt wiring), `android-skills:android-dev` (overall app architecture).

## Error propagation — the layered model

The goal: data-layer errors (`IOException` / `HttpException` / `SQLiteException`) must never reach the ViewModel. Map them to a domain error type at the repository boundary. If the project already has an error convention, match it; otherwise a sealed `DataError` hierarchy is a reasonable default:

```kotlin
sealed class DataError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Network(cause: Throwable) : DataError("Network error", cause)
    class Server(val code: Int, message: String?) : DataError("Server error $code: $message")
    class Local(cause: Throwable) : DataError("Local storage error", cause)
}

// repository = error boundary: catch platform exceptions, return Result<T> (no domain layer) or throw DataError (with one)
suspend fun refreshNews(): Result<Unit> = withContext(io) {
    try { newsDao.insertAll(newsApi.fetchLatest().map(NewsDto::toEntity)); Result.success(Unit) }
    catch (e: IOException) { Result.failure(DataError.Network(e)) }
    catch (e: HttpException) { Result.failure(DataError.Server(e.code(), e.message())) }
}
```

The boundary moves outward by one layer when a domain layer exists:

1. **Data sources** throw platform/library exceptions (`IOException`, `HttpException`, `SQLiteException`).
2. **Repository** is the error boundary — catch those and remap to `DataError`; never let raw platform types leak. *Without a domain layer (simple MVVM):* the repository returns `Result<T>` directly and the ViewModel handles it without knowing about platform exceptions.
3. **Use cases** (when present) are the `Result` boundary — the repository instead *throws* `DataError`, and the use case catches it and returns `Result<T>` with a domain-specific error model. Use cases never catch platform exception types.
4. **ViewModels** handle `Result<T>` and map it to UI state (explicit loading / success / error).

(Default to the `Entity` suffix — `ArticleEntity` — for Room types; match an existing convention such as a `Cached` prefix if the project already uses one.)

## Room in KMP (`commonMain`)

Room has been KMP-stable since 2.7.0. The shared setup differs from the Android-only setup in three places:

1. **`@ConstructedBy(...)`** on the `@Database`, paired with an `expect object` Room generates per-platform `actual`s for.
2. **`BundledSQLiteDriver`** (from `androidx.sqlite:sqlite-bundled`) — pins the same SQLite version across Android/iOS/JVM/web (Android's system SQLite drifts between API levels and devices).
3. **`setQueryCoroutineContext(Dispatchers.IO)`** — Android Room defaults this; KMP doesn't.

```kotlin
// commonMain
@Database(entities = [ArticleEntity::class], version = 1, exportSchema = true)
@ConstructedBy(AppDatabaseConstructor::class)
abstract class AppDatabase : RoomDatabase() { abstract fun articleDao(): ArticleDao }

@Suppress("KotlinNoActualForExpect")
expect object AppDatabaseConstructor : RoomDatabaseConstructor<AppDatabase>

fun getRoomDatabase(builder: RoomDatabase.Builder<AppDatabase>): AppDatabase =
    builder.setDriver(BundledSQLiteDriver()).setQueryCoroutineContext(Dispatchers.IO).build()
```

Each platform provides its own builder — Android `Room.databaseBuilder(context, AppDatabase::class.java, "app.db")`; iOS/JVM `Room.databaseBuilder<AppDatabase>(databasePath = …)`. **KSP must be wired per target** (`ksp(libs.androidx.room.compiler)` is Android-only):

```kotlin
dependencies {
    add("kspAndroid", libs.androidx.room.compiler)
    add("kspIosArm64", libs.androidx.room.compiler)
    add("kspIosSimulatorArm64", libs.androidx.room.compiler)
    // … one per target
}
room { schemaDirectory("$projectDir/schemas") }   // export the schema for migration-history tracking
```

For pure-Android projects, skip `@ConstructedBy` and call `Room.databaseBuilder(context, AppDatabase::class.java, "app.db")` directly — Room behaves identically; the KMP setup is opt-in when the data layer must live in `commonMain`.
