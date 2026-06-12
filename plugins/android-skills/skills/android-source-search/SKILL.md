---
name: android-source-search
description: Use when needing to fetch Android source code — AOSP platform internals (@hide APIs, framework classes, system services) or AndroidX/Jetpack library source and samples. Also use when public docs are insufficient to complete a task and implementation details must be read directly from source.
---

# Android Source Search

## Overview

Two separate source trees, two access strategies. AOSP lives on `android.googlesource.com` (Gitiles); AndroidX lives on GitHub. **`cs.android.com` blocks automated fetching** — it's for human browsing only.

## Preferred: android-source-explorer MCP

If `mcp__android-sources__*` tools are available, **always prefer them** over WebFetch/gh. They provide local source with sub-10ms lookups:

| Goal | MCP tool |
|------|----------|
| Find a class by name/pattern | `mcp__android-sources__search_classes` (glob, e.g. `*ViewModel*`) |
| Read full class source | `mcp__android-sources__lookup_class` (by fully qualified name) |
| Read a specific method | `mcp__android-sources__lookup_method` (class + method name) |
| List members of a class | `mcp__android-sources__list_class_members` |
| Get class hierarchy | `mcp__android-sources__get_class_hierarchy` |
| Search text/regex across sources | `mcp__android-sources__search_in_source` |
| List AndroidX artifact versions | `mcp__android-sources__list_available_versions` |
| Go to definition (requires LSP) | `mcp__android-sources__goto_definition` |
| Find references (requires LSP) | `mcp__android-sources__find_references` |
| Get type info/hover (requires LSP) | `mcp__android-sources__get_type_info` |

If MCP tools are not available, fall back to the WebFetch/gh strategies below.

## Fallback: WebFetch and gh CLI

### Which Source?

| You need... | Source | Access method |
|-------------|--------|---------------|
| Framework internals (`View`, `Activity`, system services) | AOSP | WebFetch → Gitiles |
| `@hide` APIs, internal constants, default attr values | AOSP | WebFetch → Gitiles |
| AndroidX/Jetpack source (`androidx.*`) | AndroidX GitHub | WebFetch → raw.githubusercontent.com |
| AndroidX samples (e.g. `LookaheadScope`, `LazyColumn`) | AndroidX GitHub | WebFetch → raw.githubusercontent.com |
| Directory listings (when path is unknown) | AndroidX GitHub | `gh api` via Bash |

### AOSP — Fetching via Gitiles

### HTML view
```
https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/{path}
```

### Raw text (base64-encoded, smaller payload)
```
https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/{path}?format=TEXT
```

### Key repo structure

| Repo | Path | Contains |
|------|------|----------|
| `platform/frameworks/base` | `core/java/android/` | View, Activity, Context, etc. |
| `platform/frameworks/base` | `services/core/java/` | System services (AMS, WMS, etc.) |
| `platform/frameworks/base` | `core/res/` | Default attrs, styles, drawables |
| `platform/libcore` | `ojluni/src/main/java/` | Java core libraries |
| `platform/development` | `samples/` | AOSP sample apps |

### Path inference
`android.view.ViewGroup` → `core/java/android/view/ViewGroup.java`

### AndroidX — Fetching via GitHub

### File content (WebFetch)
```
https://raw.githubusercontent.com/androidx/androidx/androidx-main/{path}
```

### Directory listing (Bash + gh CLI)
```bash
gh api repos/androidx/androidx/contents/{path} --jq '.[].name'
```

### Key repo paths

| Library | Path prefix |
|---------|-------------|
| Compose UI | `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/` |
| Compose UI samples | `compose/ui/ui/samples/src/main/java/androidx/compose/ui/samples/` |
| Compose Animation | `compose/animation/animation/src/commonMain/kotlin/` |
| Compose Animation samples | `compose/animation/animation/samples/src/main/java/` |
| Compose Foundation | `compose/foundation/foundation/src/commonMain/kotlin/` |
| Navigation | `navigation/navigation-compose/src/main/java/` |

### Example — fetch LookaheadScope samples
```
https://raw.githubusercontent.com/androidx/androidx/androidx-main/compose/ui/ui/samples/src/main/java/androidx/compose/ui/samples/LookaheadScopeSamples.kt
```

### Search Strategy (path unknown)

1. Use `cs.android.com` as a **human search UI** to find the class/file path
2. For AOSP: fetch via Gitiles once path is known
3. For AndroidX: fetch via `raw.githubusercontent.com` or list via `gh api`

```
# Human search (not WebFetch — JS SPA)
https://cs.android.com/search?q=ClassName+methodName&ss=android
https://cs.android.com/search?q=ClassName&ss=androidx
```

## Common Patterns

| Goal | What to look for |
|------|-----------------|
| Default attribute value | `mGroupFlags \|=` or field initializer |
| `@hide` method signature | Full method with `/** @hide */` Javadoc |
| Delegation to system service | `getService()` or `IActivityManager` calls |
| API level gating | `Build.VERSION.SDK_INT >= Build.VERSION_CODES.X` |
| AndroidX sample for an API | `{ClassName}Samples.kt` in the `samples/` subpath |

## Common Mistakes

- **Trusting training data line numbers** — both trees change frequently. Always fetch current source.
- **Using WebFetch on cs.android.com** — JS SPA, results won't be in raw HTML.
- **Picking the wrong Gitiles ref** — use `refs/heads/main` (the active default branch), or a tag like `android-14.0.0_r74` for a specific API level.
- **Defaulting to Gitiles for AndroidX** — AndroidX *is* mirrored on `android.googlesource.com/platform/frameworks/support` (`androidx-main`), but prefer GitHub `raw.githubusercontent.com` / `gh api`; the GitHub layout is the canonical, better-documented path for `androidx.*`.
- **Using WebFetch on github.com** — use `raw.githubusercontent.com` for file content, `gh api` for listings.
