# Kotlin Skills for Claude Code

Claude Code skills for Kotlin coroutines, flows, and RxJava migration — covering Android and KMP projects.

## Skills

### `kotlin-coroutines`
Dispatcher selection, scope management, structured concurrency, cancellation, exception handling, and Android/KMP patterns. Includes the DispatcherProvider pattern for testable dispatcher injection.

### `kotlin-flows`
Flow type selection (Flow/StateFlow/SharedFlow), operator chains, callback bridging, lifecycle-safe collection, Channel migration, and UI state management.

### `rxjava-migration`
Triggered only when you explicitly ask to migrate. Assesses complexity, maps RxJava types and operators to coroutines equivalents, and provides interop patterns for incremental migration.

## Installation

### Claude Code

Copy the skill directories into your Claude Code skills folder:

```bash
git clone https://github.com/rcosteira79/coroutine-skills.git
cp -r coroutine-skills/skills/* ~/.claude/skills/
```

Skills are invoked automatically based on context:

- Working with coroutines → `kotlin-coroutines` skill activates
- Working with Flow/StateFlow/SharedFlow → `kotlin-flows` skill activates
- Migrating from RxJava → ask Claude to migrate, `rxjava-migration` skill activates

### Cursor, Windsurf, and other agentic editors

The skills are plain markdown files. Copy the content of whichever `SKILL.md` files are relevant into your editor's context mechanism:

- **Cursor** — add to `.cursor/rules/` as `.mdc` files
- **Windsurf** — add to `.windsurf/rules/` as `.md` files
- **Copilot** — add to `.github/copilot-instructions.md`
- **Other editors** — paste into your project's custom instructions or context file

Each skill is self-contained and can be used independently.

## License

MIT
