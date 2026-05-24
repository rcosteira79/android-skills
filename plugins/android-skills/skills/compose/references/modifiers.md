# Jetpack Compose Modifiers Reference

Modifiers are the primary way to decorate or augment a composable. They apply layout, drawing, gesture, and accessibility behavior. Understanding modifier ordering and the available APIs is critical for correctness and performance.

> **Modifier and slots together form the public-API contract of any reusable composable.** The caller owns *placement* (the `modifier` parameter) and *what to place* (the content slots). This file covers the modifier side; see `compose/references/view-composition.md` for the slot authoring rules.

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

**Why:** Modifier chains resolve left-to-right with later layout/size modifiers losing to earlier ones for *size* constraints, and inversely for *padding/background* visuals — but the practical rule is simpler: whichever `.size(...)` appears first wins for the outer measurement that the parent sees. Putting the hardcoded `.size(48.dp)` first means caller `.size(120.dp)` becomes a no-op for the Avatar's outer dimensions. Caller intent must come first; only modifiers that define what the composable *is* (a circular crop for `Avatar`) belong after.

### Rule 4 — No hardcoded placement on a reusable root

A reusable composable's root MUST NOT carry `.fillMaxWidth()`, `.height(56.dp)`, `.padding(horizontal = 16.dp)`, or any other placement decision. Placement is the parent's job — that's what the `modifier` parameter is for.

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

**Why:** Hardcoded placement makes a composable usable only in the one screen it was extracted from. The moment another screen needs the same component at a different width, inside a `Row`, or without that padding, the only options are forking or wrapping. The `modifier` parameter exists precisely to let parents make these calls; using it correctly is what makes a composable reusable. See `android-skills:compose` for the broader API design context.

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

**Why:** `Modifier` is an immutable, ordered chain — reassignment forces readers to mentally replay each statement to recover the final order, and it scatters the chain across lines that look like state mutations. A single `val` expression makes the order explicit, makes the diff small when you add a modifier, and lets the compiler/IDE inline the chain. The `.then(...)` idiom for conditionals is the supported pattern (see existing "Conditional Modifier Chains Done Wrong" section below).

### Rule 6 — Multiline chain threshold: at least 3 calls

Format the chain inline for 1–2 calls; multiline for 3 or more. This rule applies only to parameters literally named `modifier`.

```kotlin
// 1 call — inline
Box(modifier = modifier.padding(16.dp))

// 2 calls — inline (still readable on one line)
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

**Why:** Modifier order is load-bearing (see "Modifier Chain Ordering" below). Once a chain has three or more calls, ordering bugs become invisible in a one-liner, and diffs that add/remove a modifier touch the entire line. Multiline lets each modifier own a line, makes reorderings obvious in code review, and matches the convention used in the AndroidX codebase. The 1–2 carve-out keeps trivial chains compact.

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

**Carve-outs — keep the wrapping layout when:**

- **(a) The layout carries semantics.** A modifier, alignment, or arrangement is doing real work.
  ```kotlin
  // Keep — Box centers the banner and applies padding
  Box(modifier = Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
      if (showBanner) Banner()
  }
  ```
- **(b) The `if` has siblings.** Other content shares the layout.
  ```kotlin
  // Keep — Column groups header with the conditional banner
  Column {
      Header()
      if (showBanner) Banner()
      Footer()
  }
  ```
- **(c) It's an `if/else` where both branches contribute layout.** Hoisting would duplicate the wrapper.
  ```kotlin
  // Keep — both branches need the same Box semantics
  Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
      if (isLoading) CircularProgressIndicator() else Content()
  }
  ```

**Why:** Every layout composable creates a real layout node — measure pass, placement pass, recomposition scope. A `Box { if (cond) Foo() }` allocates that node every recomposition just to (sometimes) show one child. Hoisting the `if` eliminates the dead node, simplifies recomposition scopes, and reads better. See `compose/references/performance.md` for the broader cost model.

## Modifier Chain Ordering

Order matters. Modifiers are applied left-to-right in the DSL, but conceptually they wrap bottom-to-top. Each modifier receives a lambda that draws/measures the content below it.

```kotlin
// Example: different results depending on order
Box(
    Modifier
        .background(Color.Red)
        .padding(16.dp)
        .size(100.dp)
)
// Red background wraps the padded content, which wraps the 100x100 box

