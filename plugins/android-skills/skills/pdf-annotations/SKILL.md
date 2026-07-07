---
name: pdf-annotations
description: >
  Use when reading, adding, updating, or removing PDF annotations (highlight,
  free-text, stamp) or page objects (path/text/image) with Android's platform
  PDF APIs, or when saving those edits back to disk — the editing surface added
  in API 36.1 (PdfRenderer.Page) and SDK extension 18 (PdfRendererPreV.Page on
  API 31+), android.graphics.pdf.component. Covers the version gate, the
  open-edit-write workflow, and the id/render-flag/save contracts. Not for
  display-only PdfViewerFragment work, PdfDocument creation-from-scratch, form
  filling, or third-party PDF SDKs (iText, PDFBox, PSPDFKit).
---

# Platform PDF annotation & page-object editing

Android can natively edit PDF annotations since API 36.1 — before that the
platform story was render-only and the docs still say so: the Jetpack viewer
guide's PDF surface is `PdfViewerFragment`, which explicitly does **not**
support edit mode and hands annotation off to other apps via an
`android.intent.action.ANNOTATE` intent
[kb://android/develop/ui/views/layout/pdf/implement-pdf-viewer]. Do not
conclude "use a third-party library" for annotation work before applying the
version gate below.

## The version gate (decide the entry point first)

Two parallel renderers expose the same editing surface
(`android.graphics.pdf.component`):

| Entry point | Editing available | Device requirement |
|---|---|---|
| `PdfRenderer.Page` | API 36.1+ | platform release |
| `PdfRendererPreV.Page` | SDK extension 18 | API 31+ with the PDF module updated (PreV itself needs extension 13) |

Gate at runtime with `SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S)`
[kb://android/guide/sdk-extensions/index]. Extension 18 reaches back to API 31
via mainline updates, so `PdfRendererPreV` is the branch that covers most
devices.

## The workflow: open → edit → write

```kotlin
// The fd must be seekable — pipes/sockets are rejected at construction.
ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
    PdfRenderer(fd).use { renderer ->                    // or PdfRendererPreV on the ext-18 branch
        renderer.openPage(0).use { page ->
            // Only SUPPORTED annotation types are listed. The pairs are
            // android.util.Pair — NO Kotlin destructuring (no component1/2);
            // read them with .first / .second.
            val existing = page.getPageAnnotations()
            val staleId: Int? = existing.firstOrNull { it.second is FreeTextAnnotation }?.first

            val highlight = HighlightAnnotation(boundsList)   // List<RectF> quads
            val id = page.addPageAnnotation(highlight)
            check(id != -1) { "annotation rejected" }         // add returns -1, it does NOT throw

            highlight.color = newColor
            page.updatePageAnnotation(id, highlight)          // by id -> Boolean success
            staleId?.let { page.removePageAnnotation(it) }    // by id, not list position
        }
        // Write BEFORE close(), to a separate writable fd; the boolean is
        // removePasswordProtection (IOException if true and the doc stays encrypted).
        ParcelFileDescriptor.open(
            dest,
            ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_CREATE,
        ).use { out ->
            renderer.write(out, false)
        }
    }
}
```

Contracts:

- **`addPageAnnotation` returns the annotation id, or `-1` when the annotation
  cannot be added — check the return; only null/`UNKNOWN`-type/already-attached
  arguments throw** (`IllegalArgumentException`).
- **An annotation instance is single-attach document-wide**: adding one that is
  "already added in this page or some other page" throws. Construct a fresh
  component object per add; don't reuse a removed one across pages.
- **Ids, not list positions, drive `update`/`remove`.** `getPageAnnotations()`
  returns only annotation types the API models, so a page with unsupported
  annotations has gaps — the `Pair.first` id is the stable handle.
- **One page open at a time** — the pre-existing `PdfRenderer` invariant
  ("you can have only a single page opened at any given time") still applies;
  close the page before opening the next.
- **`write()` before `close()`**, destination must be a distinct writable
  seekable fd; `IllegalStateException` after close.
- **The pairs are `android.util.Pair`, not `kotlin.Pair`** — Kotlin
  destructuring (`for ((id, a) in …)`) does not compile against them; use
  `.first`/`.second`.

## Rendering what you edited

Annotation types render only when `RenderParams.renderFlags` includes them:
`FLAG_RENDER_TEXT_ANNOTATIONS` / `FLAG_RENDER_HIGHLIGHT_ANNOTATIONS` (and the
36.1 additions `FLAG_RENDER_FREETEXT_ANNOTATIONS` /
`FLAG_RENDER_STAMP_ANNOTATIONS`). An added stamp or free-text that "doesn't
show up" in your preview bitmap is usually a missing render flag, not a failed
add — re-render with the matching flags set via
`RenderParams.Builder.setRenderFlags(...)` and the `render(bitmap, clip,
transform, params)` overload. The render-mode constants live on
**`RenderParams`** (and legacy `PdfRenderer.Page`) — `PdfRendererPreV.Page`
has none, so on the PreV branch write
`RenderParams.Builder(RenderParams.RENDER_MODE_FOR_DISPLAY)`; qualifying it
via `PdfRendererPreV.Page` does not compile.

## Component vocabulary (android.graphics.pdf.component)

- `HighlightAnnotation(List<RectF>)` — quad list, one rect per highlighted run.
- `FreeTextAnnotation(RectF, String)` — bounds + text; text/background colors
  settable.
- `StampAnnotation(RectF)` — a container: **only** `PdfPagePathObject`,
  `PdfPageTextObject`, or `PdfPageImageObject` children (`addObject`), per the
  class contract.
- Page objects also attach directly to the page (`addPageObject` /
  `getPageObjects` / `updatePageObject` / `removePageObject` — same id-based
  contract as annotations), and carry a transform matrix
  (`PdfPageObject.setMatrix`/`transform`). `PdfPagePathObject` stroke defaults
  to opaque black in sRGB.
- `Page.getTopPageObjectAtPosition(PointF, …)` hit-tests the topmost object —
  use it for tap-to-select before update/remove.

## Out of scope (route elsewhere)

Creating PDFs from scratch (`PdfDocument` canvas API), form filling
(`applyEdit`, API 35), text extraction/search, and embedding a viewer UI
(`PdfViewerFragment` — display-only
[kb://android/develop/ui/views/layout/pdf/implement-pdf-viewer]) are separate
surfaces; third-party SDKs remain the answer only below the version gate or
for annotation types the component API doesn't model.
