# Enhance Annotation Editor

## Status: DRAFT

## Summary

Fix the upside-down image rendering bug, add a custom color picker to the toolbar, and wire up the save/export actions (PNG format picker, Save As dialog, immediate copy).

## Motivation

The annotation editor has three gaps that block daily-driver usage:

1. **Image renders upside-down** — `CGContext.draw` in a flipped NSView renders the capture inverted. Already fixed in this session (counter-flip transform in `draw(_:)`), needs verification.

2. **No custom color** — The toolbar offers 5 preset color dots (red, yellow, blue, green, black) but no way to pick an arbitrary color. Power users (design engineers using Figma precision tools) need exact hex colors.

3. **Save/export stubs** — The "PNG" title bar button is a no-op stub. "Save" writes directly to `~/Desktop` with no dialog. Users need a proper NSSavePanel for Save As, and the PNG button should offer format selection (PNG vs JPEG).

## Scope

- `AnnotationEditorView.swift` — image flip fix (done)
- `AnnotationToolbar.swift` — add custom color well after color dots
- `AnnotationEditorWindow.swift` — wire PNG button to format picker, Save to NSSavePanel
- `AppDelegate.swift` — update save/copy handlers

## Out of Scope

- New annotation tool types
- Multi-image editing
- Cloud export
