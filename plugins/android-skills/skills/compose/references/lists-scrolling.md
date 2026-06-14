# Lists and Scrolling in Jetpack Compose

This reference covers the performance traps and hardening details of lazy lists, not the basics of `LazyColumn` / `LazyRow`, the `items` DSL, keys, or grids.

## The `indexOf()`-in-item-factory O(n²) trap

Calling `indexOf` / `lastIndexOf` / `indexOfFirst { }` on the source list **inside** the item lambda is O(n) per item, so a single scroll pass costs O(n²) over the list. It's a convincing trap because the lookup is often genuinely needed ("highlight the active item").

```kotlin
// WRONG — O(n²): each item rescans the whole list for its own position, on every scroll recomposition
items(items, key = { it.id }) { item ->
    val isActive = items.indexOf(item) == activeIndex      // O(n) per item
    ItemRow(item, isActive)
}

// RIGHT — itemsIndexed gives the index for free
itemsIndexed(items, key = { _, it -> it.id }) { position, item -> ItemRow(item, position == activeIndex) }

// RIGHT (lookup is by id, not index) — build a Map once, outside the lambda
val byId = remember(items) { items.associateBy { it.id } }
items(items, key = { it.id }) { item -> ItemRow(item, byId[activeId] === item) }   // O(1)
```

(LazyList *crash* patterns — `indexOf` → `IndexOutOfBoundsException`, duplicate/colliding keys + the dedup-index fix, `derivedStateOf` driving a collection count — live in `compose/references/production-crash-playbook.md`, §2/§4/§5/§8.)

## Keys: never build a new object in the key lambda

A stable-id key is the easy part; the trap is computing a *new object* in the key lambda, which defeats it (the key changes every recomposition):

```kotlin
items(users, key = { User(it.id, it.name) }) { … }   // WRONG — new object every recomposition
items(users, key = { it.id }) { … }                  // RIGHT — primitive, stable id
```

## `animateItem()` needs stable keys

`items(list, key = { it.id })` gives each item identity across recompositions — which is exactly what makes `animateItem()` (per-item add/remove/move animation), efficient diffing, and per-item state preservation work. Reach for `itemsIndexed` only when you genuinely need the index for display.

```kotlin
items(items, key = { it.id }) { item ->
    ItemRow(item, modifier = Modifier.animateItem(
        fadeInSpec = tween(250),
        placementSpec = spring(Spring.DampingRatioLowBouncy, Spring.StiffnessMediumLow),
        fadeOutSpec = tween(150),
    ))
}
```

## `ReportDrawnWhen` for startup metrics

Signal that the first meaningful content is visible so Android vitals measures TTID/TTFD correctly:

```kotlin
@Composable
fun ConversationListScreen(items: List<Conversation>) {
    ReportDrawnWhen { items.isNotEmpty() }
    LazyColumn { items(items, key = { it.id }) { ConversationRow(it) } }
}
```

## Infinite scroll — derive the trigger, and test across OEMs

```kotlin
val shouldLoadMore by remember {
    derivedStateOf {
        val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
        last >= listState.layoutInfo.totalItemsCount - PREFETCH_THRESHOLD   // e.g. 5
    }
}
LaunchedEffect(shouldLoadMore) { if (shouldLoadMore) viewModel.loadNextPage() }
```

Some OEMs (notably Samsung) deliver scroll events differently and trigger lazy-load with fewer confirmations — make `PREFETCH_THRESHOLD` configurable and test on multiple devices. (For full Paging-3-backed infinite scroll, see `android-skills:paging`.)

**Two scroll containers fighting:** don't wrap a lazy child in a `verticalScroll` modifier, or nest a `Column(verticalScroll)` inside a `LazyColumn` item — use nested lazy composables, or a `nestedScroll` connection for coordinated scroll.
