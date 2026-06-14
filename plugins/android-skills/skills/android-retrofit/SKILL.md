---
name: android-retrofit
description: Use when setting up or working with Retrofit in Android — service interface definitions, coroutines integration, OkHttp configuration, Hilt module setup, and error handling in the repository layer.
---

# Android Networking with Retrofit

Modern Retrofit setup for Android using coroutines, `kotlinx.serialization`, and Hilt. This reference covers the decisions that are easy to get wrong, not the standard boilerplate of service interfaces, Hilt module wiring, and the converter setup.

## Service interface

Declare every endpoint as a `suspend` function. **Return the body type directly** — Retrofit throws `HttpException` on non-2xx, giving a clean `try/catch` at the repository boundary. Use `Response<T>` **only** when you need the status code, headers, or error body (e.g. server-side validation messages):

```kotlin
// Direct body — throws HttpException on non-2xx; the common case
@GET("users/{user}/repos")
suspend fun listRepos(@Path("user") user: String): List<Repo>

// Response wrapper — only when you need code/headers/error body
@GET("users/{user}")
suspend fun getUser(@Path("user") user: String): Response<User>
```

Wrapping every endpoint in `Response<T>` "just in case" forces callers to check `isSuccessful` and handle a nullable body even when only the body matters — don't.

## OkHttp & JSON

Standard wiring (in a Hilt `@Module`/`@Provides @Singleton`): `HttpLoggingInterceptor` with its level gated on `BuildConfig.DEBUG`, sensible connect/read timeouts, and the `kotlinx.serialization` converter (`json.asConverterFactory("application/json".toMediaType())`). For an API that's loose with its payloads, configure:

```kotlin
Json { ignoreUnknownKeys = true; coerceInputValues = true; isLenient = true }
```

## Auth: interceptor, and the throw-vs-proceed decision

Attach the token via an `Interceptor`, not a per-endpoint `@Header` — a single missed `@Header` parameter is an unauthenticated request that fails at runtime, not compile time. The part most often gotten wrong is **what to do when the token is absent**:

```kotlin
class AuthInterceptor @Inject constructor(
    private val tokenProvider: TokenProvider,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = tokenProvider.getToken()
            ?: throw IOException("Auth token unavailable") // fail fast — see note below
        val request = chain.request().newBuilder()
            .header("Authorization", "Bearer $token")
            .build()
        return chain.proceed(request)
    }
}
```

> **Throw vs proceed:** **Throw** when all endpoints require auth — a missing token should surface immediately rather than silently producing a confusing 401. **Proceed without the header** only if the same `OkHttpClient` is shared between authenticated and public endpoints: `?: return chain.proceed(chain.request())`. Silently proceeding when every call needs auth is a common mistake.

## Error handling

The repository is the error boundary: catch `HttpException`/`IOException` there and map them to a domain error type — never let Retrofit/OkHttp exception types reach the ViewModel, and never expose Retrofit DTOs to it. Don't redefine the error hierarchy here; see `android-skills:android-data-layer` for the repository pattern and the shared `DataError` taxonomy.

## Checklist

- [ ] All service functions are `suspend`
- [ ] `Response<T>` only when you need the status code, headers, or error body
- [ ] `OkHttpClient` logging gated behind `BuildConfig.DEBUG`; sensible timeouts set
- [ ] Auth applied via an `Interceptor`, with the token-absent policy chosen (throw vs proceed)
- [ ] Network exceptions mapped to domain types at the repository; DTOs never reach the ViewModel
