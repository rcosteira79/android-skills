---
name: android-data-layer
description: Use when implementing the data layer in Android — Repository pattern, Room local database, offline-first synchronization, and coordinating local and remote sources.
---

# Android Data Layer

The data layer coordinates data from multiple sources. Its public API to the rest of the app is repository interfaces; its internal implementation details (DAOs, API services, DTOs) never leak upward.

**Related skills:** See `android-skills:android-retrofit` for Retrofit service setup, OkHttp configuration, and Hilt module wiring. See `android-skills:android-dev` for how the data layer fits into the overall architecture and error propagation model.

## Repository Pattern

The repository is the **single source of truth**. It decides whether to serve cached data or fetch fresh data, and maps raw data-layer types to domain models.

```kotlin
class NewsRepository @Inject constructor(
    private val newsDao: NewsDao,
    private val newsApi: NewsApi,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
) {
    // Room DAO as the source of truth — UI always reads from local DB
    val newsStream: Flow<List<News>> = newsDao.getAllNews()

    // Triggered by UI or WorkManager to refresh data
    suspend fun refreshNews(): Result<Unit> = withContext(ioDispatcher) {
        try {
            val remoteNews = newsApi.fetchLatest()
            newsDao.insertAll(remoteNews.map { it.toDomain() })
            Result.success(Unit)
        } catch (e: IOException) {
            Result.failure(DataError.Network(e))
        } catch (e: HttpException) {
            Result.failure(DataError.Server(e.code(), e.message()))
        }
    }
}

// Domain-level errors — never expose HTTP/IO types above the data layer.
// Ask the user if this structure fits their project. Adapt naming, granularity,
// and hierarchy to match existing error conventions if present.
sealed class DataError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Network(cause: Throwable) : DataError("Network error", cause)
    class Server(val code: Int, message: String?) : DataError("Server error $code: $message")
    class Local(cause: Throwable) : DataError("Local storage error", cause)
}
```

**With a domain layer:** When use cases exist, the repository throws `DataError` exceptions instead of returning `Result<T>`. Use cases catch `DataError` and return `Result<T>` with domain-specific error models. See `android-skills:android-dev` Error Handling section for the full layered propagation model.

Bind the interface to its implementation in a Hilt module:

```kotlin
@Binds
abstract fun bindNewsRepository(impl: OfflineFirstNewsRepository): NewsRepository
```

---

## Room — Local Database

### Entity

**Ask the user** which naming convention they prefer for cached/database models:
- `Entity` suffix (e.g. `ArticleEntity`) — Room convention, ties the name to the persistence layer
- `Cached` prefix (e.g. `CachedArticle`) — abstracts the cache mechanism, useful if the storage backend might change

If the project already has a convention, match it. If no preference, default to `Entity` suffix.

```kotlin
@Entity(tableName = "articles")
data class ArticleEntity(       // or CachedArticle
    @PrimaryKey val id: String,
    val title: String,
    val body: String,
    val publishedAt: Long
)
```

### DAO

Return `Flow<T>` for observable queries; `suspend fun` for one-shot reads and writes.

```kotlin
@Dao
interface ArticleDao {

    @Query("SELECT * FROM articles ORDER BY publishedAt DESC")
    fun observeAll(): Flow<List<ArticleEntity>>

    @Query("SELECT * FROM articles WHERE id = :id")
    suspend fun findById(id: String): ArticleEntity?

    @Upsert
    suspend fun upsertAll(articles: List<ArticleEntity>)

    @Query("DELETE FROM articles")
    suspend fun deleteAll()
}
```

### Database

```kotlin
@Database(entities = [ArticleEntity::class], version = 1, exportSchema = true)
abstract class AppDatabase : RoomDatabase() {
    abstract fun articleDao(): ArticleDao
}
```

Provide as a singleton via Hilt and export the schema for migration history tracking.

### Room in KMP (commonMain)

Room has been KMP-stable since 2.7.0. The shared setup differs from the Android-only setup in three places:

