# ZigShot Progress Log

## April 2026

### Phase 4 Complete (2026-04-06)

All three OpenSpec changes landed in a single session:

**enhance-annotation-editor** -- 5/6 tasks
- Image flip fix in CGContext rendering
- Custom NSColorWell in toolbar (`.minimal` style)
- PNG one-click save + NSSavePanel with format picker (PNG/JPEG/PDF)
- Color picker keyboard shortcut (P key)

**editor-power-features** -- 42/44 tasks
- Highlight brush: freehand path tracking, Ramer-Douglas-Peucker simplification (max 100 pts), adjustable width (`[`/`]`) and opacity (Shift+`[`/`]`)
- PDF export: `savePDF(to:dpi:)` via Quartz PDFContext, one-click button + save dialog option
- Session persistence: `SessionManager` saves original image + Codable annotation JSON to `~/Library/Application Support/ZigShot/sessions/`
- Capture history: thumbnails + metadata in `~/Library/Application Support/ZigShot/history/`, "Recent Captures" submenu with dynamic population via NSMenuDelegate
- Rich text: Bold/Italic toggles, Left/Center/Right alignment, font picker popup (system + custom fonts)
- Custom fonts: `FontManager` imports TTF/OTF via `CTFontManagerRegisterFontsForURL(.process)`, validates on import
- Preferences: 3-tab window (General: format/location/color/width, Shortcuts: table view, Fonts: import/remove)
- UserDefaults wired into AppDelegate (default save location, format, color, stroke width)

**editor-enhancements** -- 11/12 groups
- Zoom controls: discrete steps 0.25-4.0x, `Cmd+=/Cmd+-/Cmd+0`, toolbar buttons + label, `scrollWheel` with Cmd modifier
- Share button: NSSharingServicePicker in title bar, `Cmd+Shift+S` shortcut
- Crop-aware annotations: `translated(by:dy:clippedTo:)` on all 9 descriptor types, `transformForCrop` offsets + clips, `applyCrop` now crops original and transforms (not bakes+clears)
- 17 new annotation transform tests (arrow, line, ruler, rect, blur, highlight, numbering, text translations + clipping + workflow)
- Groups 2-5, 7-9, 11 confirmed already implemented from prior work
- Group 10 (Truth Table) deferred -- niche feature

### Build Status
- Swift build: clean, no errors
- Test suite: 37/37 passing (20 pixel transforms + 17 annotation transforms)
- New files: FontManager, SessionManager, PreferencesWindow, StickyNoteRenderer, NumberingRenderer, OCRController
- Net change: ~2,800 lines added across 10 modified + 6 new Swift source files

### Phase 3 Complete (2026-04-05)

Annotation editor built in 4 commits:
1. `feat(core): add zs_image_copy_pixels and zs_composite_rgba to C API`
2. `feat(app): annotation model, editor window, and bridge extensions`
3. `feat(app): annotation editor canvas, 8 tools, toolbar, and text controller`
4. `feat(app): integrate annotation editor into capture flow`

### Phase 1-2 Complete (2026-04-04)

Foundation laid:
- Zig core with C API (`libzigshot.a` + `zigshot.h`)
- Swift app with ScreenCaptureKit capture
- Menu bar app with global hotkeys
- Area selection overlay + window picker
