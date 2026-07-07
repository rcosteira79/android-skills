---
name: android-dev
description: >
  Use this skill as the baseline for ALL Android and Kotlin Multiplatform (KMP) work —
  whenever the user mentions Android, Kotlin (in an Android context), KMP, CMP, commonMain,
  androidMain, iosMain, AndroidManifest, Gradle, build.gradle, Hilt, Dagger, Room, Retrofit,
  Ktor, ViewModel, LiveData, StateFlow, SharedFlow, Compose, Activity, Fragment, Intent, ADB,
  Logcat, MVVM, MVI, repository pattern, or any Android SDK / Jetpack / AndroidX API. Always
  load this skill alongside the more specific skills (android-skills:compose,
  android-skills:kotlin-flows, android-skills:kmp-ktor, android-skills:android-retrofit,
  etc.): it routes to them and adds the few baseline rules that are easy to get wrong. Casual
  mentions like "fix this bug in my Android app," "refactor this ViewModel," "my KMP project,"
  or any work inside an Android project directory should trigger this skill.
---

# Android / KMP baseline

House defaults — apply them without reminders or re-derivation; where the project's actual conventions differ, follow the project:

- **DI:** Hilt + KSP (or `android-skills:koin` when the project uses Koin). **Async:** Coroutines/Flow — no `LiveData` in new code. **JSON:** `kotlinx.serialization`. **Images:** Coil.
- **Network/local:** Android uses Retrofit/OkHttp + Room; KMP shared uses Ktor + Room or SQLDelight. Retrofit is Android-only — never in a shared module.
- **Modules:** feature-vertical packages and modules; `:core:model` has zero Android deps; `:feature:*` modules never depend on each other.
- **Errors:** mapped to a domain type at the repository boundary — platform exceptions never leak past it; UI state explicitly models loading / success / error (see `android-skills:android-data-layer`).

## Skill routing

Load the specific skill for the task, always with the **fully-qualified `android-skills:` prefix** — never the short name (`compose`, `koin`, …).

| For | Load |
|---|---|
| Compose detail — stability, `remember`, modifiers, side effects, lists, animation, navigation | `android-skills:compose` |
| M3 UX — touch targets, adaptive/foldable layouts, accessibility & M3-compliance audit | `android-skills:android-ux` |
| Coroutines & Flow — operators, `Channel` vs `SharedFlow`, structured concurrency | `android-skills:kotlin-coroutines`, `android-skills:kotlin-flows` |
| Repository / data layer + error model | `android-skills:android-data-layer` |
| Networking | `android-skills:android-retrofit` (Android) · `android-skills:kmp-ktor` (KMP) |
| Paging | `android-skills:paging` |
| Image loading | `android-skills:coil-compose` |
| Preferences / typed local storage | `android-skills:datastore` |
| KMP `expect`/`actual` boundary design | `android-skills:kmp-boundaries` |
| RxJava → Coroutines/Flow migration | `android-skills:rxjava-migration` |
| Testing | `android-skills:android-testing` |
| DI with Koin | `android-skills:koin` |
| Build logic / convention plugins | `android-skills:android-gradle-logic` |
| Build speed, kapt → KSP | `android-skills:gradle-build-performance` |
| Debugging — Logcat, crashes, ANRs, profiling | `android-skills:android-debugging` |
| AOSP / AndroidX source lookup | `android-skills:android-source-search` |
| Multi-module visibility & module boundaries | `android-skills:modularization` |
| Platform PDF annotation / page-object editing (API 36.1 / SDK ext 18) | `android-skills:pdf-annotations` |

## New-project UI convention (greenfield)

For a **new** project or feature with no established convention. In existing code, match what's already there — see *Reuse the project's existing mechanism* below.

The UI layer is MVVM with an MVI-style state/effect split:

- **One immutable `UiState` per screen**, exposed as `StateFlow<UiState>` and structured with the four buckets below. The content composable renders it and emits callbacks — nothing else.
- **One effects stream for fire-once imperatives** — navigate, snackbar/toast, scroll-to, share-sheet, haptics. Use `Channel(Channel.BUFFERED).receiveAsFlow()`, **not** `SharedFlow`: an effect emitted while the screen is backgrounded buffers and replays on resume instead of being dropped. Collect it in a `LaunchedEffect` (lifecycle-scoped via `repeatOnLifecycle`), never `collectAsStateWithLifecycle`. Channel-vs-`SharedFlow` rationale: `android-skills:kotlin-flows`.
- **State vs effect — "does it survive a config change?"** Anything still true after rotation / process death is **state** (an error to show = a field in `UiState`); anything the UI runs once and forgets is an **effect**. This is the `durable-state-over-events` rule in `compose/references/state-management.md`: keep durable things in state; the effect stream is only for one-shot imperatives.
- **Promote callbacks to a `@Stable Actions` interface at ~4–5+** (or when the same set is threaded through several composable layers). Below that, individual lambdas are simpler — don't abstract early. The ViewModel implements the interface; the content composable depends on `FooActions`, **never** the ViewModel, so it stays pure and previewable (a no-op `object : FooActions {}` in previews).

