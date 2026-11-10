---
name: android-debugging
description: >
  Use when debugging Android or KMP issues — crashes, ANRs, performance regressions, obfuscated
  release stack traces, wrong on-screen UI state, or a bad value crossing several layers.
---

# Android Debugging

- **No fix before the root cause is found.** Investigate first — reproduce, gather evidence (observed values, not assumed), trace the cause. Patching a symptom you don't understand creates two bugs.
- **Three failed guesses ⇒ stop and question the architecture** rather than guessing again.

This layers on top of a dedicated debugging-discipline skill (`superpowers:systematic-debugging`, `ace:systematic-debugging`) but requires none. It covers the Android-specific parts that are easy to get wrong, not standard `adb` / Logcat / LeakCanary usage or reading a Gradle error.

## ANRs

ANR traces are `/data/anr/anr_*` files on current releases (a single `traces.txt` only on old ones): `adb shell ls /data/anr`, then `adb pull /data/anr/<filename>`; without root, capture `adb bugreport`. For triaging the dump, use Google's [`anr-audit-and-fix`](https://github.com/android/skills/tree/main/performance/anr-audit-and-fix) skill (`android skills add anr-audit-and-fix`).

## Performance regressions

**Measure before you fix.** For performance regressions, logs usually mislead — capture a *baseline* measurement before changing anything, then bisect against it. A trace tells you where time goes; only a comparison against a known-good baseline tells you what actually regressed.

To record and query a Perfetto trace, use Google's [`android-profiler`](https://github.com/android/skills/tree/main/profilers/android-profiler) skill (`android skills list` to check for a local install; `android skills add android-profiler` otherwise).

## R8 / ProGuard — obfuscated stack traces

Release crash stack traces are obfuscated. Decode them with the mapping file generated at build time.

```bash
# R8 retrace ships in the SDK command-line tools (cmdline-tools/<version>/bin/)
retrace mapping.txt crash.txt
```

Mapping files are in `app/build/outputs/mapping/<variant>/mapping.txt`. Always archive them alongside release builds.

If a class is unexpectedly removed or renamed, add a `-keep` rule in `proguard-rules.pro` and verify with:

```bash
./gradlew :app:assembleRelease
# Then inspect: app/build/outputs/mapping/release/usage.txt (removed) and seeds.txt (kept)
```

For the **inverse problem** — reading obfuscated third-party code or decoding a stack trace from a library where the mapping file isn't yours — `retrace` doesn't apply. Use `jadx --deobf` (consistent renames across the decompiled output) or `jadx --deobf-map` (when the SDK ships a mapping). The [`android-reverse-engineering` plugin](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) covers the full workflow including the anchor-via-strings strategy for navigating obfuscated code by string literals and framework class names that survive obfuscation (check if it's already installed locally first — it ships as `android-reverse-engineering:*` skills).

## Runtime UI inspection

When a bug is visual (wrong element state, missing content, overlap), dump the layout tree directly instead of reasoning from a screenshot:

```bash
# Full layout tree as JSON — search by class/text/bounds instead of parsing an image
android layout --pretty

# Target a specific device, write to file
android layout --device=emulator-5554 -o layout.json
```

Prefer `android layout` over `adb screencap` whenever the question is "what is the UI state?" rather than "what does it look like?". The JSON tree is grep-able; to see what changed between two states, write each dump with `-o` and diff the files.

## Compose recomposition bugs

Stability, skipping and phase diagnosis live in `android-skills:compose` → `compose/references/performance.md`. Since Kotlin 2.0.20 strong skipping memoizes lambdas automatically — when a composable recomposes too often, look for a parameter that gets a new instance each time, not for a lambda to wrap in `remember`.

## Multi-component evidence template

For issues spanning multiple layers (e.g. Repository → ViewModel → UI):

```kotlin
// Temporarily instrument each boundary with a UNIQUE run-specific tag
// (pick a fresh suffix per session, e.g. DEBUG-a4f2) so the SAME tag both
// filters logcat at runtime and greps cleanly at teardown.
class UserRepository(...) {
    suspend fun fetchUser(id: String): User {
        Log.d("DEBUG-a4f2", "Repository: fetching user $id")
        val result = api.getUser(id)
        Log.d("DEBUG-a4f2", "Repository: received ${result}")
        return result
    }
}
```

Run once to identify **which layer** produces the bad value. Filter the run at runtime with `adb logcat -s "DEBUG-a4f2"`, then tear the instrumentation back out with a single `grep -rl "DEBUG-a4f2"`. A unique per-session tag is what makes both one-liners work — a shared tag like `DEBUG_LAYER` collides across sessions and leaves orphaned logs behind. Then investigate the implicated layer in isolation before proposing a fix.

Remove every temporary log before declaring the fix done.