Box(
    Modifier
        .size(100.dp)
        .padding(16.dp)
        .background(Color.Red)
)
// 100x100 box is padded, then the whole thing (132x132) gets red background
```

**Do:** Order modifiers from outer (layout/sizing) to inner (styling/interaction).
**Don't:** Put `size` after `padding` if you want the padding included in the final size.

Source: `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/Modifier.kt`

## Common Modifier Patterns

### Padding and Sizing

```kotlin
// Padding: external spacing around content
Box(Modifier.padding(16.dp)) { }

// Size: exact dimensions (overrides requested size from parent)
Box(Modifier.size(100.dp)) { }
Box(Modifier.size(width = 200.dp, height = 100.dp)) { }

// FillMaxWidth/FillMaxHeight: expand to available space
Box(Modifier.fillMaxWidth(0.8f)) { }  // 80% of parent width
Box(Modifier.fillMaxSize()) { }       // 100% of parent

// Do: use fillMaxWidth before adding padding for alignment clarity
Column(Modifier.fillMaxWidth()) {
    Box(Modifier.padding(16.dp).fillMaxWidth()) { }
}

// Don't: apply fillMaxWidth after background if you want background to expand
// Instead:
Box(Modifier.fillMaxWidth().background(Color.Blue)) { }
```

### Background and Border

```kotlin
// Background applies a color to the surface
Box(Modifier.background(Color.Blue)) { }
Box(Modifier.background(Color.Blue, shape = RoundedCornerShape(8.dp))) { }

// Border draws a stroke (order matters!)
Box(
    Modifier
        .size(100.dp)
        .border(2.dp, Color.Black, RoundedCornerShape(8.dp))
        .background(Color.White)
)
// The border is drawn AFTER background in visual order (because modifiers below it are drawn first)

// Combine background + border: apply border first in chain
Box(
    Modifier
        .border(2.dp, Color.Black, RoundedCornerShape(8.dp))
        .background(Color.White)
)
```

### Clipping

```kotlin
// Clip content to a shape
Box(Modifier.clip(RoundedCornerShape(8.dp))) {
    Image(painter = painterResource(id = R.drawable.my_image), contentDescription = "")
}

// Do: apply clip before background if you want background inside the shape
Box(
    Modifier
        .clip(RoundedCornerShape(8.dp))
        .background(Color.Blue)
) { }

// Don't: apply background then clip (works but semantically wrong)
Box(
    Modifier
        .background(Color.Blue)
        .clip(RoundedCornerShape(8.dp))
) { }
```

## Clickable and Combined Clickable

```kotlin
// Basic click handling with ripple effect (Material 3 default)
Button(onClick = { }) { Text("Click me") }

// Manual clickable with ripple
Box(
    Modifier
        .size(100.dp)
        .clickable(
            indication = ripple(),  // Material ripple feedback
            interactionSource = remember { MutableInteractionSource() }
        ) { /* handle click */ }
)

// Combined clickable: long press + double click + click
Box(
    Modifier
        .combinedClickable(
            onClick = { },
            onLongClick = { },
            onDoubleClick = { },
            indication = ripple()
        )
) { }

// Do: provide explicit interactionSource for testing/state observation
val interactionSource = remember { MutableInteractionSource() }
Box(
    Modifier.clickable(
        interactionSource = interactionSource,
        indication = ripple()
    ) { }
)

// Don't: forget indication parameter (will have no visual feedback)
Box(Modifier.clickable { }) { }  // No ripple
```

## Modifier.composed vs Modifier.Node

The old API (`composed`) is being phased out in favor of the new `ModifierNodeElement` API. Both work, but new code should use the latter.

### Old API: Modifier.composed

```kotlin
fun Modifier.myCustomModifier(value: String) = composed {
    val state = remember { mutableStateOf(value) }
    this.then(
        Modifier
            .background(Color.Blue)
            .clickable { state.value = "updated" }
    )
}
```

- Creates a new composable scope
- Captures composition locals
- Causes recomposition when remember state changes
- Deprecated but still supported

### New API: Modifier.Node

```kotlin
class MyCustomNode(val value: String) : Modifier.Node {
    override fun onDetach() {
        // Cleanup when removed
    }
}

data class MyCustomElement(val value: String) : ModifierNodeElement<MyCustomNode>() {
    override fun create() = MyCustomNode(value)
    override fun update(node: MyCustomNode) {
        node.value = value
    }
}

