---
name: paging
description: Use when implementing paginated lists in Android or Compose with Paging 3 — PagingSource, Pager and PagingConfig setup, RemoteMediator for offline-first lists, LazyPagingItems and itemKey integration in LazyColumn, dynamic filters via flatMapLatest, and unit tests with TestPager and asSnapshot. Triggers include Paging 3, infinite list, infinite scroll, paginated list, LazyPagingItems, collectAsLazyPagingItems, and cachedIn.
---

# Paging 3 for Android and Compose

Adapted from [Meet-Miyani/compose-skill](https://github.com/Meet-Miyani/compose-skill)'s Paging references. MIT licensed.

**Related skills:** `android-skills:android-data-layer` for the non-paged repository pattern, `android-skills:android-retrofit` / `android-skills:kmp-ktor` for the network layer that feeds `PagingSource`, and `android-skills:compose` for `LazyColumn` integration.

Paging 3 streams paged data from a `PagingSource` (and optionally a `RemoteMediator`) through a `Pager` into `LazyPagingItems`. For non-paged repositories, defer to `android-skills:android-data-layer`. KMP support is Android-only as of `androidx.paging` 3.5.0 — multiplatform Paging is on the roadmap; verify status at https://developer.android.com/jetpack/androidx/releases/paging.

---

## Dependencies

```toml
# libs.versions.toml
[versions]
paging = "3.5.0"

[libraries]
androidx-paging-common   = { module = "androidx.paging:paging-common",   version.ref = "paging" }
androidx-paging-runtime  = { module = "androidx.paging:paging-runtime",  version.ref = "paging" }
androidx-paging-compose  = { module = "androidx.paging:paging-compose",  version.ref = "paging" }
androidx-paging-testing  = { module = "androidx.paging:paging-testing",  version.ref = "paging" }
```
Wire into the module: `implementation(libs.androidx.paging.runtime)` + `implementation(libs.androidx.paging.compose)` + `testImplementation(libs.androidx.paging.testing)`.

**Domain layer (clean architecture):** if the project has a framework-agnostic domain module, depend only on `androidx.paging:paging-common` there — it ships `PagingSource`, `PagingData`, `LoadResult`, and the core types with no Android dependencies, so `PagingSource` interfaces and use cases can live in domain without pulling Android in. The `paging-runtime` artifact stays in the data layer.

---

## PagingSource

Define a `PagingSource<Key, Value>` per remote endpoint. The factory passed to `Pager` must return a **new instance** every call — Paging asserts a `PagingSource` is never reused.

```kotlin
class RepoPagingSource(private val service: GitHubService, private val query: String) :
    PagingSource<Int, RepoDto>() {

    override suspend fun load(params: LoadParams<Int>): LoadResult<Int, RepoDto> {
        val page = params.key ?: 1
        return try {
            val response = service.searchRepos(query, page = page, perPage = params.loadSize)
            LoadResult.Page(
                data = response.items,
                prevKey = if (page == 1) null else page - 1,
                nextKey = if (response.items.isEmpty()) null else page + 1,
            )
        } catch (e: IOException) { LoadResult.Error(e) }
        catch (e: HttpException) { LoadResult.Error(e) }
    }

    override fun getRefreshKey(state: PagingState<Int, RepoDto>): Int? =
        state.anchorPosition?.let { pos ->
            state.closestPageToPosition(pos)?.let { it.prevKey?.plus(1) ?: it.nextKey?.minus(1) }
        }
}
```

Catch specific exceptions (`IOException`, `HttpException`, DB-specific). Return `null` for `prevKey` / `nextKey` to signal the boundary. For cursor-based APIs, switch the key type to `String` and pass the server cursor through `nextKey`.

---

## Pager and ViewModel — the dual-flow rule

**`PagingData` must be a separate `Flow`, never a field inside `UiState`.** The ViewModel exposes `uiState: StateFlow<UiState>` for non-paging concerns AND `pagingItems: Flow<PagingData<T>>` for the paged stream. `cachedIn(viewModelScope)` sits on the paging flow so materialised data survives configuration changes.

```kotlin
@HiltViewModel
class RepoListViewModel @Inject constructor(private val repository: RepoRepository) : ViewModel() {

    private val _uiState = MutableStateFlow(RepoListUiState())
    val uiState: StateFlow<RepoListUiState> = _uiState.asStateFlow()

    val pagingItems: Flow<PagingData<RepoUi>> = Pager(
        config = PagingConfig(pageSize = 20, prefetchDistance = 5, enablePlaceholders = false, initialLoadSize = 40),
        pagingSourceFactory = { repository.repoPagingSource(query = "") },
    ).flow
        .map { pagingData -> pagingData.map { it.toUi() } }
        .cachedIn(viewModelScope)
}
```

| `PagingConfig` parameter | Purpose |
|---|---|
| `pageSize` | Items requested per page (required). |
| `prefetchDistance` | Distance from the edge that triggers the next load. |
| `enablePlaceholders` | Null slots for unloaded items — disable for variable-height rows. |
| `initialLoadSize` | First-request size; defaults to `3 * pageSize`. |

Apply `.map { }` / `.filter { }` / `.insertSeparators { }` on the outer `Flow<PagingData>` **before** `cachedIn`. Anything chained after `cachedIn` is recomputed on every collector.

---

## Dynamic filters and search

Use `flatMapLatest` so a parameter change replaces the active `Pager`. Debounce text input and `distinctUntilChanged` upstream so identical emissions don't rebuild the `Pager`.

```kotlin
private val _query = MutableStateFlow("")
private val _status = MutableStateFlow(StatusFilter.ALL)

val pagingItems: Flow<PagingData<RepoUi>> = combine(
    _query.debounce(300).distinctUntilChanged(),
    _status.distinctUntilChanged(),
) { q, s -> q to s }
    .flatMapLatest { (q, s) ->
        Pager(PagingConfig(pageSize = 20)) { repository.repoPagingSource(query = q, status = s) }
            .flow.map { pagingData -> pagingData.map { it.toUi() } }
    }
    .cachedIn(viewModelScope)
```

`cachedIn` **must come after** `flatMapLatest`. Placed inside the lambda it caches a per-emission scope and leaks a fresh cache on every filter change.

---

## Compose UI with LazyPagingItems

```kotlin
@Composable
fun RepoListRoute(viewModel: RepoListViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val pagingItems = viewModel.pagingItems.collectAsLazyPagingItems()
    RepoListScreen(uiState, pagingItems, viewModel::onEvent)
}

@Composable
fun RepoListScreen(state: RepoListUiState, pagingItems: LazyPagingItems<RepoUi>, onEvent: (RepoListEvent) -> Unit) {
    LazyColumn {
        items(
            count = pagingItems.itemCount,
            key = pagingItems.itemKey { it.id },
            contentType = pagingItems.itemContentType { "repo" },
        ) { idx -> pagingItems[idx]?.let { RepoRow(it, onClick = { onEvent(RepoListEvent.Clicked(it.id)) }) } }

        when (val append = pagingItems.loadState.append) {
            is LoadState.Loading -> item { LoadingFooter() }
            is LoadState.Error -> item { ErrorFooter(append.error) { pagingItems.retry() } }
            is LoadState.NotLoading -> Unit
        }
    }
    when (val refresh = pagingItems.loadState.refresh) {
        is LoadState.Loading -> if (pagingItems.itemCount == 0) FullScreenLoader()
        is LoadState.Error -> if (pagingItems.itemCount == 0) FullScreenError(refresh.error) { pagingItems.retry() }
        is LoadState.NotLoading -> Unit
    }
}
```

| Operation | Effect |
|---|---|
| `pagingItems[index]` | Reads the item **and** triggers load near the edge. |
| `pagingItems.peek(index)` | Reads without triggering a load. |
| `pagingItems.retry()` / `refresh()` | Retry last failed page / reload from scratch. Call from event handlers, never composable bodies. |
| `loadState.refresh` | Full chain (PagingSource + RemoteMediator). |
| `loadState.source.refresh` | PagingSource only — use when a `RemoteMediator` is present so the spinner stays until Room writes complete. |

`itemKey` with a stable domain ID is mandatory — without it `LazyColumn` reuses slots by index and scroll jumps when items prepend.

---

## Offline-first with RemoteMediator

The Room DAO is the `PagingSource`; a `RemoteMediator<Key, Value>` orchestrates network refresh + DB writes. The DAO method must return `PagingSource<Int, RepoEntity>` — e.g. `@Query("SELECT * FROM repos") fun pagingSource(): PagingSource<Int, RepoEntity>`. See `android-skills:android-data-layer` for the broader offline-first model.

```kotlin
@OptIn(ExperimentalPagingApi::class)
class RepoRemoteMediator(private val service: GitHubService, private val db: AppDatabase) :
    RemoteMediator<Int, RepoEntity>() {

    override suspend fun initialize(): InitializeAction {
        val lastUpdated = db.remoteKeyDao().getLastUpdated("repos") ?: 0L
        return if (System.currentTimeMillis() - lastUpdated < TimeUnit.HOURS.toMillis(1))
            InitializeAction.SKIP_INITIAL_REFRESH else InitializeAction.LAUNCH_INITIAL_REFRESH
    }

    override suspend fun load(loadType: LoadType, state: PagingState<Int, RepoEntity>): MediatorResult {
        val page = when (loadType) {
            LoadType.REFRESH -> 1
            LoadType.PREPEND -> return MediatorResult.Success(endOfPaginationReached = true)
            LoadType.APPEND -> db.remoteKeyDao().getRemoteKey("repos")?.nextPage
                ?: return MediatorResult.Success(endOfPaginationReached = true)
        }
        return try {
            val response = service.searchRepos(page = page, perPage = state.config.pageSize)
            db.withTransaction {
                if (loadType == LoadType.REFRESH) { db.repoDao().deleteAll(); db.remoteKeyDao().delete("repos") }
                db.repoDao().insertAll(response.items.map { it.toEntity() })
                db.remoteKeyDao().upsert(RemoteKey("repos", if (response.items.isEmpty()) null else page + 1))
            }
            MediatorResult.Success(endOfPaginationReached = response.items.isEmpty())
        } catch (e: IOException) { MediatorResult.Error(e) }
        catch (e: HttpException) { MediatorResult.Error(e) }
    }
}

@OptIn(ExperimentalPagingApi::class)
val pagingItems: Flow<PagingData<RepoEntity>> = Pager(
    config = PagingConfig(pageSize = 20),
    remoteMediator = RepoRemoteMediator(service, db),
    pagingSourceFactory = { db.repoDao().pagingSource() },
).flow.cachedIn(viewModelScope)
```

With a `RemoteMediator`, the UI must observe `loadState.source.refresh` rather than `loadState.refresh` — the convenience property can flip to `NotLoading` before Room finishes writing, dropping the spinner too early.

---

## Testing

`paging-testing` provides `TestPager` for `PagingSource` unit tests and `Flow<PagingData<T>>.asSnapshot { }` for ViewModel integration tests. Never call `.first()` / `.toList()` on a paging flow — it is hot and never completes; `asSnapshot` is the only correct test collector.

```kotlin
@Test fun `PagingSource returns first page`() = runTest {
    val source = RepoPagingSource(FakeGitHubService(items = listOf(repo1, repo2)), query = "kotlin")
    val pager = TestPager(PagingConfig(pageSize = 10), source)
    val page = pager.refresh() as PagingSource.LoadResult.Page

    assertEquals(2, page.data.size); assertNull(page.prevKey); assertEquals(2, page.nextKey)
}

@Test fun `PagingSource maps IOException to LoadResult Error`() = runTest {
    val source = RepoPagingSource(FakeGitHubService(error = IOException()), query = "")
    val result = source.load(LoadParams.Refresh(key = null, loadSize = 20, placeholdersEnabled = false))
    assertTrue(result is LoadResult.Error)
}

@Test fun `ViewModel paging flow exposes first two pages`() = runTest {
    val viewModel = RepoListViewModel(FakeRepoRepository())
    val items: List<RepoUi> = viewModel.pagingItems.asSnapshot { scrollTo(index = 30) }
    assertTrue(items.size >= 30); assertEquals("repo_1", items.first().id)
}
```

---

## RIGHT vs WRONG Patterns

### `PagingData` inside `UiState`

```kotlin
// WRONG — paging flow embedded in the state flow
data class UiState(val pagingData: Flow<PagingData<RepoUi>>, val filter: Filter = Filter.ALL)
private val _uiState = MutableStateFlow(UiState(pagingData = repo.repoPager().cachedIn(viewModelScope)))

// RIGHT — two separate flows on the ViewModel
val uiState: StateFlow<UiState> = _uiState.asStateFlow()
val pagingItems: Flow<PagingData<RepoUi>> =
    Pager(PagingConfig(pageSize = 20)) { repo.repoPagingSource() }.flow.cachedIn(viewModelScope)
```

WRONG because every non-paging state change (selection toggle, filter chip, snackbar) re-emits `UiState`, which hands a brand-new `Flow<PagingData>` to `collectAsLazyPagingItems()`. That collector sees a new upstream, drops its cache, restarts loads, and resets scroll to top. Two independent flows is the only correct shape.

### `cachedIn` before `flatMapLatest`

```kotlin
// WRONG — cachedIn upstream of the flatMapLatest that builds Pagers
val pagingItems = _query
    .map { Pager(PagingConfig(20)) { repo.source(it) }.flow }
    .cachedIn(viewModelScope)          // caches a Flow<Flow<...>>, not paged data
    .flatMapLatest { it }

// RIGHT — cachedIn at the bottom, after flatMapLatest emits PagingData
val pagingItems = _query
    .debounce(300).distinctUntilChanged()
    .flatMapLatest { q -> Pager(PagingConfig(20)) { repo.source(q) }.flow }
    .cachedIn(viewModelScope)
```

WRONG because `cachedIn` must wrap the final `Flow<PagingData<T>>`. Placed earlier it caches a flow-of-flows and the inner `Pager` is recreated for every collector, undoing the cache entirely.

### Missing `itemKey` in `LazyColumn`

```kotlin
// WRONG — positional identity; prepended page shifts every existing item
items(count = pagingItems.itemCount) { idx -> pagingItems[idx]?.let { RepoRow(it) } }

// RIGHT — stable domain ID survives prepend / refresh
items(
    count = pagingItems.itemCount,
    key = pagingItems.itemKey { it.id },
    contentType = pagingItems.itemContentType { "repo" },
) { idx -> pagingItems[idx]?.let { RepoRow(it) } }
```

WRONG because positional keys mean a prepended page shifts every existing item's identity. `LazyColumn` reuses the wrong row state, `rememberSaveable` values collide, animations target the wrong slot, and scroll position visibly jumps. `itemKey { it.id }` ties identity to the data.

### Transformations downstream of `cachedIn`

```kotlin
// WRONG — filtering after cachedIn; re-runs per collector and breaks separators
Pager(PagingConfig(20)) { repo.source() }.flow
    .cachedIn(viewModelScope)
    .map { it.filter { repo -> !repo.archived } }

// RIGHT — map / filter / insertSeparators before cachedIn
Pager(PagingConfig(20)) { repo.source() }.flow
    .map { pagingData -> pagingData.filter { !it.archived }.map { it.toUi() } }
    .cachedIn(viewModelScope)
```

WRONG because anything chained after `cachedIn` runs in the collector's scope — cached data is re-transformed for every subscriber and `insertSeparators` boundaries can desync. All `PagingData` transformations belong **above** `cachedIn`.

---

## Checklist

- [ ] `Flow<PagingData<T>>` is exposed as a **separate** property from `StateFlow<UiState>`.
- [ ] `cachedIn(viewModelScope)` sits at the bottom of the chain, after any `flatMapLatest`.
- [ ] `pagingSourceFactory` returns a **new** `PagingSource` on every invocation.
- [ ] `PagingSource.load` catches specific exceptions (`IOException`, `HttpException`) and returns `LoadResult.Error`.
- [ ] `LazyColumn` uses `itemKey` with a stable domain ID and a meaningful `itemContentType`.
- [ ] `loadState.refresh` / `append` drive loaders and retry; with `RemoteMediator`, use `loadState.source.refresh`.
- [ ] `RemoteMediator.load` wraps DB writes in `withTransaction` and clears local state on `LoadType.REFRESH`.
- [ ] Dynamic filters are debounced and `distinctUntilChanged` before `flatMapLatest`.
- [ ] `refresh()` is called from event handlers or `LaunchedEffect`, never from a composable body.
- [ ] Tests use `TestPager` for `PagingSource` and `asSnapshot { }` for ViewModel flows — never `.first()` on a paging flow.
