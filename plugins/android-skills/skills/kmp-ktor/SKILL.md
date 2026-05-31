---
name: kmp-ktor
description: Use when setting up or working with Ktor client in KMP or Android projects — HttpClient configuration, per-platform engine selection, kotlinx.serialization, bearer auth with refresh, MockEngine testing, and error mapping at the repository boundary.
---

# Ktor Client for KMP and Android

Modern Ktor client setup for Kotlin Multiplatform and Android projects using `kotlinx.serialization`, the `Auth` plugin for bearer tokens, and `MockEngine` for testing. The same `HttpClient` configuration runs on Android, iOS, Desktop, and Web — only the engine changes per platform.

**Related skills:** See `android-skills:android-data-layer` for the Repository pattern, error propagation model, and offline-first strategies. See `android-skills:android-retrofit` for the equivalent Android-only setup with Retrofit.

---

## Dependencies and Platform Engines

Ktor's `HttpClient` is platform-agnostic — only the underlying engine is platform-specific. Pick one engine per source set.

### Per-platform engine selection

| Platform | Engine | Dependency |
|----------|--------|------------|
| Android | OkHttp | `ktor-client-okhttp` |
| iOS | Darwin (NSURLSession) | `ktor-client-darwin` |
| JVM/Desktop | CIO (or OkHttp) | `ktor-client-cio` |
| JS/Wasm | JS | `ktor-client-js` |
| Tests (any platform) | MockEngine | `ktor-client-mock` |

### Version catalog

```toml
[versions]
ktor = "<latest>"  # verify at https://ktor.io/docs/releases.html

[libraries]
ktor-client-core = { module = "io.ktor:ktor-client-core", version.ref = "ktor" }
ktor-client-content-negotiation = { module = "io.ktor:ktor-client-content-negotiation", version.ref = "ktor" }
ktor-serialization-kotlinx-json = { module = "io.ktor:ktor-serialization-kotlinx-json", version.ref = "ktor" }
ktor-client-logging = { module = "io.ktor:ktor-client-logging", version.ref = "ktor" }
ktor-client-auth = { module = "io.ktor:ktor-client-auth", version.ref = "ktor" }
ktor-client-okhttp = { module = "io.ktor:ktor-client-okhttp", version.ref = "ktor" }
ktor-client-darwin = { module = "io.ktor:ktor-client-darwin", version.ref = "ktor" }
ktor-client-cio = { module = "io.ktor:ktor-client-cio", version.ref = "ktor" }
ktor-client-mock = { module = "io.ktor:ktor-client-mock", version.ref = "ktor" }
```

### Source set wiring

```kotlin
commonMain.dependencies {
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.ktor.client.logging)
    implementation(libs.ktor.client.auth)
}

androidMain.dependencies {
    implementation(libs.ktor.client.okhttp)
}

iosMain.dependencies {
    implementation(libs.ktor.client.darwin)
}

commonTest.dependencies {
    implementation(libs.ktor.client.mock)
}
```

The engine module belongs in the platform source set. The factory is provided via `expect/actual` or DI — see DI Setup below.

---

## HttpClient Configuration

Create a single `HttpClient` instance and reuse it. Each `HttpClient` owns a connection pool, dispatcher threads, and plugin state — creating one per request leaks resources and defeats keep-alive.

```kotlin
fun createHttpClient(
    engine: HttpClientEngine,
    baseUrl: String,
    isDebug: Boolean = false,
): HttpClient = HttpClient(engine) {
    install(ContentNegotiation) {
        json(Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
            encodeDefaults = true  // include default-valued fields when serializing — see RIGHT vs WRONG below
        })
    }

    defaultRequest {
        url(baseUrl)
        headers.append(HttpHeaders.Accept, ContentType.Application.Json.toString())
    }

    install(HttpTimeout) {
        connectTimeoutMillis = 15_000
        requestTimeoutMillis = 30_000
        socketTimeoutMillis = 15_000
    }

    install(Logging) {
        logger = Logger.DEFAULT
        level = if (isDebug) LogLevel.BODY else LogLevel.HEADERS
        sanitizeHeader { it.equals(HttpHeaders.Authorization, ignoreCase = true) }
    }

    expectSuccess = true  // Ktor throws ClientRequestException / ServerResponseException on non-2xx
}
```

