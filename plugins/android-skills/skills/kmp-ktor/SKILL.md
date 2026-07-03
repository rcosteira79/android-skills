---
name: kmp-ktor
description: Use when setting up or working with Ktor client in KMP or Android projects — HttpClient configuration, per-platform engine selection, kotlinx.serialization, bearer auth with refresh, MockEngine testing, and error mapping at the repository boundary.
---

# Ktor Client for KMP and Android

This reference covers the Ktor client configuration traps — plugin install order, serialization flags, auth refresh, and error mapping — not the basics of a shared `HttpClient`, engine selection, or `ContentNegotiation` setup. **Related:** `android-skills:android-data-layer` (repository + the `DataError` error model — its canonical home), `android-skills:android-retrofit` (Android-only equivalent).

## Plugin install order — `HttpRequestRetry` BEFORE `HttpTimeout`

The install order most often gotten wrong: installing `HttpTimeout` before `HttpRequestRetry`. Plugins run in install order for outgoing requests; retries must be able to catch timeout errors, so retry has to wrap timeout.

```kotlin
val json = Json { ignoreUnknownKeys = true; coerceInputValues = true; encodeDefaults = true }  // encodeDefaults: see the section below

HttpClient(engine) {
    install(ContentNegotiation) { json(json) }
    install(Auth) { bearer { /* loadTokens / refreshTokens */ } }
    install(HttpRequestRetry) {                 // BEFORE HttpTimeout
        retryOnServerErrors(maxRetries = 3)
        exponentialDelay()
    }
    install(HttpTimeout) {                       // AFTER HttpRequestRetry
        requestTimeoutMillis = 30_000; connectTimeoutMillis = 15_000; socketTimeoutMillis = 15_000
    }
}
```

Reversed, `HttpTimeout` resolves the request as failed before the retry plugin sees it, so timeouts are never retried. (Separately, the `Auth` plugin handles 401 refresh independently — let `HttpRequestRetry` cover transient/5xx failures; don't chain the two around the same status code.)

## `encodeDefaults = true` — or protocol-constant fields silently vanish

`kotlinx.serialization` defaults to `encodeDefaults = false`, which **strips any property whose value equals its declared default** from the serialized output. A `jsonrpc: String = "2.0"` (or `version = "1.0"`, `type = "..."`) disappears from the payload; the server rejects every request with a generic "invalid request," and the fix is a one-line flag — found only after hours chasing HTTP-layer red herrings. Always set it for client APIs — the `val json` defined at the top of this file does, alongside `ignoreUnknownKeys` and `coerceInputValues`. That one configured instance is what the whole client shares: `install(ContentNegotiation) { json(json) }` and the WebSocket converter both take it.

## `expectSuccess` — pick one model, consistently

`expectSuccess = true` makes Ktor throw `ClientRequestException` (4xx) / `ServerResponseException` (5xx) on non-2xx — and that throw **runs before any manual status check**, so an `if (response.status == OK)` branch after it is dead code. Pick one model project-wide: `expectSuccess = true` + `try/catch` (matches the repository pattern), or `expectSuccess = false` + explicit `response.status.isSuccess()` inspection. Never mix them.

## Bearer refresh — `markAsRefreshTokenRequest()` or it loops

In the `Auth` `bearer { refreshTokens { … } }` block, mark the refresh POST with `markAsRefreshTokenRequest()` so it isn't intercepted by the same `Auth` plugin — without it, a failing refresh triggers another refresh, looping infinitely. It's an `HttpRequestBuilder` extension: call it **inside the request builder block**, not bare in `refreshTokens { }` (where it doesn't compile).

```kotlin
install(Auth) {
    bearer {
        loadTokens { tokenStorage.getTokens()?.let { BearerTokens(it.access, it.refresh) } }
        refreshTokens {
            val refresh = oldTokens?.refreshToken ?: return@refreshTokens null
            val r = client.post("auth/refresh") {
                markAsRefreshTokenRequest()                      // skip the Auth plugin for this call
                setBody(RefreshRequestDto(refresh))
            }.body<TokenResponseDto>()
            tokenStorage.save(r.accessToken, r.refreshToken); BearerTokens(r.accessToken, r.refreshToken)
        }
        sendWithoutRequest { it.url.pathSegments.none { seg -> seg in listOf("login", "register") } }
    }
}
```

Keep `BearerTokens` at the plugin boundary; the rest of the app uses your own token type. `TokenStorage` is project-defined (DataStore on Android/JVM, Keychain on iOS).

## WebSockets & SSE — use the serialization converter

For real-time transports, install the kotlinx-serialization converter so typed messages flow over the same `Json` config as `ContentNegotiation`; without it you hand-encode/decode `Frame.Text`. (SSE = server→client only, plain HTTP, built-in reconnect; WebSocket = bidirectional, manual reconnect, binary frames — default to SSE when the client only consumes.)

```kotlin
val client = HttpClient(engine) {
    install(WebSockets) {
        pingIntervalMillis = 30_000
        contentConverter = KotlinxWebsocketSerializationConverter(json)  // the shared configured instance — bare `Json` reverts to encodeDefaults = false
    }
    install(SSE)
}

client.webSocket("wss://api.example.com/ws") {
    sendSerialized(SubscribeMessage(topic = "items"))
    while (true) { val msg = receiveDeserialized<ServerMessage>(); /* handle */ }
}

// SSE — incoming is a Flow<ServerSentEvent>
client.sse("https://api.example.com/events") { incoming.collect { event -> /* event.event / event.data / event.id */ } }
```

Wrap SSE/WebSocket collection in a `LaunchedEffect` or repository coroutine so cancellation closes the HTTP connection when the consumer goes away.

## Error mapping + testing

Catch **specific** Ktor types at the repository (`ClientRequestException` / `ServerResponseException` / `HttpRequestTimeoutException` / `IOException`) and map to `DataError` — `catch (e: Exception)` would swallow `CancellationException`. The full repository pattern + `DataError` taxonomy lives in `android-skills:android-data-layer`. For richer per-error UI states (`Unauthorized`, `RateLimited`, `Forbidden`, …), a sealed `ApiResult<T>` + a `safeRequest` wrapper with `expectSuccess = false` is the alternative shape — pick one per project.

Inject `HttpClientEngine` so tests swap in `MockEngine`, reusing the production `createHttpClient` factory so plugin config matches:

```kotlin
val mockEngine = MockEngine { request ->
    assertEquals("/users/42", request.url.encodedPath)
    respond("""{"id":"42","name":"Ada","created_at":1700000000000}""",
        HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
}
val repo = UserRepository(UserService(createHttpClient(mockEngine, baseUrl = "https://api.example.com/")))
```
