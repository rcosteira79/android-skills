# Navigation in Jetpack Compose

Reference: `androidx/navigation/navigation-compose/src/commonMain/kotlin/androidx/navigation/compose/`

## Setup

### Basic NavHost and NavController

```kotlin
val navController = rememberNavController()

NavHost(
    navController = navController,
    startDestination = "home" // Use Route::class with type-safe navigation
) {
    composable<Home> {
        HomeScreen(onNavigate = { navController.navigate(Details()) })
    }
}
```

`rememberNavController()` creates a `NavController` that survives recomposition. Always use it in `NavHost`—never create `NavController` in a ViewModel.

## Type-Safe Navigation (Navigation 2.8+)

Use `@Serializable` route classes instead of string routes. This is the recommended pattern.

```kotlin
@Serializable
data class Home(val userId: String? = null)

@Serializable
data class Details(val itemId: Int)

NavHost(navController, startDestination = Home()) {
    composable<Home> { backStackEntry ->
        val args = backStackEntry.toRoute<Home>()
        HomeScreen(userId = args.userId)
    }
    composable<Details> { backStackEntry ->
        val args = backStackEntry.toRoute<Details>()
        DetailsScreen(itemId = args.itemId)
    }
}
```

Serialize complex types using `@Serializable` on nested data classes:

```kotlin
@Serializable
data class User(val id: Int, val name: String)

@Serializable
data class UserProfile(val user: User)

// Navigate:
navController.navigate(UserProfile(user = User(1, "Alice")))
```

## Declaring Destinations

### composable — Screen destinations

```kotlin
composable<Route> { backStackEntry ->
    ScreenContent()
}
```

### dialog — Dialog destinations

```kotlin
dialog<Route> { backStackEntry ->
    AlertDialog(...)
}
```

### navigation — Nested graphs (feature modules)

```kotlin
navigation<RootRoute>(startDestination = Home()) {
    composable<Home> { HomeScreen() }
    composable<Details> { DetailsScreen() }
}
```

## Navigating

### Navigate to a destination

```kotlin
// Type-safe
navController.navigate(Details(itemId = 42))

// Avoid: string-based navigation
navController.navigate("details/42") // Anti-pattern
```

### Pop back stack

```kotlin
navController.popBackStack()

// Pop with return value (save state before popping)
navController.previousBackStackEntry?.savedStateHandle?.set("key", value)
navController.popBackStack()

// In destination, retrieve:
val result = navController.currentBackStackEntry?.savedStateHandle?.get<T>("key")
```

### popUpTo — Clear back stack

```kotlin
// Navigate to Details, clearing Home from stack
navController.navigate(
    Details(itemId = 42),
    navOptions = navOptions {
        popUpTo(Home::class) { inclusive = false }
    }
)

// inclusive = true: Remove the target route too
navController.navigate(
    Login(),
    navOptions = navOptions {
        popUpTo(Home::class) { inclusive = true }
    }
)

// launchSingleTop: Reuse existing instance if already on stack
navController.navigate(
    Details(itemId = 42),
    navOptions = navOptions {
        launchSingleTop = true
    }
)
```

## Arguments and Back Stack Data

Compose Navigation handles serialization automatically with `@Serializable` routes.

### Passing complex data

```kotlin
@Serializable
data class Message(val id: Int, val text: String, val metadata: Metadata)

@Serializable
data class Metadata(val timestamp: Long, val priority: Int)

navController.navigate(Message(1, "Hello", Metadata(System.currentTimeMillis(), 1)))
```

### Result passing via SavedStateHandle

```kotlin
// Send result back
navController.previousBackStackEntry?.savedStateHandle?.set("result", "success")
navController.popBackStack()

// Receive in previous screen
val result = navController.currentBackStackEntry?.savedStateHandle?.get<String>("result")
```

## Nested Navigation Graphs

Organize related destinations into feature graphs.

```kotlin
navigation<FeatureRoot>(startDestination = FeatureHome()) {
    composable<FeatureHome> { FeatureHomeScreen(onNext = { navController.navigate(FeatureDetail()) }) }
    composable<FeatureDetail> { FeatureDetailScreen() }
}
```

Benefits: scoped ViewModels, separate back stack behavior, feature isolation.

## Deep Links

Declare deep links to open your app from URLs or notifications.