`expectSuccess = true` matches the try/catch error model used by the Repository pattern below. If you prefer to inspect status codes manually, set `expectSuccess = false` and apply that choice consistently across the project — never mix the two.

| Setting | Behavior | Use when |
|---|---|---|
| `true` (used above) | Throws `ClientRequestException` / `ServerResponseException` on non-2xx | Pairing with `try/catch` at the repository boundary — matches the pattern in this skill |
| `false` | Returns the response regardless of status | Inspecting `response.status` manually in a custom wrapper (see "Advanced: Sealed `ApiResult<T>`" below) |

### Plugin install order

Plugins execute in installation order for outgoing requests and reverse order for responses. The order that holds up across most projects:

```
ContentNegotiation → Auth → HttpRequestRetry → HttpTimeout → ContentEncoding
```

The two installs that interact in non-obvious ways:

- **`HttpRequestRetry` before `HttpTimeout`** — retries should be able to catch timeout errors. Reversing this skips timeouts because `HttpTimeout` resolves the request as failed before the retry plugin sees the response.
- **`Auth` plugin handles 401s independently from `HttpRequestRetry`** — let `Auth` do the bearer refresh dance; let `HttpRequestRetry` cover transient network failures and 5xx. Don't try to chain them around the same status code.

---

## Service Layer

Wrap `HttpClient` in a typed service class. Service methods return DTOs — mapping to domain models happens in the repository.

```kotlin
class UserService(private val client: HttpClient) {

    suspend fun listUsers(page: Int = 1): UserListDto =
        client.get("users") {
            parameter("page", page)
        }.body()

    suspend fun getUser(id: String): UserDto =
        client.get("users/$id").body()

    suspend fun createUser(request: CreateUserDto): UserDto =
        client.post("users") {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

    suspend fun deleteUser(id: String) {
        client.delete("users/$id")
    }
}
```

Path parameters use Kotlin string templates. Query parameters use `parameter("key", value)`. Request bodies use `setBody(request)` paired with `contentType(ContentType.Application.Json)`.

---

## DTOs and Mapping

DTOs are `@Serializable` and mirror the API contract exactly. Domain models have no serialization annotations.

```kotlin
@Serializable
data class UserDto(
    val id: String,
    val name: String,
    @SerialName("created_at") val createdAt: Long,
)

data class User(val id: String, val name: String, val createdAt: Instant)

fun UserDto.toDomain(): User = User(
    id = id,
    name = name,
    createdAt = Instant.fromEpochMilliseconds(createdAt),
)
```

Use `@SerialName` when JSON keys differ from Kotlin field names. Provide defaults for optional fields so missing keys don't throw.

---

## Repository — Error Handling

Catch Ktor exceptions at the repository layer and map to domain error types. Never let `ClientRequestException`, `ServerResponseException`, `HttpRequestTimeoutException`, or `IOException` reach the ViewModel. See `android-skills:android-data-layer` for the full repository pattern.

```kotlin
class UserRepository(private val service: UserService) {

    suspend fun getUser(id: String): Result<User> = try {
        Result.success(service.getUser(id).toDomain())
    } catch (e: ClientRequestException) {  // 4xx
        Result.failure(DataError.Server(e.response.status.value, e.message))
    } catch (e: ServerResponseException) {  // 5xx
        Result.failure(DataError.Server(e.response.status.value, e.message))
    } catch (e: HttpRequestTimeoutException) {
        Result.failure(DataError.Network(e))
    } catch (e: IOException) {
        Result.failure(DataError.Network(e))
    }
}

// Reuse the same error hierarchy across the data layer — see android-skills:android-data-layer
sealed class DataError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Network(cause: Throwable) : DataError("Network error", cause)
    class Server(val code: Int, message: String?) : DataError("Server error $code: $message")
    class Local(cause: Throwable) : DataError("Local storage error", cause)
}
```

