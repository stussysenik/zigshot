# ZigShot Roadmap

## Phase 0: Foundation
**Status:** Complete

- [x] Zig core with image processing, annotations, blur
- [x] CLI-driven capture (fullscreen, area, window)
- [x] PNG/JPEG export
- [x] ObjC bridge for basic AppKit integration
- [x] Global hotkeys, menu bar app (prototype)

## Phase 1: Quality & Core API
**Status:** Complete

- [x] Build `c_api.zig` -- C-callable surface for all core operations
- [x] Add DPI metadata embedding to all export formats
- [x] Embed sRGB ICC color profile in exports
- [x] Add JPEG quality control (0.0-1.0 parameter)
- [x] Upgrade line rendering from Bresenham to Wu's anti-aliased algorithm
- [x] Add ruler annotation type (pixel distance measurement)
- [x] Generate `zigshot.h` C header
- [x] Compile to `libzigshot.a` static library
- [x] `zs_image_copy_pixels` and `zs_composite_rgba` for undo and text compositing
- [x] Full test suite for core (no OS deps)

## Phase 2: Swift App -- Capture
**Status:** Complete

- [x] Swift project setup (SPM, linking libzigshot.a via CZigShot)
- [x] ScreenCaptureKit integration -- fullscreen capture at native Retina resolution
- [x] Area selection overlay (semi-transparent, crosshair cursor, pixel coordinates)
- [x] Window picker (hover to highlight, click to capture)
- [x] Global hotkey registration (Cmd+Shift+3/4/5)
- [x] Permission handling (Screen Recording prompt)
- [x] Capture -> pixel buffer handoff to Zig core via C API
- [x] Menu bar app with status icon

## Phase 3: Swift App -- Annotation Editor
**Status:** Complete

- [x] Editor window (titled, resizable, image-centered with shadow)
- [x] Bottom toolbar with tool palette, color dots, action buttons
- [x] 12 annotation tools: Crop, Arrow, Rectangle, Text, Sticky Note, Highlight Brush, Blur, Line, Ruler, Numbering, Eraser, OCR
- [x] Anti-aliased rendering via Zig core + CoreGraphics preview
- [x] Color picker -- 5 preset + 5 custom colors, color well, keyboard shortcuts (1-5, P)
- [x] Line width control -- bracket keys [/]
- [x] Undo/Redo stack (Cmd+Z / Cmd+Shift+Z)
- [x] Selection, move, delete annotations
- [x] Keyboard shortcuts for all tools (C/A/R/T/S/H/B/L/U/N/E/O)
- [x] Freehand highlight brush with Ramer-Douglas-Peucker path simplification
- [x] Sticky note annotations with rounded-rect background + wrapped text
- [x] Numbering tool with auto-incrementing counter (persisted)
- [x] OCR text extraction via Vision framework (copy to clipboard)
- [x] Eraser tool (stroke-based annotation removal)
- [x] Crop tool with dimension label, dark overlay, corner handles
- [x] Crop-aware annotations -- coordinates transform instead of being destroyed
- [x] Image transforms: rotate CW/CCW, flip H/V

## Phase 4: Export, Polish & Power Features
**Status:** Complete

- [x] PDF export (one-click title bar button + save dialog)
- [x] PNG/JPEG export with DPI metadata
- [x] Copy to clipboard (PNG, lossless)
- [x] Save dialog with format picker (PNG/JPEG/PDF)
- [x] Share sheet (NSSharingServicePicker -- AirDrop, Messages, Mail, etc.)
- [x] Quick-save to default directory (Cmd+S)
- [x] Session persistence -- save/restore last edit (Cmd+Shift+L to reopen)
- [x] Capture history -- recent captures with thumbnails in menu bar submenu
- [x] Rich text annotations -- bold, italic, alignment, font picker
- [x] Custom font import (TTF/OTF via CTFontManager, app-scoped)
- [x] Preferences window (General / Shortcuts / Fonts tabs)
- [x] User-configurable defaults (save location, export format, color, stroke width)
- [x] Zoom controls (25%-400%, Cmd+/-/0, toolbar, scroll wheel)
- [x] Favorite color presets with UserDefaults persistence
- [x] 37 passing tests (pixel transforms + annotation transforms)

## Phase 5: Daily Driver Readiness
**Focus:** Polish to replace Shottr/CleanShot

- [ ] Click-to-record keyboard shortcut customization in Preferences
- [ ] Scrolling capture (auto-scroll + stitch)
- [ ] Pin screenshot (floating always-on-top window)
- [ ] Drag-and-drop from editor to other apps
- [ ] Capture sound (optional)
- [ ] App icon and branding
- [ ] DMG distribution packaging
- [ ] Notarization for Gatekeeper
- [ ] Screen recording (MP4/GIF via ScreenCaptureKit)
- [ ] Annotation templates / presets

## Phase 6: Linux Port
**Focus:** Native Linux app using same Zig core

- [ ] GTK4 application shell
- [ ] xdg-desktop-portal capture integration (Wayland + X11)
- [ ] PipeWire screen capture stream
- [ ] Selection overlay (GTK4 window)
- [ ] Annotation editor (GTK4 drawing area + Cairo)
- [ ] Clipboard (wl-copy / xclip)
- [ ] Global hotkeys (libkeybinder or portal)
- [ ] Export with same format support
- [ ] Flatpak / AppImage packaging

---

## Timeline Priorities

**Done:** Phases 0-4 (fully functional annotation editor with power features)
**Now:** Phase 5 (daily driver polish -- packaging, shortcuts, recording)
**Next:** Phase 6 (Linux port)

Each phase is independently shippable. Phases 0-4 give you a complete screenshot + annotation tool.
