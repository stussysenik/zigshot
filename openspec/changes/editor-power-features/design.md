## Context

ZigShot is a Zig-core + Swift-shell screenshot tool. The annotation editor (Phase 3) is functional with 12 tools, undo/redo, and PNG/JPEG export. All rendering flows through a Zig pixel buffer via C FFI. The app is a menu bar agent with no persistent state between sessions. Text annotations use system font only, no formatting controls.

Current architecture: `AppDelegate` → `AnnotationEditorWindow` (NSWindow) → `AnnotationEditorView` (NSView canvas) → `AnnotationToolbar` (NSView bottom bar). Annotations are `AnnotationDescriptor` enum cases rendered via `AnnotationModel.renderAll()`. No user preferences exist.

## Goals / Non-Goals

**Goals:**
- Highlight tool that feels like a real highlighter pen (freehand, rounded, variable width)
- One-click PDF and PNG export from title bar
- Re-open the last edited screenshot with annotations intact
- Browse recent captures from the menu bar
- Rich text annotations (bold, italic, alignment, custom fonts)
- User-configurable keyboard shortcuts and defaults via Preferences

**Non-Goals:**
- Cloud sync of captures or settings
- Annotation templates or presets (Phase 5)
- Drag-and-drop export (Phase 4 separate work)
- WebP export (not enough demand yet)
- Multi-page PDF support (single image per PDF)

## Decisions

### D1: Highlight — Freehand path instead of rectangle

**Choice**: Store highlight as an array of `CGPoint` + width + color, rendered as a thick rounded-cap stroke with alpha blending.

**Why**: The current rect-fill highlight looks cheap. A freehand path with rounded caps feels like a real highlighter. This matches Shottr/CleanShot behavior.

**Alternative rejected**: Keeping rect but adding rounded corners — still doesn't give the marker feel users expect.

**Implementation**: New `AnnotationDescriptor.highlightPath(points: [CGPoint], color: NSColor, width: UInt32)` replaces the existing `.highlight(rect:color:)` case. The Zig side already has line-drawing primitives; we render as a series of thick line segments with round caps. Preview draws via Core Graphics `CGContext.addLines()` with round line cap.

### D2: Session persistence — JSON + PNG in Application Support

**Choice**: On editor close (copy/save/PNG actions), serialize `{original: URL, annotations: [JSON], timestamp}` to `~/Library/Application Support/ZigShot/sessions/last.json` and save the original image as `last-original.png`. On "Re-open Last" (Cmd+Shift+L), deserialize and restore.

**Why**: Simplest approach that covers the core use case. No database, no migration complexity.

**Alternative rejected**: SQLite store — overkill for "last edit" + 50 recent captures. JSON files are inspectable and trivial to implement.

**Annotation serialization**: Add `Codable` conformance to `AnnotationDescriptor` via a custom `CodingKeys` enum. NSColor serializes as hex string. CGPoint/CGRect use standard Codable.

### D3: Capture history — Thumbnail directory with metadata index

**Choice**: Save thumbnails (max 300px wide) + metadata JSON for last 50 captures in `~/Library/Application Support/ZigShot/history/`. Menu bar gets a "Recent Captures" submenu with thumbnail + timestamp. Clicking re-opens in editor.

**Why**: File-based approach is simple, debuggable, and doesn't require a database dependency.

**Cleanup**: On app launch, prune entries older than 50 to cap disk usage. Each thumbnail is ~30-50KB, so 50 entries ≈ 2.5MB max.

### D4: PDF export — Quartz PDFContext

**Choice**: Use `CGContext(url:mediaBox:)` with PDF media type. Draw the final composited CGImage into a single-page PDF. Add "PDF" button to title bar accessory alongside PNG.

**Why**: Quartz PDF is built into macOS, zero dependencies. ImageIO doesn't support PDF writing, but CGContext does natively.

**Alternative rejected**: Using PDFKit's PDFDocument — heavier API, more code, no benefit for single-image PDFs.

### D5: Rich text — NSAttributedString attributes in AnnotationDescriptor

**Choice**: Extend `AnnotationDescriptor.text` to carry `fontName: String?`, `isBold: Bool`, `isItalic: Bool`, `alignment: NSTextAlignment`. Toolbar shows formatting controls when text/stickyNote tool is active.

**Why**: Attribute-based approach keeps the descriptor simple. The font name is a string (system font name or custom font PostScript name).

**UI**: When text/stickyNote tool is selected, toolbar shows: `[B] [I] [L|C|R] [Font ▾] [12|16|20|24|32]`. Font dropdown is an NSPopUpButton with system fonts + user-imported fonts.

### D6: Custom fonts — CTFontManagerRegisterFontsForURL

**Choice**: Load user `.ttf`/`.otf` files via `CTFontManagerRegisterFontsForURL` with `.process` scope (app-only, no system install). Store font files in `~/Library/Application Support/ZigShot/fonts/`. Font picker shows them alongside system fonts.

**Why**: Process-scoped registration is the macOS-blessed way to use fonts without polluting the user's system font library.

### D7: Preferences — NSWindow with tab view

**Choice**: Native `NSWindow` with `NSTabView` (not SwiftUI Settings). Tabs: General, Shortcuts, Fonts.

- **General**: Default export format (PNG/JPEG/PDF), default save location, default annotation color, default stroke width
- **Shortcuts**: Table of action → shortcut pairs. Click to record new shortcut. Stored in UserDefaults.
- **Fonts**: List of imported fonts with Add/Remove buttons. Font files managed by FontManager.

**Why**: NSWindow matches the existing AppKit architecture. SwiftUI Settings scene requires SwiftUI app lifecycle which we don't use.

**Shortcut storage**: Dictionary `[String: String]` in UserDefaults mapping action identifiers to key-equivalent strings. HotkeyManager reads these on launch.

## Risks / Trade-offs

- **Highlight path storage size**: Freehand paths can have hundreds of points per stroke → JSON gets large. Mitigation: Downsample path to ~50 points max using Ramer-Douglas-Peucker before storing.
- **Font loading edge cases**: Some fonts have unusual PostScript names or require specific activation. Mitigation: Validate font loads successfully before adding to the picker; show error if not.
- **Session persistence on crash**: If the app crashes, last session isn't saved. Mitigation: Auto-save session state periodically (every 5 annotations or 30 seconds). Acceptable for v1 to only save on clean close.
- **Preferences complexity**: Adding a full preferences system is the largest piece of this change. Mitigation: Ship General tab first, Shortcuts tab second. Shortcuts editor is complex (conflict detection, recording UI).
- **Breaking AnnotationDescriptor change**: Replacing `.highlight(rect:color:)` with `.highlightPath(points:color:width:)` breaks any code that pattern-matches on the old case. Mitigation: No annotations are persisted yet, so this is safe today. Once session persistence ships, we'll need migration.
