# Focus Navigation Reference

Focus is the *primary* input model on TV, ChromeOS, keyboard, desktop, and any D-pad/remote device — clicks are secondary. A UI that looks right with a mouse can be unusable with a keyboard.

Covers `FocusRequester`, `Modifier.focusable()`, `onFocusChanged`, `focusProperties`, key events, lazy-list focus restoration, focus traps, TV patterns, predictive back, and testing. Source: `androidx/compose/ui/focus/` and `androidx/compose/ui/input/key/`.

## Core Principle

**Make focus targets explicit, request focus after composition succeeds, and test with the input model users use** (D-pad/Tab, not tap). Three rules govern every decision here:

1. **Don't fight the framework.** `Button`, `TextField`, `Modifier.clickable`, and `Modifier.selectable` already participate in focus. Add hooks only when behaviour demands it.
2. **Request focus from an effect, never the composable body.** `LaunchedEffect` guarantees composition finished and the node is attached.
3. **Restore focus by stable id, not by index.** Lists reorder; ids don't.

## When To Reach For Focus APIs

| Need | Add |
|------|-----|
| Normal button / text field / clickable focus | Nothing — already focusable |
| Programmatic initial or restored focus | `FocusRequester` + `Modifier.focusRequester(...)` |
| Visual/state reaction to focus changes | `Modifier.onFocusChanged { ... }` |
| Custom interactive surface not already focusable | `Modifier.focusable()` + role/semantics |
| Override directional navigation (D-pad/arrows) | `Modifier.focusProperties { ... }` |
| Handle hardware keys (Back, Enter, custom) | `Modifier.onPreviewKeyEvent` / `onKeyEvent` |
| Constrain focus to a region (modal, menu) | `FocusRequester` + `focusProperties` traps |

If no row applies, the screen needs none of this. Don't sprinkle `focusRequester`/`onFocusChanged` on every button "just in case."

## FocusRequester — Programmatic Focus

```kotlin
val requester = remember { FocusRequester() }

Button(onClick = onPlay, modifier = Modifier.focusRequester(requester)) {
    Text("Play")
}

// Request from an effect, not the composable body:
LaunchedEffect(requester) { requester.requestFocus() }
```

`requestFocus()` from the composable body races composition: the node may not be attached, the requester may be re-allocated on recomposition, or the call may run before layout. `LaunchedEffect` avoids all three.

**Key the effect to the condition that makes the target exist** — not `Unit`:

```kotlin
// BAD: fires once on initial composition, before items exist
LaunchedEffect(Unit) { firstItemRequester.requestFocus() }

// GOOD: fires when items become available
LaunchedEffect(items.isNotEmpty()) {
    if (items.isNotEmpty()) firstItemRequester.requestFocus()
}
```

**Target inside a lazy list:** items aren't composed until scrolled into view, so the requester's node may not be attached. Scroll first, then request: `listState.scrollToItem(i); requester.requestFocus()` — or keep the first visible item focused and let spatial search take over.

**Special values:**

```kotlin
focusProperties { up = FocusRequester.Default }   // defer to spatial search
focusProperties { left = FocusRequester.Cancel }  // block focus leaving this direction
```

`Cancel` traps focus inside a region (modal, menu); `Default` opts back into spatial search. Source: `androidx/compose/ui/focus/FocusRequester.kt`.

## Modifier.focusable() — Custom Interactive Surfaces

A `Box` is not focusable; `Modifier.clickable` makes it focusable as a side effect. For an interactive surface without a click handler, add `focusable()` plus role/semantics so screen readers see what focus sees:

```kotlin
Box(modifier = Modifier.focusable().semantics {
    role = Role.Button; contentDescription = "Drag handle"
})
```

**Don't add `focusable()` to a `Column`/`Row` with interactive children — it swallows focus that should reach them.** A card that acts as one big button should use `Surface(onClick = ...)` or `Modifier.clickable`.

## Modifier.onFocusChanged — React to Focus State

`FocusState` properties:
- `isFocused` — this node is the focused target.
- `hasFocus` — this node *or any descendant* is focused (usually what you want for "this section is active").
- `isCaptured` — focus forcibly held (rare; modals).

**Don't infer focus from selection.** A user D-pads through a list (focus moves) without selecting (commit pressed). Conflating them breaks every keyboard/TV interaction:

```kotlin
// WRONG — focus conflated with selection
if (item.id == selectedId) Modifier.scale(1.05f)

// RIGHT — observe focus separately
Modifier.onFocusChanged { state -> isFocused = state.isFocused }
```

## Modifier.focusProperties — Override Spatial Navigation

