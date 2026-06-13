# Screen Structure in Jetpack Compose

Screen-level structure — the architectural layer above individual composables. For composable naming / slots / extraction, see `compose/references/view-composition.md`; for M3 UX (touch targets, foldable postures, canonical layouts, M3 compliance), see `android-skills:android-ux`.

A strong model already structures screens correctly by default: a public screen composable that integrates the ViewModel (`collectAsStateWithLifecycle`, `LaunchedEffect` for the initial load) above a stateless content composable receiving state + callbacks; `Scaffold` with its `innerPadding` applied; `WindowSizeClass` / `NavigationSuiteScaffold` for adaptive layouts. This reference keeps the two things it under-does.

## Make the content composable `private`

The screen/content split itself is default; making the **content composable `private`** (or `internal`) is the part the default skips. The public screen composable wires the ViewModel; the private content composable is pure — testable, previewable, and impossible to accidentally hand a ViewModel from elsewhere.

```kotlin
@Composable
fun UserDetailsScreen(userId: String, viewModel: UserDetailsViewModel = hiltViewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    LaunchedEffect(userId) { viewModel.loadUser(userId) }
    UserDetailsContent(uiState = uiState, onRetry = { viewModel.loadUser(userId) })
}

@Composable
private fun UserDetailsContent(uiState: UiState, onRetry: () -> Unit) {   // private — pure, previewable
    when (uiState) { /* Loading / Success / Error */ }
}
```

Pass **data, not the ViewModel**, down to child composables — `UserCard(user: User)`, never `UserCard(viewModel)` — or the child couples to the VM and stops being reusable and previewable.

## Framework state stays in the UI composable — don't hoist it to the ViewModel

`LazyListState`, `LazyGridState`, `ScrollState`, `PagerState`, `FocusRequester`, `BringIntoViewRequester`, `Animatable`, `TextFieldState`, and snackbar/drawer holders are **framework state** (Compose mechanics), not business state — keep them in the composable. Only **business state** (loaded data, screen mode, inputs that drive queries — anything with semantic meaning that must survive a configuration change) belongs in the ViewModel.

```kotlin
// ✅ framework state in the composable; the animation clock is owned by the composition
@Composable
fun ConversationScreen(viewModel: ConversationViewModel = hiltViewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()                 // stays here
    LaunchedEffect(uiState.scrollToTopSignal) { listState.animateScrollToItem(0) }
    ConversationContent(uiState, listState, onAction = viewModel::onAction)
}

// ❌ LazyListState hoisted to the ViewModel — animateScrollToItem from viewModelScope runs on the
//    wrong clock/scope and breaks: the animation clock is tied to the composition, not the VM.
class ConversationViewModel : ViewModel() { val listState = LazyListState() /* … */ }
```

See `compose/references/state-management.md` for the full clock/scope failure mode.
