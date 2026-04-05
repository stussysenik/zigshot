# Phase 3: Annotation Editor — Design Specification

## Design DNA

iA Writer (content-first, interface disappears) + Things (progressive disclosure, delight) + CW&T (extreme craft, nothing superfluous) + Bakken & Bæck (Scandinavian clarity, quiet confidence). Every pixel earns its place. Simplicity is the ultimate sophistication.

## Philosophy

**One surface. The screenshot is the interface.**

After capture, the image appears centered on a softly dimmed screen. No window chrome. No title bar. No panels. Just your screenshot, floating. A single slim toolbar hovers below — barely there. The fastest path is capture → Cmd+C → gone. The tool completes and vanishes, like Things' quick entry.

No modes. No "view mode" vs "edit mode." The image is always annotatable. Click and drag without selecting a tool? Arrow — the most common annotation. The tool just appears in your hand.

## The Surface

### Canvas

- Borderless fullscreen `NSWindow` (`.borderless` style mask)
- Dimmed backdrop: 40% black over the entire screen
- Captured image floats centered with a subtle drop shadow (like a card on a desk)
- The canvas is the screen itself — no window chrome, no title bar

### Toolbar

A single floating pill below the image. Frosted glass (`NSVisualEffectView`, `.hudWindow` material), 12px border-radius.

8 tool icons in a row, 28pt each, monochrome at 50% opacity. Brighten to 100% on hover. No labels by default — tooltip appears after 0.5s hover pause.

```
╭───────────────────────────────────╮
│  ↗  ▭  ◻  ⊘  T  ▬  📏  ①      │
╰───────────────────────────────────╯
 Arrow Rect Blur High Text Line Ruler Num
```

### Action Buttons

Below the toolbar, right-aligned: **Copy** (primary, filled), **Save**, **Discard**. Small, quiet. Copy is the default action — pressing Enter triggers it.

### Contextual Config Pill

Select a tool → a small secondary pill fades in beside the toolbar:
- 5 preset color dots + custom color picker
- Thickness slider (stroke width)

Change tool → config pill morphs to match the new tool's options. No tool selected → config pill disappears. Like Things' task detail — present when needed, invisible when not.

### Default Color Presets