Default spatial search is good. Override only when the layout creates an unsolvable graph (off-screen item, two valid targets in one direction, a jump across the screen).

```kotlin
val firstRow = remember { FocusRequester() }

Column(modifier = Modifier.focusProperties {
    down = firstRow                 // "down" jumps directly to the first row
    left = FocusRequester.Cancel    // keep focus inside the column
}) {
    Header()
    LazyRow { item { FirstCard(modifier = Modifier.focusRequester(firstRow)) } }
}
```

- Override **only the broken edges**; leave spatial search responsible for everything else.
- `FocusRequester.Cancel` traps; `FocusRequester.Default` returns to framework search.
- Overriding more than two directions on one node usually means the layout is wrong — fix the layout. Source: `androidx/compose/ui/focus/FocusProperties.kt`.

## Key Events — onPreviewKeyEvent / onKeyEvent

```kotlin
Modifier.onPreviewKeyEvent { event ->
    when {
        event.type == KeyEventType.KeyUp && event.key == Key.Back -> { onBack(); true }
        event.type == KeyEventType.KeyDown && event.key == Key.Escape -> { onDismiss(); true }
        else -> false
    }
}
```

- **Return `true` only when consumed.** Returning `true` for everything swallows text input, accessibility shortcuts, and parent navigation. Default to `false`.
- `onPreviewKeyEvent` runs **before** children (intercept — e.g. a shortcut that should beat a focused `TextField`); `onKeyEvent` runs **after** (children first, the normal case). Dialog/back/escape usually wants preview, since focus is on a `TextField` below.

| Key | Use |
|-----|-----|
| `Key.Back` | Hardware/browser back |
| `Key.Escape` | Dismiss dialogs/menus |
| `Key.Enter` / `Key.NumPadEnter` / `Key.DirectionCenter` | Activate focused item (D-pad center) |
| `Key.DirectionUp/Down/Left/Right` | D-pad / arrow navigation |
| `Key.Tab` | Focus traversal (Shift+Tab reverses) |

**Throttle expensive D-pad responses at the boundary** — a TV remote fires 10+ events/sec. Throttle the response (scrolling, paging), not the handler:

```kotlin
val scrollChannel = remember { Channel<Int>(Channel.CONFLATED) }

LaunchedEffect(scrollChannel) {
    scrollChannel.receiveAsFlow().collectLatest { delta ->
        listState.animateScrollBy(delta.toFloat())
    }
}

Modifier.onPreviewKeyEvent { event ->
    if (event.type == KeyEventType.KeyDown && event.key == Key.DirectionRight) {
        scrollChannel.trySend(itemWidth); true
    } else false
}
```

Source: `androidx/compose/ui/input/key/KeyEvent.kt`.

## Lazy List Focus Restoration

When list content refreshes (pull-to-refresh, filter, paging), focus disappears unless restored. Restoring by index breaks the moment items reorder, insert, or delete — restore by stable id:

```kotlin
@Composable
fun ArticleList(
    articles: ImmutableList<Article>,
    listState: LazyListState = rememberLazyListState(),
) {
    // id -> FocusRequester, regenerated when ids change
    val requesters = remember(articles) { articles.associate { it.id to FocusRequester() } }
    // Track focused article so we can restore after refresh
    var lastFocusedId by rememberSaveable { mutableStateOf<String?>(null) }

    LaunchedEffect(articles, lastFocusedId) {
        val id = lastFocusedId ?: return@LaunchedEffect
        val requester = requesters[id] ?: run {
            requesters.values.firstOrNull()?.requestFocus()  // focused id gone — fall back
            return@LaunchedEffect
        }
        val index = articles.indexOfFirst { it.id == id }
        if (index >= 0) {
            listState.scrollToItem(index)   // scroll into view first
            requester.requestFocus()
        }
    }

    LazyColumn(state = listState) {
        items(articles, key = { it.id }) { article ->
            ArticleRow(
                article = article,
                modifier = Modifier
                    .focusRequester(requesters.getValue(article.id))
                    .onFocusChanged { if (it.isFocused) lastFocusedId = article.id }
            )
        }
    }
}
```

**Fallback when the focused id no longer exists:** same id → nearest neighbour → first item → parent container. Pick one per screen and stick to it; the framework can't guess which the user expects.

## Focus Traps — Dialogs, Modals, Menus

A modal must keep focus inside until it closes, or D-pad/Tab walks the user out the back into the obscured content. Request initial focus on a button inside, and `Cancel` the edges:

