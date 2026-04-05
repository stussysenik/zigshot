# ZigShot Native Redesign — Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Approach:** B — Swift GUI + Zig Core Library

---

## Context

ZigShot is a Zig-based screenshot tool currently macOS-only with CLI-driven annotations. The current implementation suffers from:

1. **Low-quality captures** — no DPI metadata, no color profile embedding, no quality controls on export
2. **CLI-only annotations** — not viable for daily use (need GUI like Shottr/CleanShot X)
3. **No anti-aliasing** — Bresenham rendering produces jagged lines
4. **Limited format support** — PNG/JPEG only, no WebP/TIFF/HEIF, no quality slider

**Goal:** Ship a native macOS GUI screenshot tool (daily driver) with a portable Zig core that will later power a Linux version.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Swift macOS App                 │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐  │
│  │  Capture   │  │  Editor  │  │   Export      │  │
│  │ (SCKit)    │  │ (Canvas) │  │ (Format/     │  │
│  │            │  │          │  │  Clipboard)   │  │
│  └─────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│        │              │               │          │
│  ┌─────▼──────────────▼───────────────▼───────┐  │
│  │           ZigShotBridge.swift               │  │
│  │         (Swift wrapper around C API)        │  │
│  └─────────────────┬──────────────────────────┘  │
└────────────────────┼─────────────────────────────┘
                     │ C FFI
┌────────────────────▼─────────────────────────────┐
│              libzigshot.a (Zig Core)             │
│  ┌──────────┐ ┌────────┐ ┌────────┐ ┌─────────┐ │
│  │ pipeline │ │  blur  │ │ format │ │ quality │ │
│  │ annotate │ │        │ │ encode │ │ DPI/ICC │ │
│  └──────────┘ └────────┘ └────────┘ └─────────┘ │
│  ┌──────────┐ ┌────────┐ ┌─────────────────────┐ │
│  │  image   │ │geometry│ │      c_api          │ │
│  │  RGBA    │ │        │ │ (C-callable surface) │ │
│  └──────────┘ └────────┘ └─────────────────────┘ │
└──────────────────────────────────────────────────┘
```

**Separation principle:** Zig core has ZERO OS dependencies. It takes pixel buffers in, produces pixel buffers out. All platform capture and GUI lives in Swift. Future Linux version replaces Swift with GTK4, same Zig core.

---

## Capture Pipeline

### Current Problem
- `CGWindowListCreateImage` + `CGImageDestinationAddImage(dest, cg_image, null)` — that `null` discards all image properties (DPI, color profile, quality)
- No Retina DPI metadata embedded in output files
- Viewers display screenshots at wrong scale, making them look soft

### Solution: ScreenCaptureKit (Swift)

```swift
// Modern capture API — replaces CGWindowListCreateImage
let filter = SCContentFilter(display: display, excludingWindows: [])
let config = SCStreamConfiguration()
config.scalesToFit = false              // Full native resolution
config.pixelFormat = kCVPixelFormatType_32BGRA
config.colorSpaceName = CGColorSpace.sRGB
config.width = display.width * scaleFactor   // Retina-aware
config.height = display.height * scaleFactor
```

**Capture modes:**
| Mode | Trigger | Implementation |
|------|---------|----------------|
| Fullscreen | Cmd+Shift+3 | `SCScreenshotManager.captureImage(contentFilter:configuration:)` |
| Area | Cmd+Shift+4 | Selection overlay → crop from fullscreen capture |
| Window | Cmd+Shift+5 | `SCContentFilter(desktopIndependentWindow:)` |

**Pixel handoff to Zig:**
```
SCScreenshot → CVPixelBuffer → lock base address → pass (ptr, width, height, stride) to Zig C API
```

---

## Format & Quality Strategy

### Guiding Principle
"Best fidelity and compatible formats when space allows, middle-ground with minimal loss."

### Format Matrix

| Format | Use Case | Quality | File Size | Compatibility |
|--------|----------|---------|-----------|---------------|
| **PNG** | Default save, clipboard | Lossless | Large | Universal |
| **JPEG** | Quick share, web upload | Configurable (0.0-1.0, default 0.92) | Small | Universal |
| **WebP** | Modern web, Discord/Slack | Lossless or lossy, default 0.90 | Smallest | Broad (not universal) |
| **TIFF** | Archival, print | Lossless | Largest | Professional tools |
| **HEIF** | Apple ecosystem | Near-lossless, tiny | Very small | Apple + modern browsers |

### Quality Controls (Zig Core)

```zig
pub const ExportConfig = struct {
    format: Format = .png,
    quality: f32 = 0.92,          // 0.0-1.0 for lossy formats
    dpi: u32 = 144,               // 72=1x, 144=2x Retina, 216=3x
    embed_color_profile: bool = true,  // sRGB ICC profile
    strip_metadata: bool = false,  // Privacy: strip EXIF/location
};
```

### Smart Defaults
- **Save to file:** PNG (lossless, always safe)
- **Copy to clipboard:** PNG (lossless)
- **Quick share (drag & drop):** User-configurable (default JPEG @ 92%)
- **Export dialog:** Format picker with live file size preview

### DPI Fix (Root Cause of Blurriness)
Every exported image will embed:
- Correct DPI (144 for 2x Retina captures)
- sRGB ICC color profile
- Pixel dimensions matching actual capture resolution

---

## Annotation Editor

### UX Flow (Shottr Paradigm)
```
Hotkey → Screen dims → Selection overlay → Capture → Editor opens
                                                         │
                                          ┌──────────────┤
                                          ▼              ▼
                                    Annotate         Quick actions
                                    (draw, blur,     (copy, save,
                                     ruler, text)     share, discard)
                                          │
                                          ▼
                                    Save / Copy / Share
