# Platform-Specific APIs and Gotchas (Compose Multiplatform)

CMP shares most UI code; entry points and platform APIs differ (Desktop `Window` / `MenuBar` / `Tray` / `DialogWindow` + `ComposePanel` / `SwingPanel` interop; iOS `ComposeUIViewController` + `UIKitView`; Web `ComposeViewport`). This reference covers the per-platform **gotchas**, not the entry-point boilerplate.

## iOS

- **`ImeAction.Done` inserts a newline instead of submitting** ([compose-multiplatform#3473](https://github.com/JetBrains/compose-multiplatform/issues/3473)). Workaround — detect the inserted `\n` and submit:
  ```kotlin
  onValueChange = { new -> if ("\n" in new && "\n" !in text) onSubmit() else text = new }
  ```
- **A focused `TextField` in a scrollable `Column` pushes the `TopAppBar` off-screen** when the keyboard opens ([#3621](https://github.com/JetBrains/compose-multiplatform/issues/3621)) — use `LazyColumn`, or `imePadding()` on the scroll area below the bar.
- **`DisposableEffect.onDispose` is unreliable when a screen is popped from a `UINavigationController`** — don't rely on it for critical cleanup (location, resources); use the ViewModel's `onCleared()` or explicit lifecycle observation.
- **`Flow` collection does NOT pause in the background** ([#3889](https://github.com/JetBrains/compose-multiplatform/issues/3889)) — unlike Android, iOS keeps collecting (wasting CPU/battery). Use `collectAsStateWithLifecycle(lifecycle = …)` if your CMP version exposes it, or observe `UIApplication` background/foreground notifications via `DisposableEffect`.
- **ProMotion 120Hz needs an Info.plist entry** — Compose renders at 60Hz on ProMotion by default; add `<key>CADisableMinimumFrameDurationOnPhone</key><true/>` or animation/scroll feels less smooth than native.
- **`UIKitView` interaction mode:** `Cooperative(delayMillis)` gives Compose first touch then passes to UIKit after the delay (maps / web views — ~150ms is perceptible, so tune it); `NonCooperative` gives UIKit all touches.
- **App-size overhead:** a minimal CMP iOS app is ~25MB (Skia adds 15–20MB) — a fixed cost that matters in download-size-sensitive markets.
- **Perf:** `graphicsLayer { clip = true }` is costlier on Metal than native UIKit clipping; image decoding is synchronous — use Coil's `rememberAsyncImagePainter` to avoid blocking the main thread on image-heavy screens.

## Desktop (JVM)

- **Scrolling is mouse-wheel only** — no touch physics, no momentum/fling, no overscroll bounce. It feels mechanical compared to mobile; that's expected, not a bug.
- Desktop has explicit `VerticalScrollbar` / `HorizontalScrollbar` (`adapter = rememberScrollbarAdapter(scrollState | lazyListState)`) — mobile has none; leave room for it (`padding(end = …)`).
- macOS `Tray` responds to right-click only (left-click does nothing by default) — OS behavior.

## Web / WASM

**Compose for Web renders everything to a single `<canvas>` — there are zero DOM elements for your UI.** Consequences:

| Doesn't work | Why |
|---|---|
| Ctrl/Cmd+F text search, browser translate, SEO indexing | canvas pixels, no DOM text |
| HTML form autofill, password managers | no `<input>` elements |
| Browser context menus, native copy/paste | canvas intercepts |
| Server-side rendering | needs the JS + WASM runtime |

If you need SEO, text search, or browser-native form behavior, **Compose for Web is the wrong choice** — use Kobweb (Compose HTML) or a traditional web framework. Also: WASM-GC requires Chrome/Edge 119+, Firefox 120+, Safari 18.2+ (older browsers show a blank page, no fallback), and the initial download is multi-megabyte (Skiko ~5–8MB + app code) — unsuitable for landing pages, fine for internal tools / dashboards / app-like experiences.
