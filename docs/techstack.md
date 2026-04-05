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
| `annotation.zig` | Annotation type definitions | Arrow, Rect, Blur, Ruler, Text, etc. |
| `pipeline.zig` | Image compositing & rendering | Anti-aliased (Wu's algorithm), Porter-Duff blending |
| `blur.zig` | Gaussian blur | Configurable radius, box-blur approximation |
| `format.zig` | Multi-format encoder | PNG, JPEG, WebP, TIFF, HEIF |
| `quality.zig` | Quality metadata | DPI, ICC color profiles, compression level |
| `geometry.zig` | Spatial math | Point, Size, Rect, distance, intersection |
| `c_api.zig` | C-callable API surface | What Swift/GTK calls via FFI |

**Zero OS dependencies.** Pure computation. Compiles on any platform Zig supports.

**Build:** `zig build` produces `libzigshot.a` (static library) + `include/zigshot.h` (C header).

## macOS App (`app/`)

| Technology | Purpose |
|------------|---------|
| **Swift 5.9+** | App language |
| **AppKit** | GUI framework (NSWindow, NSView, NSMenu) |
| **ScreenCaptureKit** | Modern screen capture (macOS 12.3+) |
| **CoreGraphics** | On-screen anti-aliased rendering in editor |
| **CGEvent** | Global hotkey registration |
| **NSPasteboard** | Clipboard integration |
| **SPM or Xcode** | Build system, links libzigshot.a |

**Target:** macOS 13+ (Ventura)

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

## Format Support

| Format | Encoder | Quality | Use Case |
|--------|---------|---------|----------|
| PNG | libpng (via Zig) or ImageIO | Lossless | Default, clipboard |
| JPEG | libjpeg-turbo or ImageIO | 0.0-1.0 (default 0.92) | Web sharing |
| WebP | libwebp | Lossless or lossy (default 0.90) | Modern web |
| TIFF | libtiff or ImageIO | Lossless | Archival |
| HEIF | ImageIO (macOS only) | Near-lossless | Apple ecosystem |

## Build Pipeline

```bash
# Step 1: Build Zig core
cd core && zig build -Doptimize=ReleaseSafe
# Produces: zig-out/lib/libzigshot.a + include/zigshot.h

# Step 2: Build Swift app (links libzigshot.a)
cd app && swift build
# Or: open ZigShot.xcodeproj in Xcode

# Step 3: Run tests
cd core && zig build test          # Zig core tests
cd app && swift test               # Swift integration tests
```

## Dependencies

| Dependency | Type | Why |
|------------|------|-----|
| Zig 0.15.x | Build-time | Core library compiler |
| Xcode 15+ | Build-time | Swift app compiler |
| macOS 13+ SDK | Build-time | ScreenCaptureKit, modern AppKit |
| **No runtime dependencies** | — | Static linking, system frameworks only |
