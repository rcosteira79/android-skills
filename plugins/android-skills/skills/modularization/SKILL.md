---
name: modularization
description: Use when writing or changing any class, object, function, property, or constant in a multi-module Android/Kotlin project (settings.gradle(.kts) includes more than one module — :app, :core:*, :feature:*, :data, etc.). Symptoms — a top-level declaration left at Kotlin's default public visibility; an implementation class, mapper, helper, constant, or UI-state holder reachable from another module though only used within its own; reaching for public "because the caller needs it"; "should this be public or internal?".
---

# Modularization

**Declare everything at the lowest visibility that still compiles.** Start `private`; widen to `internal` only when another file in the *same module* needs it; widen to `public` only when a *different module* actually consumes it. Kotlin defaults to `public`, and in a multi-module project that default is usually wrong — a `public` symbol joins the module's API surface: it leaks implementation across the boundary and you are then obliged to keep it stable.

- Public interface as the module's API → the interface is `public`; its **implementation class stays `internal`** (DI-bound, never named from another module).
- Mapper / helper / extension / constant / UI-state holder used only inside the module → `internal` (or `private` if a single file uses it). "Rendered by a composable in this module" does **not** require `public` — `internal` is visible to the whole module.
- Member used only within its class → `private`.

Widening a symbol to `public` is a decision, not a default: confirm a real cross-module consumer first.