1. Red (#FF3B30) — primary annotation color
2. Yellow (#FFCC00) — highlight
3. Blue (#007AFF) — informational
4. Green (#34C759) — approval/success
5. White (#FFFFFF) — on dark backgrounds

Default stroke width: 3px. Default annotation color: Red.

## Tools (8 total)

### Arrow (A)

Click and drag start → end. Renders anti-aliased line with arrowhead at endpoint. Uses Zig's `zs_annotate_arrow` (Wu's AA algorithm). Configurable: color, stroke width.

### Rectangle (R)

Click and drag to define bounding rect. Outline only (no fill). Rounded corners: 4px radius. Configurable: color, stroke width. Shift-constrain: perfect square.

### Blur (B)

Click and drag a rectangle → region under it blurs. Gaussian blur only — no pixelation. Drag handles to resize after placing. Configurable: blur radius (default 10px). **Preview strategy:** during drag, show a 50%-resolution blur preview for responsiveness; full-resolution blur renders on mouseUp via Zig's `blurRegion`.

### Highlight (H)

Click and drag a rectangle → semi-transparent color overlay. Default yellow at 40% opacity. Configurable: color, opacity.

### Text (T)

Click canvas → NSTextView appears at click point. Just type. One typeface: SF Pro (system font). Size adjustable via `[` / `]` keys. Click elsewhere or press Escape → text commits. No font dialog, no formatting panel. Configurable: color, font size (default 16pt).

### Line (L)

Click and drag start → end. Anti-aliased line (no arrowhead). Uses Zig's `zs_annotate_line`. Configurable: color, stroke width. Shift-constrain: 45° angle snapping.

### Ruler (U)

Click start → drag to end → pixel distance label appears along the measurement line. Label auto-positions to avoid overlapping the line. Developer-grade precision (displays px value). Uses Zig's `zs_annotate_ruler`. Configurable: color.

### Numbering (N)

Click → circle with "1" appears. Click again → "2". Auto-incrementing. Delete a number → remaining numbers renumber automatically. Circle has filled background with white text. Configurable: color (circle fill color). Size: 28px diameter.

## Interaction Model

### Drawing

One gesture = one annotation. Click → drag → release. Shape renders in real-time during drag (rubber-band preview via Core Graphics). Committed to Zig pixel buffer on mouseUp. No confirmation dialogs, no "click to place then drag handles."

### Default Tool

No tool selected = Arrow. Click and drag on canvas without picking anything? Arrow. The most common action has zero setup.

### Selection

**Hit-testing priority:** mouseDown first checks if the click hits an existing annotation. If yes → select it (regardless of active tool). If no → use the active tool to draw. This means you can always grab and move annotations without switching tools.

Click existing annotation → subtle selection handles appear (small circles at corners/endpoints, 60% opacity, 6px diameter). Drag body to move. Drag handles to resize. Press Delete to remove. Click empty canvas → deselect.

### Constraint Modifiers

- `Shift` while drawing → perfect squares, straight 45° lines, circles
- `Option` while drawing rect/ellipse → draw from center outward

### Text Editing

Click canvas with Text tool → NSTextView appears. Type freely. Full Unicode/emoji/IME support via native NSTextView. Click elsewhere → commit. Escape while editing text → cancel text (not close editor). Text renders into Zig buffer via Swift's `NSAttributedString.draw(in:)` composited into pixel buffer.

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `A` | Arrow tool |
| `R` | Rectangle tool |
| `B` | Blur tool |
| `H` | Highlight tool |
| `T` | Text tool |
| `L` | Line tool |
| `U` | Ruler tool |
| `N` | Numbering tool |
| `Cmd+C` | Copy to clipboard and close |
| `Cmd+S` | Save to file |
| `Cmd+Z` | Undo |
| `Cmd+Shift+Z` | Redo |
| `Enter` | Copy to clipboard and close |
| `Esc` | Cancel current action (text edit, drawing), or close editor if idle |
| `1`–`5` | Quick color presets |
| `[` / `]` | Decrease / increase stroke width |
| `Delete` | Remove selected annotation |

## Undo/Redo

Custom enum-based dual-stack. Not Apple's UndoManager.

```swift
enum UndoEntry {
    case added(AnnotationDescriptor)
    case deleted(AnnotationDescriptor, Int)  // annotation + former index
    case modified(old: AnnotationDescriptor, new: AnnotationDescriptor)
}
```

Every mouseUp that changes state = one undo entry. Moving or resizing = one entry. `Cmd+Z` pops from undoStack, applies inverse, pushes to redoStack. Any new action clears redoStack.

On undo of an `added` entry: remove annotation from model, re-render all remaining annotations from original image via Zig.

## Architecture

**Swift owns interaction and model. Zig owns pixels. C API is the membrane.**

### Rendering Pipeline — Two Layers, One View

1. **Base layer:** Original capture + all committed annotations, rendered by Zig into pixel buffer. Wrapped as CGImage via `CGDataProvider` (zero-copy — reads Zig memory directly). Re-rendered only when annotations change.

2. **Preview layer:** In-progress annotation drawn with Core Graphics in `draw()`. Updates every mouseDragged. One shape — trivially fast.

Layer-backed NSView with `layerContentsRedrawPolicy = .onSetNeedsDisplay`. No Metal — overkill for tens of shapes.

### Data Flow

```
User Input (mouse/keyboard)
       │
       ▼
 AnnotationEditorView (NSView, layer-backed)
       │
       ├── draw() renders:
       │     1. Zig pixel buffer as CGImage (committed)
       │     2. Core Graphics overlay (in-progress)
       │
       ├── Mouse events → ToolHandler protocol
       │     - start(at:)    ← mouseDown
       │     - update(to:)   ← mouseDragged
       │     - finish()      ← mouseUp → zs_annotate_*
       │
       ├── AnnotationModel (flat array, painter's algorithm)
       │     - [AnnotationDescriptor] source of truth
       │     - undoStack / redoStack
       │     - On undo: re-render all from original
       │
       └── AnnotationToolbar (frosted pill)
             - Tool buttons + contextual config pill
```

### Text Rendering Split

Zig has zero OS dependencies — no font rasterization. Text annotations render via Swift's `NSAttributedString.draw(in:)` into a temporary CGContext. Those pixels are composited into the Zig buffer for export.

### Export Path

1. Create fresh Zig image from original capture pixels
2. Replay all annotations from model via `zs_annotate_*`
3. Composite text annotation bitmaps from Swift
4. `CGImageDestination` (ImageIO) encodes with DPI/ICC metadata
5. Copy to clipboard or save to disk

## New Files

### Swift (in `app/Sources/ZigShot/`)

| File | Purpose |
|------|---------|
| `AnnotationEditorWindow.swift` | Borderless NSWindow, dimmed backdrop, window lifecycle |
| `AnnotationEditorView.swift` | Canvas NSView — draw loop, mouse dispatch, coordinate transforms |
| `AnnotationModel.swift` | Annotation descriptor array, undo/redo stacks, re-render logic |
| `AnnotationToolHandler.swift` | Protocol + 8 concrete tool handlers (Arrow, Rect, Blur, etc.) |
| `AnnotationToolbar.swift` | Frosted pill toolbar, tool buttons, contextual config pill |
| `TextEditingController.swift` | NSTextView overlay lifecycle for Text tool |

### Zig (in `src/core/`)

Minimal additions — the C API already exposes all annotation functions:

| Addition | Purpose |
|----------|---------|
| `zs_render_all` in `c_api.zig` | Batch re-render: accepts annotation descriptor array, replays all onto image |
| `zs_composite_rgba` in `c_api.zig` | Overlay pre-rendered text bitmap onto image at (x, y) |

## Performance Targets

- Mouse tracking: < 2ms per `mouseDragged` (CG overlay only)
- Annotation commit: < 16ms per `zs_annotate_*` call (under one frame at 60fps)
- Full re-render on undo: < 50ms for 20 annotations on a 4K image
- Export: < 200ms for full composite + PNG encode
- Editor open: < 100ms from capture to visible editor

## Success Criteria

1. Capture → editor visible in < 100ms
2. All 8 tools work with anti-aliased rendering
3. Default action (no tool selection, just drag) draws an arrow
4. Cmd+C / Enter copies annotated image and closes editor in < 200ms
5. Undo/redo works for all operations including text
6. Keyboard shortcuts for every tool (single-key)
7. Toolbar feels invisible — content dominates, chrome recedes
8. Exported image is pixel-identical whether saved from editor or re-rendered from model
9. Zero configuration required for first use — sensible defaults for everything

## Out of Scope (Phase 3)

- Zoom/pan on canvas (Phase 4)
- Export format dialog with quality slider (Phase 4)
- Pin-to-desktop floating screenshots (Phase 4)
- Canvas expansion beyond original capture bounds (Phase 4)
- Crop tool (Phase 4)
- Cloud upload / sharing (Phase 5)
