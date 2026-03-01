# Kotlin Skills for Claude Code

Claude Code skills for Kotlin coroutines, flows, and RxJava migration — covering Android and KMP projects.

## Skills

### `kotlin-coroutines`
Dispatcher selection, scope management, structured concurrency, cancellation, exception handling, and Android/KMP patterns. Includes the DispatcherProvider pattern for testable dispatcher injection.

### `kotlin-flows`
Flow type selection (Flow/StateFlow/SharedFlow), operator chains, callback bridging, lifecycle-safe collection, Channel migration, and UI state management.

### `rxjava-migration`
Triggered only when you explicitly ask to migrate. Assesses complexity, maps RxJava types and operators to coroutines equivalents, provides interop patterns for incremental migration.

## Installation

```
/plugin install <your-github-username>/kotlin-skills
```

## Usage

Skills are invoked automatically by Claude Code based on context. You can also reference them explicitly:

- Working with coroutines → `kotlin-coroutines` skill activates
- Working with Flow/StateFlow/SharedFlow → `kotlin-flows` skill activates
- Migrating from RxJava → ask Claude to migrate, `rxjava-migration` skill activates
