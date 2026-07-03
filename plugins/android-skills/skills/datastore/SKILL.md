---
name: datastore
description: Use when persisting key-value preferences or small typed settings on Android or KMP with Jetpack DataStore — Preferences vs Typed (Proto/JSON) vs Room selection, the IOException and corruption-recovery error traps, serializers with corruption handlers, and the KMP factory with per-platform file paths. Triggers on DataStore, Preferences, PreferenceDataStoreFactory, DataStoreFactory, preferencesDataStore, Serializer, SharedPreferences-to-DataStore migration, or persistent settings work.
---

# Jetpack DataStore for Android and KMP

Reactive coroutine-based key-value / typed storage; the same `androidx.datastore:datastore-preferences-core` runs on Android, iOS, and JVM — only the file-path producer is platform-specific. (Web support is 1.3.0-alpha only, and it's `sessionStorage`/OPFS-backed there, not file-path-based.) This reference covers the storage-choice call plus the two error/path traps, not the basics of Preferences keys, `edit { }`, or `Serializer<T>`. Adapted from [Meet-Miyani/compose-skill](https://github.com/Meet-Miyani/compose-skill); MIT. **Related:** `android-skills:android-data-layer`, `android-skills:kmp-boundaries`, `android-skills:kotlin-flows`.

## Preferences vs Typed vs Room

| Need | Storage |
|---|---|
| Key-value flags (theme, locale, onboarding done) | Preferences DataStore |
| One typed object, many related fields, schema evolution | Typed DataStore + `Serializer<T>` |
| Relational data, indexes, `WHERE` / `JOIN`, >100 entries, paging | Room |
| Payloads above ~50KB per write | Room / filesystem — DataStore rewrites the **whole file** on every `edit` |

Rule of thumb: if a `WHERE` clause would be useful, use Room.

## The two traps

**`.catch` must match `IOException` specifically — never a broad `catch`.** A bare `catch { emit(emptyPreferences()) }` swallows `CancellationException` (breaking structured concurrency) and hides serializer/corruption errors behind a silent empty state.

```kotlin
val settings: Flow<UserSettings> = dataStore.data
    .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e }
    .map { p -> UserSettings(p[Keys.DARK_MODE] ?: false, p[Keys.LOCALE] ?: "en") }
```

**Typed-DataStore corruption recovery triggers on `CorruptionException`, NOT `IOException`.** The serializer's `readFrom` must wrap parse failures in `CorruptionException`, and the store needs a `ReplaceFileCorruptionHandler` — without it, one corrupt file makes every read fail permanently.

```kotlin
object AppSettingsSerializer : Serializer<AppSettings> {
    override val defaultValue = AppSettings()
    override suspend fun readFrom(input: InputStream): AppSettings =
        try { Json.decodeFromString(input.readBytes().decodeToString()) }
        catch (e: SerializationException) { throw CorruptionException("Cannot read AppSettings", e) }
    override suspend fun writeTo(t: AppSettings, output: OutputStream) =
        output.write(Json.encodeToString(t).encodeToByteArray())
}
val store = DataStoreFactory.create(
    serializer = AppSettingsSerializer,
    corruptionHandler = ReplaceFileCorruptionHandler { AppSettings() },
    produceFile = { File(context.filesDir, "app_settings.json") },
)
```

## KMP factory — per-platform path (not the temp dir)

```kotlin
// commonMain
fun createPreferencesDataStore(producePath: () -> String): DataStore<Preferences> =
    PreferenceDataStoreFactory.createWithPath(produceFile = { producePath().toPath() })
// android: context.filesDir.resolve(PREFS_FILE).absolutePath
// ios:     NSDocumentDirectory via NSFileManager
// jvm:     File(System.getProperty("user.home"), ".myapp") — NOT java.io.tmpdir (the OS may wipe it on reboot)
```

(In a composable, never `runBlocking` on DataStore — it parks the main thread on disk I/O, risking an ANR, and re-runs every recomposition. Expose a `StateFlow` and collect with `collectAsStateWithLifecycle`.)
