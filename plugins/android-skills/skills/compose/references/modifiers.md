# Jetpack Compose Modifiers Reference

> **Modifier and slots together form the public-API contract of any reusable composable.** The caller owns *placement* (the `modifier` parameter) and *what to place* (the content slots). This file covers the modifier side; see `compose/references/view-composition.md` for the slot authoring rules.

This reference covers the **API-contract rules** for the modifier parameter, plus the chain-ordering reference other files point here for — not the modifier catalogue itself.

## Modifier as API Contract

Every reusable composable has a public surface: a `modifier` parameter and (often) content slots. Declare `modifier: Modifier = Modifier` and apply it to the root node (lint enforces both). The two rules below are the ones lint doesn't catch; violating them silently breaks callers — sizes won't apply, and the composable becomes un-reusable outside its original screen.

### Rule 1 — Caller's modifier comes FIRST in the chain

Caller modifiers must precede internal modifiers so the caller's intent wins. The only exception: modifiers tied to the composable's visual *identity* (e.g., `Avatar`'s `.clip(CircleShape)`) may follow.

```kotlin
// WRONG — hardcoded chain first; caller's modifier overridden
@Composable
fun Avatar(modifier: Modifier = Modifier) {
    Box(modifier = Modifier.size(48.dp).clip(CircleShape).then(modifier)) { ... }
}

// RIGHT — caller's modifier first; identity modifier (clip) after
@Composable
fun Avatar(modifier: Modifier = Modifier) {
    Box(modifier = modifier.clip(CircleShape)) { ... }
}
```

**Why:** Whichever `.size(...)` appears first wins for the outer measurement the parent sees. Putting a hardcoded `.size(48.dp)` first makes a caller's `.size(120.dp)` a no-op for the Avatar's outer dimensions. Caller intent must come first; only modifiers that define what the composable *is* (a circular crop for `Avatar`) belong after.

### Rule 2 — No hardcoded placement on a reusable root

A reusable composable's root MUST NOT carry `.fillMaxWidth()`, `.height(56.dp)`, `.padding(horizontal = 16.dp)`, or any other placement decision. Placement is the parent's job — that's what the `modifier` parameter is for. (This is the one most often gotten wrong.)

```kotlin
// WRONG — root hardcodes "I take full width and 56dp tall with horizontal padding".
// Caller cannot place this in a Row, give it a different size, or remove the padding.
@Composable
fun ListItem(text: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .padding(horizontal = 16.dp)
    ) {
        Text(text)
    }
}

// RIGHT — placement is the caller's call; component only decides its own internals
@Composable
fun ListItem(text: String, modifier: Modifier = Modifier) {
    Row(modifier = modifier) {
        Text(text, modifier = Modifier.padding(horizontal = 16.dp))
    }
}
// Caller decides placement:
// ListItem("Hello", modifier = Modifier.fillMaxWidth().height(56.dp))
```

**Identity carve-out:** Visual-identity modifiers — the ones without which the composable wouldn't *be* that composable — may stay on the root. `.clip(CircleShape)` on `Avatar` qualifies. Apply them AFTER the caller's modifier in the chain (see Rule 1).

**Why:** Hardcoded placement makes a composable usable only in the one screen it was extracted from. The moment another screen needs it at a different width, inside a `Row`, or without that padding, the only options are forking or wrapping. The `modifier` parameter exists precisely to let parents make these calls.

## Modifier Chain Ordering

Modifiers apply left-to-right in the DSL but conceptually wrap bottom-to-top — each wraps the content below it. **Order outer (layout/sizing) → inner (styling/interaction).**

```kotlin
Modifier.background(Color.Red).padding(16.dp).size(100.dp)   // red wraps the padded 100dp box
Modifier.size(100.dp).padding(16.dp).background(Color.Red)   // outer stays 100dp; padding sits inside it, red fills the inner 68dp
```

`.padding(16.dp).size(100.dp)` is 132dp outside with 100dp of content, `.size(100.dp).padding(16.dp)` is 100dp outside with 68dp of content; `.clip` before `.background` clips the background to the shape (after, it doesn't). This is the ordering reference `compose/references/design-to-compose.md` and `view-composition.md` point here for.

## Custom modifiers, semantics, testTag — defer

- **Custom modifiers:** prefer the `Modifier.Node` / `ModifierNodeElement` API over the deprecated `composed { }` (which creates a composition scope per use and captures composition locals). The deprecation + migration path lives in `compose/references/deprecated-patterns.md`.
- **Semantics** (`contentDescription`, `role`, `clearAndSetSemantics`, `mergeDescendants`) and **`testTag`** are standard. For the more advanced a11y bits (traversal order via `traversalIndex`/`isTraversalGroup`, live-region mode) see `compose/references/accessibility.md`; for test-selector strategy (semantics-first over `testTag`) see `android-skills:android-testing`.