```kotlin
data class FooUiState(/* the four buckets — see below */)

sealed interface FooEffect {
    data class NavigateTo(val id: String) : FooEffect
    data class ShowSnackbar(val message: String) : FooEffect
}

@Stable                                       // promote here once lambdas pile up (~4-5+)
interface FooActions {
    fun onItemClick(id: String)
    fun onRefresh()
}

class FooViewModel(/* … */) : ViewModel(), FooActions {
    private val _uiState = MutableStateFlow(FooUiState())
    val uiState: StateFlow<FooUiState> = _uiState.asStateFlow()

    private val _effects = Channel<FooEffect>(Channel.BUFFERED)   // not SharedFlow — buffers while backgrounded
    val effects = _effects.receiveAsFlow()

    override fun onItemClick(id: String) { /* _uiState.update { … } */ _effects.trySend(FooEffect.NavigateTo(id)) }
    override fun onRefresh() { /* … */ }
}

@Composable
fun FooScreen(viewModel: FooViewModel = hiltViewModel(), onNavigate: (String) -> Unit) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(Unit) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            viewModel.effects.collect { effect ->
                when (effect) {
                    is FooEffect.NavigateTo -> onNavigate(effect.id)
                    is FooEffect.ShowSnackbar -> { /* show snackbar */ }
                }
            }
        }
    }
    FooContent(uiState = uiState, actions = viewModel)   // VM passed as FooActions — FooContent sees only the interface
}
```

> **Kotlin 2.4+:** collapse the `_uiState`/`uiState` pair with explicit backing fields (`val uiState: StateFlow<FooUiState>` + `field = MutableStateFlow(…)`) — `uiState` only, never the effects `Channel`. Full idiom + version gate: `android-skills:kotlin-flows`.

## Four-bucket state modeling

Screens with rich interactions (forms, calculators, multi-step wizards) get unmanageable when state is one flat `data class`. Slice `UiState` into four explicit buckets, and **derive computed values as class properties, not constructor parameters**:

```kotlin
data class CheckoutUiState(
    // 1. Editable input — what the user types
    val email: String = "",
    val cardNumber: String = "",
    // 3. Persisted snapshot — last value read from the repository / stored cross-screen
    val savedShippingAddress: Address? = null,
    // 4. Transient UI-only — flags that must NOT survive the screen
    val isSubmitting: Boolean = false,
    val showCardScannerOverlay: Boolean = false,
) {
    // 2. Derived — getters, NOT constructor params, so no caller can copy() into an
    //    inconsistent state (e.g. emailValid = false next to a valid email).
    val emailValid: Boolean get() = email.isValidEmail()
    val canSubmit: Boolean get() = emailValid && cardNumber.passesLuhn() && !isSubmitting
}
```

The bucket dictates lifecycle and persistence, not the field. Persisting `isSubmitting` keeps the spinner forever after process death; computing `canSubmit` outside the class lets it drift from the inputs; persisting `cardNumber` cross-screen leaks PII. Mixing the buckets produces bugs that look architectural.

## Reuse the project's existing mechanism

Before adding any new mechanism — an event dispatcher, an effects `Channel`/`SharedFlow`, a use-case layer, or a parallel state field — open a sibling ViewModel in the same feature and reuse what's already there. The easy miss here is **duplicating** an existing mechanism instead of widening it — adding a second `shouldDisplayUndoX` flag beside the existing one rather than generalizing the one that's there. If existing code contradicts a "best practice," follow the code and flag the inconsistency; never silently override the project's architecture.

## Comments — earn every one

**The test for every comment: could a reader quickly infer what it says from the code beside it? If yes, it's redundant — delete it.** A comment survives only by carrying what the code cannot: a non-obvious *why* — a decision, constraint, workaround, or gotcha. Never narrate *what* the code does; clear names and small functions already say it. "What a well-known type or call does" is a *what* the reader can look up, not a *why*.

Write the **fewest comments that pass that test** — this holds even when a task says "make it readable" or "for juniors." Readability comes from naming and structure; a comment a newcomer needs in order to follow *what* the code does is a signal to rename or extract, not to annotate.

**Keep** a genuine *why* (`// rethrow first — a broad catch would swallow CancellationException`), a justifying comment at a surprising call site, KDoc on a public API that adds information beyond its signature, and `TODO(owner-or-link)`. Honor an explicit request for documentation.

**Delete on sight** — each is trivially inferable from the code beside it:

```kotlin
// ---- domain model ----                                 // section-divider / banner (any width)
/** The user profile as the app cares about it. */        // KDoc restating the class name
val uiState = _uiState.asStateFlow()  // private mutable, public read-only   (restates the idiom)
} catch (e: IOException) {  // no connectivity, timeout, DNS failure   (restates what the type means)
```

## KMP

Inject a `CoroutineDispatcher` everywhere rather than calling `Dispatchers.Main` / `Dispatchers.IO` directly: `Dispatchers.Main` isn't guaranteed on every KMP target without the `-ktx` artifacts, and injection is also what makes dispatcher-swapped tests possible. Use `expect`/`actual` for platform specifics (file I/O, push tokens, biometrics); on iOS prefer immutable shared state.
