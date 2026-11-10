---
name: android-source-search
description: Use when needing to fetch Android source code — AOSP platform internals (@hide APIs, framework classes, system services) or AndroidX/Jetpack library source and samples. Also use when public docs are insufficient to complete a task and implementation details must be read directly from source.
---

# Android Source Search

Two source trees, two access strategies. AOSP lives on `android.googlesource.com` (Gitiles); AndroidX lives on GitHub. **`cs.android.com` blocks automated fetching — it's a human-browse JS SPA only** (never WebFetch it).

## Preferred: the android-sources MCP

If `mcp__android-sources__*` tools are available, **always prefer them** over WebFetch/gh — local source, sub-10ms lookups. Fall back to the strategies below only when they aren't.

## Fallback: WebFetch + gh

**AOSP** (framework internals, `@hide` APIs, internal constants, default attr values) **→ Gitiles.** Raw text is base64-encoded and smaller:

```
https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/{path}?format=TEXT
```

Use `refs/heads/main` (the active default branch), or a tag like `android-14.0.0_r74` for a specific API level. Key repos: `platform/frameworks/base` (`core/java/android/` → View/Activity/Context; `services/core/java/` → system services; `core/res/` → default attrs/styles), `platform/libcore` (`ojluni/src/main/java/` → Java core).

**AndroidX** (`androidx.*` source + samples) **→ GitHub.** File content via `raw.githubusercontent.com`; directory listings via `gh api`:

```
https://raw.githubusercontent.com/androidx/androidx/androidx-main/{path}
gh api repos/androidx/androidx/contents/{path} --jq '.[].name'
```

Samples live next to the source as `{ClassName}Samples.kt` under a `samples/` subpath. Key path prefixes: Compose UI `compose/ui/ui/src/commonMain/kotlin/androidx/compose/ui/`, Foundation `compose/foundation/foundation/src/commonMain/kotlin/`, Animation `compose/animation/animation/src/commonMain/kotlin/`. AndroidX *is* mirrored on Gitiles (`platform/frameworks/support`, `androidx-main`), but the GitHub layout is the canonical, better-documented path for `androidx.*` — prefer it.

## When the path is unknown

Use `cs.android.com` as a **human search UI** (not WebFetch — JS SPA) to locate the class/file, then fetch via Gitiles (AOSP) or `raw.githubusercontent.com` / `gh api` (AndroidX):

```
https://cs.android.com/search?q=ClassName+methodName&ss=android    # &ss=androidx for AndroidX
```

Both trees change frequently — always fetch current source rather than trusting remembered line numbers.
