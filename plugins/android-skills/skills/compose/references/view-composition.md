# Jetpack Compose View Composition Reference

**The slot pattern and the `modifier` parameter form one paired API contract:** the caller owns *what to place* (slots) and *placement* (modifier). This file covers the slot side; see `compose/references/modifiers.md` for the modifier authoring rules.

## Composable Function Naming Conventions

Names communicate intent. Follow these patterns consistently.

### Nouns (UI Components)
- PascalCase, describe *what* the composable displays
- Used for UI widgets, screens, layout building blocks

```kotlin
@Composable
fun Button(...)  // Displays a button

@Composable
fun UserCard(user: User)  // Displays a user card

@Composable
fun LoginScreen()  // Displays a login screen

@Composable
fun CheckboxWithLabel(...)  // Displays a checkbox with label
```

### Verbs (Side Effects / Effects)
- PascalCase, describe *what action* happens
- Used for composables that don't emit UI, only perform side effects

```kotlin
@Composable
fun LaunchedEffect(...)  // Launches a coroutine

@Composable
fun DisposableEffect(...)  // Manages resource lifecycle

@Composable
fun SideEffect(...)  // Performs a side effect
```

### Anti-Pattern: Ambiguous Names
```kotlin
// ❌ Unclear if this is a UI component or effect
@Composable
fun HandleLogin(...)

// ✅ Explicit
@Composable
fun LoginScreen(...)  // Displays UI

@Composable
fun PerformLogin(...)  // Side effect function (if truly a side effect)
```

## The Slot Pattern

Accept `@Composable` lambda parameters to create flexible, reusable containers.

### Basic Slot Pattern
```kotlin
@Composable
fun Card(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .background(Color.White)
            .padding(16.dp)
    ) {
        content()
    }
}

// Usage
Card {
    Text("Hello")
    Image(...)
}
```

### Multiple Slots
```kotlin
@Composable
fun ListItem(
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
    title: @Composable () -> Unit,
    subtitle: @Composable (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null
) {
    Row(modifier = modifier.padding(16.dp)) {
        icon()
        Column(modifier = Modifier.weight(1f)) {
            title()
            subtitle?.invoke()
        }
        trailing?.invoke()
    }
}

// Usage
ListItem(
    icon = { Icon(Icons.Default.Person, "") },
    title = { Text("Alice") },
    subtitle = { Text("Online") },
    trailing = { Badge() }
)
```

**Key principle:** Slots accept `@Composable` lambdas, not pre-composed values. This ensures composition is deferred and scope-aware.

```kotlin
// ❌ Wrong: passes composed value
fun CustomLayout(content: String) { ... }

// ✅ Correct: passes composition lambda
fun CustomLayout(content: @Composable () -> Unit) { ... }
```

Source: Material 3 composables in `androidx.compose.material3` use slots extensively.

### Slot Authoring Rules

#### 1. Receiver-scoped slots when the parent's scope is useful

When the slot is rendered inside a standard layout (`Row`, `Column`, `Box`, `LazyListScope`) that exposes useful caller-facing APIs, scope the slot to that receiver. A slot rendered inside a `Row` should be `@Composable RowScope.() -> Unit`; inside a `Box` should be `BoxScope.() -> Unit`.

**WHY:** This is what makes caller-side `RowScope.weight()`, `ColumnScope.weight()`, `BoxScope.matchParentSize()`, and `BoxScope.align()` actually work. Without the receiver, the caller can't reach the layout-specific modifiers the slot's parent layout provides.

**Don't reflexively scope every slot** — only when the parent's scope offers something the caller meaningfully needs. A slot rendered inside a custom `Layout {}` with no public scope shouldn't be scoped just for symmetry.

```kotlin
// ✅ RIGHT — actions land in a Row; scope lets callers .weight() and .align()
@Composable
fun TopAppBar(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {},  // scoped: caller gets .weight() / .align()
) {
    Row(modifier = modifier) {
        title()
        Spacer(Modifier.weight(1f))
        actions()
    }
}

// Caller can do this:
TopAppBar(
    title = { Text("Inbox") },
    actions = {
        IconButton(onClick = {}) { Icon(Icons.Default.Search, null) }
        IconButton(onClick = {}) { Icon(Icons.Default.MoreVert, null) }
    }
)
```

