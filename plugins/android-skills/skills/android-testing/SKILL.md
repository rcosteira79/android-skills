---
name: android-testing
description: Use when writing, fixing, or refactoring Android/KMP code in Kotlin — supplements superpowers:test-driven-development with Android's three-tier test model, fake-first strategy, coroutine testing, and Compose UI testing.
---

# Android Testing

## Overview

Extends `superpowers:test-driven-development` with Android-specific patterns.

**REQUIRED BACKGROUND:** You MUST follow `superpowers:test-driven-development`. This skill adds Android context — it does not replace the Iron Law or RED-GREEN-REFACTOR cycle.

**Greenfield setup:** This skill teaches the *practice* of writing tests once the stack is in place — TDD loop, fake-first strategy, three-tier model, semantics matchers. For *bootstrapping* the testing stack from scratch (DI for tests, JUnit/Robolectric/Roborazzi/Paparazzi selection, instrumented test runner configuration, Compose Preview Screenshot Testing, end-to-end with UI Automator, Jacoco coverage), see Google's official [`testing-setup`](https://github.com/android/skills/tree/main/testing/testing-setup) skill (`android skills list` to check for a local install; `android skills add testing-setup` otherwise). The two are complementary.

## Android's Three Testing Tiers

Choose the lowest tier that can meaningfully test the behaviour:

| Tier | Location | Runs on | Speed | Use for |
|------|----------|---------|-------|---------|
| **Unit** | `src/test/` | JVM | Fast | Pure logic, ViewModels, UseCases, Repositories |
| **Integration** | `src/test/` with Robolectric | JVM (simulated) | Medium | Room DAOs, Context-dependent code, Fragment logic |
| **Instrumented** | `src/androidTest/` | Device/emulator | Slow | Compose UI, real DB, end-to-end flows |

**Rationalization trap:** "Instrumented tests are too slow" is never a reason to skip UI testing for UI code.

## Fakes Over Mocks

**Prefer hand-written fakes to mocking frameworks.**

Fakes implement the real interface with in-memory behaviour. They are:
- Easier to read and reason about
- Reusable across many tests
- Immune to internal implementation changes
- Not tied to call verification (which tests implementation, not behaviour)

Use a mock **only** when:
- The dependency has no meaningful state (pure function delegation)
- Verifying a specific interaction IS the behaviour under test (e.g. analytics events)
- Creating a fake would require duplicating complex external library logic

```kotlin
// PREFER: Fake with real interface
class FakeUserRepository : UserRepository {
    private val users = mutableMapOf<String, User>()
    var saveCallCount: Int = 0
        private set

    override suspend fun findById(id: String): User? = users[id]

    override suspend fun save(user: User) {
        saveCallCount++
        users[user.id] = user
    }
}

// AVOID: Mock with call verification
val mockRepo = mockk<UserRepository>()
every { mockRepo.save(any()) } just Runs
verify { mockRepo.save(expectedUser) } // tests implementation, not behaviour
```

## Assertion Library

Match the project's existing assertion library. If there is no established convention, ask the user which they prefer. Common options: kotlin-test (`assertEquals`, `assertIs`), Google Truth (`assertThat(...).isEqualTo(...)`), Kotest matchers (`shouldBe`, `shouldBeInstanceOf`). The examples in this skill use kotlin-test style — adapt to the project's choice.

## Coroutine Testing

Use `runTest` for all suspend functions. Never use `runBlocking` in tests.

```kotlin
@Test
fun `given invalid credentials, when logging in, then emits error state`() = runTest {
    // Given
    val fakeRepository = FakeAuthRepository()
    val viewModel = LoginViewModel(fakeRepository)

    // When
    viewModel.login(inputEmail = "bad@email.com", inputPassword = "wrong")
    advanceUntilIdle()

    // Then
    val actualState = viewModel.uiState.value
    assertIs<LoginUiState.Error>(actualState)
}
```

**Hot flows (`StateFlow` / `SharedFlow`) never complete**, so collecting one directly on the `TestScope` hangs to the 60-second `runTest` timeout:

```kotlin
viewModel.uiState.collect { seen += it } // WRONG: hangs the test
```