```kotlin
composable<Details>(
    deepLinks = listOf(
        navDeepLink<Details>(
            uriPattern = "https://example.com/details/{itemId}"
        )
    )
) { backStackEntry ->
    val args = backStackEntry.toRoute<Details>()
    DetailsScreen(itemId = args.itemId)
}

// Navigate via deep link
navController.navigate("https://example.com/details/42")
```

Handle in `AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="example.com" />
    </intent-filter>
</activity>
```

## Back Stack Management

### saveState / restoreState

Preserve screen state during navigation:

```kotlin
navController.navigate(
    Details(itemId = 42),
    navOptions = navOptions {
        saveState = true
        restoreState = true
    }
)
```

### Check current route

```kotlin
val currentRoute = navController.currentBackStackEntry?.destination?.route
```

### Observe back stack

```kotlin
val backStackEntry by navController.currentBackStackEntryAsState()
val route = backStackEntry?.destination?.route
```

## Bottom Navigation Integration

```kotlin
var selectedItem by remember { mutableStateOf("home") }
val navController = rememberNavController()

Scaffold(
    bottomBar = {
        NavigationBar {
            NavigationBarItem(
                selected = selectedItem == "home",
                onClick = {
                    selectedItem = "home"
                    navController.navigate(Home()) {
                        popUpTo(Home::class) { inclusive = true }
                        launchSingleTop = true
                    }
                },
                icon = { Icon(Icons.Default.Home, null) },
                label = { Text("Home") }
            )
            NavigationBarItem(
                selected = selectedItem == "profile",
                onClick = {
                    selectedItem = "profile"
                    navController.navigate(Profile()) {
                        popUpTo(Home::class) { inclusive = false }
                        launchSingleTop = true
                    }
                },
                icon = { Icon(Icons.Default.Person, null) },
                label = { Text("Profile") }
            )
        }
    }
) {
    NavHost(navController, startDestination = Home()) {
        composable<Home> { HomeScreen() }
        composable<Profile> { ProfileScreen() }
    }
}
```

## Shared Element Transitions

```kotlin
NavHost(navController, startDestination = List()) {
    composable<List>(
        sharedTransitionSpec = {
            SharedTransitionLayout()
        }
    ) {
        ListScreen()
    }
    composable<Detail>(
        sharedTransitionSpec = {
            SharedTransitionLayout()
        }
    ) {
        DetailScreen()
    }
}
```

Use in screens:

```kotlin
Image(
    painter = painterResource(id = R.drawable.image),
    contentDescription = null,
    modifier = Modifier.sharedBounds(
        sharedContentState = rememberSharedContentState(key = "image"),
        animatedVisibilityScope = this
    )
)
```

## ViewModel Scoping with Navigation

Use `hiltViewModel()` to scope ViewModels to a back stack entry.

```kotlin
composable<Details> { backStackEntry ->
    val viewModel: DetailsViewModel = hiltViewModel()
    DetailsScreen(viewModel = viewModel)
}
```

ViewModels scoped this way survive configuration changes but are cleared when the back stack entry is removed.

## Testing Navigation

Use `TestNavHostController` to test navigation behavior.

```kotlin
@get:Rule
val composeTestRule = createComposeRule()

@Test
fun navigateToDetails() {
    val navController = TestNavHostController(ApplicationProvider.getApplicationContext())
    navController.navigatorProvider.addNavigator(ComposeNavigator())

    composeTestRule.setContent {
        NavHost(navController, startDestination = Home()) {
            composable<Home> { HomeScreen(onNavigate = { navController.navigate(Details()) }) }
            composable<Details> { DetailsScreen() }
        }
    }

    composeTestRule.onNodeWithTag("detail_button").performClick()
    assertEquals(Details::class.serializer().descriptor.serialName, navController.currentBackStackEntry?.destination?.route)
}
```

## Anti-Patterns

### Don't: Use string-based routes
```kotlin
// ❌ Anti-pattern
navController.navigate("details/42")

// ✅ Correct
navController.navigate(Details(itemId = 42))
```

### Don't: Create NavController in ViewModel
```kotlin
// ❌ Anti-pattern
class MyViewModel : ViewModel() {
    val navController = NavController(context) // Wrong!
}

// ✅ Correct
// NavController lives in NavHost, injected into composables
```

