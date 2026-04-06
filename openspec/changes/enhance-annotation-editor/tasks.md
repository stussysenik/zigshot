# Tasks: Enhance Annotation Editor

- [x] **Task 1: Verify image flip fix**
  - File: `app/Sources/ZigShot/AnnotationEditorView.swift:153-163`
  - Counter-flip transform applied. Build passes, image displays right-side-up.

- [x] **Task 2: Add custom color well to toolbar**
  - File: `app/Sources/ZigShot/AnnotationToolbar.swift`
  - Added `NSColorWell` (`.minimal` style on macOS 13+) after preset color dots.
  - Wired to `onColorChanged`. Preset dot selection syncs the well; custom color deselects all dots.

- [x] **Task 3: Wire PNG button for quick-save**
  - Files: `AnnotationEditorWindow.swift`, `AppDelegate.swift`
  - Added `onPNG` callback. PNG button saves `ZigShot-{timestamp}.png` to default save directory with DPI metadata.
  - Annotations baked via `rerender()` before save.

- [x] **Task 4: Wire Save button to NSSavePanel**
  - Files: `AnnotationEditorWindow.swift`, `AppDelegate.swift`
  - Save button opens NSSavePanel as sheet. Format picker accessory (PNG/JPEG/PDF).
  - Default filename `ZigShot-{timestamp}`, default location from UserDefaults.
  - JPEG saves at 92% quality. Dismisses window after save.

- [x] **Task 5: Add keyboard shortcut for color picker**
  - File: `app/Sources/ZigShot/AnnotationEditorView.swift`
  - "P" key opens `NSColorPanel.shared`.

- [ ] **Task 6: Verify all 12 annotation tools render correctly**
  - Manual verification pass: Crop, Arrow, Rectangle, Text, Sticky Note, Highlight, Blur, Line, Ruler, Numbering, Eraser, OCR.
  - Depends on visual testing in simulator.