Catch specific Ktor exception types — `catch (e: Exception)` would swallow `CancellationException` and break structured concurrency. See `android-skills:kotlin-flows` for the full pattern.

### Advanced: sealed `ApiResult<T>` with `expectSuccess = false`

The `Result<T>` + `DataError` pattern above is the default. When error handling needs structured per-error-type data — distinct UI states for `Unauthorized`, `RateLimited`, `Forbidden`, `SerializationError`, `Timeout` — a sealed `ApiResult<T>` paired with `expectSuccess = false` and a `safeRequest` wrapper is the alternative shape:

```kotlin
sealed class ApiResult<out T> {
    data class Success<T>(val data: T) : ApiResult<T>()
    sealed class Failure : ApiResult<Nothing>() {
        data class HttpError(val code: Int, val message: String, val serverMessage: String? = null) : Failure()
        data class NetworkError(val message: String) : Failure()
        data class SerializationError(val message: String) : Failure()
        data class Timeout(val message: String) : Failure()
        data class Unauthorized(val serverMessage: String? = null) : Failure()
        data class Unknown(val cause: Throwable) : Failure()
    }
}

suspend inline fun <reified T> HttpClient.safeRequest(
    block: HttpRequestBuilder.() -> Unit,
): ApiResult<T> = try {
    val response = request { block() }
    when (response.status.value) {
        in 200..299 -> ApiResult.Success(response.body<T>())
        401 -> ApiResult.Failure.Unauthorized()
        in 400..499 -> ApiResult.Failure.HttpError(response.status.value, "Request failed")
        in 500..599 -> ApiResult.Failure.HttpError(response.status.value, "Server error")
        else -> ApiResult.Failure.HttpError(response.status.value, "Unexpected status")
    }
} catch (e: CancellationException) {
    throw e  // never swallow — breaks structured concurrency
} catch (e: HttpRequestTimeoutException) {
    ApiResult.Failure.Timeout("Request timed out")
} catch (e: IOException) {
    ApiResult.Failure.NetworkError("No internet connection")
} catch (e: SerializationException) {
    ApiResult.Failure.SerializationError("Invalid response format")
} catch (e: Exception) {
    ApiResult.Failure.Unknown(e)
}
```

Configure the client with `expectSuccess = false` when using this wrapper — the wrapper inspects `response.status.value` itself rather than relying on Ktor to throw.

| Pattern | Pick when |
|---|---|
| `Result<T>` + `DataError` (default) | Three or four UI states are enough (`Loading`, `Success`, `Network error`, `Server error`); team prefers Kotlin stdlib types |
| `ApiResult<T>` + `safeRequest` (advanced) | UI needs distinct surface for `Unauthorized`, `RateLimited`, `Forbidden`, etc.; team prefers exhaustive `when` matching at the ViewModel boundary |

Pick one per project. Mixing both produces inconsistent error surfaces and confused reviewers.

---

## Bearer Token Authentication

Use Ktor's `Auth` plugin with `bearer`. The plugin loads the cached token, attaches it to outgoing requests, and refreshes on 401 automatically.

```kotlin
fun createAuthenticatedClient(
    engine: HttpClientEngine,
    baseUrl: String,
    tokenStorage: TokenStorage,
    onSessionExpired: () -> Unit,
): HttpClient = HttpClient(engine) {
    install(ContentNegotiation) {
        json(Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        })
    }
    defaultRequest { url(baseUrl) }

    install(Auth) {
        bearer {
            loadTokens {
                val tokens = tokenStorage.getTokens() ?: return@loadTokens null
                BearerTokens(tokens.access, tokens.refresh)
            }

            refreshTokens {
                val refresh = oldTokens?.refreshToken ?: return@refreshTokens null
                try {
                    markAsRefreshTokenRequest()  // skip Auth plugin for this call
                    val response = client.post("auth/refresh") {
                        contentType(ContentType.Application.Json)
                        setBody(RefreshRequestDto(refresh))
                    }.body<TokenResponseDto>()

                    tokenStorage.save(response.accessToken, response.refreshToken)
                    BearerTokens(response.accessToken, response.refreshToken)
                } catch (e: Exception) {
                    onSessionExpired()
                    null
                }
            }

            sendWithoutRequest { request ->
                request.url.pathSegments.none { it in listOf("login", "register") }
            }
        }
    }
}
```