Use [Turbine](https://github.com/cashapp/turbine)'s `test {}`, which collects and cancels for you:

```kotlin
viewModel.uiState.test {
    assertIs<LoginUiState.Loading>(awaitItem())
    assertIs<LoginUiState.Error>(awaitItem())
    cancelAndIgnoreRemainingEvents()
}
```

Or, without Turbine, launch the collector on `backgroundScope` (auto-cancelled at end of test):

```kotlin
viewModel.uiState.onEach { seen += it }.launchIn(backgroundScope)
```

Dispatcher injection is required for testability:

```kotlin
class LoginViewModel(
    private val repository: AuthRepository,
    private val dispatcher: CoroutineDispatcher = Dispatchers.Main
) : ViewModel()
```

Replace `Dispatchers.Main` in tests via the canonical `MainDispatcherRule` from androidx `testutils-ktx`:

```kotlin
@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val dispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description?) {
        super.starting(description); Dispatchers.setMain(dispatcher)
    }
    override fun finished(description: Description?) {
        super.finished(description); Dispatchers.resetMain()
    }
}

class LoginViewModelTest {
    @get:Rule val mainRule = MainDispatcherRule()

    @Test fun loadsItems() = runTest(mainRule.dispatcher) {
        val vm = LoginViewModel(fakeRepo, mainRule.dispatcher)
        vm.login(/* … */)
        advanceUntilIdle()
        assertIs<LoginUiState.Success>(vm.uiState.value)
    }
}
```

**Two-schedulers trap.** `MainDispatcherRule`'s dispatcher and the default dispatcher `runTest { }` creates have separate `TestCoroutineScheduler`s. Pass `mainRule.dispatcher` into `runTest(...)` so `Dispatchers.Main` and the test body share one scheduler — otherwise `advanceUntilIdle()` only flushes one of them and assertions race the ViewModel.

Prefer `StandardTestDispatcher` over `UnconfinedTestDispatcher` — it queues continuations (matching `runTest` semantics). Reach for `UnconfinedTestDispatcher` only when hot-flow collector eagerness is genuinely the point.

## Compose UI Testing

Use `createComposeRule()` for component tests, `createAndroidComposeRule()` for integration tests needing Activity.

**Prefer v2 entry points for new code.** Import from `androidx.compose.ui.test.junit4.v2.createComposeRule` (or `androidx.compose.ui.test.v2.runComposeUiTest`) — they use `StandardTestDispatcher` and match `kotlinx.coroutines.test.runTest` semantics. The v1 imports (`androidx.compose.ui.test.junit4.createComposeRule`, `androidx.compose.ui.test.runComposeUiTest`) use `UnconfinedTestDispatcher` and are deprecated `WARNING`. After migrating, a `LaunchedEffect` that previously ran eagerly may need an explicit `mainClock.advanceTimeBy(0)` or `runCurrent()` to drain queued work.

### Semantics first, `testTag` as fallback

Prefer user-visible semantics — text, `contentDescription`, role, focused/toggled/selected state — over `testTag`. Real users (and screen readers) see semantics; `testTag` is invisible to everyone except tests.

```kotlin
@get:Rule
val composeTestRule = createComposeRule()

@Test
fun `given loading state, when screen renders, then shows progress indicator`() {
    // Given
    val inputState = LoginUiState.Loading

    // When
    composeTestRule.setContent {
        LoginScreen(uiState = inputState, onLogin = {})
    }

    // Then — semantics-first: assert what the user sees
    composeTestRule.onNodeWithContentDescription("Loading").assertIsDisplayed()
}
```

Selector priority (top of list wins):

1. `onNodeWithText("...")` — visible text the user reads.
2. `onNodeWithContentDescription("...")` — accessibility label (icons, images).
3. Role / state matchers — `hasClickAction()`, `isSelected()`, `isFocused()`, `isEnabled()`.
4. `onNodeWithTag("...")` — **only when** there's no stable user-visible text or the text is duplicated/ambiguous (lists of identical rows, dynamic copy that changes per locale, multiple instances of the same component).

Test what the user perceives, not implementation details. A test that asserts text the user sees survives refactors that move components around; a test that asserts `onNodeWithTag("loading_indicator")` breaks the moment the tag changes — and doesn't catch the user-facing regression where the spinner is wired wrong.

**Counterargument worth knowing.** [skydoves/android-testing-skills](https://github.com/skydoves/android-testing-skills) argues for tag-first finders backed by androidx/material3's own ratios (1825 `onNodeWithTag` vs 424 `onNodeWithText` vs 46 `onNodeWithContentDescription`) — the tag-first stance is more robust to i18n rotation and copy edits. We still recommend semantics-first because text/`contentDescription` assertions exercise accessibility and catch a class of bugs `testTag` can never see — but if your app has separate accessibility coverage and prioritises i18n robustness, the tag-first stance is defensible.

### Callbacks as test surfaces

Test that a click fires the expected callback — don't route the assertion through a ViewModel mock.

```kotlin
@Test
fun `tapping article row invokes onArticleClick with article id`() {
    var clickedId: String? = null
    val article = Article(id = "42", title = "Hello")

    composeTestRule.setContent {
        ArticleRow(article = article, onArticleClick = { clickedId = it })
    }

    composeTestRule.onNodeWithText("Hello").performClick()
    assertEquals("42", clickedId)
}
```

The composable's contract is "render state, emit callbacks." Test exactly that.

### Synchronisation: test clock vs wall clock

| API | Source | When |
|---|---|---|
| `mainClock.advanceTimeUntil(timeoutMillis) { condition }` | Test clock — advances frame-by-frame | Compose-state-observable conditions (`state.value == Done`); deterministic, fast |
| `rule.waitUntil(timeoutMillis) { condition }` | Wall clock + 10 ms sleep per iteration | Non-Compose conditions (`Job.isCompleted`, an external counter) |
| `rule.waitUntilExactlyOneExists(matcher, timeoutMillis)` (experimental) | Wall clock | "Wait until exactly one node matches"; cleaner than hand-rolling `waitUntil` over `fetchSemanticsNodes()` |

Mixing wall-clock and test-clock waits in the same test is a common flake source. For any condition observable through Compose state, `mainClock.advanceTimeUntil` is correct.

**Animation tests require `mainClock.autoAdvance = false`** set **before** `setContent`. Otherwise the framework's `InfiniteAnimationPolicy` throws `CancellationException` on indeterminate animations, and finite animations finish in one auto-advanced burst with no observable intermediate state. After pausing the clock, drive frames with `advanceTimeByFrame()` (kick-off) then `advanceTimeBy(durationMillis)`.

### Choosing the Test Shape

**Test the smallest UI contract that proves the behavior.**

A plain UI Compose test (`createComposeRule()` + state + callbacks) is enough for most behaviour. Reach for an integration test, screenshot test, or key-input test only when that shape is the one being proven.

| Thing being proven | Test shape |
|---|---|
| Text rendered, conditional content visible, loading/error branches, callback wiring from clicks | Plain UI Compose test (state + callbacks, no graph) |
| Focus navigation, keyboard, TV/D-pad behavior | Compose test with key input — drive with `performKeyInput`, assert with `assertIsFocused()`. See `compose/references/focus-navigation.md` |
| Visual contract semantics can't prove: spacing, themed colors, typography, elevation, gradients, focus highlight, skeleton loaders | Screenshot test, one per meaningful state |
| State holder updates UI correctly | State-holder unit test + ONE wiring smoke test (two tests, not one big integration) |
| Lifecycle, navigation, or DI integration itself under test | Integration test (`createAndroidComposeRule`, Hilt rule, real graph) |

**Screenshot determinism rules:**

- Fixed state data — no current time, no random seeds, no remote URLs in the screenshot path
- Freeze clocks (`Clock.fixed(...)`) and animation progress (disable animations or set fixed progress)
- Fake image loaders for image-heavy screens — use Coil's `setContentWithFakeImageLoader { ... }` (see `android-skills:coil-compose`)
- One screenshot per meaningful state (loading/error/success/empty), not one per UI element

**Fake image loader pattern:**

```kotlin
@Test
fun `article row renders with fake image`() {
    composeTestRule.setContent {
        AppTheme {
            val imageLoader = FakeImageLoader(LocalContext.current) // Coil 3 test util
            CompositionLocalProvider(LocalImageLoader provides imageLoader) {
                ArticleRow(article = previewArticle(), onClick = {})
            }
        }
    }
    composeTestRule.onRoot().captureRoboImage()
}
```

## Hilt Testing

Use `@HiltAndroidTest` with `HiltAndroidRule` to inject real Hilt dependencies in instrumented tests.

```kotlin
@HiltAndroidTest
class UserRepositoryTest {

    @get:Rule
    var hiltRule = HiltAndroidRule(this)

    @Inject
    lateinit var database: AppDatabase
    private lateinit var dao: UserDao

    @Before
    fun setUp() {
        hiltRule.inject()
        dao = database.userDao()
    }

    @Test
    fun `given user saved, when queried by id, then returns user`() = runTest {
        // Given
        val inputUser = User(id = "1", name = "Alice")
        dao.insert(inputUser)

        // When
        val actualUser = dao.findById("1")

        // Then
        assertEquals(inputUser, actualUser)
    }
}
```

For unit tests with Hilt (without instrumentation), use `@TestInstallIn` to replace modules with fakes.

## Screenshot Testing with Roborazzi

Roborazzi runs screenshot tests on the JVM via Robolectric — no emulator required. Use it to catch visual regressions.

### Setup

```toml
# libs.versions.toml
[versions]
roborazzi = "1.x.x"

[plugins]
roborazzi = { id = "io.github.takahirom.roborazzi", version.ref = "roborazzi" }

[libraries]
roborazzi = { group = "io.github.takahirom.roborazzi", name = "roborazzi", version.ref = "roborazzi" }
```

```kotlin
// module build.gradle.kts
plugins {
    alias(libs.plugins.roborazzi)
}
```

### Writing a Screenshot Test

```kotlin
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [33], qualifiers = RobolectricDeviceQualifiers.Pixel5)
class LoginScreenScreenshotTest {

    @get:Rule
    val composeTestRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun `given loading state, captures loading screen`() {
        // Given
        composeTestRule.setContent {
            AppTheme {
                LoginScreen(uiState = LoginUiState.Loading, onLogin = {})
            }
        }

        // Then
        composeTestRule.onRoot().captureRoboImage()
    }
}
```

Screenshot tests exercise visual state you can't assert with `assertIsDisplayed()`. Write one per meaningful UI state (loading, error, success, empty).

## Gradle Commands

```bash
# Run JVM unit tests (fast — run on every change)
./gradlew test

# Run unit tests for a specific module
./gradlew :feature:login:test

# Run a single test class
./gradlew :feature:login:test --tests "com.example.login.LoginViewModelTest"

# Run instrumented tests (requires connected device/emulator)
./gradlew connectedAndroidTest

# Run instrumented tests for a specific module
./gradlew :feature:login:connectedAndroidTest
```

```bash
# Record screenshot baselines
./gradlew recordRoborazziDebug

# Verify screenshots against baselines (CI)
./gradlew verifyRoborazziDebug
```

## ViewModel Test Template (Given-When-Then)

```kotlin
class LoginViewModelTest {

    private val fakeRepository = FakeAuthRepository()
    private val viewModel = LoginViewModel(
        repository = fakeRepository,
        dispatcher = UnconfinedTestDispatcher()
    )

    @Test
    fun `given valid credentials, when logging in, then emits success state`() = runTest {
        // Given
        fakeRepository.willSucceedFor(inputEmail = "user@example.com")

        // When
        viewModel.login(inputEmail = "user@example.com", inputPassword = "pass123")

        // Then
        val actualState = viewModel.uiState.value
        assertIs<LoginUiState.Success>(actualState)
    }
}
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Instrumented tests are slow, I'll skip" | Slow tests > no tests. Optimise test selection, don't skip. |
| "Mocks are easier to write than fakes" | Fakes are more valuable and readable. Invest once, reuse everywhere. |
| "I can't test this ViewModel, it uses Dispatchers.Main" | Inject the dispatcher. Hard to test = design smell. |
| "This Composable is too simple to test" | Simple UI breaks. A `setContent` + `assertIsDisplayed` takes 2 minutes. |
| "Room DAOs test themselves" | Write DAO tests with in-memory database to verify your queries. |

## Red Flags

- Using `Thread.sleep()` in any test
- Using `runBlocking` instead of `runTest`
- Mocking data classes or simple value types
- `onNodeWithTag` used as the first reach when stable user-visible text or `contentDescription` exists
- `testTag` sprinkled across every interactive component "for testability" — semantics first
- Test asserts that a node *exists* after an action, instead of asserting the action's callback fired
- Click-only test for UI that ships on TV, ChromeOS, or keyboard-first Android (drive with key input instead — see `compose/references/focus-navigation.md`)
- Screenshot test asserts focus ownership instead of using `assertIsFocused()` — see `compose/references/focus-navigation.md`
- Screenshot test contains current time, random IDs, or remote image URLs
- Integration test used when a plain UI test would prove the same behavior
- Instrumented tests for logic that could run on JVM
