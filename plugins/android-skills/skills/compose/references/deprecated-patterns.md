# Deprecated Patterns & API Migrations in Jetpack Compose

A canonical list of old → current Compose APIs, for catching retired Accompanist APIs and superseded overloads.

## Accompanist retirement (everything folded into AndroidX — remove the deps)

| Old (Accompanist / pre-built) | Current | Since |
|---|---|---|
| `rememberSystemUiController().setSystemBarsColor(...)` | `enableEdgeToEdge()` in `Activity.onCreate` before `setContent` | Compose 1.7 |
| `accompanist-pager` `HorizontalPager(count = n, …)` | Foundation `HorizontalPager(state = rememberPagerState(pageCount = { n }))` | foundation 1.6 |
| `accompanist-swiperefresh` `SwipeRefresh(...)` | M3 `PullToRefreshBox(isRefreshing, onRefresh) { … }` | material3 1.2 |
| `accompanist-flowlayout` `FlowRow(mainAxisSize = SizeMode.Expand)` | Foundation `FlowRow` / `FlowColumn` (standard modifiers, no `SizeMode`) | foundation 1.6 |

## Other current-vs-deprecated APIs

- **`Modifier.animateItemPlacement()` → `Modifier.animateItem()`** (Compose 1.7) — for LazyList add/remove/move animation. The old one still works but is superseded.

- **`Modifier.composed { }` → `Modifier.Node` / `ModifierNodeElement`** — `composed {}` creates a composition scope and captures composition locals on every use; the Node API is allocation-light. Prefer Node for new custom modifiers (Compose 1.8); benchmark before migrating existing ones.
  ```kotlin
  class MyElement(val value: Int) : ModifierNodeElement<MyNode>() {
      override fun create() = MyNode(value)
      override fun update(node: MyNode) { node.value = value }
  }
  private class MyNode(var value: Int) : Modifier.Node
  fun Modifier.myModifier(value: Int) = this then MyElement(value)
  ```

- **`@ExperimentalMaterial3Api` graduated** (Material3 1.3): `DatePicker`, `TimePicker`, `ExposedDropdownMenuBox`, and `SearchBar` are stable — drop the `@OptIn`.

- **`LinearProgressIndicator(progress = 0.5f)` → `progress = { 0.5f }`** — the raw-`Float` M3 overload is deprecated; the lambda defers the read so an `Animatable` / `State<Float>` can drive it without recomposing the parent every frame. Same for `CircularProgressIndicator`.

- **`DropdownMenuItem("text", onClick)` → slot form** — the positional-`String` overload is deprecated; the current API uses composable slots, matching the rest of M3:
  ```kotlin
  DropdownMenuItem(text = { Text("Profile") }, onClick = { … }, leadingIcon = { Icon(Icons.Default.Person, null) })
  ```

- **API 35+ edge-to-edge is the default** — on Android 15+, content draws behind the system bars by default; `enableEdgeToEdge()` manages bar colors and `WindowInsets.safeDrawing` handles notch-aware layouts. Manual `Modifier.systemBarsPadding()` is superseded.

## Also superseded — but covered in detail in their own references

- **String routes → type-safe `@Serializable` routes** (`composable<Route> { it.toRoute<Route>() }`, navigation-compose 2.8+) — see `compose/references/navigation.md`.
- **`collectAsState()` → `collectAsStateWithLifecycle()`** *on Android* (lifecycle-aware; stops collecting in the background). Android-only — `collectAsState()` remains correct in CMP `commonMain` (see `multiplatform.md`).
- **`mutableStateOf(0)` → `mutableIntStateOf(0)`** (and `mutableFloatStateOf` / `mutableLongStateOf`) — avoids boxing; see `state-management.md`.
- **`Scaffold { }` → `Scaffold { innerPadding -> … }`** — applying `innerPadding` has been compiler-enforced since 1.6 (the old form won't compile).
- **Material 2 → Material 3** — mostly API-compatible; `MaterialTheme.colors` → `.colorScheme`, the new shape system, updated ripple defaults. Align versions via the Compose BOM.