```kotlin
val confirmRequester = remember { FocusRequester() }
LaunchedEffect(confirmRequester) { confirmRequester.requestFocus() }

Dialog(onDismissRequest = onDismiss) {
    Surface(modifier = Modifier
        .focusProperties {
            up = FocusRequester.Cancel; down = FocusRequester.Cancel
            left = FocusRequester.Cancel; right = FocusRequester.Cancel
        }
        .onPreviewKeyEvent { e ->
            if (e.type == KeyEventType.KeyUp && e.key == Key.Escape) { onDismiss(); true } else false
        }
    ) {
        Column {
            Text("Delete this item?")
            Row {
                Button(onClick = onDismiss) { Text("Cancel") }
                Button(onClick = onConfirm, modifier = Modifier.focusRequester(confirmRequester)) { Text("Delete") }
            }
        }
    }
}
```

`Dialog` and `ModalBottomSheet` trap focus on Android **only if focus is inside them when they open** — always request initial focus on a child; never rely on the framework to do it.

## TV and androidx.tv.material3

Prefer `androidx.tv:tv-material` / `tv-foundation` over regular Material 3 — the TV components ship focus-aware visuals (rings, scale, elevation) and integrate with the leanback navigation model. Gotchas:

- **Touch targets don't apply** — D-pad jumps don't need 48dp; visual focus indication (ring/scale/glow) matters more.
- **No hover on TV** — `hover ≠ focus`.
- **`Modifier.clickable` registers for D-pad center** automatically; no custom activation handler needed.
- **Don't trap horizontal focus on rows** — a row that swallows `left`/`right` at its edges feels broken. Let edges escape to siblings.

## Predictive Back Focus Restoration (Android 14+)

`PredictiveBackHandler` animates the back gesture but does **not** restore focus on the destination — the source screen does. Its `rememberSaveable` `lastFocusedId` (see the lazy-list recipe above) drives restoration when it recomposes after back; the detail screen's job is just to navigate. See `compose/references/animation.md` for the visual side.

## Testing Focus

Drive the same input model users use — a click test on a TV/keyboard UI proves nothing.

```kotlin
@Test
fun `D-pad down from header focuses first item`() {
    composeTestRule.setContent { AppTheme { BrowseScreen(uiState = previewSuccessState()) } }
    composeTestRule.onNodeWithTag("header").performKeyInput {
        keyDown(Key.DirectionDown); keyUp(Key.DirectionDown)
    }
    composeTestRule.onNodeWithTag("first-item").assertIsFocused()
}

@Test
fun `search screen focuses query field on entry`() {
    composeTestRule.setContent { AppTheme { SearchScreen(onQueryChange = {}) } }
    composeTestRule.onNodeWithTag("search-field").assertIsFocused()
}
```

Restoration test — proves id-not-index by shuffling (same ids, new order):

```kotlin
@Test
fun `refreshing list restores focus to previously-focused article by id`() {
    val initial = previewArticles()
    val refreshed = initial.shuffled()
    composeTestRule.setContent {
        var articles by remember { mutableStateOf(initial) }
        Column {
            Button(onClick = { articles = refreshed }) { Text("Refresh") }
            ArticleList(articles = articles.toImmutableList())
        }
    }
    composeTestRule.onNodeWithTag("article-${initial[2].id}").performClick()
    composeTestRule.onNodeWithText("Refresh").performClick()
    composeTestRule.waitForIdle()
    composeTestRule.onNodeWithTag("article-${initial[2].id}").assertIsFocused()
}
```

Use `assertIsFocused()` to assert *which* node owns focus; screenshot tests are for the *appearance* of focus (ring/scale/elevation), not ownership. See `android-skills:android-testing` for the broader test-shape decision.

## Review Red Flags

- "It focuses when I tap it" for a TV/ChromeOS/keyboard screen — drive D-pad/Tab instead.
- Initial focus works with fixed data but fails after load/refresh — usually `LaunchedEffect(Unit)` instead of keying to the loaded condition.
- Focus inferred from selection state.
- `focusable()` on a `Column`/`Row` with interactive children (swallows focus).
- `Modifier.onPreviewKeyEvent { _ -> true }` — swallows unhandled keys.
- A modal opens without requesting focus on a child inside it.
- Lazy-list refresh with no restoration recipe.

## Resources

- Compose focus: https://developer.android.com/develop/ui/compose/touch-input/focus
- TV with Compose: https://developer.android.com/develop/ui/compose/tv
- Key events: https://developer.android.com/develop/ui/compose/touch-input/handling-key-events
- androidx.tv.material3: https://developer.android.com/jetpack/androidx/releases/tv

For test-shape decisions and semantics-first selectors, see `android-skills:android-testing`. For predictive-back animation, see `compose/references/animation.md`. For the semantics layer (separate from focus traversal), see `compose/references/accessibility.md`.
