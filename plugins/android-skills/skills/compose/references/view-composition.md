# Compose View Composition — slot-authoring rules

**The slot pattern and the `modifier` parameter form one paired API contract:** the caller owns *what to place* (slots) and *placement* (modifier). This file covers the slot side; see `compose/references/modifiers.md` for the modifier authoring rules.

This reference covers how to author a slot API correctly — the six rules below.

## Slot authoring rules

### 1. Carry the parent's receiver scope on the slot — don't silently drop it

When a slot renders inside a standard layout (`Row`, `Column`, `Box`, `LazyListScope`) whose scope exposes useful caller-facing APIs, the slot type **must** carry that receiver: a slot rendered inside a `Row` is `@Composable RowScope.() -> Unit`, inside a `Box` is `@Composable BoxScope.() -> Unit`. Writing it as a bare `@Composable () -> Unit` instead is a **silent API regression** — it strips `RowScope.weight()`, `ColumnScope.weight()`, `BoxScope.matchParentSize()`, and `BoxScope.align()` from every caller, and nothing flags it because the code still compiles.

**Don't reflexively scope every slot** — only when the parent's scope offers something the caller meaningfully needs. A slot rendered inside a custom `Layout {}` with no public scope shouldn't be scoped just for symmetry (leaking an internal scope is its own smell).

```kotlin
// ✅ RIGHT — actions land in a Row; the receiver lets callers .weight() and .align()
@Composable
fun TopAppBar(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},   // scoped: caller gets .weight() / .align()
) {
    Row(modifier = modifier) {
        title()
        Spacer(Modifier.weight(1f))
        actions()
    }
}

// ❌ WRONG — bare lambda silently strips RowScope from every caller
fun TopAppBar(/* … */ actions: @Composable () -> Unit = {})

// ❌ ALSO WRONG — scoping a custom Layout's internal scope the caller has no use for
fun MyCustomLayout(content: @Composable MyInternalScope.() -> Unit)
```

### 2. Optional slots: nullable, not empty-lambda

**DO** use `slot: (@Composable () -> Unit)? = null` for optional slots and branch on `null` to omit the surrounding spacing/padding/divider. **DON'T** use `slot: @Composable () -> Unit = {}`.

**WHY:** an empty lambda is still *invoked* — it emits nothing, but the parent layout can't tell, so any `Spacer`, padding, divider, or container allocated for that slot stays in the layout, producing ghost space. With `null`, the component branches and omits the surrounding layout machinery entirely.

```kotlin
// ❌ WRONG — empty default leaves ghost space
@Composable
fun ListItem(
    title: @Composable () -> Unit,
    trailing: @Composable () -> Unit = {},          // ❌ empty lambda
) {
    Row {
        title()
        Spacer(Modifier.width(8.dp))                // ❌ unconditional — nothing signals it to be omitted
        trailing()                                  // emits nothing, but the Spacer already added 8.dp
    }
}

// ✅ RIGHT — nullable lets the component omit the spacer
@Composable
fun ListItem(
    title: @Composable () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row {
        title()
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            trailing()
        }
    }
}
```

### 3. `XxxDefaults` object for composable defaults

When a slot has a sensible default that is itself a composable, expose it via a public `XxxDefaults` object — not as an inline default expression on the parameter.

**WHY:** composable default expressions (`trailingContent: @Composable () -> Unit = { Icon(...) }`) hide the default in the signature, can't be reused by callers who want "the default plus one more thing," and tangle the default's implementation with the API surface. A `XxxDefaults` object mirrors Material 3 (`ButtonDefaults`, `CardDefaults`, `TopAppBarDefaults`), is discoverable via autocomplete, and lets callers compose with the default explicitly.

