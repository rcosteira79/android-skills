---
name: android-debugging
description: >
  Use when debugging Android or KMP issues — Android-specific techniques covering Logcat, ADB,
  ANR traces, R8 stack trace decoding, memory leaks, Gradle build failures, and Compose
  recomposition bugs, on a root-cause-first foundation.
---

# Android Debugging

## Overview

Android-specific evidence-gathering and investigation techniques on a root-cause-first foundation.

**Root-cause-first foundation:**
- **No fix before the root cause is found.** Investigate first — reproduce, gather evidence (observed values, not assumed), trace the cause. Patching a symptom you don't understand creates two bugs.
- **Three failed guesses ⇒ stop and question the architecture** rather than guessing again.

The Android-specific tools below serve that investigation. *Optional:* if you run a dedicated debugging-discipline skill (e.g. `superpowers:systematic-debugging` or `ace:systematic-debugging`), this layers on top of it — but it requires none.

## Evidence-Gathering by Problem Type

### Crashes & Exceptions

```bash
# Stream crash logs filtered by app package
adb logcat --pid=$(adb shell pidof -s com.example.app)

# Save full logcat to file for analysis
adb logcat -d > crash_log.txt

# Filter by tag
adb logcat -s "YourTag:E"
```

Key logcat log levels: `V` (verbose) `D` (debug) `I` (info) `W` (warn) `E` (error) `F` (fatal)

Read the **full stack trace** — the root cause is usually at the bottom of the `Caused by:` chain, not the top-level exception.

### ANR (Application Not Responding)

ANRs mean the main thread was blocked. Evidence:

```bash
# Pull ANR trace from device
adb pull /data/anr/traces.txt ./anr_traces.txt

# Or stream while reproducing
adb logcat -s "ActivityManager:E" | grep -A 30 "ANR in"
```

Look for: `main` thread in state `MONITOR` (waiting for a lock) or blocking I/O on `main`. Trace backward to find what holds the lock.

**Common causes:** Database/network call on main thread, `runBlocking` on main thread, deadlock between coroutine scopes.

### Memory Leaks

