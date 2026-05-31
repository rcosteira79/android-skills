# iOS Swift Interop (KMP Boundaries Reference)

Kotlin↔Swift binding mechanics that apply to any KMP module exposed to iOS. Companion to `kmp-boundaries/SKILL.md` (boundary design) and `compose/references/multiplatform.md` (Compose-specific multiplatform patterns).

---

## Kotlin → Swift Naming

| Kotlin construct | Swift call site | Notes |
|---|---|---|
| Top-level `fun foo()` in `Bar.kt` | `BarKt.foo()` | File name + `Kt` suffix |
| `object AppInit` | `AppInit.shared` | Singleton access |
| `companion object` member | Direct on class (`MyClass.value`) | No `Companion` namespace |
| `sealed class UiState` | Class hierarchy (or SKIE exhaustive enum) | See [Sealed Classes in Swift](#sealed-classes-in-swift) |
| `suspend fun load()` | SKIE: `async func load()` | See [Coroutines → Swift Async](#coroutines--swift-async) |
| Generic types | Erased or boxed unpredictably | Use concrete types at boundary |

Example: a Kotlin file `MainViewController.kt` with `fun MainViewController(): UIViewController` becomes `MainViewControllerKt.MainViewController()` in Swift.

---

## Nullability and Type Bridging

| Kotlin | Swift | Notes |
|---|---|---|
| `String` | `String` | Non-null bridged directly |
| `String?` | `String?` | Optional bridged directly |
| `Int` / `Long` | `Int32` / `Int64` | **Not Swift `Int`.** Swift `Int` is platform-sized; the Kotlin types map to fixed-width Swift types. Cast explicitly when passing to Swift APIs that expect `Int`. |
| `Unit` | `KotlinUnit` | Awkward — avoid in public API. Caller must discard explicitly. |
| `List<T>` | `[T]` (read-only copy) | Mutability and structural sharing lost at the boundary. |
| `Map<K, V>` | `[K: V]` (read-only copy) | Same caveat as `List`. |

The `Int` width mismatch is the most common foot-gun: Kotlin `Int` (32-bit) does not match Swift `Int` (64-bit on 64-bit platforms). Cross-boundary arithmetic needs explicit casts.

Pass collections across the boundary sparingly — they're copied, not shared. Batch data; don't iterate across the boundary in hot paths.

---

## Coroutines → Swift Async

Two approaches, with strong defaults:

| Tool | When to use | Trade-off |
|---|---|---|
| **SKIE** | Default for new CMP/KMP projects | Automatic `async` / `AsyncSequence` bridging; adds a build plugin |
| **KMP-NativeCoroutines** | Existing projects already using it | Annotation-driven via `@NativeCoroutines`; SKIE preferred for greenfield |

### SKIE (recommended)

SKIE converts `suspend` functions to Swift `async` automatically — no annotations on the Kotlin side. SKIE detects suspend functions during the framework build and generates the bridge.

```kotlin
// commonMain
suspend fun loadItems(): List<Item> = repository.getAll()
```
```swift
let items = try await viewModel.loadItems()
```

---

## Flow → Swift Observation

The critical MVI bridge — iOS observes `StateFlow<UiState>`.

### SKIE: `Flow` → `AsyncSequence`

```swift
func observeState() async {
    for await state in viewModel.state {
        self.uiState = state
    }
}
```

`AsyncSequence` is the iOS-native iteration shape, compatible with `Task { ... }` and SwiftUI's `.task { ... }` lifecycle.

### Without SKIE — manual collector

Expose a callback-based observer from Kotlin; Swift holds the returned cancel closure and invokes it in `deinit`:

```kotlin
// iosMain
class IosStateCollector<T>(
    private val flow: StateFlow<T>,
    private val scope: CoroutineScope,
) {
    private var job: Job? = null
    fun observe(onChange: (T) -> Unit): () -> Unit {
        job = scope.launch(Dispatchers.Main) { flow.collect { onChange(it) } }
        return { job?.cancel() }
    }
}
```

---

## Sealed Classes in Swift

### Without SKIE — non-exhaustive

```swift
if let loading = state as? UiState.Loading { /* … */ }
else if let success = state as? UiState.Success { /* … */ }
else if let error = state as? UiState.Error { /* … */ }
// No exhaustiveness check — silently broken when a new sealed subclass is added
```

### With SKIE — exhaustive Swift enum

```swift
switch onEnum(of: state) {
case .loading: showSpinner()
case .success(let s): render(items: s.items)
case .error(let e): showError(e.message)
}
// Compiler error if a new sealed subclass is added
```

### SKIE edge cases

- **Generic sealed classes** — SKIE cannot convert generics to Swift enums. Use concrete types at the iOS boundary: `ItemListState` not `ListState<Item>`.
- **Nested sealed hierarchies** — SKIE flattens names: `UiState.Error.Network` → `.errorNetwork`.
- **Opt out** — annotate with `@SealedInterop.Disabled` to skip SKIE conversion for a specific class (rare; reach for it when the generated enum confuses Swift call sites).

---

## iOS API Design Rules

- Keep the public API surface small — use `internal` visibility + `@HiddenFromObjC` to exclude Kotlin internals from the generated ObjC header.
- Avoid generics in public iOS-facing API — ObjC/Swift interop erases or boxes them unpredictably.
- Prefer data classes over deep class hierarchies at the boundary — simpler Swift mapping.
- Set `isStatic = true` in framework configuration for static linkage (smaller binary, faster startup).
- Minimize Kotlin↔Swift boundary crossings in hot paths — batch data, don't iterate across the boundary.
- Avoid `suspend` functions that return `Unit` — Swift receives `KotlinUnit`, which callers must discard explicitly.

---

## Embedding SwiftUI in Compose (`UIHostingController`)

`UIKitView` embeds UIKit views directly. SwiftUI views can't be used directly — wrap in `UIHostingController` and pass the controller to a Kotlin factory:

```kotlin
// iosMain
@OptIn(ExperimentalForeignApi::class)
fun ComposeWithSwiftUI(
    createViewController: () -> UIViewController,
): UIViewController = ComposeUIViewController {
    Column(Modifier.fillMaxSize()) {
        Text("Compose content above")
        UIKitViewController(
            factory = createViewController,
            modifier = Modifier.size(300.dp),
        )
    }
}
```
```swift
MainViewControllerKt.ComposeWithSwiftUI {
    UIHostingController(rootView: MySwiftUIMapView())
}
```

For direct UIKit views (`MKMapView`, `WKWebView`, `AVCaptureSession`), use `UIKitView(factory = { ... })` from Kotlin — no Swift bridge needed. See `compose/references/multiplatform.md` for the broader Compose-side embedding patterns.

---

## Checklist

- [ ] No generics in types crossing the iOS boundary — use concrete sealed/data classes
- [ ] `suspend` returning `Unit` avoided; if unavoidable, callers explicitly discard
- [ ] `Int` width handled — explicit casts when bridging to Swift `Int`
- [ ] SKIE installed (or KMP-NativeCoroutines if existing) for `Flow`/`async` bridging
- [ ] Sealed classes use SKIE `onEnum(of:)` switches for exhaustiveness
- [ ] `@HiddenFromObjC` applied to internal Kotlin classes that shouldn't appear in Swift
- [ ] `isStatic = true` set in framework config for smaller binary and faster startup
- [ ] Boundary crossings batched, not iterated, in hot paths
