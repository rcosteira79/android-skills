---
name: datastore
description: Use when persisting key-value preferences or small typed settings on Android or KMP with Jetpack DataStore — Preferences vs Typed (Proto/JSON) selection, KMP factory with per-platform file paths, SharedPreferences migration, serializers with corruption handlers, DI singletons, and repository/MVI integration. Triggers on DataStore, Preferences, PreferenceDataStoreFactory, DataStoreFactory, preferencesDataStore, SharedPreferencesMigration, Serializer, or persistent settings work.
---

# Jetpack DataStore for Android and KMP

Reactive, coroutine-based key-value and typed storage. The same `androidx.datastore:datastore-preferences-core` runs on Android, iOS, JVM, and Web — only the file-path producer is platform-specific. Adapted from [Meet-Miyani/compose-skill](https://github.com/Meet-Miyani/compose-skill)'s DataStore reference. MIT licensed.

**Related skills:** `android-skills:android-data-layer` (Repository pattern, `DataError` hierarchy), `android-skills:kmp-boundaries` (`expect/actual` factory), `android-skills:kotlin-flows` (collecting DataStore `Flow` into UI state).

## Decision: Preferences vs Typed vs Room

| Need | Storage | Why |
|------|---------|-----|
| Key-value flags (theme, locale, onboarding done) | Preferences DataStore | No schema, reactive `Flow<Preferences>` |
| Single typed object with many related fields | Typed DataStore + `Serializer<T>` | Type-safe, schema evolution via `@Serializable` |
| Relational data, indexes, `WHERE`/`JOIN`, >100 entries | Room | SQL-backed, compile-time queries, Paging |
| Payloads above ~50KB per write | Room or filesystem | DataStore rewrites the **whole file** on every `edit` |

Rule of thumb: if a `WHERE` clause would be useful, use Room.

## Critical Rules

1. **One `DataStore` instance per file.** A second instance throws `IllegalStateException("There are multiple DataStores active for the same file")`, and concurrent access races the file lock and can corrupt data. Enforce via a DI singleton.
2. **Immutable types only** — mutation breaks the read-modify-write guarantee of `updateData`/`edit`.
3. **Don't mix single-process and multi-process factories** for the same file.

Dependencies: `androidx.datastore:datastore-preferences-core` (KMP Preferences), `datastore-core` + `kotlinx-serialization-json` (Typed DataStore), `datastore-preferences` (Android `Context.preferencesDataStore` delegate). Pin from the [release page](https://developer.android.com/jetpack/androidx/releases/datastore); apply `org.jetbrains.kotlin.plugin.serialization` for Typed.

## KMP Factory

```kotlin
// commonMain
internal const val PREFS_FILE = "app_settings.preferences_pb"
fun createPreferencesDataStore(producePath: () -> String): DataStore<Preferences> =
    PreferenceDataStoreFactory.createWithPath(produceFile = { producePath().toPath() })
// androidMain — context.filesDir
fun createPlatformDataStore(context: Context): DataStore<Preferences> =
    createPreferencesDataStore { context.filesDir.resolve(PREFS_FILE).absolutePath }
// iosMain — NSDocumentDirectory via NSFileManager
fun createPlatformDataStore(): DataStore<Preferences> = createPreferencesDataStore {
    val dir = NSFileManager.defaultManager.URLForDirectory(NSDocumentDirectory, NSUserDomainMask, null, false, null)
    requireNotNull(dir).path + "/$PREFS_FILE"
}
// jvmMain — app-specific dir under user.home, NOT java.io.tmpdir (OS may wipe on reboot)
fun createPlatformDataStore(): DataStore<Preferences> = createPreferencesDataStore {
    val appDir = File(System.getProperty("user.home"), ".myapp").apply { mkdirs() }
    File(appDir, PREFS_FILE).absolutePath
}
```

On Android-only projects, the `Context.preferencesDataStore("settings")` delegate is a shorter equivalent that also accepts `produceMigrations`.

## Preferences: Keys, Reads, Writes

Key factories in `androidx.datastore.preferences.core` follow the value type (`booleanPreferencesKey`, `intPreferencesKey`, `stringPreferencesKey`, `stringSetPreferencesKey`, …). Declare keys and defaults together so reads and writes share one source of truth.

```kotlin
internal object Keys { val DARK_MODE = booleanPreferencesKey("dark_mode"); val LOCALE = stringPreferencesKey("locale") }
internal object Defaults { const val DARK_MODE = false; const val LOCALE = "en" }

class SettingsRepository(private val dataStore: DataStore<Preferences>) {
    val settings: Flow<UserSettings> = dataStore.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
        .map { p -> UserSettings(p[Keys.DARK_MODE] ?: Defaults.DARK_MODE, p[Keys.LOCALE] ?: Defaults.LOCALE) }
    suspend fun setDarkMode(enabled: Boolean) { dataStore.edit { it[Keys.DARK_MODE] = enabled } }
}
```

`edit` is an atomic read-modify-write. `.catch` **must match `IOException` specifically** (file unreadable on first launch or after corruption) and rethrow everything else — most importantly `CancellationException`. A broad `catch { emit(...) }` swallows cancellation (breaking structured concurrency) and hides serializer/corruption errors behind a silent empty state.

## Typed DataStore with kotlinx.serialization

```kotlin
@Serializable data class AppSettings(val darkMode: Boolean = false, val locale: String = "en")

object AppSettingsSerializer : Serializer<AppSettings> {
    override val defaultValue = AppSettings()
    override suspend fun readFrom(input: InputStream): AppSettings =
        try { Json.decodeFromString(input.readBytes().decodeToString()) }
        catch (e: SerializationException) { throw CorruptionException("Cannot read AppSettings", e) }
    override suspend fun writeTo(t: AppSettings, output: OutputStream) =
        output.write(Json.encodeToString(t).encodeToByteArray())
}

val settingsDataStore: DataStore<AppSettings> = DataStoreFactory.create(
    serializer = AppSettingsSerializer,
    corruptionHandler = ReplaceFileCorruptionHandler { AppSettings() },
    produceFile = { File(context.filesDir, "app_settings.json") },
)
// Read: settingsDataStore.data — Write: settingsDataStore.updateData { it.copy(locale = "fr") }
```

`ReplaceFileCorruptionHandler` recovers when `readFrom` fails — but the trigger is `CorruptionException`, **not** `IOException`. Without it, one corrupt file makes every read fail permanently.

## SharedPreferences Migration

`SharedPreferencesMigration` copies all keys from a legacy `SharedPreferences` file on first access, then deletes it (runs once). For custom key transformations, implement `DataMigration<Preferences>` directly.

```kotlin
val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "settings",
    produceMigrations = { ctx -> listOf(SharedPreferencesMigration(ctx, "legacy_shared_prefs")) },
)
```

## DI — Single Instance per File

```kotlin
// Koin (KMP) — commonMain
val storageModule = module {
    single<DataStore<Preferences>> { createPlatformDataStore(get()) }
    single { SettingsRepository(get()) }
}
// Hilt (Android-only)
@Module @InstallIn(SingletonComponent::class) object StorageModule {
    @Provides @Singleton
    fun provideDataStore(@ApplicationContext ctx: Context): DataStore<Preferences> = createPlatformDataStore(ctx)
}
```

## Repository / MVI Integration

The repository maps `Flow<Preferences>` to a domain model and **owns writes** (`dataStore.edit` stays in the repository, never the ViewModel); it maps `IOException` to `DataError.Local` at the boundary. The ViewModel collects via `stateIn`/`combine` and never sees DataStore types. **Never `runBlocking` on DataStore inside a composable** — it parks the main thread on disk I/O (ANR risk) and re-runs every recomposition. Expose a `StateFlow` and collect with `collectAsStateWithLifecycle`.

```kotlin
class SettingsViewModel(private val repository: SettingsRepository) : ViewModel() {
    val uiState: StateFlow<SettingsUiState> = combine(repository.settings, repository.featureFlags()) { s, f -> SettingsUiState(s, f) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsUiState.Loading)

    fun onToggleDarkMode(enabled: Boolean) { viewModelScope.launch { repository.setDarkMode(enabled) } }
}
```