```

### Tool Palette
| Tool | Shortcut | Description |
|------|----------|-------------|
| Arrow | A | Draw arrows with configurable head size |
| Rectangle | R | Outline or filled rectangles, rounded corners |
| Blur | B | Drag to blur region (gaussian, pixelate options) |
| Ruler | U | Measure pixel distances, shows px values |
| Text | T | Click to place text with font/size/color |
| Highlight | H | Semi-transparent color overlay |
| Line | L | Simple lines |
| Numbering | N | Auto-incrementing numbered circles |
| Color picker | C | Quick color palette + custom |
| Undo/Redo | Cmd+Z / Cmd+Shift+Z | Full undo stack |

### Rendering Strategy
- **On-screen (Swift):** CoreGraphics/CALayer for anti-aliased, real-time preview
- **Export (Zig):** Anti-aliased rendering in the Zig core with subpixel precision
  - Upgrade from Bresenham to Wu's algorithm (anti-aliased lines)
  - Gaussian blur with configurable radius
  - Porter-Duff alpha compositing (existing, proven)
- **Text rendering:** Handled by Swift (CoreText) on macOS, not Zig core. Font rasterization requires OS font system access. On Linux, Pango/Cairo will handle it. Text is composited onto the pixel buffer by the platform layer before Zig export.
- **Format encoding:** On macOS, Swift uses ImageIO for all format encoding (PNG, JPEG, WebP, TIFF, HEIF) — it handles DPI metadata and ICC profiles natively. Zig core provides raw pixel access. For the Linux port, Zig-native encoders (libpng, libjpeg-turbo, libwebp) will be added to the core.

### Editor Window
- Borderless NSWindow at screen size with dark semi-transparent background
- Canvas shows captured image at 1:1 pixel scale
- Floating toolbar (compact, draggable) on the side
- Bottom bar: format selector, quality slider, save/copy/share buttons
- Escape to discard, Enter to save with defaults

---

## Hotkey System

| Combo | Action |
|-------|--------|
| Cmd+Shift+3 | Capture fullscreen → editor |
| Cmd+Shift+4 | Area selection → editor |
| Cmd+Shift+5 | Window picker → editor |
| Cmd+Shift+6 | Scrolling capture (future) |

Registered via `CGEvent.tapCreate` (existing approach) or modern `NSEvent.addGlobalMonitorForEvents`. Configurable in preferences.

---

## Menu Bar App

- Status bar icon (camera icon, changes during capture)
- Click: Show recent captures (thumbnails)
- Right-click / long press: Preferences
- Preferences window:
  - Default save location
  - Default format & quality
  - Hotkey customization
  - Startup at login toggle
  - Capture sound on/off

---

## Zig Core C API

The public interface Swift will call:

```zig
// c_api.zig — exported functions

