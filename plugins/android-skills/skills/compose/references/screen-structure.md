# Screen Structure in Jetpack Compose

Screen-level composables, screen structure patterns, and adaptive layouts — the architectural concerns that sit *above* individual view composition. For composable naming, slots, extraction, statefulness, and reusability, see [view-composition.md](view-composition.md). For Material 3 UX patterns (touch targets, foldable postures, M3 compliance), see `android-skills:android-ux`.

## Screen-Level Composables

Structure screens as a thin ViewModel integration layer above pure composables.

### Recommended Pattern
```kotlin
// ✅ Screen composable: connects ViewModel
@Composable
fun UserDetailsScreen(
    viewModel: UserDetailsViewModel = hiltViewModel(),
    userId: String
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(userId) {
        viewModel.loadUser(userId)
    }

    UserDetailsContent(
        uiState = uiState,
        onRetry = { viewModel.loadUser(userId) }
    )
}

// ✅ Content composable: pure (testable, reusable)
@Composable
private fun UserDetailsContent(
    uiState: UiState,
    onRetry: () -> Unit
) {
    when (uiState) {
        is UiState.Loading -> LoadingUI()
        is UiState.Success -> SuccessUI(uiState.user)
        is UiState.Error -> ErrorUI(uiState.message, onRetry)
    }
}

// ✅ Composable for preview/testing
@Preview
@Composable
private fun UserDetailsContentPreview() {
    UserDetailsContent(
        uiState = UiState.Success(User(1, "Alice")),
        onRetry = {}
    )
}
```

**Benefits:**
- Public screen composable integrates ViewModel
- Private content composable is pure, testable, previewable
- Clear separation: UI logic (public) vs rendering (private)

### Framework state stays in the UI composable

**Framework state is *allowed* in the UI composable** — not over-hoisted to the ViewModel. `LazyListState`, `LazyGridState`, `ScrollState`, `PagerState`, `FocusRequester`, `BringIntoViewRequester`, `Animatable`, `TextFieldState`, and snackbar/drawer state holders are **framework state** (the Compose layer's mechanics), not business state.

**WHY:** Hoisting framework state to a ViewModel couples UI mechanics to the state holder and breaks Compose lifecycle assumptions. Animation suspend functions (`Animatable.animateTo`, `LazyListState.animateScrollToItem`, `BringIntoViewRequester.bringIntoView`) called from `viewModelScope` produce broken behaviour because the animation clock is tied to the composition, not the ViewModel — see `compose/references/state-management.md` for the full failure mode.

**Only business state** — loaded data, screen mode, user inputs that drive queries, anything that must survive configuration change with semantic meaning — belongs in the state holder.

```kotlin
// ✅ RIGHT — framework state in the UI composable, business state in the ViewModel
@Composable
fun ConversationScreen(viewModel: ConversationViewModel = hiltViewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()        // ✅ framework state — stays here
    val focusRequester = remember { FocusRequester() }  // ✅ framework state — stays here

    LaunchedEffect(uiState.scrollToTopSignal) {
        listState.animateScrollToItem(0)            // ✅ animation clock owned by composition
    }

    ConversationContent(
        uiState = uiState,                          // ✅ business state from VM
        listState = listState,
        focusRequester = focusRequester,
        onAction = viewModel::onAction,
    )
}
```

```kotlin
// ❌ WRONG — LazyListState hoisted to ViewModel
class ConversationViewModel : ViewModel() {
    val listState = LazyListState()                 // ❌ animation clock won't work

    fun scrollToTop() {
        viewModelScope.launch {
            listState.animateScrollToItem(0)        // ❌ broken: wrong clock, wrong scope
        }
    }
}
```

**Anti-pattern:** Passing ViewModel to child composables. Keep it at screen level only.

```kotlin
// ❌ Couples child to ViewModel
@Composable
fun UserCard(viewModel: UserViewModel) {
    val user by viewModel.user.collectAsStateWithLifecycle()
    Text(user.name)
}

// ✅ Pass only the data
@Composable
fun UserCard(user: User) {
    Text(user.name)
}
```

## Screen Structure Patterns

The standard screen pattern separates ViewModel integration from UI:

```kotlin
@Composable
fun ConversationScreen(
    viewModel: ConversationViewModel = hiltViewModel(),
    onNavigateToDetail: (String) -> Unit
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    ConversationContent(
        uiState = uiState,
        onAction = viewModel::onAction,
        onNavigateToDetail = onNavigateToDetail
    )
}

@Composable
private fun ConversationContent(
    uiState: ConversationUiState,
    onAction: (ConversationAction) -> Unit,
    onNavigateToDetail: (String) -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Conversations") })
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { onAction(ConversationAction.Create) }) {
                Icon(Icons.Default.Add, contentDescription = "New conversation")
            }
        }
    ) { innerPadding ->
        // MUST use innerPadding -- ignoring it causes content overlap
        when (val state = uiState) {
            is ConversationUiState.Loading -> {
                Box(Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            is ConversationUiState.Success -> {
                LazyColumn(modifier = Modifier.padding(innerPadding)) {
                    items(state.conversations, key = { it.id }) { conversation ->
                        ConversationRow(
                            conversation = conversation,
                            onClick = { onNavigateToDetail(conversation.id) }
                        )
                    }
                }
            }
            is ConversationUiState.Error -> {
                ErrorContent(state.message, modifier = Modifier.padding(innerPadding))
            }
        }
    }
}
```

Key pattern: ViewModel at screen level, pure content composable underneath. The content composable receives state + callbacks, never the ViewModel. This makes it previewable and testable.

## Adaptive Layouts

Use `WindowSizeClass` to adapt layouts for different screen sizes:

```kotlin
@Composable
fun AdaptiveScreen(windowSizeClass: WindowSizeClass) {
    when (windowSizeClass.widthSizeClass) {
        WindowWidthSizeClass.Compact -> {
            // Phone: single column
            SinglePaneLayout()
        }
        WindowWidthSizeClass.Medium -> {
            // Small tablet: two panes
            TwoPaneLayout()
        }
        WindowWidthSizeClass.Expanded -> {
            // Large tablet/desktop: list-detail
            ListDetailLayout()
        }
    }
}
```

For navigation, use `NavigationSuiteScaffold` which automatically switches between bottom nav (compact), rail (medium), and drawer (expanded).

For canonical layout patterns (Feed, List-Detail, Supporting Pane), foldable postures (tabletop, book mode), and M3 compliance auditing, see `android-skills:android-ux`.
