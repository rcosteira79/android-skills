# Design-to-Compose

This reference covers the easy-to-miss parts of translating a Figma mockup into Compose: transcription fidelity, fine-grained shadows, and custom spacing/elevation scales.

## Transcription fidelity

Implementing a design is **transcription, not adaptation**. Every place the output differs from the design is a defect — including the places where your version is arguably nicer. Improvements belong in design review, not in the transcription.

### Copy: exact case and punctuation

Reproduce each string character for character.

- `GET STARTED` is not `Get started`. A styling convention you would apply to a screen of your own design — sentence-case button labels, title-case headings — is a reason to *ask design*, never a licence to quietly recase a label they specified.
- `Cancel anytime — no questions asked.` keeps the em dash (`—`, U+2014) and the trailing period. A hyphen is a different character.
- Casing is usually **mixed within one frame** — an all-caps CTA above a sentence-case step label. Normalising the frame to one style is the same bug as recasing one label; it just looks more deliberate.

### Numbers: keep the design's format

Padding, precision, and units are load-bearing; tidying them is a defect.

| Design | Transcribe as | Common defect |
|---|---|---|
| `Step 01 of 03` | `"Step 01 of 03"` | `"Step 1 of 3"` — padding dropped |
| `USD 9.00 / month` | `"USD 9.00 / month"` | `"USD 9 / month"` — precision dropped |

A zero-padded counter holds a fixed width so the row doesn't reflow as the step advances; trailing zeros on a price are usually a consistency or legal call. You rarely know the reason from the frame — which is the point.

### Resolve the exact token, not a near neighbour

The design names a **value**; bind it to the token whose value matches that value exactly.

- A CTA filled `#2A1FCC` maps to `primaryDark`, even when `primary` (`#4A3AFF`) is *the primary action's* colour. "Primary action → `primary`" is your role reasoning; the hex is the design's instruction. Match on value, then sanity-check the name — never the reverse.
- A gap one step off the scale (20dp where the scale runs 16, 24) is not licence to snap to the nearest rung.

**A token the theme genuinely lacks is added, never substituted.** An accent `#00C2A8` with no matching role means the theme is missing a role: add it. Mapping it onto the nearest existing colour silently redraws the design *and* hides the gap from whoever owns the design system. Same for an off-scale spacing step — add the step, or carry the literal with a comment saying why; don't round it away.

### Read the export, not the render

Dev mode emits a code export (React/Tailwind/CSS) carrying the frame's literal values — exact strings, hex, px, weights. Read it. A rendered screenshot has to be *eyeballed*, and the eye is the wrong instrument here: `#2A1FCC` and `#4A3AFF` are the same indigo at a glance, a trailing period is a few pixels, and zero-padding disappears the moment you read `01` as "one".

Trust, in order:

1. **Dev-mode / code export** — literal values, the whole frame at once.
2. **Inspect panel / variable names** — literal values, one node at a time.
3. **Rendered frame** — structure, hierarchy, and layout only.
4. **Prose about the design** — review notes, ticket copy, alt text: never a value source. Prose paraphrases, and paraphrase is lossy in exactly the ways above — it drops padding, straightens dashes, and recases labels on its way to being readable.

When two sources disagree, the export wins — and say so, so the disagreement is fixed at the source instead of relitigated at the next hand-off.

## Shadows: `dropShadow` / `innerShadow` (Compose UI 1.9+)

1.9 added `Modifier.dropShadow()` and `Modifier.innerShadow()` (in `androidx.compose.ui.draw`) for fine-grained shadows that map directly to Figma's drop/inner-shadow fields — superseding the single-parameter `Modifier.shadow(elevation, shape)` for anything beyond a plain elevation shadow. Two things to get right: the properties go in a **`Shadow` object** (there is no flat `blur`/`offsetX`/`offsetY` parameter list), and **chain placement** matters — a drop shadow comes *before* the background, an inner shadow *after* it.

```kotlin
import androidx.compose.ui.graphics.shadow.Shadow   // NOT androidx.compose.ui.graphics.Shadow (the text-shadow class)
import androidx.compose.ui.unit.DpOffset

// Drop shadow — BEFORE background
Box(
    Modifier
        .dropShadow(
            shape = RoundedCornerShape(12.dp),
            shadow = Shadow(
                radius = 8.dp,                          // Figma "Blur"
                color = Color.Black.copy(alpha = 0.15f),
                offset = DpOffset(0.dp, 4.dp),          // Figma X / Y offset
            ),
        )
        .background(Color.White, RoundedCornerShape(12.dp))
)

// Inner shadow — AFTER background
Box(
    Modifier
        .background(Color.White, RoundedCornerShape(12.dp))
        .innerShadow(
            shape = RoundedCornerShape(12.dp),
            shadow = Shadow(radius = 4.dp, color = Color.Black.copy(alpha = 0.1f), offset = DpOffset(0.dp, 2.dp)),
        )
)
```

Figma shadow fields map onto `Shadow(...)`: Blur → `radius`, X/Y offset → `offset = DpOffset(x, y)`, Spread → `spread`, Color+opacity → `color = Color(hex).copy(alpha = …)`. For an animated shadow, the `dropShadow(shape) { … }` lambda form exposes the same fields as mutable `ShadowScope` properties (`radius`/`spread` as px `Float`, `offset` as `Offset`) without allocating a new `Shadow` each frame. `Modifier.shadow(elevation, shape)` is still fine for a simple elevation shadow.

## Spacing & elevation scales — a custom CompositionLocal

M3 ships `colorScheme`, `typography`, and `shapes` — but **no spacing or elevation scale**. Define your design system's scale once and provide it alongside `MaterialTheme`, so call sites read named tokens (`spacing.md`) instead of scattering raw `dp` literals:

```kotlin
@Immutable
data class AppSpacing(
    val xs: Dp = 4.dp, val sm: Dp = 8.dp, val md: Dp = 16.dp,
    val lg: Dp = 24.dp, val xl: Dp = 32.dp,
)
val LocalAppSpacing = staticCompositionLocalOf { AppSpacing() }

@Immutable
data class AppElevation(val sm: Dp = 2.dp, val md: Dp = 4.dp, val lg: Dp = 8.dp)
val LocalAppElevation = staticCompositionLocalOf { AppElevation() }

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppSpacing provides AppSpacing()) {
        MaterialTheme { content() }
    }
}

// call site
val spacing = LocalAppSpacing.current
Column(
    verticalArrangement = Arrangement.spacedBy(spacing.sm),
    modifier = Modifier.padding(spacing.md),
) { /* … */ }
```

Use `staticCompositionLocalOf` — these tokens don't change after the theme is set (see `compose/references/composition-locals.md` for the static-vs-dynamic rule). This is the same custom-token mechanism `compose/references/theming-material3.md` uses for brand colours.

## Modifier ordering

Modifier order is load-bearing (sizing/layout → decoration → interaction, outer to inner). The full rules and common mistakes live in `compose/references/modifiers.md`.