fun Modifier.myCustomModifier(value: String) = this.then(MyCustomElement(value))
```

**Do:** Use `Modifier.Node` for new custom modifiers. It's more efficient and doesn't create composition scopes.
**Don't:** Create new `composed` modifiers; migrate existing ones to `Modifier.Node`.

Source: `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/modifier/ModifierNodeElement.kt`

## Layout vs Drawing vs Pointer Input Modifiers

Modifiers fall into categories that affect when they execute:

```kotlin
// Layout modifier: affects measurement and layout pass
fun Modifier.customSize(width: Dp, height: Dp) =
    this.then(object : LayoutModifier {
        override fun MeasureScope.measure(measurable: Measurable, constraints: Constraints) =
            measurable.measure(Constraints.fixed(width.roundToPx(), height.roundToPx()))
                .run { layout(width = size.width, height = size.height) { place(0, 0) } }
    })

// Drawing modifier: doesn't affect layout, just draws after content
fun Modifier.customDraw() = drawBehind { drawCircle(Color.Red) }

// Pointer input modifier: handles gestures/events
fun Modifier.detectCustomGesture() = pointerInput(Unit) {
    detectTapGestures { offset -> /* handle */ }
}
```

**Do:** Use layout modifiers for sizing/positioning, drawing modifiers for visual effects, pointer modifiers for input.
**Don't:** Use layout modifiers to create visual effects; use drawing modifiers instead.

## Modifier.graphicsLayer — Performance Implications

`graphicsLayer` applies transformations at the graphics rendering level. It's more efficient than recomposing for animations.

```kotlin
// Efficient: transforms applied on the graphics layer, no recomposition
Box(
    Modifier.graphicsLayer(
        scaleX = 1.2f,
        scaleY = 1.2f,
        translationX = 10f,
        rotationZ = 45f,
        alpha = 0.8f
    )
) { }

// Less efficient: recomposes every frame
var scaleX by remember { mutableStateOf(1f) }
LaunchedEffect(Unit) {
    while (true) {
        scaleX = 1.2f
        delay(16)
    }
}
Box(Modifier.scale(scaleX)) { }
```

**Do:** Use `graphicsLayer` for animations and frequent property changes.
**Don't:** Animate state values that trigger recomposition when `graphicsLayer` would suffice.

Source: `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/graphics/GraphicsLayerModifier.kt`

## Modifier.semantics — Accessibility

Semantics describe the meaning of UI elements for screen readers and accessibility tests.

```kotlin
// Add semantic label
Button(onClick = { }) {
    Icon(Icons.Default.Add, contentDescription = null)
    Text("Add item")
}

// Custom semantic properties
Box(
    Modifier
        .size(100.dp)
        .semantics {
            contentDescription = "Custom box"
            onClick(label = "Activate") { true }
        }
) { }

// Do: always provide contentDescription for images
Image(
    painter = painterResource(id = R.drawable.icon),
    contentDescription = "User avatar"
)

// Don't: forget contentDescription (screen readers won't announce it)
Image(painter = painterResource(id = R.drawable.icon), contentDescription = null) // Wrong
```

Source: `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/semantics/Semantics.kt`

## Modifier.testTag — UI Testing

```kotlin
// Add a test tag for finding composables in tests
Box(Modifier.testTag("my_box")) { }

// In tests:
composeTestRule.onNodeWithTag("my_box").performClick()
composeTestRule.onNodeWithTag("my_box").assertIsDisplayed()
```

**Do:** Use unique, descriptive test tags.
**Don't:** Use test tags in production code for business logic.

## Anti-patterns

### Creating Modifiers in Composition

```kotlin
// Don't: hardcoded chain on a reusable root — no modifier parameter, no way for the caller
// to place this composable, plus a fresh Modifier built every recomposition
@Composable
fun BadModifier() {
    Box(Modifier.padding(16.dp).background(Color.Blue)) { }
}

// Do: accept a modifier, apply caller's first, then component-internal styling.
@Composable
fun GoodModifier(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.background(Color.Blue)
    ) { }
}
```

### Conditional Modifier Chains Done Wrong

```kotlin
// Don't: breaks type checking and readability
val mod = if (isSelected) Modifier.background(Color.Blue) else Modifier
Box(mod.padding(16.dp)) { }

// Do: use then() for conditional chaining
Box(
    Modifier
        .padding(16.dp)
        .then(if (isSelected) Modifier.background(Color.Blue) else Modifier)
) { }
```

---

**Summary:** Master modifier ordering, prefer `Modifier.Node` over `composed`, use `graphicsLayer` for animations, and always consider the semantic layer for accessibility.
