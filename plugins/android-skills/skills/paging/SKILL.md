---
name: paging
description: Use when implementing paginated lists in Android or Compose with Paging 3 — PagingSource, Pager and PagingConfig setup, RemoteMediator for offline-first lists, LazyPagingItems and itemKey integration in LazyColumn, dynamic filters via flatMapLatest, and unit tests with TestPager and asSnapshot. Triggers include Paging 3, infinite list, infinite scroll, paginated list, LazyPagingItems, collectAsLazyPagingItems, and cachedIn.
---

# Paging 3 for Android and Compose

Adapted from [Meet-Miyani/compose-skill](https://github.com/Meet-Miyani/compose-skill)'s Paging references. MIT licensed. **Related:** `android-skills:android-data-layer` (non-paged repository), `android-skills:android-retrofit` / `android-skills:kmp-ktor` (network feeding `PagingSource`), `android-skills:compose` (`LazyColumn`).

This reference covers the current-version fact, the placement and identity rules that are easy to get wrong, and the `RemoteMediator` offline-first timing — not the basics of `PagingSource` / `Pager` / `collectAsLazyPagingItems`.

## Version (current fact)

As of `androidx.paging` **3.5.0**, `paging-common`, `paging-compose`, and `paging-testing` are Kotlin Multiplatform (Android, JVM, iOS, Native, JS/Wasm); only `paging-runtime` (and `-guava`/`-rxjava`) stay Android-only. So in a clean-architecture domain module, depend only on `androidx.paging:paging-common` — it ships `PagingSource` / `PagingData` / `LoadResult` with no Android dependency, so `PagingSource` interfaces and use cases can live in domain. (Verify the current version and KMP support at the [releases page](https://developer.android.com/jetpack/androidx/releases/paging).)

## Dual-flow rule — `PagingData` is its own `Flow`, never a field in `UiState`

Expose `uiState: StateFlow<UiState>` AND `pagingItems: Flow<PagingData<T>>` as **separate** properties.

```kotlin
val uiState: StateFlow<UiState> = _uiState.asStateFlow()
val pagingItems: Flow<PagingData<RepoUi>> =
    Pager(PagingConfig(pageSize = 20, prefetchDistance = 5, enablePlaceholders = false)) { repo.repoPagingSource() }
        .flow
        .map { data -> data.map { it.toUi() } }   // transforms BEFORE cachedIn
        .cachedIn(viewModelScope)
```

If `PagingData` rides inside `UiState`, every non-paging state change (selection, filter chip, snackbar) re-emits `UiState` and hands `collectAsLazyPagingItems()` a brand-new `Flow<PagingData>` — it drops its cache, restarts loads, and resets scroll to top.

## `cachedIn` placement

`cachedIn(viewModelScope)` sits at the **bottom** of the chain: after any `flatMapLatest` (filters/search), and after every `map` / `filter` / `insertSeparators`. Anything chained *after* `cachedIn` re-runs in each collector's scope (re-transforming cached data, desyncing separators); a `cachedIn` placed *inside* a `flatMapLatest` lambda leaks a fresh cache on every filter change.

```kotlin
val pagingItems = combine(_query.debounce(300).distinctUntilChanged(), _status.distinctUntilChanged(), ::Pair)
    .flatMapLatest { (q, s) -> Pager(PagingConfig(20)) { repo.repoPagingSource(q, s) }.flow.map { it.map(RepoDto::toUi) } }
    .cachedIn(viewModelScope)
```

## `itemKey` is mandatory in `LazyColumn`

```kotlin
items(
    count = pagingItems.itemCount,
    key = pagingItems.itemKey { it.id },              // stable domain id
    contentType = pagingItems.itemContentType { "repo" },
) { idx -> pagingItems[idx]?.let { RepoRow(it) } }
```

Without `itemKey`, `LazyColumn` reuses slots by index — a prepended page shifts every existing item's identity, so row state / `rememberSaveable` / animations target the wrong slot and scroll visibly jumps. (`pagingItems[i]` reads *and* triggers a load near the edge; `peek(i)` reads without loading. Call `retry()` / `refresh()` from event handlers or a `LaunchedEffect`, never a composable body.)

## `RemoteMediator` (offline-first)

With offline-first paging the Room DAO is the `PagingSource` and a `RemoteMediator` drives network refresh + DB writes. Wrap those writes in `db.withTransaction { }`, and clear local state on `LoadType.REFRESH`. Gate the full-screen loader on `loadState.source.refresh` + `itemCount == 0` — **not** the combined `loadState.refresh`, which flips to `NotLoading` before Room finishes writing and drops the spinner a frame early.

## Testing — `TestPager` / `asSnapshot`, never `.first()`

A paging flow is hot and never completes, so `.first()` / `.toList()` on it hangs. Use `paging-testing`:

```kotlin
@Test fun `source returns first page`() = runTest {
    val pager = TestPager(PagingConfig(10), RepoPagingSource(FakeGitHubService(repo1, repo2), "kotlin"))
    val page = pager.refresh() as PagingSource.LoadResult.Page
    assertEquals(2, page.data.size); assertNull(page.prevKey); assertEquals(2, page.nextKey)
}

@Test fun `viewmodel paging flow exposes first pages`() = runTest {
    val items = RepoListViewModel(FakeRepoRepository()).pagingItems.asSnapshot { scrollTo(index = 30) }
    assertTrue(items.size >= 30)
}
```
