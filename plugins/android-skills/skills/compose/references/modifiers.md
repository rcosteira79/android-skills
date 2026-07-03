# Jetpack Compose Modifiers Reference

> **Modifier and slots together form the public-API contract of any reusable composable.** The caller owns *placement* (the `modifier` parameter) and *what to place* (the content slots). This file covers the modifier side; see `compose/references/view-composition.md` for the slot authoring rules.

This reference covers the **API-contract rules** for the modifier parameter, plus the chain-ordering reference other files point here for — not the modifier catalogue itself.

## Modifier as API Contract

Every reusable composable has a public surface: a `modifier` parameter and (often) content slots. The rules below govern the modifier half of that contract. Violating them silently breaks callers — sizes won't apply, paddings stack twice, and the composable becomes un-reusable outside its original screen.

### Rule 1 — Param naming is exact

Any composable that emits layout MUST declare `modifier: Modifier = Modifier`. The name must be literally `modifier` — not `mod`, `m`, `wrapperModifier`, or `outerModifier`. Place it after required params and before content lambdas.

```kotlin
// WRONG — non-standard names break tooling, lint, and reader expectations
@Composable
fun Avatar(url: String, m: Modifier = Modifier) { ... }

@Composable
fun Card(wrapperModifier: Modifier = Modifier, content: @Composable () -> Unit) { ... }

// RIGHT — canonical signature: required params, modifier with default, then slots
@Composable
fun Avatar(url: String, modifier: Modifier = Modifier) { ... }

@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) { ... }
```

**Why:** Lint rules (`ComposableModifierParameterPosition`, `ModifierParameter`), Android Studio's inspections, and every Compose codebase convention assume this exact name and position. Renaming it breaks IDE auto-import of `Modifier.Companion`, defeats lint, and surprises every reader. The default value `= Modifier` lets callers omit it; the name `modifier` is non-negotiable.

### Rule 2 — Apply the caller's modifier to the ROOT layout, not a child

Caller-supplied modifiers like `.size(...)`, `.padding(...)`, or `.weight(...)` must reach the outermost emitted node.

```kotlin
// WRONG — caller's .size(120.dp) lands on the inner Image, not the outer Box.
// The Box still measures intrinsic, so the Avatar is the wrong size in its parent's layout.
@Composable
fun Avatar(url: String, modifier: Modifier = Modifier) {
    Box {
        Image(
            painter = rememberAsyncImagePainter(url),
            contentDescription = null,
            modifier = modifier  // wrong node
        )
    }
}

// RIGHT — modifier reaches the outermost node; child layout stays internal
@Composable
fun Avatar(url: String, modifier: Modifier = Modifier) {
    Box(modifier = modifier) {
        Image(
            painter = rememberAsyncImagePainter(url),
            contentDescription = null
        )
    }
}
```

**Why:** Layout modifiers measure the node they're attached to. If the caller writes `Avatar(modifier = Modifier.size(120.dp))`, they expect the *Avatar* — the unit the parent positions — to be 120dp. Routing the modifier to a child silently drops sizing/weight/padding constraints from the parent's perspective and produces hard-to-debug layout bugs.

### Rule 3 — Caller's modifier comes FIRST in the chain

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

### Rule 4 — No hardcoded placement on a reusable root

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

**Identity carve-out:** Visual-identity modifiers — the ones without which the composable wouldn't *be* that composable — may stay on the root. `.clip(CircleShape)` on `Avatar` qualifies. Apply them AFTER the caller's modifier in the chain (see Rule 3).

**Why:** Hardcoded placement makes a composable usable only in the one screen it was extracted from. The moment another screen needs it at a different width, inside a `Row`, or without that padding, the only options are forking or wrapping. The `modifier` parameter exists precisely to let parents make these calls.

### Rule 5 — No `var m = Modifier; m = m.x()` reassignment

Modifier chains MUST be built as one fluent `val` expression. Conditional segments stay inline via `.then(if (cond) Modifier.x() else Modifier)`.

