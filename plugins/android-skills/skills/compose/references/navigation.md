# Navigation in Jetpack Compose

> **Navigation 3 (`androidx.navigation3`) is the default for new work** — see the Nav3 section below. Navigation 2 (`NavHost` / `NavController`) is legacy/interop.

## Navigation 2 (legacy)

These are the house defaults for Nav2:

- **Type-safe `@Serializable` route classes, never string routes:** `composable<Details> { it.toRoute<Details>() }`, `navController.navigate(Details(itemId = 42))`. Nested `@Serializable` data classes serialize automatically.
- `rememberNavController()` lives in the `NavHost`, never in a ViewModel.
- `navOptions { popUpTo(Route::class) { inclusive = … }; launchSingleTop = true }` for back-stack control; `previousBackStackEntry?.savedStateHandle` for result passing; `navDeepLink<Route>(uriPattern = …)` + a manifest `intent-filter` for deep links; nested graphs via `navigation<Root>(startDestination = …)`; `hiltViewModel()` to scope a ViewModel to a back-stack entry; `TestNavHostController` for tests.
- Traps to avoid: don't navigate during composition (do it in a `LaunchedEffect`), don't mix string and type-safe routes, don't hold a `NavController` in a ViewModel.

---

## Navigation 3 (`androidx.navigation3`)

**Default to Navigation 3 for new work — Nav3 all the way unless impossible.** It's a separate, Compose-first library: you own the back stack as observable state and a `NavDisplay` renders it via an `entryProvider` (no `NavController`, no graph builder). It's the direction Jetpack navigation is heading, so the Navigation 2 patterns above are legacy/interop — reach for Nav2 only when Nav3 genuinely can't do the job, or when bending a case into Nav3 would be far more complex than the Nav2 equivalent.

There's deliberately no Nav3 API mirrored here: Google maintains an official, current `navigation-3` skill, and duplicating it would only drift.

- **Preferred — the installed skill.** Google ships an installable `navigation-3` skill for Claude Code (also Cursor/Copilot). If it's present (check `android skills list`, or `~/.claude/skills/navigation-3/`), invoke it — it's the authoritative, maintained source. Install with `android skills add navigation-3`.
- **Fallback — the KB.** Without it installed, fetch the same content: `android docs fetch kb://android/agents/skills/navigation/navigation-3/skill` (overview at `.../navigation-3/index`).
- **Recipes** (basic, animations, deep links, multiple back stacks, list-detail, DI): `github.com/android/nav3-recipes`.

The recipes are building blocks, not drop-in solutions — compose what your use case needs from them, without over-engineering something Nav2 would do trivially.

### Compose-shape guardrails (apply with any Nav version)

These constrain *how composables interact with navigation* — they catch projects that adopt Nav 3 without rethinking the shape:

1. **Destination keys/data are top-level `@Serializable`** — fields, not captured callbacks. Captured callbacks defeat type-safe routing and break SavedState restoration.
2. **No `@Composable` lambdas in destination data** — the key describes *where you are*, not what's drawn; a `@Composable` field couples graph identity to composition identity and breaks back-stack restoration.
3. **ViewModels emit navigation events via `Flow<NavEvent>`** (or `Channel<NavEvent>(BUFFERED).receiveAsFlow()`), collected in a `LaunchedEffect` that calls the navigator — don't inject `backStack` / `NavController` into the ViewModel.
4. **Decorator order matters** — `rememberSaveableStateHolderNavEntryDecorator` wraps `rememberViewModelStoreNavEntryDecorator`, not the reverse, or ViewModels survive but their saved state doesn't.

**Carry-over from this skill:** `NavDisplay` owns its transitions (`transitionSpec` / `popTransitionSpec` / `predictivePopTransitionSpec`), so don't wrap a destination's content in `AnimatedContent` — same double-animation trap as Nav2 (see `references/animation.md`).
