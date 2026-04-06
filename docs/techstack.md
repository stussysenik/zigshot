# ZigShot Tech Stack

## Architecture: Shared Core + Native Shell

```
┌──────────────────┐     ┌──────────────────┐
│   macOS App      │     │   Linux App       │
│   Swift/AppKit   │     │   GTK4 (future)   │
└────────┬─────────┘     └────────┬──────────┘
         │ C FFI                  │ C FFI
         ▼                        ▼
┌─────────────────────────────────────────────┐
│          libzigshot.a  (Zig Core)           │
│   Image processing, annotations, encoding  │
└─────────────────────────────────────────────┘
```

## Zig Core (`core/`)

| Component | Purpose | Key Details |
|-----------|---------|-------------|
| `image.zig` | RGBA pixel buffer type | 8-bit per channel, stride-aware |
| `annotation.zig` | Annotation rendering | Arrow, Rect, Blur, Ruler, Line, Ellipse, Highlight |
| `pipeline.zig` | Image compositing & rendering | Anti-aliased (Wu's algorithm), Porter-Duff blending |
| `blur.zig` | Gaussian blur | Configurable radius, box-blur approximation |
| `format.zig` | Multi-format encoder | PNG, JPEG, WebP, TIFF, HEIF |
| `quality.zig` | Quality metadata | DPI, ICC color profiles, compression level |
| `geometry.zig` | Spatial math | Point, Size, Rect, distance, intersection |
| `c_api.zig` | C-callable API surface | What Swift calls via FFI |

**Zero OS dependencies.** Pure computation. Compiles on any platform Zig supports.

**Build:** `zig build` produces `libzigshot.a` (static library) + `include/zigshot.h` (C header).

### Key C API Functions

| Function | Purpose |
|----------|---------|
| `zs_image_create` / `zs_image_create_empty` | Create image from pixels or blank |
| `zs_image_copy_pixels` | Copy pixels between images (undo reset) |
| `zs_composite_rgba` | Overlay RGBA bitmap (text/numbering compositing) |
| `zs_annotate_arrow` / `zs_annotate_line` / `zs_annotate_rect` | Draw primitives |
| `zs_annotate_blur` | Gaussian blur region (redaction) |
| `zs_annotate_highlight` | Semi-transparent overlay |
| `zs_annotate_ruler` | Measurement line with distance |
| `zs_annotate_ellipse` | Draw ellipse annotation |

## macOS App (`app/`)

| Technology | Purpose |
|------------|---------|
| **Swift 5.9+** | App language |
| **AppKit** | GUI framework (NSWindow, NSView, NSMenu) |
| **ScreenCaptureKit** | Modern screen capture (macOS 14+) |
| **CoreGraphics** | On-screen anti-aliased rendering, PDF export |
| **CoreText** | Custom font registration (CTFontManager) |
| **Vision** | OCR text extraction (VNRecognizeTextRequest) |
| **ImageIO** | PNG/JPEG export with DPI metadata |
| **CGEvent** | Global hotkey registration |
| **NSPasteboard** | Clipboard integration |
| **NSSharingServicePicker** | System share sheet |
| **SPM** | Build system, links libzigshot.a |

**Target:** macOS 14+ (Sonoma)

### Swift Source Files

| File | Purpose | LOC |
|------|---------|-----|
| `AppDelegate.swift` | Menu bar app, capture flow, editor wiring | ~440 |
| `AnnotationEditorView.swift` | Canvas NSView, mouse/key events, zoom, transforms | ~730 |
| `AnnotationEditorWindow.swift` | Window chrome, title bar buttons (PDF/PNG/Save/Share/Copy) | ~210 |
| `AnnotationModel.swift` | Descriptor enum (9 types), Codable, undo/redo, crop transforms | ~560 |
| `AnnotationToolHandler.swift` | Tool protocol + 10 tool implementations | ~700 |
| `AnnotationToolbar.swift` | Bottom toolbar: 12 tools, colors, fonts, zoom, transforms | ~870 |
| `TextEditingController.swift` | Inline NSTextView editing, text bitmap rendering | ~210 |
| `ZigShotBridge.swift` | Swift wrapper for C API, image transforms, export | ~360 |
| `CaptureManager.swift` | ScreenCaptureKit fullscreen/area/window capture | ~110 |
| `SessionManager.swift` | Session persistence + capture history | ~180 |
| `FontManager.swift` | Custom font import/registration (TTF/OTF) | ~130 |
| `PreferencesWindow.swift` | Preferences with General/Shortcuts/Fonts tabs | ~370 |
| `StickyNoteRenderer.swift` | Sticky note bitmap rendering | ~85 |
| `NumberingRenderer.swift` | Numbered circle bitmap rendering | ~85 |
| `OCRController.swift` | Vision framework OCR integration | ~45 |
| `HotkeyManager.swift` | Global hotkey registration | ~50 |
| `SelectionOverlay.swift` | Area selection overlay | ~100 |
| `WindowPicker.swift` | Window selection for capture | ~80 |

### Annotation System

9 annotation types, each with:
- **Descriptor** (Codable enum with associated values)
- **Tool Handler** (mouse gesture -> descriptor)
- **Renderer** (Zig bridge or Swift bitmap)
- **Toolbar button** (SF Symbol, hover state, keyboard shortcut)

```
AnnotationDescriptor
  ├── .arrow(from:to:color:width:)
  ├── .rectangle(rect:color:width:)
  ├── .line(from:to:color:width:)
  ├── .blur(rect:radius:)
  ├── .highlightPath(points:color:width:opacity:)
  ├── .ruler(from:to:color:width:)
  ├── .numbering(position:number:color:)
  ├── .text(position:content:fontSize:color:fontName:isBold:isItalic:alignment:)
  └── .stickyNote(rect:content:fontSize:bgColor:textColor:fontName:isBold:isItalic:alignment:)
```

## Testing

| Suite | Framework | Tests | Coverage |
|-------|-----------|-------|----------|
| Pixel transforms | XCTest + CZigShot | 20 | Crop, rotate, flip, CGImage roundtrip |
| Annotation transforms | XCTest | 17 | Coordinate translation, crop clipping |
| Zig core | Zig test | ~50 | Image ops, blur, annotations |

```bash
cd app && swift test    # 37 tests, all passing
cd core && zig build test  # Zig core tests
```

## Linux App (`app-linux/`, future)

| Technology | Purpose |
|------------|---------|
| **GTK4** | GUI framework |
| **xdg-desktop-portal** | Screen capture (Wayland-compatible) |
| **PipeWire** | Screen capture stream |
| **wl-copy / xclip** | Clipboard |
| **libkeybinder** | Global hotkeys |
| **Meson or Zig** | Build system |

## CLI (`cli/`)

The original Zig CLI remains functional. Uses the same `core/` library. Good for scripting, CI pipelines, automation.

## Build Pipeline

```bash
# Step 1: Build Zig core
cd core && zig build -Doptimize=ReleaseSafe
# Produces: zig-out/lib/libzigshot.a + include/zigshot.h

# Step 2: Build Swift app (links libzigshot.a)
cd app && swift build

# Step 3: Run tests
cd app && swift test               # 37 Swift tests
cd core && zig build test          # Zig core tests
```

## Dependencies

| Dependency | Type | Why |
|------------|------|-----|
| Zig 0.15.x | Build-time | Core library compiler |
| Xcode 16+ | Build-time | Swift app compiler |
| macOS 14+ SDK | Build-time | ScreenCaptureKit, modern AppKit, Vision |
| **No runtime dependencies** | -- | Static linking, system frameworks only |