```kotlin
// WRONG — imperative reassignment defeats the fluent design and hides the chain shape
@Composable
fun Banner(isError: Boolean, modifier: Modifier = Modifier) {
    var m = modifier
    m = m.fillMaxWidth()
    if (isError) m = m.background(Color.Red)
    m = m.padding(16.dp)
    Box(modifier = m) { ... }
}

// RIGHT — one fluent val; conditional segment inlined with .then
@Composable
fun Banner(isError: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(if (isError) Modifier.background(Color.Red) else Modifier)
            .padding(16.dp)
    ) { ... }
}
```

**Why:** `Modifier` is an immutable, ordered chain — reassignment forces readers to mentally replay each statement to recover the final order, and scatters the chain across lines that look like state mutations. A single `val` makes the order explicit and the diff small. The `.then(...)` idiom is the supported pattern for conditionals.

### Rule 6 — Multiline chain threshold: at least 3 calls

Format the chain inline for 1–2 calls; multiline for 3 or more. (Applies only to parameters literally named `modifier`.)

```kotlin
// 1–2 calls — inline
Box(modifier = modifier.fillMaxWidth().padding(16.dp))

// 3+ calls — multiline, each call on its own line
Box(
    modifier = modifier
        .fillMaxWidth()
        .padding(16.dp)
        .background(Color.Blue)
        .clip(RoundedCornerShape(8.dp))
)
```

**Why:** Modifier order is load-bearing. Once a chain has three or more calls, ordering bugs become invisible in a one-liner, and diffs that add/remove a modifier touch the whole line. Multiline lets each modifier own a line and makes reorderings obvious in review (the AndroidX convention).

### Rule 7 — Hoist a single `if` out of a layout

When a layout composable's *only* content is one `if`, hoist the `if` to wrap the layout instead.

```kotlin
// WRONG — the Box exists only to host an if; the Box itself is dead weight
@Composable
fun Screen(showBanner: Boolean) {
    Box {
        if (showBanner) Banner()
    }
}

// RIGHT — hoist the if; no wasted layout node
@Composable
fun Screen(showBanner: Boolean) {
    if (showBanner) Banner()
}
```

**Keep the wrapping layout when:** (a) it carries real semantics (a modifier, alignment, or arrangement doing work); (b) the `if` has siblings sharing the layout; or (c) it's an `if/else` where both branches need the same wrapper. **Why:** every layout composable creates a real layout node (measure + placement + recomposition scope); `Box { if (cond) Foo() }` allocates that node every recomposition just to sometimes show one child. See `compose/references/performance.md` for the cost model.

## Modifier Chain Ordering

Modifiers apply left-to-right in the DSL but conceptually wrap bottom-to-top — each wraps the content below it. **Order outer (layout/sizing) → inner (styling/interaction).**

```kotlin
Modifier.background(Color.Red).padding(16.dp).size(100.dp)   // red wraps the padded 100dp box
Modifier.size(100.dp).padding(16.dp).background(Color.Red)   // 100dp box is padded, then the 132dp total gets red
```

`.size` after `.padding` excludes the padding from the final outer size; `.clip` before `.background` clips the background to the shape (after, it doesn't). This is the ordering reference `compose/references/design-to-compose.md` and `view-composition.md` point here for.

## Custom modifiers, semantics, testTag — defer

- **Custom modifiers:** prefer the `Modifier.Node` / `ModifierNodeElement` API over the deprecated `composed { }` (which creates a composition scope per use and captures composition locals). The deprecation + migration path lives in `compose/references/deprecated-patterns.md`.
- **Semantics** (`contentDescription`, `role`, `clearAndSetSemantics`, `mergeDescendants`) and **`testTag`** are standard. For the more advanced a11y bits (traversal order via `traversalIndex`/`isTraversalGroup`, live-region mode) see `compose/references/accessibility.md`; for test-selector strategy (semantics-first over `testTag`) see `android-skills:android-testing`.
