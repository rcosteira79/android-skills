---
name: android-testing
description: >
  Use when writing, fixing, or refactoring Android/KMP code in Kotlin — a test-first
  (RED-GREEN-REFACTOR) foundation plus the Android test traps: Compose-test dispatching
  (StandardTestDispatcher default, the two-schedulers trap), semantics-first selectors,
  choosing the smallest test shape, test-clock vs wall-clock, and animation/screenshot
  determinism.
---

# Android Testing

Android-specific testing on a **test-first** foundation. This reference focuses on the test-first discipline plus the Compose-test traps that are easy to get wrong, not the basics of the three tiers, fakes over mocks, `runTest`, or Given-When-Then naming.

## Test-first (the foundation)

- **No production code without a failing test first.** Write the test, watch it fail (RED), write the minimal code to pass (GREEN), then refactor. A behaviour you never watched fail isn't proven.
- **A bug isn't fixed until a test that was red *because of the bug* is green.**

This layers on top of any dedicated TDD discipline skill (`superpowers:test-driven-development`, `ace:test-driven-development`) but requires none. For *bootstrapping* the test stack from scratch (test DI, JUnit/Robolectric/Roborazzi/Paparazzi selection, the instrumented runner, Compose Preview Screenshot Testing, UI Automator, Jacoco), see Google's official [`testing-setup`](https://github.com/android/skills/tree/main/testing/testing-setup) skill (`android skills add testing-setup`).

## Compose tests now default to `StandardTestDispatcher`

`createComposeRule()` / `runComposeUiTest {}` default to `StandardTestDispatcher` (matching `kotlinx.coroutines.test.runTest`) — **there is no separate "v2" package.** It's gated by `androidx.compose.ui.test.ComposeUiTestFlags.isStandardTestDispatcherSupportEnabled` (defaults to `true`), so the regular `androidx.compose.ui.test.junit4.createComposeRule` already uses it. To pin a scheduler, pass it through: `createComposeRule(effectContext = StandardTestDispatcher())`. Under this default, a `LaunchedEffect` that previously ran eagerly (the old `UnconfinedTestDispatcher` behaviour) may need an explicit `mainClock.advanceTimeBy(0)` / `runCurrent()` to drain queued work; set the flag `false` only to temporarily restore the legacy behaviour.

**Two-schedulers trap** (the one coroutine-test gotcha worth stating): a `MainDispatcherRule`'s `TestDispatcher` and the dispatcher `runTest { }` creates have **separate** `TestCoroutineScheduler`s. Pass `mainRule.dispatcher` into `runTest(mainRule.dispatcher)` so `Dispatchers.Main` and the test body share one — otherwise `advanceUntilIdle()` flushes only one and assertions race the ViewModel.

## Semantics first, `testTag` as fallback

Prefer user-visible semantics over `testTag` — real users and screen readers see semantics; `testTag` is invisible to everyone except tests. Selector priority: (1) `onNodeWithText`; (2) `onNodeWithContentDescription`; (3) role/state matchers (`hasClickAction()`, `isSelected()`, `isFocused()`, `isEnabled()`); (4) `onNodeWithTag` **only** when there's no stable user-visible text or it's duplicated/ambiguous (lists of identical rows, per-locale copy, multiple instances). A text assertion survives refactors and exercises accessibility; a `testTag` assertion breaks the moment the tag changes and misses the user-facing regression.

*(Counterview worth knowing: [skydoves/android-testing-skills](https://github.com/skydoves/android-testing-skills) argues tag-first for i18n robustness, backed by androidx/material3's own 1825 : 424 : 46 `testTag` : `onNodeWithText` : `onNodeWithContentDescription` ratio. Defensible if you have separate accessibility coverage; this skill defaults to semantics-first because it catches a class of bugs `testTag` never can.)*

## Callbacks as test surfaces

A composable's contract is "render state, emit callbacks" — test exactly that; don't route the assertion through a ViewModel mock.

```kotlin
@Test fun `tapping article row invokes onArticleClick with id`() {
    var clickedId: String? = null
    composeTestRule.setContent { ArticleRow(Article(id = "42", title = "Hello"), onArticleClick = { clickedId = it }) }
    composeTestRule.onNodeWithText("Hello").performClick()
    assertEquals("42", clickedId)
}
```

## Choosing the test shape — the smallest contract that proves the behaviour

| Proving | Shape |
|---|---|
| Text rendered, conditional content, loading/error branches, callback wiring | Plain UI Compose test (state + callbacks, no graph) |
| Focus navigation, keyboard, TV/D-pad | Compose test with `performKeyInput` + `assertIsFocused()` (see `compose/references/focus-navigation.md`) |
| Visual contract semantics can't prove — spacing, themed colour, typography, elevation, gradients, skeletons | Screenshot test, one per meaningful state |
| State holder updates UI correctly | State-holder unit test + ONE wiring smoke test |
| Lifecycle, navigation, or DI integration itself | Integration test (`createAndroidComposeRule`, Hilt rule, real graph) |

**Test clock vs wall clock:** for any Compose-state-observable condition use `mainClock.advanceTimeUntil(ms) { state.value == Done }` (deterministic, fast); use `rule.waitUntil(ms) { … }` only for non-Compose conditions (`Job.isCompleted`, an external counter). Mixing the two in one test is a common flake source.

**Animation tests need `mainClock.autoAdvance = false` set *before* `setContent`** — otherwise the framework's `InfiniteAnimationPolicy` throws `CancellationException` on indeterminate animations, and finite animations finish in one auto-advanced burst with no observable intermediate state. After pausing, drive frames with `advanceTimeByFrame()` (kick-off) then `advanceTimeBy(durationMillis)`.

**Screenshot determinism:** fixed state data (no current time, random seeds, or remote URLs in the screenshot path); frozen clocks (`Clock.fixed(...)`) and animation progress; a fake image loader for image-heavy screens (Coil 3's test double: `LocalImageLoader provides FakeImageLoader(LocalContext.current)`, or `setContentWithFakeImageLoader { … }`); one shot per meaningful state (loading / error / success / empty), not one per UI element.
