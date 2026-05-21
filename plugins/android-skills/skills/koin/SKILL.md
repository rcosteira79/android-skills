---
name: koin
description: Use when setting up or working with Koin in Android or KMP projects — module declarations with Classic DSL or KSP annotations, ViewModel injection in Compose, scopes, Nav 3 entry providers, application startup, and compile-time verification via `verify()`. Triggers on Koin, `single`, `factory`, `koinViewModel`, `koinInject`, `parametersOf`, `startKoin`, "KMP DI", "shared DI".
---

# Koin Dependency Injection (Android and KMP)

Adapted from [Meet-Miyani/compose-skill](https://github.com/Meet-Miyani/compose-skill)'s Koin reference. MIT licensed.

Koin is a pragmatic Kotlin DI library — no annotation processor required for the Classic DSL, full KMP support, and a `verify()` check that catches missing bindings at test time. **Pick Koin when** the project targets KMP (Hilt does not run in `commonMain`), the team wants compile-time verification via `verify()` rather than annotation-processor codegen, or build speed matters and an annotation processor is unwelcome. **Pick Hilt when** the project is Android-only, the team wants compile-time DI graph validation enforced by codegen, or deep Jetpack integration (`@HiltViewModel`, `@HiltAndroidApp`, `hiltViewModel()`) is desired — both are first-class. **Related skills:** `android-skills:kmp-ktor` (per-platform engine pattern wired via Koin), `android-skills:android-retrofit` and `android-skills:android-data-layer` (Hilt-centric equivalents).

## Dependencies

Use the BOM (`koin-bom`) so artifacts stay version-aligned. Core artifacts: `koin-core` (KMP engine), `koin-android` (Android `Application`/`Context` integration), `koin-androidx-compose` (`koinViewModel`/`koinInject` on Android), `koin-compose-viewmodel` (KMP Compose), `koin-compose-viewmodel-navigation` (Nav 3), `koin-test` (`checkModules`, `KoinTest`, `KoinTestRule`), `koin-annotations` + `koin-ksp-compiler` (KSP module generation). Android-only modules import `platform(koin-bom)` + `koin-android` + `koin-androidx-compose` + `koin-compose-viewmodel-navigation`. KMP `commonMain` imports `koin-core` + `koin-compose-viewmodel`; `androidMain` adds `koin-android` + `koin-androidx-compose`.

## Module Declarations — Classic DSL

Constructor arguments resolve via `get()`. ViewModel binding requires `koin-androidx-compose` (Android) or `koin-compose-viewmodel` (KMP).

```kotlin
val featureModule = module {
    single<HttpClient> { createHttpClient(get(), baseUrl = "https://api.example.com/") }
    single<UserRepository> { UserRepositoryImpl(get()) }
    factory { UserFormValidator() }
    viewModel { UserListViewModel(get()) }
    viewModel { (id: String) -> UserDetailViewModel(id, get()) }   // runtime param
}
```

| DSL | Lifecycle | When to use |
|---|---|---|
| `single { }` | App lifetime | Stateless services, repositories, API clients, databases |
| `factory { }` | New per call | Stateful/short-lived — validators, formatters |
| `scoped { }` | Scope lifetime | Shared within a flow (e.g. checkout) |
| `viewModel { }` | ViewModel lifecycle | Survives recomposition and config changes |

## Module Declarations — KSP Annotations

An alternative to the Classic DSL. Pick one style per module — mixing inside a single module hides ownership. `@Module` + `@ComponentScan` discovers annotated classes in the package and emits a generated module passed to `startKoin` as `UserModule().module`.

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
// androidMain — engine + Android-specific storage
actual val platformModule: Module = module {
    single<HttpClientEngine> { OkHttp.create() }
    single<TokenStorage> { DataStoreTokenStorage(get()) }
}
// iosMain — engine + iOS-specific storage
actual val platformModule: Module = module {
    single<HttpClientEngine> { Darwin.create() }
    single<TokenStorage> { KeychainTokenStorage() }
}
```

## Application Startup

`androidContext()` registers the `Application` so `get<Context>()` works in modules; declare `MyApp` with `android:name=".MyApp"` in `AndroidManifest.xml`. On iOS, call `InitKoinKt.doInitKoin(config: nil)` from `iOSApp.init()` — Swift reserves `init`, hence the `do` prefix.

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

For testability, pass dependencies as composable parameters with `koinInject()` defaults: `fun Screen(service: AnalyticsService = koinInject())`.

```kotlin
@Composable
fun UserDetailRoute(userId: String) {
    val viewModel: UserDetailViewModel = koinViewModel { parametersOf(userId) }
    val analytics: AnalyticsService = koinInject()
    // Keyed — unique instance per entity: koinViewModel<UserDetailViewModel>(key = "detail_$userId", parameters = { parametersOf(userId) })
    UserDetailScreen(state = viewModel.state.collectAsState().value)
}
```

## Scopes

Scopes bind dependencies to a lifecycle narrower than singleton — for state shared across a small set of screens but not the whole app. On Android, `activityRetainedScope { }` survives configuration changes.

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

`koinEntryProvider()` resolves ViewModels per Nav 3 destination. Destinations register inside Koin modules rather than inline at the `NavDisplay` call site.

```kotlin
val navigationModule = module {
    navigation<HomeRoute> { HomeScreen(viewModel = koinViewModel()) }
    navigation<DetailRoute> { route -> DetailScreen(viewModel = koinViewModel { parametersOf(route.id) }) }
}
NavDisplay(backStack = backStack, onBack = { backStack.removeLastOrNull() }, entryProvider = koinEntryProvider())
```

## Testing

`verify()` walks each declaration's constructor and confirms every dependency is declared in the graph. Missing bindings become test failures instead of runtime `NoDefinitionFoundException`s. For integration tests, override `single<HttpClientEngine>` with Ktor's `MockEngine` (see `android-skills:kmp-ktor`). `KoinTestRule` (JUnit 4) or `KoinTestExtension` (JUnit 5) installs a Koin context per test.

```kotlin
class ModuleVerificationTest : KoinTest {
    @Test fun `all modules resolve cleanly`() {
        koinApplication { modules(appModule, networkModule, platformModule) }.checkModules()
    }
    // Per-module check with runtime-resolved types: featureModule.verify(extraTypes = listOf(SavedStateHandle::class))
}
```

## RIGHT vs WRONG Patterns

### Service locator vs constructor injection

```kotlin
// WRONG — pulling dependencies from Koin inside a class
class UserController {
    private val repository: UserRepository = KoinJavaComponent.get(UserRepository::class.java)
}
// RIGHT — constructor injection wired in a module
class UserController(private val repository: UserRepository)   // module { factory { UserController(get()) } }
```

WRONG because reaching into the container hides dependencies from the type signature, prevents `verify()` from catching missing bindings, and makes the class hard to test without spinning up a real Koin context.

### Mixing Classic DSL and KSP annotations in the same module

```kotlin
// WRONG — split ownership inside one module: @Single declares UserRepositoryImpl, DSL declares UserService
@Single class UserRepositoryImpl(...) : UserRepository
val userModule = module { single<UserService> { UserService(get()) } }
// RIGHT — single source of truth per module (here, Classic DSL)
val userModule = module {
    single<UserService> { UserService(get()) }
    single<UserRepository> { UserRepositoryImpl(get()) }
}
```

WRONG because reviewers must trace bindings across two systems to know whether a dependency comes from the DSL block or a generated module. Switching styles between modules is fine; inside a single module the source of truth must be unambiguous.

### Not running `verify()` in tests

```kotlin
// WRONG — UserDetailViewModel requires AnalyticsService but no single<AnalyticsService> is registered.
// Crashes the first time koinViewModel<UserDetailViewModel>() runs: NoDefinitionFoundException.
// RIGHT — checkModules() catches the missing binding in CI
@Test fun `all modules resolve`() {
    koinApplication { modules(appModule, networkModule, platformModule) }.checkModules()
}
```

WRONG because Koin lookup is runtime by default — missing bindings surface only when the user navigates to the affected screen. `checkModules()` in CI shifts the failure to build time, recovering one of Hilt's main advantages without giving up Koin's flexibility.

### `viewModel { }` without `koin-androidx-compose`

```kotlin
// WRONG — koin-core only; koinViewModel() is not on the classpath
implementation("io.insert-koin:koin-core")
val viewModel: UserListViewModel = koinViewModel()      // unresolved reference
// RIGHT — add the Compose integration module
implementation("io.insert-koin:koin-androidx-compose")  // Android
implementation("io.insert-koin:koin-compose-viewmodel") // KMP
```

WRONG because `koin-core` knows nothing about `ViewModel` or the Compose runtime. `viewModel { }` compiles without the integration artifact but fails at the call site.

### `single` for stateful per-request objects

```kotlin
// WRONG — singleton holding mutable per-request state; request A's errors leak into request B
class UserFormValidator { private val errors = mutableListOf<String>() }
val module = module { single { UserFormValidator() } }
// RIGHT — factory issues a fresh instance per call
val module = module { factory { UserFormValidator() } }
```

WRONG because `single` makes one instance for the whole app — stateful objects accumulate state across unrelated callers. Use `factory` for anything that mutates instance state during use.

## Checklist

- [ ] BOM (`koin-bom`) imported so artifacts stay version-aligned
- [ ] One DSL style per module — Classic DSL or KSP annotations, not both
- [ ] Constructor injection everywhere; no `KoinJavaComponent.get()` in production code
- [ ] `single` for stateless/app-lifetime objects; `factory` for stateful ones
- [ ] `viewModel { }` bindings backed by `koin-androidx-compose` or `koin-compose-viewmodel`
- [ ] KMP platform bindings declared in `expect val platformModule: Module` with per-target actuals
- [ ] `startKoin` called once at app startup; `androidContext()` set on Android
- [ ] `verify()` / `checkModules()` test running in CI for every Koin module
- [ ] Test modules override real bindings with fakes (e.g. `MockEngine` for Ktor — see `android-skills:kmp-ktor`)