```kotlin
// ❌ WRONG — slot exposes a custom Layout's scope that the caller has no use for
@Composable
fun MyCustomLayout(
    content: @Composable MyInternalScope.() -> Unit,  // internal scope leaks abstraction
) { ... }

// ✅ RIGHT — keep slot scopeless when the parent's scope has nothing public to offer
@Composable
fun MyCustomLayout(content: @Composable () -> Unit) { ... }
```

#### 2. Optional slots: nullable, not empty-lambda

**DO** use `slot: (@Composable () -> Unit)? = null` for optional slots and branch on `null` to omit spacing/padding/dividers for the absent case.

**DON'T** use `slot: @Composable () -> Unit = {}` for "optional" slots.

**WHY:** An empty lambda is still *invoked* — it just emits nothing. But the parent layout has no way to know it emitted nothing, so any surrounding `Spacer`, padding, divider, or container allocated for that slot stays in the layout, producing ghost space. With `null`, the component branches and *omits* the surrounding layout machinery entirely.

The existing `ListItem` example earlier in this section already follows this pattern — that's the right shape:

```kotlin
@Composable
fun ListItem(
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit,
    title: @Composable () -> Unit,
    subtitle: @Composable (() -> Unit)? = null,    // ✅ nullable
    trailing: @Composable (() -> Unit)? = null     // ✅ nullable
) {
    Row(modifier = modifier.padding(16.dp)) {
        icon()
        Column(modifier = Modifier.weight(1f)) {
            title()
            subtitle?.invoke()                      // ✅ branches: subtitle column has no extra row
        }
        trailing?.invoke()                          // ✅ no trailing spacing if absent
    }
}
```

```kotlin
// ❌ WRONG — empty default leaves ghost space
@Composable
fun ListItem(
    title: @Composable () -> Unit,
    trailing: @Composable () -> Unit = {},          // ❌ empty lambda
) {
    Row {
        title()
        Spacer(Modifier.width(8.dp))                // ❌ unconditional — an empty-lambda default gives no signal to omit it
        trailing()                                  // emits nothing, but the Spacer above already added 8.dp
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

#### 3. `XxxDefaults` object for composable defaults

When a slot has a sensible default that is itself a composable, expose it via a public `XxxDefaults` companion object — not as an inline default expression on the parameter.

**WHY:** Composable default expressions (`trailingContent: @Composable () -> Unit = { Icon(...) }`) hide the default in the signature, can't be reused by callers who want "the default plus one more thing," and tangle the default's implementation with the API surface. A `XxxDefaults` object mirrors Material 3's convention (`ButtonDefaults`, `CardDefaults`, `TopAppBarDefaults`), is discoverable by IDE autocomplete, and lets callers compose with the default explicitly.

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
    fun Chevron() = Icon(
        Icons.AutoMirrored.Default.KeyboardArrowRight,
        contentDescription = null,
    )
}

// Callers can opt out, opt in, or override:
SettingsRow(title = "Notifications")                                  // default chevron
SettingsRow(title = "Logout", trailingContent = {})                   // suppress
SettingsRow(title = "Theme", trailingContent = { Switch(...) })       // custom
```

```kotlin
// ❌ WRONG — default tangled in signature, not reusable
@Composable
fun SettingsRow(
    title: String,
    trailingContent: @Composable () -> Unit = {
        Icon(Icons.AutoMirrored.Default.KeyboardArrowRight, null)
    },
) { ... }
```

#### 4. Naming convention

| Slot shape | Naming | Examples |
|------------|--------|----------|
| Free-form, multi-element | `xxxContent` or bare `content` | Material 3's `content`, `bottomBar`, `floatingActionButton`, `topBar` |
| Semantically constrained, singular role | Singular noun | `title`, `actions`, `icon`, `label`, `trailing` |

**WHY:** Material 3 already established this vocabulary — `Scaffold(content = ...)`, `TopAppBar(title = ...)`, `ListItem(trailingContent = ...)`. Matching it makes your APIs feel native to Compose; deviating creates friction.

**DON'T mix bare `content` with other `xxxContent` slots in one component.** Either every free-form slot is `xxxContent` or your single main slot is bare `content` — not both.

