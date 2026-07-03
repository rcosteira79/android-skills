---
name: coil-compose
description: Use when loading images in Compose or Compose Multiplatform with Coil 3 — AsyncImage vs SubcomposeAsyncImage vs rememberAsyncImagePainter, ImageRequest configuration, placeholder/error states, performance in lists, and KMP setup with LocalPlatformContext.
---

# Coil 3 for Compose & Compose Multiplatform

This reference covers the KMP specifics and two performance guardrails, not the basics of `AsyncImage` / `SubcomposeAsyncImage` / `ImageRequest` / `placeholder` / `error` / `contentDescription` / a shared `ImageLoader`.

## KMP: `LocalPlatformContext`, not `LocalContext`

Coil 3 is fully multiplatform — `AsyncImage` / `SubcomposeAsyncImage` / `rememberAsyncImagePainter` are identical in `commonMain`, with **no `expect`/`actual` needed**. The one swap: use `LocalPlatformContext.current`, not `LocalContext.current` (Android-only; a compile error in `commonMain`). It resolves to `android.content.Context` on Android and `PlatformContext.INSTANCE` on other targets.

```kotlin
// commonMain — works on all platforms
AsyncImage(
    model = ImageRequest.Builder(LocalPlatformContext.current).data(url).crossfade(true).build(),
    contentDescription = "User avatar",
    modifier = Modifier.size(48.dp).clip(CircleShape),
)
```

**Singleton setup (KMP):** call `SingletonImageLoader.setSafe { ImageLoader.Builder(it).crossfade(true).build() }` once early in the app lifecycle, or pass an `imageLoader` explicitly. **`coil-compose` vs `coil-compose-core`:** with `coil-compose`, `AsyncImage` *without* an `imageLoader` argument uses the singleton automatically; with `coil-compose-core`, the `imageLoader` parameter is **required** (no singleton convenience). Add a platform network engine as needed (e.g. `coil-network-ktor3` for KMP).

## Two performance guardrails

**`SubcomposeAsyncImage` is significantly slower than regular composition — never use it inside `LazyColumn` / `LazyRow`.** It creates a subcomposition per item; during scroll that overhead accumulates into visible jank. For custom loading/error states in a list, use `AsyncImage` with `placeholder` / `error` parameters instead — same visual result, no subcomposition.

**`rememberAsyncImagePainter` does NOT infer the display size from layout constraints** — without an explicit `.size()` it loads the image at its original dimensions (a 4000×3000 photo shown at 64dp still occupies the full bitmap in memory → OOM in a 50-item list). Reach for it only when a `Painter` is strictly required (`Canvas`, `Icon`, a custom draw); always pass `.size()`. Otherwise use `AsyncImage`, which sizes automatically.

```kotlin
// only when a Painter is genuinely required — explicit size is mandatory
val painter = rememberAsyncImagePainter(
    ImageRequest.Builder(LocalPlatformContext.current).data(url).size(Size(128, 128)).build(),
)
Image(painter = painter, contentDescription = null)
```