`markAsRefreshTokenRequest()` prevents the refresh call from being intercepted by the same `Auth` plugin — without it, a failing refresh would trigger another refresh, looping infinitely.

`TokenStorage` is a project-defined interface (DataStore on Android/JVM, Keychain on iOS). Keep `BearerTokens` at the plugin boundary only; the rest of the app uses your own token type.

---

## DI Setup

### Koin (KMP)

Engine factory lives in platform modules; the rest is shared.

```kotlin
// commonMain
val networkModule = module {
    single { createHttpClient(get(), baseUrl = "https://api.example.com/") }
    single { UserService(get()) }
}

expect val engineModule: Module

// androidMain
actual val engineModule: Module = module {
    single<HttpClientEngine> { OkHttp.create() }
}

// iosMain
actual val engineModule: Module = module {
    single<HttpClientEngine> { Darwin.create() }
}
```

### Hilt (Android-only projects)

Hilt does not run in `commonMain`. For pure Android projects:

```kotlin
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {
    @Provides @Singleton
    fun provideHttpClient(): HttpClient =
        createHttpClient(OkHttp.create(), baseUrl = "https://api.example.com/")

    @Provides @Singleton
    fun provideUserService(client: HttpClient): UserService = UserService(client)
}
```

For KMP projects that also want Hilt on Android, expose the `HttpClient` from a Koin module in `commonMain` and have a Hilt `@Provides` method on the Android side fetch it from Koin — or use Koin throughout the project.

---

## Testing with MockEngine

Inject `HttpClientEngine` into the factory so tests can swap in `MockEngine`. Reuse the production `createHttpClient` factory so plugin configuration matches.

```kotlin
@Test
fun `getUser maps DTO to domain`() = runTest {
    val mockEngine = MockEngine { request ->
        assertEquals("/users/42", request.url.encodedPath)
        respond(
            content = """{"id":"42","name":"Ada","created_at":1700000000000}""",
            status = HttpStatusCode.OK,
            headers = headersOf(HttpHeaders.ContentType, "application/json"),
        )
    }
    val client = createHttpClient(mockEngine, baseUrl = "https://api.example.com/")
    val repo = UserRepository(UserService(client))

    val result = repo.getUser("42").getOrThrow()

    assertEquals("Ada", result.name)
}

@Test
fun `getUser maps 404 to DataError-Server`() = runTest {
    val mockEngine = MockEngine {
        respond(content = """{"error":"not found"}""", status = HttpStatusCode.NotFound)
    }
    val client = createHttpClient(mockEngine, baseUrl = "https://api.example.com/")
    val repo = UserRepository(UserService(client))

    val error = repo.getUser("999").exceptionOrNull()

    assertIs<DataError.Server>(error)
    assertEquals(404, error.code)
}
```

For multi-route tests, branch on `request.url.encodedPath` inside the `MockEngine` lambda. See `android-skills:android-testing` for how Ktor fakes fit the three-tier test model.

---

## WebSockets and Server-Sent Events

Real-time transports — pick based on direction and reconnection needs.

| Criterion | SSE (`ktor-client-core`) | WebSockets (`ktor-client-websockets`) |
|---|---|---|
| Direction | Server → client only | Bidirectional |
| Protocol | HTTP (standard) | WebSocket (protocol upgrade) |
| Auto-reconnect | Built-in | Manual (caller writes the loop) |
| Binary frames | Text only | Text and binary |
| Typical use | Live feeds, notifications, progress, streaming AI tokens | Chat, gaming, real-time collaboration |

Default to SSE when the client only consumes. Use WebSockets when the client also publishes.