1. `@ConstructedBy(...)` on the `@Database`, paired with an `expect object` that Room generates per-platform `actual`s for.
2. `BundledSQLiteDriver` from `androidx.sqlite:sqlite-bundled` — ensures the same SQLite version across Android, iOS, JVM, and web targets (Android's system SQLite drifts between API levels and devices).
3. `setQueryCoroutineContext(Dispatchers.IO)` — Android Room defaults this; KMP doesn't.

```kotlin
// commonMain
@Database(entities = [ArticleEntity::class], version = 1)
@ConstructedBy(AppDatabaseConstructor::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun articleDao(): ArticleDao
}

@Suppress("KotlinNoActualForExpect")
expect object AppDatabaseConstructor : RoomDatabaseConstructor<AppDatabase>

fun getRoomDatabase(builder: RoomDatabase.Builder<AppDatabase>): AppDatabase =
    builder
        .setDriver(BundledSQLiteDriver())
        .setQueryCoroutineContext(Dispatchers.IO)
        .build()
```

Each platform provides its own `RoomDatabase.Builder`:

- **Android:** `Room.databaseBuilder(context, AppDatabase::class.java, "app.db")`
- **iOS:** `Room.databaseBuilder<AppDatabase>(databasePath = "${NSHomeDirectory()}/app.db")`
- **JVM:** `Room.databaseBuilder<AppDatabase>(databasePath = "${System.getProperty("user.home")}/app.db")`

KSP must be wired **per target** — `ksp(libs.androidx.room.compiler)` is Android-only:

```kotlin
dependencies {
    add("kspAndroid", libs.androidx.room.compiler)
    add("kspIosArm64", libs.androidx.room.compiler)
    add("kspIosX64", libs.androidx.room.compiler)
    add("kspIosSimulatorArm64", libs.androidx.room.compiler)
    // … one per target
}
room { schemaDirectory("$projectDir/schemas") }
```

For pure Android projects, skip `@ConstructedBy` and call `Room.databaseBuilder(context, AppDatabase::class.java, "app.db")` directly — Room behaves identically. The KMP setup is opt-in when the data layer needs to live in `commonMain`.

---

## Offline-First Strategies

### Read — Stale-While-Revalidate

Show local data immediately; trigger a background refresh in parallel.

```kotlin
// In ViewModel
fun loadNews() {
    viewModelScope.launch {
        // 1. Start observing the local DB immediately
        repository.newsStream
            .collect { articles -> _uiState.update { it.copy(articles = articles) } }
    }

    viewModelScope.launch {
        // 2. Trigger a network refresh in parallel
        repository.refreshNews().onFailure { error ->
            _uiState.update { it.copy(error = error.message) }
        }
    }
}
```

### Write — Outbox Pattern

Save changes locally first, then sync to the server. Use WorkManager to guarantee delivery even if the app is killed.

```kotlin
// 1. Mark item as unsynced in the DB immediately
suspend fun likeArticle(id: String) {
    articleDao.markAsUnsynced(id, action = "LIKE")
}

// 2. WorkManager job (runs when connected)
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val articleDao: ArticleDao,
    private val newsApi: NewsApi
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val unsynced = articleDao.getUnsyncedActions()
        unsynced.forEach { action ->
            newsApi.postAction(action)
            articleDao.markAsSynced(action.id)
        }
        return Result.success()
    }
}
```

---

## Model Mapping

Keep three distinct model types and map between them at layer boundaries:

| Layer | Model Type | Purpose |
|-------|-----------|---------|
| Network | DTO (`ArticleDto`) | Matches API JSON structure |
| Database | Entity (`ArticleEntity`) or Cached (`CachedArticle`) | Matches Room table schema — naming per user preference |
| Domain/UI | Domain model (`Article`) | What the rest of the app uses |

```kotlin
// DTO → Entity (in repository, before writing to DB)
fun ArticleDto.toEntity(): ArticleEntity = ArticleEntity(
    id = id,
    title = title,
    body = body,
    publishedAt = publishedAt
)

// Entity → Domain model (in repository, before returning to ViewModel)
fun ArticleEntity.toDomain(): Article = Article(
    id = id,
    title = title,
    body = body,
    publishedAt = Instant.ofEpochMilli(publishedAt)
)
```

---

## RIGHT vs WRONG Patterns

### DAO return types

```kotlin
// WRONG — suspend fun when the UI needs to observe ongoing changes
@Dao
interface ArticleDao {
    @Query("SELECT * FROM articles")
    suspend fun getAll(): List<ArticleEntity> // caller must re-query manually to see new inserts
}

// RIGHT — Flow for queries the UI observes; suspend for one-shot reads and mutations
@Dao
interface ArticleDao {
    @Query("SELECT * FROM articles ORDER BY publishedAt DESC")
    fun observeAll(): Flow<List<ArticleEntity>> // emits whenever table changes

    @Query("SELECT * FROM articles WHERE id = :id")
    suspend fun findById(id: String): ArticleEntity? // one-shot lookup — suspend is correct

    @Upsert
    suspend fun upsertAll(articles: List<ArticleEntity>) // mutation — suspend is correct
}
```

WRONG when the UI needs to stay in sync with the database — a `suspend fun` query returns a single snapshot, so inserts or updates after the initial load are invisible to the caller. A `Flow` return type makes Room automatically re-emit whenever the underlying table changes. That said, `suspend fun` is the right choice for one-shot queries where the caller only needs the current state — e.g., checking if a record exists before inserting, or loading data that won't change during the screen's lifetime.

### Exposing data layer types to the UI

```kotlin
// WRONG — ViewModel exposes Entity directly; couples UI to the database schema
class ArticleViewModel(private val dao: ArticleDao) : ViewModel() {
    val articles = dao.observeAll() // Flow<List<ArticleEntity>>
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

// In UI — forced to work with raw DB fields:
Text(Instant.ofEpochMilli(entity.publishedAt).toString()) // raw Long from Room

// RIGHT — map at each layer boundary; UI works with UI models
// Repository maps Entity → Domain (or directly to a model the ViewModel consumes):
val articlesStream: Flow<List<Article>> = articleDao.observeAll()
    .map { entities -> entities.map { it.toDomain() } }

// ViewModel maps Domain → UI model:
class ArticleViewModel(private val repository: ArticleRepository) : ViewModel() {
    val articles = repository.articlesStream
        .map { articles -> articles.map { it.toUiModel() } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
}

// In UI — stable UI model with presentation-ready fields:
Text(uiArticle.formattedDate) // formatting lives in toUiModel(), not in the domain
```

WRONG because the ViewModel exposes `ArticleEntity` directly to the UI, coupling it to the database schema — adding a column or renaming a field breaks the UI. The exact mapping chain depends on the architecture: with a domain layer, the repository maps Entity → Domain and the ViewModel maps Domain → UI model; without a domain layer, the ViewModel (or repository) maps the data model to a UI model directly. Either way, the UI works with stable UI models and never sees data layer types. Presentation logic like date formatting belongs in the UI model mapping, not in the domain model.

### Error boundary placement

```kotlin
// WRONG — IOException and HttpException escape to the ViewModel
class ArticleRepository(private val api: NewsApi, private val dao: ArticleDao) {
    suspend fun refreshArticles() { // throws IOException, HttpException
        val articles = api.fetchLatest()
        dao.upsertAll(articles.map { it.toEntity() })
    }
}

// ViewModel is forced to catch network exceptions it shouldn't know about

// RIGHT — repository catches and maps to domain error types
class ArticleRepository(private val api: NewsApi, private val dao: ArticleDao) {
    suspend fun refreshArticles(): Result<Unit> = try {
        val articles = api.fetchLatest()
        dao.upsertAll(articles.map { it.toEntity() })
        Result.success(Unit)
    } catch (e: IOException) {
        Result.failure(DataError.Network(e))
    } catch (e: HttpException) {
        Result.failure(DataError.Server(e.code(), e.message()))
    }
}
```

WRONG because uncaught `IOException` and `HttpException` force the ViewModel to import Retrofit and OkHttp types. The repository is the error boundary — it converts implementation-specific exceptions into domain error types that the rest of the app can handle without knowing the underlying network or storage implementation.

## Checklist

- [ ] Repository exposes `Flow` for streams and `suspend fun` returning `Result<T>` for one-shot operations
- [ ] Raw DTOs, entities, and HTTP/IO exceptions never reach the ViewModel — map to domain models and domain errors at the repository boundary
- [ ] Room DAOs return `Flow` for observed queries; `suspend` for mutations
- [ ] Schema exported (`exportSchema = true`) and migration scripts provided for version bumps
- [ ] Offline-first: local DB is the source of truth; network writes go through an outbox if reliability matters
- [ ] WorkManager used for sync operations that must survive process death
