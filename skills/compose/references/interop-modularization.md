# Interop & Modularization

## AndroidView — Legacy View Interop

Use `AndroidView` to embed a traditional `View` inside a Compose hierarchy. Keep usage isolated — don't spread it across the codebase.

```kotlin
@Composable
fun LegacyMapView(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { context ->
            MapView(context).apply {
                onCreate(Bundle())
                onResume()
            }
        },
        update = { mapView ->
            // Called on recomposition — update the view here
            mapView.getMapAsync { googleMap ->
                googleMap.moveCamera(CameraUpdateFactory.zoomTo(15f))
            }
        },
        modifier = modifier
    )
}
```

### Rules

- **Isolate** `AndroidView` inside a dedicated composable wrapper — never scatter it inline in screen composables
- **Handle lifecycle** manually inside the `factory` lambda for views that need it (e.g., `MapView`, `SurfaceView`)
- **Avoid mixing state**: manage the View's state inside `update`, not by recreating the view on every recomposition (`factory` is only called once)
- Prefer migrating the legacy view to Compose over time; `AndroidView` is a bridge, not a permanent pattern

### Avoid LiveData in Compose UI

Convert `LiveData` to `StateFlow` before exposing it from the ViewModel:

```kotlin
// Correct: expose StateFlow
class MyViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()
}

// Avoid: LiveData in Compose UI
class MyViewModel : ViewModel() {
    val uiState: LiveData<UiState> = MutableLiveData(UiState())
    // Forces .observeAsState() in UI — not lifecycle-safe by default
}
```

If you must observe `LiveData` temporarily (third-party library, incremental migration), use `observeAsState()` from `androidx.compose.runtime:runtime-livedata`.

---

## Modularization

### Feature-based UI modules

Each feature owns a `:feature:<name>:ui` module. Keep the feature's composables, ViewModel, and navigation entry points inside that module.

```
:app
:feature:home:ui       ← HomeScreen, HomeViewModel
:feature:profile:ui    ← ProfileScreen, ProfileViewModel
:feature:settings:ui   ← SettingsScreen, SettingsViewModel
:core:design-system    ← shared components, theme
:core:navigation       ← route definitions, NavGraph
```

Avoid a "god UI module" that imports all features — it defeats incremental compilation and makes boundaries unclear.

### Public UI contracts

Expose the minimum surface area from each feature module:

```kotlin
// :feature:home:ui — public API
fun NavGraphBuilder.homeGraph(
    onNavigateToProfile: (String) -> Unit
) {
    navigation<HomeGraph>(startDestination = HomeRoute) {
        composable<HomeRoute> {
            HomeScreen(onNavigateToProfile = onNavigateToProfile)
        }
    }
}

// Internal — not exposed
internal fun HomeScreen(...) { ... }
internal class HomeViewModel : ViewModel() { ... }
```

The navigation extension function is the module's only public entry point. The screen composable and ViewModel are `internal`.

### Design system module

Shared UI primitives (buttons, cards, typography, color tokens) live in `:core:design-system`, not in any feature module. Features import from the design system — never from each other.

```kotlin
// Correct
import com.example.core.designsystem.components.PrimaryButton

// Wrong: feature importing another feature's composable
import com.example.feature.home.ui.HomeButton
```