```kotlin
// ✅ RIGHT
@Composable
fun SettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    trailingContent: @Composable () -> Unit = SettingsRowDefaults.Chevron(),
) {
    Row(modifier = modifier) {
        Text(title, modifier = Modifier.weight(1f))
        trailingContent()
    }
}

object SettingsRowDefaults {
    @Composable
    fun Chevron() = Icon(Icons.AutoMirrored.Default.KeyboardArrowRight, contentDescription = null)
}

SettingsRow(title = "Notifications")                            // default chevron
SettingsRow(title = "Logout", trailingContent = {})            // suppress
SettingsRow(title = "Theme", trailingContent = { Switch(...) }) // custom
```

### 4. Naming convention

| Slot shape | Naming | Examples |
|------------|--------|----------|
| Free-form, multi-element | `xxxContent` or bare `content` | M3's `content`, `bottomBar`, `floatingActionButton`, `topBar` |
| Semantically constrained, singular role | Singular noun | `title`, `actions`, `icon`, `label`, `trailing` |

**WHY:** Material 3 already established this vocabulary (`Scaffold(content = …)`, `TopAppBar(title = …)`, `ListItem(trailingContent = …)`). Matching it makes your APIs feel native; deviating creates friction. **Don't mix bare `content` with other `xxxContent` slots in one component** — either every free-form slot is `xxxContent`, or your single main slot is bare `content`, not both.

### 5. Boolean-flag / sealed-variant smells

When you reach for `showChevron: Boolean`, `mode: TrailingMode`, or "I'll model trailing variants with a sealed `Trailing` type" — **that's a slot trying to be born.** Replace it with `xxxContent: @Composable () -> Unit`.

**WHY:** boolean flags and sealed variants enumerate the cases *you* thought of; a slot lets the caller decide. Every new variant becomes a caller-side composable, not an API change.

```kotlin
// ❌ WRONG — boolean enumerates one of N future cases (what about a switch? a badge? a count?)
fun SettingsRow(title: String, showChevron: Boolean = true)

// ❌ WRONG — sealed variant is just a worse slot; every new case touches the API
sealed interface Trailing { /* Chevron, None, Switch(...), Badge(count) … */ }
fun SettingsRow(title: String, trailing: Trailing = Trailing.Chevron)

// ✅ RIGHT — slot; callers compose any variant freely, no API change
@Composable
fun SettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    trailingContent: @Composable () -> Unit = SettingsRowDefaults.Chevron(),
) { /* … */ }

SettingsRow("Wi-Fi", trailingContent = { Switch(checked = on, onCheckedChange = {}) })
SettingsRow("Inbox", trailingContent = { Badge { Text("99+") } })
```

### 6. Partial-slot trap

If you slot the trailing area but keep `leadingIcon: ImageVector` because "leading is always an icon," you've left the API half-rigid for no real reason. **Slot all the variable areas, or none.**

**WHY:** "leading is always an icon" is a load-bearing assumption that fails the first time someone needs a `CircularProgressIndicator`, an `Image`, an avatar, or an icon-with-badge there. A `@Composable () -> Unit` slot costs nothing extra at the common call site (still `{ Icon(...) }`) and absorbs every future variant for free.

```kotlin
// ❌ WRONG — partial-slot: trailing is flexible, leading is hardcoded to an icon
@Composable
fun ListItem(title: String, leadingIcon: ImageVector, trailingContent: @Composable () -> Unit = {}) { /* … */ }

// ✅ RIGHT — both flexible areas are slots
@Composable
fun ListItem(
    title: String,
    modifier: Modifier = Modifier,
    leadingContent: (@Composable () -> Unit)? = null,
    trailingContent: (@Composable () -> Unit)? = null,
) {
    Row(modifier = modifier) {
        leadingContent?.invoke()
        Text(title, Modifier.weight(1f))
        trailingContent?.invoke()
    }
}

ListItem(title = "Profile", leadingContent = { Icon(Icons.Default.Person, null) })            // common case, cheap
ListItem(title = "Syncing", leadingContent = { CircularProgressIndicator(Modifier.size(20.dp)) }) // complex, no API change
```