```kotlin
// ❌ WRONG — inconsistent vocabulary inside one signature
@Composable
fun MyCard(
    content: @Composable () -> Unit,
    headerContent: @Composable () -> Unit,
    footerContent: @Composable () -> Unit,
) { ... }

// ✅ RIGHT — pick one
@Composable
fun MyCard(
    headerContent: @Composable () -> Unit,
    mainContent: @Composable () -> Unit,
    footerContent: @Composable () -> Unit,
) { ... }

// ✅ RIGHT — bare `content` for the dominant slot, singular nouns for the constrained ones
@Composable
fun MyCard(
    title: @Composable () -> Unit,
    actions: @Composable RowScope.() -> Unit,
    content: @Composable () -> Unit,
) { ... }
```

#### 5. Boolean-flag / sealed-variant smells

When you reach for `showChevron: Boolean`, `mode: TrailingMode`, or "I'll model trailing variants with a sealed `Trailing` type" — **that's a slot trying to be born.** Replace it with `xxxContent: @Composable () -> Unit`.

**WHY:** Boolean flags and sealed variants enumerate the cases *you* thought of. A slot lets the caller decide. Every new variant request becomes a caller-side composable, not an API change.

```kotlin
// ❌ WRONG — boolean flag enumerates one of N future cases
@Composable
fun SettingsRow(
    title: String,
    showChevron: Boolean = true,        // smell: what about a switch? a badge? a count?
) { ... }

// ❌ WRONG — sealed variant is just a worse slot
sealed interface Trailing {
    data object Chevron : Trailing
    data object None : Trailing
    data class Switch(val checked: Boolean, val onChange: (Boolean) -> Unit) : Trailing
    data class Badge(val count: Int) : Trailing
}

@Composable
fun SettingsRow(
    title: String,
    trailing: Trailing = Trailing.Chevron,
) { ... }  // every new variant requires touching the API

// ✅ RIGHT — slot
@Composable
fun SettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    trailingContent: @Composable () -> Unit = SettingsRowDefaults.Chevron(),
) { ... }

// Callers compose any variant freely — no API change needed
SettingsRow("Wi-Fi", trailingContent = { Switch(checked = on, onCheckedChange = {}) })
SettingsRow("Inbox", trailingContent = { Badge { Text("99+") } })
SettingsRow("Logout", trailingContent = {})
```

#### 6. Partial-slot trap

If you slot the trailing area but keep `leadingIcon: ImageVector` because "leading is always an icon," you've left the API half-rigid for no real reason. **Slot all the variable areas, or none.**

**WHY:** "Leading is always an icon" is a load-bearing assumption that will fail the first time someone needs a `CircularProgressIndicator`, an `Image`, an avatar, or an icon-with-badge in the leading position. A `@Composable () -> Unit` slot costs nothing extra at the call site (the common case is still `{ Icon(...) }`) and absorbs every future variant for free.

```kotlin
// ❌ WRONG — partial-slot: trailing is flexible, leading is hardcoded to icon
@Composable
fun ListItem(
    title: String,
    leadingIcon: ImageVector,                       // ❌ rigid: only icons allowed
    trailingContent: @Composable () -> Unit = {},
) {
    Row {
        Icon(leadingIcon, contentDescription = null)
        Text(title, Modifier.weight(1f))
        trailingContent()
    }
}

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

// Callers still get the common case cheaply:
ListItem(
    title = "Profile",
    leadingContent = { Icon(Icons.Default.Person, null) },
)
// And complex cases work without API changes:
ListItem(
    title = "Syncing",
    leadingContent = { CircularProgressIndicator(Modifier.size(20.dp)) },
)
```

## Extracting Composables

Know when to extract and when to keep composables together.

### Extract When
- **Reused in multiple places:** DRY principle
- **Single responsibility:** Composable handles one concern
- **Easier to test:** Small, focused unit
- **Performance:** Enables skipping and independent recomposition

```kotlin
// ❌ Before: god composable
@Composable
fun UserProfile(user: User) {
    Column {
        // Header
        Box(modifier = Modifier.fillMaxWidth()) {
            Image(user.photo)
            Text(user.name, style = MaterialTheme.typography.headlineSmall)
            IconButton({ /* edit */ }) { Icon(Icons.Default.Edit, "") }
        }

        // Stats
        Row(modifier = Modifier.fillMaxWidth()) {
            StatItem(user.followers, "Followers")
            StatItem(user.following, "Following")
            StatItem(user.posts, "Posts")
        }

        // Bio
        Text(user.bio, style = MaterialTheme.typography.bodyMedium)
    }
}

// ✅ After: extracted composables
@Composable
fun UserProfile(user: User) {
    Column {
        UserProfileHeader(user)
        UserStats(user)
        UserBio(user.bio)
    }
}

@Composable
private fun UserProfileHeader(user: User) { ... }

@Composable
private fun UserStats(user: User) { ... }

@Composable
private fun UserBio(bio: String) { ... }
```

