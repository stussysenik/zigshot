# Design: Enhance Annotation Editor

## Architecture Decisions

### Custom Color Picker

**Approach:** Add an `NSColorWell` after the 5 preset color dots in the toolbar. When the user picks a custom color, it deselects the active preset dot and applies the chosen color to the editor.

**Why NSColorWell:** Native macOS color picker — no custom UI to build, supports hex input, eyedropper, and color space conversion out of the box. Matches the platform convention (Shottr, Skitch, Preview all use the system color panel).

**Integration:**
- `AnnotationToolbar` gets a new `NSColorWell` added to the color section stack
- The well's action fires `onColorChanged` with the picked color
- Selecting a preset dot resets the well's color to match (sync both ways)

### Save/Export Actions

**Approach:** Three distinct title bar buttons with clear behavior:

| Button | Action |
|--------|--------|
| **PNG** | Quick-save to Desktop as PNG (no dialog, instant feedback) |
| **Save** | NSSavePanel dialog — user picks location, format (PNG/JPEG), filename |
| **Copy** | Copy to clipboard as PNG and dismiss (existing behavior, works) |

**Why this split:** The user wants an "immediate save" option (PNG button) AND a proper save dialog (Save button). This mirrors Shottr's UX where Cmd+S quick-saves and Cmd+Shift+S opens Save As.

**NSSavePanel integration:**
- Accessory view with format picker (PNG / JPEG)
- Default filename: `ZigShot-{timestamp}`
- Default location: Desktop (or last-used directory)
- JPEG quality slider shown only when JPEG selected

### Image Flip Fix

**Root cause:** `AnnotationEditorView.isFlipped` returns `true` (Y=0 at top), but `CGContext.draw(cgImage, in: rect)` maps image bottom to `rect.minY`. In flipped context, `minY` is at the visual top, so the image renders upside-down.

**Fix:** Counter-flip the context around the image rect's vertical center before drawing:
```swift
ctx.translateBy(x: 0, y: imageRect.minY + imageRect.maxY)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(cgImage, in: imageRect)
```

This is already applied in the current session.
