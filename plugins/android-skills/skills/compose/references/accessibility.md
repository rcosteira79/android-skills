# Accessibility — what isn't default-obvious

A strong model already produces correct Compose accessibility by default: `contentDescription` on meaningful images/icons and `null` on decorative ones; `Modifier.semantics { role = …; onClick(label) { } }` for custom controls; `clearAndSetSemantics` to replace child semantics and `mergeDescendants` to control merging; 48dp minimum touch targets via `sizeIn(minWidth = 48.dp, minHeight = 48.dp)`; `heading()` for section navigation; `stateDescription` + `Role.Checkbox` for stateful controls; `CustomAccessibilityAction` for complex gestures; and testing via `onNodeWithContentDescription` / `isHeading()`. This reference keeps the two areas the default handles less reliably.

## Traversal order — `traversalIndex` and `isTraversalGroup`

Screen-reader order follows layout position by default. When the visual order and the reading order should differ — or when scattered elements should be read as one unit — set it explicitly. This is the part the default rarely reaches for.

```kotlin
// Reorder within a group: lower traversalIndex is read first
Row {
    Button(onClick = {}, modifier = Modifier.semantics { traversalIndex = 1f }) { Text("Read second") }
    Button(onClick = {}, modifier = Modifier.semantics { traversalIndex = 0f }) { Text("Read first") }
}

// Read a label + value as a single focus stop
Column(modifier = Modifier.semantics { isTraversalGroup = true }) {
    Text("Label")
    Text("Value")
}
```

`traversalIndex` is relative *within* a traversal group; set `isTraversalGroup = true` on a container to bound it — e.g. so a floating bottom bar's items aren't interleaved with the screen body. Use these sparingly: good layout structure usually produces the right order on its own.

## Live regions — `Polite` vs `Assertive`

A live region announces dynamic content changes without the user moving focus to it (loading → loaded, validation results, async status). The trap is the mode — the default tends to reach for `Assertive`, which **interrupts** whatever the screen reader is currently saying.

```kotlin
Text(
    text = status,
    modifier = Modifier.semantics {
        liveRegion = LiveRegionMode.Polite   // queues after the current utterance
    }
)
```

- **`Polite`** — queues after the current utterance. The right default for status, progress, and validation messages.
- **`Assertive`** — interrupts immediately. Reserve for genuinely critical, time-sensitive alerts (a blocking error, a session-expiry warning). Overusing it makes the app talk over itself.