### Don't Extract When
- **Single use:** Extraction adds indirection without benefit
- **Tightly coupled logic:** Would require passing many parameters
- **Too small:** Single `Text()` or `Icon()` doesn't need extraction

```kotlin
// ❌ Over-extraction: trivial wrapper
@Composable
private fun UserName(name: String) {
    Text(name, style = MaterialTheme.typography.headlineSmall)
}

// ✅ Keep inline if only used once
@Composable
fun UserProfile(user: User) {
    Text(user.name, style = MaterialTheme.typography.headlineSmall)
}
```

## Stateful vs Stateless Composables

Structure composables as a stateless layer with optional stateful wrapper.

### Pattern: Stateless + Wrapper

```kotlin
// ✅ Stateless composable (reusable, testable)
@Composable
fun ToggleButton(
    isEnabled: Boolean,
    onToggle: (Boolean) -> Unit,
    text: String
) {
    Button(
        onClick = { onToggle(!isEnabled) },
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isEnabled) Color.Blue else Color.Gray
        )
    ) {
        Text(text)
    }
}

// ✅ Stateful wrapper (manages state, uses stateless child)
@Composable
fun StatefulToggleButton(text: String = "Toggle") {
    var isEnabled by remember { mutableStateOf(false) }
    ToggleButton(
        isEnabled = isEnabled,
        onToggle = { isEnabled = it },
        text = text
    )
}

// Usage: choose based on need
@Composable
fun MyScreen() {
    // Use stateless when caller manages state
    var featureEnabled by remember { mutableStateOf(false) }
    ToggleButton(featureEnabled, { featureEnabled = it }, "Feature")

    // Use stateful wrapper for isolated state
    StatefulToggleButton("Local Toggle")
}
```

**Advantage:** Caller can test and reuse `ToggleButton` without mocking state. `StatefulToggleButton` provides convenience for simple cases.

## Preview Annotations

Use previews for rapid UI development and regression testing.

### @Preview
Basic preview of a single composable.

```kotlin
@Preview
@Composable
fun UserCardPreview() {
    UserCard(user = User(1, "Alice"))
}

// Multiple previews
@Preview(name = "Light")
@Preview(name = "Dark", uiMode = UI_MODE_NIGHT_YES)
@Composable
fun UserCardPreviews() {
    UserCard(user = User(1, "Alice"))
}
```

### @PreviewLightDark
Automatically generates light and dark theme previews.

```kotlin
@PreviewLightDark
@Composable
fun UserCardPreview() {
    MyTheme {
        UserCard(user = User(1, "Alice"))
    }
}
```

### @PreviewFontScale
Shows how composable responds to different font sizes.

```kotlin
@Preview(fontScale = 0.8f, name = "Small Fonts")
@Preview(fontScale = 1f, name = "Normal Fonts")
@Preview(fontScale = 1.2f, name = "Large Fonts")
@Composable
fun TextPreview() {
    Text("This is text")
}
```

### @PreviewScreenSizes
Tests multiple screen dimensions.

```kotlin
@Preview(device = Devices.PHONE, name = "Phone")
@Preview(device = Devices.TABLET, name = "Tablet")
@Preview(device = Devices.FOLDABLE, name = "Foldable")
@Composable
fun ResponsiveLayoutPreview() {
    ResponsiveLayout()
}
```

Source: `androidx.compose.ui.tooling.preview`

### Composite Preview Annotations

Define once, use everywhere:

```kotlin
@Preview(name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(name = "Dark", uiMode = Configuration.UI_MODE_NIGHT_YES)
@Preview(name = "Large Font", fontScale = 1.5f)
@Preview(name = "Small Device", device = "spec:width=320dp,height=640dp,dpi=320")
@Preview(name = "Tablet", device = Devices.TABLET)
@Preview(name = "Foldable", device = Devices.FOLDABLE)
@Preview(name = "RTL", locale = "ar")
annotation class ComponentPreviews
```

