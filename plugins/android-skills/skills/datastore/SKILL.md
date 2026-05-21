---
name: datastore
description: Use when persisting key-value preferences or small typed settings on Android or KMP with Jetpack DataStore — Preferences vs Typed (Proto/JSON) selection, KMP factory with per-platform file paths, SharedPreferences migration, serializers with corruption handlers, DI singletons, and repository/MVI integration. Triggers on DataStore, Preferences, PreferenceDataStoreFactory, DataStoreFactory, preferencesDataStore, SharedPreferencesMigration, Serializer, or persistent settings work.
---

# Jetpack DataStore for Android and KMP

Reactive, coroutine-based key-value and typed storage. The same `androidx.datastore:datastore-preferences-core` runs on Android, iOS, JVM, and Web — only the file path producer is platform-specific. For relational data, queries, or anything larger than ~50KB per write, use Room. Adapted from [Meet-Miyani/compose-skill](https://github.com/Meet-Miyani/compose-skill)'s DataStore reference. MIT licensed.

**Related skills:** `android-skills:android-data-layer` for the Repository pattern and unified `DataError` hierarchy; `android-skills:kmp-boundaries` for `expect/actual` factory patterns; `android-skills:kotlin-flows` for collecting DataStore `Flow` into UI state.

## Decision: Preferences vs Typed vs Room

| Need | Storage | Why |
|------|---------|-----|
| Key-value flags (theme, locale, onboarding done) | Preferences DataStore | No schema, reactive `Flow<Preferences>`, simplest API |
| Single typed object with many related fields | Typed DataStore + `Serializer<T>` | Type-safe, schema evolution via `@Serializable` |
| Relational data, indexes, `WHERE`/`JOIN`, >100 entries | Room | SQL-backed, compile-time queries, Paging support |
| Payloads above ~50KB per write | Room or filesystem | DataStore rewrites the whole file on every `edit` |

**Rule of thumb:** if a `WHERE` clause would be useful, use Room.

## Critical Rules

1. **One `DataStore` instance per file.** A second instance throws `IllegalStateException` and can corrupt the file. Enforce via DI singleton.
2. **Immutable types only.** Mutation breaks the read-write-modify guarantee of `updateData`/`edit`.
3. **Do not mix single-process and multi-process factories** for the same file.

## Dependencies

```toml
[libraries]
androidx-datastore-preferences-core = { module = "androidx.datastore:datastore-preferences-core", version.ref = "datastore" }
androidx-datastore-core = { module = "androidx.datastore:datastore-core", version.ref = "datastore" }
androidx-datastore-preferences = { module = "androidx.datastore:datastore-preferences", version.ref = "datastore" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "kotlinx-serialization" }
```

Verify the latest version at the [DataStore release page](https://developer.android.com/jetpack/androidx/releases/datastore). Apply the `org.jetbrains.kotlin.plugin.serialization` Gradle plugin for Typed DataStore.

| Source set | Module | Purpose |
|------------|--------|---------|
| `commonMain` | `androidx-datastore-preferences-core` | KMP Preferences API |
| `commonMain` | `androidx-datastore-core` + `kotlinx-serialization-json` | Typed DataStore with JSON `Serializer<T>` |
| `androidMain` (Android-only) | `androidx-datastore-preferences` | `Context.preferencesDataStore` delegate |

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

Seven key factories in `androidx.datastore.preferences.core`: `booleanPreferencesKey`, `intPreferencesKey`, `longPreferencesKey`, `floatPreferencesKey`, `doublePreferencesKey`, `stringPreferencesKey`, `stringSetPreferencesKey`. Declare keys and defaults at module top so reads and writes share one source of truth.

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

`edit` is an atomic read-modify-write transaction. `.catch` handles `IOException` specifically (file unreadable on first launch or after corruption) and rethrows everything else — most importantly `CancellationException`.

## Typed DataStore with kotlinx.serialization

For one settings object with many fields, Typed DataStore beats juggling many preference keys.

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

`ReplaceFileCorruptionHandler` recovers when `readFrom` throws `CorruptionException` — without it a corrupted file makes every read fail permanently. Throwing `CorruptionException` (not `IOException`) triggers the handler.

## SharedPreferences Migration

`SharedPreferencesMigration` copies all keys from a legacy `SharedPreferences` file on first access, then deletes it. Runs once. For custom key transformations, implement `DataMigration<Preferences>` directly.

```kotlin
val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "settings",
    produceMigrations = { ctx -> listOf(SharedPreferencesMigration(ctx, "legacy_shared_prefs")) },
)
```

## DI Setup

Single instance per file — always a singleton. See `android-skills:kmp-ktor` for the equivalent `expect/actual` engine module pattern.

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

## Repository and MVI Integration

The repository maps `Flow<Preferences>` to a domain model; the ViewModel collects it via `combine` or `stateIn`. Reading inside `combine { ... }` is fine; writing is a domain action — `dataStore.edit` stays in the repository, never the ViewModel.

```kotlin
class SettingsViewModel(private val repository: SettingsRepository) : ViewModel() {
    val uiState: StateFlow<SettingsUiState> = combine(repository.settings, repository.featureFlags()) { s, f -> SettingsUiState(s, f) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsUiState.Loading)

    fun onToggleDarkMode(enabled: Boolean) { viewModelScope.launch { repository.setDarkMode(enabled) } }
}
```

## RIGHT vs WRONG Patterns

### Multiple instances for the same file

```kotlin
// WRONG — two instances pointing at the same file
class FeatureA(context: Context) { val ds = PreferenceDataStoreFactory.create(produceFile = { context.preferencesDataStoreFile("settings") }) }
class FeatureB(context: Context) { val ds = PreferenceDataStoreFactory.create(produceFile = { context.preferencesDataStoreFile("settings") }) }

// RIGHT — single DataStore provided via DI; features inject it
@Provides @Singleton fun provideDataStore(@ApplicationContext ctx: Context) = createPlatformDataStore(ctx)
class FeatureA @Inject constructor(private val dataStore: DataStore<Preferences>)
```

WRONG because DataStore enforces single-instance-per-file at runtime — the second instance throws `IllegalStateException("There are multiple DataStores active for the same file")`, and concurrent reads race on the file lock and can corrupt the stored data.

### `.catch { IOException }` swallowing all errors

```kotlin
// WRONG — swallows every failure, including coroutine cancellation
val settings = dataStore.data.catch { emit(emptyPreferences()) }.map { /* ... */ }

// RIGHT — handle IOException explicitly, rethrow everything else, map durable failures at the repository
val settings = dataStore.data
    .catch { e -> when (e) { is IOException -> emit(emptyPreferences()); else -> throw e } }
    .map { it.toUserSettings() }

suspend fun setDarkMode(enabled: Boolean): Result<Unit> = try {
    dataStore.edit { it[Keys.DARK_MODE] = enabled }; Result.success(Unit)
} catch (e: IOException) { Result.failure(DataError.Local(e)) }
```

WRONG because the broad `catch { emit(...) }` matches `CancellationException` too, breaking structured concurrency, and hides serializer/corruption errors behind a silent empty state. Match `IOException` specifically and surface durable failures as `DataError.Local` at the repository boundary. See `android-skills:kotlin-flows`.

### `runBlocking` on the main thread or inside a composable

```kotlin
// WRONG — blocks the UI thread; produces ANRs on slow storage
@Composable fun ThemeToggle(dataStore: DataStore<Preferences>) {
    val darkMode = runBlocking { dataStore.data.first()[Keys.DARK_MODE] ?: false }
    Switch(checked = darkMode, onCheckedChange = { /* ... */ })
}

// RIGHT — collect a StateFlow exposed by the ViewModel; composable observes, never blocks
@Composable fun ThemeToggle(viewModel: SettingsViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    Switch(checked = state.settings.darkMode, onCheckedChange = viewModel::onToggleDarkMode)
}
```

WRONG because `runBlocking` parks the main thread waiting for disk I/O — under GC, cold-cache I/O, or a contended file lock the wait crosses the 5-second ANR threshold. Inside a composable every recomposition re-runs the block. Expose a `StateFlow` and collect it with `collectAsStateWithLifecycle`.

## Checklist

- [ ] Decision made: Preferences vs Typed vs Room based on data shape and size
- [ ] Single `DataStore` instance per file, provided as a DI singleton
- [ ] KMP factory uses `PreferenceDataStoreFactory.createWithPath` with platform-specific path producer
- [ ] Desktop path anchored in `System.getProperty("user.home")`, not `java.io.tmpdir`
- [ ] Preference keys and defaults declared together at the top of the module
- [ ] `.catch` matches `IOException` specifically and rethrows everything else
- [ ] Typed DataStore uses `ReplaceFileCorruptionHandler` and throws `CorruptionException` on parse failure
- [ ] `SharedPreferencesMigration` configured via `produceMigrations` when migrating legacy code
- [ ] Repository maps `IOException` to `DataError.Local`; ViewModel never sees DataStore types
- [ ] No `runBlocking` on the main thread or inside composables — collect a `StateFlow` instead