/// Create a new image from raw RGBA pixel buffer
export fn zs_image_create(pixels: [*]u8, width: u32, height: u32, stride: u32) ?*ZsImage;
export fn zs_image_destroy(img: *ZsImage) void;

/// Annotations
export fn zs_annotate_arrow(img: *ZsImage, x1: i32, y1: i32, x2: i32, y2: i32, color: u32, width: u32) void;
export fn zs_annotate_rect(img: *ZsImage, x: i32, y: i32, w: u32, h: u32, color: u32, width: u32, filled: bool) void;
export fn zs_annotate_blur(img: *ZsImage, x: i32, y: i32, w: u32, h: u32, radius: u32) void;
// Note: text rendering handled by Swift (CoreText) — not in Zig core
// Swift composites rendered text onto pixel buffer before calling export
export fn zs_annotate_highlight(img: *ZsImage, x: i32, y: i32, w: u32, h: u32, color: u32) void;

/// Export
export fn zs_export_png(img: *ZsImage, path: [*:0]const u8, dpi: u32) bool;
export fn zs_export_jpeg(img: *ZsImage, path: [*:0]const u8, quality: f32, dpi: u32) bool;
export fn zs_export_webp(img: *ZsImage, path: [*:0]const u8, quality: f32, dpi: u32) bool;

/// Get raw pixel buffer (for Swift to display in NSView)
export fn zs_image_get_pixels(img: *ZsImage) [*]u8;
export fn zs_image_get_width(img: *ZsImage) u32;
export fn zs_image_get_height(img: *ZsImage) u32;
```

---

## Testing Strategy

| Layer | How | What |
|-------|-----|------|
| Zig core | `zig build test` | Unit tests for blur, annotation math, format encoding, pixel manipulation |
| C API | Zig tests calling exported functions | Verify C calling convention works |
| Swift bridge | XCTest | Verify Swift can call Zig, pixel buffers round-trip |
| Capture | XCTest + manual | ScreenCaptureKit permission handling, Retina resolution |
| Editor | Manual + UI tests | Tool interactions, undo/redo, export |
| Quality | Visual regression | Compare output DPI, color accuracy against reference images |

---

## Linux Planning (Future)

The Zig core (`libzigshot.a`) compiles unchanged for Linux. Only the GUI and capture layers change:

| macOS (now) | Linux (future) |
|-------------|----------------|
| Swift + AppKit | GTK4 (C or Zig bindings) |
| ScreenCaptureKit | xdg-desktop-portal + PipeWire |
| NSPasteboard | wl-copy / xclip |
| CGEvent hotkeys | libkeybinder or portal |
| .app bundle | Flatpak or AppImage |

The C API surface (`c_api.zig`) is the contract — any GUI framework that can call C functions can be a frontend.

---

## Success Criteria

1. Hotkey triggers capture at full Retina resolution (144 DPI, correct metadata)
2. Annotation editor opens instantly with toolbar
3. All 8 annotation tools work with anti-aliased rendering
4. Ruler shows pixel distances accurately
5. Export produces visually identical output to Shottr quality
6. PNG default is pixel-perfect lossless
7. JPEG at 0.92 is indistinguishable from original on screen
8. Menu bar app with recent captures
9. Zig core compiles independently with `zig build test` (no macOS deps)
10. App size under 15MB
