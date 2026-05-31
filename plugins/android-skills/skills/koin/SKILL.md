---
name: koin
description: Use when setting up or working with Koin in Android or KMP projects — module declarations with Classic DSL or KSP annotations, ViewModel injection in Compose, scopes, Nav 3 entry providers, application startup, and compile-time verification via `verify()`. Triggers on Koin, `single`, `factory`, `koinViewModel`, `koinInject`, `parametersOf`, `startKoin`, "KMP DI", "shared DI".
---

# Koin Dependency Injection (Android and KMP)

Pragmatic Kotlin DI — no annotation processor for the Classic DSL, full KMP support, and a `verify()` check that catches missing bindings at test time. **Koin vs Hilt:** Koin runs in `commonMain` (Hilt does not) and verifies the graph via `verify()` instead of codegen; Hilt is Android-only, validates the graph through codegen, and integrates deeply with Jetpack (`@HiltViewModel`, `hiltViewModel()`). Both are first-class. **Related:** `android-skills:kmp-ktor` (per-platform engine wired via Koin), `android-skills:android-data-layer`.

Dependencies (via `koin-bom`, so artifacts stay version-aligned): `koin-core` (KMP engine), `koin-android` (`Application`/`Context`), `koin-androidx-compose` (`koinViewModel`/`koinInject` on Android), `koin-compose-viewmodel` (KMP Compose), `koin-compose-viewmodel-navigation` (Nav 3), `koin-test`, and optional `koin-annotations` + `koin-ksp-compiler` for KSP.

## Module Declarations — Classic DSL

Constructor arguments resolve via `get()`.

```kotlin
val featureModule = module {
    single<HttpClient> { createHttpClient(get(), baseUrl = "https://api.example.com/") }
    single<UserRepository> { UserRepositoryImpl(get()) }
    factory { UserFormValidator() }
    viewModel { UserListViewModel(get()) }
    viewModel { (id: String) -> UserDetailViewModel(id, get()) }   // runtime param
}
```

| DSL | Lifecycle | Use for |
|---|---|---|
| `single { }` | App lifetime | Stateless services, repositories, API clients, databases |
| `factory { }` | New per call | Stateful/short-lived — validators, formatters (a `single` holding mutable state leaks across callers) |
| `scoped { }` | Scope lifetime | Shared within a flow (e.g. checkout) |
| `viewModel { }` | ViewModel lifecycle | Survives recomposition and config changes |

## Module Declarations — KSP Annotations

An alternative to the Classic DSL. **Pick one style per module** — mixing inside a single module forces reviewers to trace bindings across two systems. Switching styles *between* modules is fine. `@Module` + `@ComponentScan` discovers annotated classes and emits a generated module passed to `startKoin` as `UserModule().module`.

```kotlin
plugins { id("com.google.devtools.ksp") }
dependencies { implementation(libs.koin.annotations); ksp(libs.koin.ksp.compiler) }
@Single class UserRepositoryImpl(private val service: UserService) : UserRepository
@Factory class UserFormValidator
@KoinViewModel class UserDetailViewModel(
    @InjectedParam private val userId: String,
    private val repository: UserRepository,
) : ViewModel()
@Module @ComponentScan("com.example.feature.user") class UserModule
```

## KMP Source Set Layout

Most bindings live in `commonMain`. Platform-typed bindings (HTTP engine, Context, Keychain) go behind `expect val platformModule: Module` — mirrors `android-skills:kmp-ktor`'s per-platform engine pattern.

```kotlin
// commonMain
expect val platformModule: Module
val networkModule = module {
    single { createHttpClient(get(), baseUrl = "https://api.example.com/") }
    single { UserService(get()) }
}
// androidMain
actual val platformModule: Module = module {
    single<HttpClientEngine> { OkHttp.create() }
    single<TokenStorage> { DataStoreTokenStorage(get()) }
}
// iosMain
actual val platformModule: Module = module {
    single<HttpClientEngine> { Darwin.create() }
    single<TokenStorage> { KeychainTokenStorage() }
}
```

## Application Startup

`androidContext()` registers the `Application` so `get<Context>()` works in modules; declare `MyApp` with `android:name=".MyApp"`. On iOS, call `InitKoinKt.doInitKoin(config: nil)` from `iOSApp.init()` — Swift reserves `init`, hence the `do` prefix.

```kotlin
class MyApp : Application() {                                  // Android
    override fun onCreate() {
        super.onCreate()
        startKoin {
            androidLogger(); androidContext(this@MyApp)
            modules(appModule, networkModule, platformModule)
        }
    }
}
fun initKoin(config: KoinAppDeclaration? = null) = startKoin { // commonMain, called from Swift
    config?.invoke(this); modules(appModule, networkModule, platformModule)
}
```

## Using Koin in Compose

```kotlin
@Composable
fun UserDetailRoute(userId: String) {
    val viewModel: UserDetailViewModel = koinViewModel { parametersOf(userId) }
    val analytics: AnalyticsService = koinInject()
    // Keyed — unique instance per entity:
    // koinViewModel<UserDetailViewModel>(key = "detail_$userId", parameters = { parametersOf(userId) })
    UserDetailScreen(state = viewModel.state.collectAsState().value)
}
```

`koinViewModel` requires `koin-androidx-compose` (Android) or `koin-compose-viewmodel` (KMP). Without it the call **compiles but fails at the call site** — `koin-core` knows nothing about `ViewModel` or the Compose runtime. For testability, pass dependencies as composable params with `koinInject()` defaults: `fun Screen(service: AnalyticsService = koinInject())`.

## Scopes

Bind a dependency to a lifecycle narrower than singleton — state shared across a small set of screens. On Android, `activityRetainedScope { }` survives configuration changes.

```kotlin
val checkoutModule = module {
    scope<CheckoutFlow> {
        scoped { CheckoutCart() }
        scoped { CheckoutPricing(get()) }
        viewModel { CheckoutViewModel(get(), get()) }
    }
}
val scope = getKoin().createScope<CheckoutFlow>("checkout-$orderId")
val cart: CheckoutCart = scope.get()
scope.close()   // when the flow ends
```

## Nav 3 Integration

`koinEntryProvider()` resolves ViewModels per destination; destinations register inside modules rather than inline at the `NavDisplay` site.

```kotlin
val navigationModule = module {
    navigation<HomeRoute> { HomeScreen(viewModel = koinViewModel()) }
    navigation<DetailRoute> { route -> DetailScreen(viewModel = koinViewModel { parametersOf(route.id) }) }
}
NavDisplay(backStack = backStack, onBack = { backStack.removeLastOrNull() }, entryProvider = koinEntryProvider())
```

## Testing

`verify()` / `checkModules()` walks each declaration's constructor and confirms every dependency is declared — missing bindings become **test failures instead of runtime `NoDefinitionFoundException`** (recovering one of Hilt's advantages). Run it in CI. For constructor params resolved at runtime (e.g. `SavedStateHandle`), pass `extraTypes` or `verify()` false-fails. Override real bindings with fakes — e.g. Ktor's `MockEngine` (see `android-skills:kmp-ktor`). `KoinTestRule` (JUnit 4) / `KoinTestExtension` (JUnit 5) installs a context per test.

```kotlin
class ModuleVerificationTest : KoinTest {
    @Test fun `all modules resolve cleanly`() {
        koinApplication { modules(appModule, networkModule, platformModule) }.checkModules()
    }
    // Per-module with runtime-resolved types:
    // featureModule.verify(extraTypes = listOf(SavedStateHandle::class))
}
```
