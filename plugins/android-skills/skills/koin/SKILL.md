---
name: koin
description: Use when setting up or working with Koin in Android or KMP projects — module declarations with Classic DSL or KSP annotations, ViewModel injection in Compose, scopes, Nav 3 entry providers, application startup, and compile-time verification via `verify()`. Triggers on Koin, `single`, `factory`, `koinViewModel`, `koinInject`, `parametersOf`, `startKoin`, "KMP DI", "shared DI".
---

# Koin Dependency Injection (Android and KMP)

Pragmatic Kotlin DI. **Koin vs Hilt:** Koin runs in `commonMain` (Hilt doesn't) and verifies the graph via `verify()` instead of codegen; Hilt is Android-only with codegen + deep Jetpack integration (`@HiltViewModel` / `hiltViewModel()`). This reference covers the traps and boundaries, not the Classic DSL basics (`single` / `factory` / `scoped` / `viewModel { }` with `get()` resolution and runtime params, `koinViewModel` / `koinInject`, `startKoin { androidLogger(); androidContext(this@MyApp); modules(...) }`). **Related:** `android-skills:kmp-ktor`, `android-skills:android-data-layer`. Deps via `koin-bom`: `koin-core`, `koin-android`, `koin-androidx-compose`, `koin-compose-viewmodel` (KMP), `koin-compose-viewmodel-navigation` (Nav 3), `koin-test`, + optional `koin-annotations` / `koin-ksp-compiler`.

## KSP Annotations — the generated-module accessor

`@Module @ComponentScan` discovers annotated classes and emits a module you pass to `startKoin` as **`UserModule().module`** — the generated `.module` extension on the annotated class is the part most often missed. Pick one style per module (don't mix Classic DSL + annotations inside a single module; switching *between* modules is fine).

```kotlin
@Single class UserRepositoryImpl(private val service: UserService) : UserRepository
@Factory class UserFormValidator
@KoinViewModel class UserDetailViewModel(
    @InjectedParam private val userId: String,
    private val repository: UserRepository,
) : ViewModel()
@Module @ComponentScan("com.example.feature.user") class UserModule
// startKoin { modules(UserModule().module) }
```

## KMP source-set layout

Most bindings live in `commonMain`; platform-typed ones (HTTP engine, `Context`, Keychain) go behind `expect val platformModule: Module` with an `actual` per platform (mirrors `android-skills:kmp-ktor`'s engine pattern). iOS startup: call `InitKoinKt.doInitKoin(config: nil)` from `iOSApp.init()` — Swift reserves `init`, hence the `do` prefix.

```kotlin
// commonMain
expect val platformModule: Module
// androidMain: actual = module { single<HttpClientEngine> { OkHttp.create() }; single<TokenStorage> { DataStoreTokenStorage(get()) } }
// iosMain:     actual = module { single<HttpClientEngine> { Darwin.create() }; single<TokenStorage> { KeychainTokenStorage() } }
```

## Compose: the call-site failure

`koinViewModel` / `koinInject` require `koin-androidx-compose` (Android) or `koin-compose-viewmodel` (KMP). Without that artifact the call **compiles but fails at the call site** — `koin-core` knows nothing about `ViewModel` or the Compose runtime. For testability, default composable params to `koinInject()`: `fun Screen(service: AnalyticsService = koinInject())`.

```kotlin
val vm: UserDetailViewModel = koinViewModel { parametersOf(userId) }
// keyed per entity: koinViewModel(key = "detail_$userId", parameters = { parametersOf(userId) })
```

## Scopes

**Survives configuration changes (the common case) → `activityRetainedScope`** — backed by the Activity's retained `ViewModel`, so it lives across rotation and closes on real finish. Declare with `activityRetainedScope { }` (or `@ActivityRetainedScope`) and access via `AndroidScopeComponent`; do **not** hand-roll `createScope` / `close` for this case.

```kotlin
val checkoutModule = module {
    activityRetainedScope {                 // retained across config changes
        scoped { CheckoutCart() }
        scoped { CheckoutPricing(get()) }
    }
}
class CheckoutActivity : AppCompatActivity(), AndroidScopeComponent {
    override val scope: Scope by activityRetainedScope()
    private val cart: CheckoutCart by inject()
}
```

**Custom lifetime not tied to an Activity** (e.g. a multi-step flow keyed by an order id) → declare a `scope<T>` and own its lifecycle: `getKoin().createScope<CheckoutFlow>("checkout-$orderId")`, resolve with `scope.get()`, and `scope.close()` when the flow ends.

## Nav 3

`koinEntryProvider()` resolves ViewModels per destination; register destinations inside modules, not inline at the `NavDisplay` site.

```kotlin
val navigationModule = module {
    navigation<HomeRoute> { HomeScreen(viewModel = koinViewModel()) }
    navigation<DetailRoute> { route -> DetailScreen(viewModel = koinViewModel { parametersOf(route.id) }) }
}
NavDisplay(backStack = backStack, onBack = { backStack.removeLastOrNull() }, entryProvider = koinEntryProvider())
```

## Testing — `verify()` / `checkModules()`

Walks each declaration's constructor and confirms every dependency is declared — missing bindings become **test failures instead of a runtime `NoDefinitionFoundException`** (recovering one of Hilt's advantages). Run it in CI. For constructor params resolved at runtime (e.g. `SavedStateHandle`), pass `extraTypes` or `verify()` false-fails. Override real bindings with fakes (e.g. Ktor `MockEngine` — see `android-skills:kmp-ktor`). `KoinTestRule` (JUnit 4) / `KoinTestExtension` (JUnit 5) installs a context per test.

```kotlin
class ModuleVerificationTest : KoinTest {
    @Test fun `all modules resolve cleanly`() {
        koinApplication { modules(appModule, networkModule, platformModule) }.checkModules()
    }
    // Per-module with runtime-resolved types:
    // featureModule.verify(extraTypes = listOf(SavedStateHandle::class))
}
```