Apply to every extracted composable:
```kotlin
@ComponentPreviews
@Composable
private fun ConversationRowPreview() {
    AppTheme {
        ConversationRow(
            conversation = previewConversation(),
            onClick = {}
        )
    }
}
```

For data-driven previews, use `PreviewParameterProvider`:
```kotlin
class ConversationPreviewProvider : PreviewParameterProvider<Conversation> {
    override val values = sequenceOf(
        Conversation(id = "1", title = "Short title", unreadCount = 0),
        Conversation(id = "2", title = "Very long conversation title that might wrap", unreadCount = 99),
        Conversation(id = "3", title = "", unreadCount = 0), // Empty title edge case
    )
}

@ComponentPreviews
@Composable
private fun ConversationRowPreview(
    @PreviewParameter(ConversationPreviewProvider::class) conversation: Conversation
) {
    AppTheme { ConversationRow(conversation = conversation, onClick = {}) }
}
```

**CMP note:** In `commonMain`, use `@Preview` from `org.jetbrains.compose.ui.tooling.preview`. Device-specific previews (`Devices.TABLET`) are Android-only.

## Composable Return Values

**Never return values from composables.** Use callbacks instead.

```kotlin
// ❌ Wrong: composables don't return values
@Composable
fun UserInput(): String {
    var text by remember { mutableStateOf("") }
    return text  // Can't do this
}

// ✅ Correct: callback pattern
@Composable
fun UserInput(onUserInput: (String) -> Unit) {
    var text by remember { mutableStateOf("") }
    TextField(
        value = text,
        onValueChange = {
            text = it
            onUserInput(it)  // Notify parent
        }
    )
}

// Usage
@Composable
fun FormScreen() {
    UserInput(onUserInput = { input -> /* handle */ })
}
```

**Rationale:** Composables are executed during composition, which happens at unpredictable times and may be skipped or reordered.

## Reusability Guidelines

Design composables to be configurable without over-parameterization.

### Configuration via Parameters
```kotlin
// ✅ Expose what varies, hide what doesn't
@Composable
fun Card(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    // Internal: fixed styling, padding, etc.
    Box(
        modifier = modifier
            .background(Color.White)
            .padding(16.dp)
            .clip(RoundedCornerShape(8.dp))
    ) {
        content()
    }
}
```

### Avoid Parameter Explosion
```kotlin
// ❌ Too many parameters, hard to use
@Composable
fun Button(
    text: String,
    textColor: Color,
    backgroundColor: Color,
    cornerRadius: Dp,
    padding: PaddingValues,
    elevation: Dp,
    ...
)

// ✅ Sensible defaults, style objects
@Composable
fun Button(
    text: String,
    modifier: Modifier = Modifier,
    style: ButtonStyle = ButtonStyle.Primary,
    onClick: () -> Unit
) { ... }

// Or: use Material composables with built-in styles
@Composable
fun Button(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    ...
) { ... }  // Material3 Button has reasonable defaults
```

## Common Anti-Patterns

### God Composables
```kotlin
// ❌ Does too much
@Composable
fun Dashboard() {
    // Header
    Box { /* 20 lines */ }

    // List
    LazyColumn {
        items(items) { /* 15 lines */ }
    }

    // Footer
    Box { /* 15 lines */ }

    // Dialogs, side effects, state management...
}

// ✅ Extract and delegate
@Composable
fun Dashboard() {
    Column {
        DashboardHeader()
        DashboardContent()
        DashboardFooter()
    }
}
```

### Deep Nesting
```kotlin
// ❌ Hard to read and debug
@Composable
fun LoginScreen() {
    Box { Column { Row { Card { Box { Text { ... } } } } } }
}

// ✅ Intermediate variables and extraction
@Composable
fun LoginScreen() {
    val form = loginFormState()
    Column {
        LoginForm(form)
        LoginButton(form)
    }
}
```

### Passing ViewModel to Children
```kotlin
// ❌ Violates composition boundaries
@Composable
fun ParentScreen(viewModel: ParentViewModel) {
    ChildCard(viewModel = viewModel)  // Don't do this
}

// ✅ Extract data, pass to child
@Composable
fun ParentScreen(viewModel: ParentViewModel) {
    val data by viewModel.data.collectAsStateWithLifecycle()
    ChildCard(data = data)
}
```

---

**Source references:** `androidx.compose.material3`, `androidx.compose.ui.tooling.preview`, `androidx.compose.runtime.CompositionLocal`