### Don't: Navigate in composition
```kotlin
// ❌ Anti-pattern
@Composable
fun MyScreen() {
    if (condition) {
        navController.navigate(Details()) // Navigates on every recomposition!
    }
}

// ✅ Correct
@Composable
fun MyScreen() {
    LaunchedEffect(condition) {
        if (condition) {
            navController.navigate(Details())
        }
    }
}
```

### Don't: Pass complex objects as arguments — pass IDs instead

```kotlin
// ❌ Anti-pattern: complex object as argument
navController.navigate(ProfileRoute(user = complexUserObject))

// ✅ Correct: pass only the ID, fetch in ViewModel
navController.navigate(ProfileRoute(userId = "user123"))

// In ViewModel:
class ProfileViewModel(savedStateHandle: SavedStateHandle) : ViewModel() {
    private val route = savedStateHandle.toRoute<ProfileRoute>()
    val user = userRepository.getUser(route.userId)
}
```

### Don't: Mix navigation approaches
```kotlin
// ❌ Anti-pattern
navigation<Feature>(startDestination = "home") {
    composable("home") { } // String-based
    composable<Details> { } // Type-safe mixed with strings
}

// ✅ Correct
@Serializable
object FeatureHome

navigation<FeatureRoot>(startDestination = FeatureHome()) {
    composable<FeatureHome> { }
    composable<FeatureDetails> { }
}
```

---

## Navigation Events (One-Time Actions)

Use `Channel` + `receiveAsFlow()` to emit navigation events from the ViewModel — **not** `SharedFlow` or `StateFlow`.

`SharedFlow` replays to new collectors, which causes navigation to fire again when the UI resubscribes (e.g. after rotation). `Channel` delivers each event exactly once.

```kotlin
class LoginViewModel : ViewModel() {

    private val _navigationEvents = Channel<LoginNavEvent>()
    val navigationEvents = _navigationEvents.receiveAsFlow()

    fun onLoginSuccess() {
        viewModelScope.launch {
            _navigationEvents.send(LoginNavEvent.GoToHome)
        }
    }
}

sealed interface LoginNavEvent {
    data object GoToHome : LoginNavEvent
    data class ShowError(val message: String) : LoginNavEvent
}
```

Collect in the composable using `LaunchedEffect` with `Dispatchers.Main.immediate` to avoid a one-frame delay:

```kotlin
@Composable
fun LoginScreen(
    viewModel: LoginViewModel = hiltViewModel(),
    onNavigateToHome: () -> Unit
) {
    LaunchedEffect(Unit) {
        viewModel.navigationEvents
            .flowOn(Dispatchers.Main.immediate)
            .collect { event ->
                when (event) {
                    LoginNavEvent.GoToHome -> onNavigateToHome()
                    is LoginNavEvent.ShowError -> { /* show snackbar */ }
                }
            }
    }
}
```

**Why not `SharedFlow`?** A `SharedFlow(replay=0)` looks safe but still risks re-delivery if the subscriber briefly drops and resubscribes. `Channel` has strict single-consumer, exactly-once semantics.

---

## Adaptive Navigation

Use `NavigationSuiteScaffold` for responsive navigation — bottom bar on phones, side rail on tablets, automatically:

```kotlin
@Composable
fun AdaptiveApp() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            item(
                icon = { Icon(Icons.Default.Home, contentDescription = "Home") },
                label = { Text("Home") },
                selected = currentDestination?.hasRoute<Home>() == true,
                onClick = {
                    navController.navigate(Home) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                }
            )
        }
    ) {
        AppNavHost(navController = navController)
    }
}
```

---

## Testing Navigation

Use `TestNavHostController` to verify navigation destinations in instrumented tests.

```kotlin
// build.gradle.kts
androidTestImplementation("androidx.navigation:navigation-testing:2.8.x")
```

```kotlin
class NavigationTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private lateinit var navController: TestNavHostController

    @Before
    fun setUp() {
        composeTestRule.setContent {
            navController = TestNavHostController(LocalContext.current)
            navController.navigatorProvider.addNavigator(ComposeNavigator())
            AppNavHost(navController = navController)
        }
    }

    @Test
    fun `given home screen, when profile tapped, then navigates to profile`() {
        composeTestRule
            .onNodeWithText("View Profile")
            .performClick()

        assertTrue(
            navController.currentBackStackEntry?.destination?.hasRoute<Profile>() == true
        )
    }
}
```