### WebSocket — typed messages

```kotlin
val client = HttpClient(engine) {
    install(WebSockets) {
        pingIntervalMillis = 30_000
        contentConverter = KotlinxWebsocketSerializationConverter(Json)
    }
}

client.webSocket("wss://api.example.com/ws") {
    sendSerialized(SubscribeMessage(topic = "items"))
    while (true) {
        val message = receiveDeserialized<ServerMessage>()
        // handle message
    }
}
```

`KotlinxWebsocketSerializationConverter` lifts `sendSerialized` / `receiveDeserialized` over the same `kotlinx.serialization` configuration as `ContentNegotiation`. Without it, the caller has to encode/decode `Frame.Text` manually.

For external control (sending from outside the `webSocket {}` lambda), keep the session reference:

```kotlin
val session = client.webSocketSession("wss://api.example.com/ws")
session.sendSerialized(Ping)
val message = session.receiveDeserialized<Pong>()
session.close()
```

### Server-Sent Events

```kotlin
val client = HttpClient(engine) {
    install(SSE)
}

client.sse("https://api.example.com/events") {
    incoming.collect { event ->
        // event.event = "message" | "delta" | …
        // event.data, event.id, event.retry
    }
}
```

The `incoming` flow is a `Flow<ServerSentEvent>`. Wrap collection in a `LaunchedEffect` or repository coroutine so cancellation propagates and the HTTP connection closes when the consumer goes away.

---

## RIGHT vs WRONG Patterns

### `HttpClient` lifecycle

```kotlin
// WRONG — new client per call; leaks the connection pool, defeats keep-alive
suspend fun listUsers(): List<User> {
    val client = HttpClient(OkHttp) {
        install(ContentNegotiation) { json() }
    }
    return client.get("https://api.example.com/users").body()
}  // client.close() never called — resource leak

// RIGHT — single client provided via DI; reused across all calls
class UserService(private val client: HttpClient) {
    suspend fun listUsers(): List<UserDto> = client.get("users").body()
}
```

WRONG because each `HttpClient` owns its own connection pool, dispatcher threads, and plugin state. Creating one per request wastes resources, prevents connection reuse, and accumulates background threads. A single shared instance — provided via DI — is the only correct lifecycle.

### Bearer auth: plugin vs per-request header

```kotlin
// WRONG — token attached to every request manually
suspend fun getProfile(token: String): Profile =
    client.get("user/profile") {
        headers.append(HttpHeaders.Authorization, "Bearer $token")
    }.body()

// Caller must thread the token through every call site, and refresh logic lives nowhere

// RIGHT — Auth plugin handles loading, attaching, and refreshing
install(Auth) {
    bearer {
        loadTokens { /* ... */ }
        refreshTokens { /* ... */ }
    }
}

// Service code is auth-agnostic:
suspend fun getProfile(): Profile = client.get("user/profile").body()
```

WRONG because manually attaching the token at every call site duplicates logic, makes refresh-on-401 impossible without bespoke retry code, and breaks the moment one endpoint is missed. The `Auth` plugin centralizes all three concerns (load, attach, refresh) and runs uniformly across every request.

### Network exceptions leaking to the ViewModel

```kotlin
// WRONG — ViewModel catches Ktor exceptions; couples UI to network internals
class UserViewModel(private val service: UserService) : ViewModel() {
    fun load(id: String) = viewModelScope.launch {
        try {
            _state.value = UiState.Success(service.getUser(id).toDomain())
        } catch (e: ClientRequestException) {
            _state.value = UiState.Error("HTTP ${e.response.status.value}")
        } catch (e: IOException) {
            _state.value = UiState.Error("No connection")
        }
    }
}

// RIGHT — repository maps to DataError; ViewModel handles domain types only
class UserViewModel(private val repository: UserRepository) : ViewModel() {
    fun load(id: String) = viewModelScope.launch {
        repository.getUser(id)
            .onSuccess { _state.value = UiState.Success(it) }
            .onFailure { error ->
                _state.value = when (error) {
                    is DataError.Network -> UiState.Error("Check your connection")
                    is DataError.Server -> UiState.Error("Something went wrong")
                    else -> UiState.Error("Unknown error")
                }
            }
    }
}
```