Add [LeakCanary](https://square.github.io/leakcanary/) to `debugImplementation`. It surfaces leak traces automatically in a notification.

Read the leak trace top-to-bottom: the first bold line is the leaking object, the path shows what's holding the reference. Fix by clearing the reference in the appropriate lifecycle callback.

```bash
# Dump heap manually for Android Profiler analysis
adb shell am dumpheap com.example.app /data/local/tmp/heap.hprof
adb pull /data/local/tmp/heap.hprof ./heap.hprof
```

### Performance Trace Investigation (Perfetto)

For bottleneck investigation across CPU, graphics, I/O, IPC, memory, or power — beyond what Logcat and ANR traces show — capture a Perfetto trace and query it with SQL.

**Measure before you fix.** For performance regressions, logs usually mislead — capture a *baseline* measurement before changing anything, then bisect against it. A trace tells you where time goes; only a comparison against a known-good baseline tells you what actually regressed.

```bash
# Capture a trace (system-level, all categories)
adb shell perfetto -c - --txt -o /data/misc/perfetto-traces/trace.pftrace \
  <<'EOF'
buffers { size_kb: 65536 }
data_sources { config { name: "linux.ftrace" } }
data_sources { config { name: "android.surfaceflinger.frame" } }
duration_ms: 10000
EOF

adb pull /data/misc/perfetto-traces/trace.pftrace ./
```

Then open the trace at https://ui.perfetto.dev and run SQL against it (`SELECT name, dur FROM slice WHERE dur > 16e6` for frames slower than 16ms, etc.).

For an agent-driven workflow — translating an investigation intent (jank, slow startup, battery drain) into the right Perfetto SQL and iterating across the trace — see Google's [`perfetto-sql`](https://github.com/android/skills/tree/main/profilers/perfetto-sql) and [`perfetto-trace-analysis`](https://github.com/android/skills/tree/main/profilers/perfetto-trace-analysis) skills (`android skills list` to check for a local install; `android skills add perfetto-sql perfetto-trace-analysis` otherwise). They provide Domain Hints (CPU/Graphics/I/O/IPC/Memory/Power), a mandatory scratchpad chain-of-evidence pattern, and `GLOB`-over-`LIKE` query rules.

### R8 / ProGuard — Obfuscated Stack Traces

Release crash stack traces are obfuscated. Decode them with the mapping file generated at build time.

```bash
# retrace a crash (AGP 7+)
./gradlew :app:retrace --stacktrace-file crash.txt

# Or use the retrace CLI directly
java -jar retrace.jar mapping.txt crash.txt
```

Mapping files are in `app/build/outputs/mapping/<variant>/mapping.txt`. Always archive them alongside release builds.

If a class is unexpectedly removed or renamed, add a `-keep` rule in `proguard-rules.pro` and verify with:

```bash
./gradlew :app:assembleRelease
# Then inspect: app/build/outputs/mapping/release/usage.txt (removed) and seeds.txt (kept)
```

For the **inverse problem** — reading obfuscated third-party code or decoding a stack trace from a library where the mapping file isn't yours — `retrace` doesn't apply. Use `jadx --deobf` (consistent renames across the decompiled output) or `jadx --deobf-map` (when the SDK ships a mapping). The [`android-reverse-engineering` plugin](https://github.com/SimoneAvogadro/android-reverse-engineering-skill) covers the full workflow including the anchor-via-strings strategy for navigating obfuscated code by string literals and framework class names that survive obfuscation (check if it's already installed locally first — it ships as `android-reverse-engineering:*` skills).

### Gradle Build Failures

Read the error from the **bottom up** — Gradle wraps errors in multiple layers.

Common patterns:

| Error | Investigation |
|-------|--------------|
| `Manifest merger failed` | Check `app/build/intermediates/merged_manifests/` for the merged output; look for conflicting `android:` attributes |
| `Duplicate class` | Run `./gradlew dependencies` and look for the same class in multiple transitive deps; use `exclude` or force a version |
| `Could not resolve` | Check repository declarations, VPN/proxy, dependency version exists |
| `D8/R8: Type not present` | Missing `keep` rule or desugaring issue; check `minSdk` vs API used |
| `KSP / KAPT error` | Look for the processor's own error above the Gradle wrapper message |

```bash
# Full dependency tree for a configuration
./gradlew :app:dependencies --configuration releaseRuntimeClasspath

# Run with stacktrace for deeper Gradle errors
./gradlew assembleDebug --stacktrace --info 2>&1 | grep -A 20 "FAILED"
```

### Runtime UI Inspection

When a bug is visual (wrong element state, missing content, overlap), dump the layout tree directly instead of reasoning from a screenshot:

```bash
# Full layout tree as JSON — search by class/text/bounds instead of parsing an image
android layout --pretty

# Only elements that changed since last call — useful for animations or transient state
android layout --diff --pretty

# Target a specific device, write to file
android layout --device=emulator-5554 -o layout.json
```

Prefer `android layout` over `adb screencap` whenever the question is "what is the UI state?" rather than "what does it look like?". The JSON tree is grep-able and survives `--diff` state across invocations.

### Compose Recomposition Bugs

For deeper Compose performance analysis (stability, recomposition skipping, baseline profiles), see `android-skills:compose` → `compose/references/performance.md`.

Wrong state or unexpected re-renders:

1. **Layout Inspector** (Android Studio) → enable "Show recomposition counts" to identify hot paths. For headless/CLI workflows, `android layout --diff` gives a JSON tree of what changed between frames.
2. Add `SideEffect { Log.d("Recompose", "MyComposable recomposed") }` temporarily to confirm
3. Check that `State` objects are not created inside the composition (use `remember`)
4. Verify `equals()` on state data classes — a new object with same values still triggers recomposition if `equals` is not implemented

**Note:** Since Compose compiler 2.0+ (Kotlin 2.0+), strong skipping mode is enabled by default and the compiler automatically memoizes lambdas that capture stable references. Manual `remember {{ }}` wrapping is no longer necessary in most cases. If you see excessive recomposition from lambdas, check whether the captured references are unstable (mutable collections, non-data classes) rather than wrapping in `remember`.

(Standard `adb` commands — `devices`, `install -r`, `am start`, `pm clear`, `ps`, `run-as … ls /data/data/<pkg>/` — aren't covered here; for visual-state bugs prefer `android layout` over `screencap` as noted above.)

## Multi-Component Evidence Template

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

## Red Flags

- Fixing a crash without reading the full `Caused by:` chain
- Guessing at an R8 issue without checking the mapping file
- Adding `Thread.sleep()` to "fix" an ANR or race condition
- Resolving a dependency conflict by adding `exclude` without understanding why the duplicate exists
- Fixing a Compose bug by wrapping in `key()` without understanding what triggers recomposition
- Leaving temporary instrumentation in the tree — tag every debug log with a unique per-session prefix (e.g. `DEBUG-a4f2`) so cleanup is one `grep`, and remove them all before declaring the fix done