WRONG because the ViewModel imports Ktor types — swapping engines, switching to a different HTTP client, or adding a cache layer would force every ViewModel to change. The repository is the boundary that converts Ktor-specific exceptions into domain error types the ViewModel can handle without knowing the implementation.

### `encodeDefaults` — silently dropped fields

```kotlin
// WRONG — Json defaults omit default-valued fields from the serialized output
val json = Json { ignoreUnknownKeys = true }

@Serializable
data class JsonRpcRequest(
    val jsonrpc: String = "2.0",  // protocol-required field with a default
    val id: Int,
    val method: String,
)

// Serializes to: {"id":1,"method":"tools/call"} — "jsonrpc" is missing
// Server rejects every request with a confusing "invalid request" error

// RIGHT — encodeDefaults = true keeps default-valued fields in the payload
val json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

// Serializes to: {"jsonrpc":"2.0","id":1,"method":"tools/call"} — server accepts it
```

WRONG because `kotlinx.serialization` defaults to `encodeDefaults = false`, which silently strips any property whose value matches its declared default. Protocol-required constants like `jsonrpc = "2.0"`, `version = "1.0"`, or `type = "..."` look harmless in the source but vanish from the wire. The server returns a generic "invalid request" error pointing at HTTP layer concerns, sending you down rabbit holes (double-serialization, content-type, swapping HTTP clients) when the actual fix is a one-line `Json {}` flag. Always set `encodeDefaults = true` for client APIs — the larger payload is negligible compared to the debugging cost.

### `expectSuccess` consistency

```kotlin
// WRONG — expectSuccess = true but caller still inspects status; exception is thrown before the check runs
val client = HttpClient(engine) {
    expectSuccess = true
    install(ContentNegotiation) { json() }
}

suspend fun getUser(id: String): UserDto? {
    val response = client.get("users/$id")
    return if (response.status == HttpStatusCode.OK) response.body() else null  // unreachable on non-2xx
}

// RIGHT — pick one error model and apply it consistently
// Option 1: expectSuccess = true + try/catch (matches Repository pattern)
suspend fun getUser(id: String): UserDto = client.get("users/$id").body()

// Option 2: expectSuccess = false + explicit status inspection
suspend fun getUser(id: String): UserDto? {
    val response = client.get("users/$id")
    return if (response.status.isSuccess()) response.body() else null
}
```

WRONG because `expectSuccess = true` makes Ktor throw `ClientRequestException`/`ServerResponseException` before the manual status check runs — the `if` branch never sees a non-2xx status. Pick one model: throw on non-2xx (`expectSuccess = true` with try/catch) or return-and-inspect (`expectSuccess = false` with status checks). Mixing both produces dead branches that hide bugs.

---

## Checklist

- [ ] Single `HttpClient` instance provided via DI — never created per request
- [ ] Engine selected per platform (`OkHttp`/`Darwin`/`CIO`) in the matching source set
- [ ] `ContentNegotiation` installed with `Json { ignoreUnknownKeys = true; encodeDefaults = true }`
- [ ] `HttpTimeout` configured with `connectTimeoutMillis`, `requestTimeoutMillis`, `socketTimeoutMillis`
- [ ] `Logging` plugin gated on debug builds; `Authorization` header sanitized
- [ ] `expectSuccess` consistent across the project (true with try/catch, or false with status inspection)
- [ ] DTOs `@Serializable`; `@SerialName` for non-matching JSON keys
- [ ] Mapping happens at the repository — DTOs never reach the ViewModel
- [ ] Ktor exceptions mapped to `DataError` at the repository layer
- [ ] Bearer auth via `Auth` plugin with `markAsRefreshTokenRequest()` in `refreshTokens`
- [ ] `HttpClientEngine` injected so tests can use `MockEngine`
- [ ] Tests reuse the production `createHttpClient` factory
