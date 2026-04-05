# ZigShot Roadmap

## Phase 0: Foundation (Current)
**Status:** Complete

- [x] Zig core with image processing, annotations, blur
- [x] CLI-driven capture (fullscreen, area, window)
- [x] PNG/JPEG export
- [x] ObjC bridge for basic AppKit integration
- [x] Global hotkeys, menu bar app (prototype)

## Phase 1: Quality & Core API
**Focus:** Fix the capture quality problem, build the C API

- [ ] Build `c_api.zig` — C-callable surface for all core operations
- [ ] Add DPI metadata embedding to all export formats
- [ ] Embed sRGB ICC color profile in exports
- [ ] Add JPEG quality control (0.0-1.0 parameter)
- [ ] Upgrade line rendering from Bresenham to Wu's anti-aliased algorithm
- [ ] Add ruler annotation type (pixel distance measurement)
- [ ] Add WebP encoder support
- [ ] Generate `zigshot.h` C header
- [ ] Compile to `libzigshot.a` static library
- [ ] Full test suite for core (no OS deps)

## Phase 2: Swift App — Capture
**Focus:** Native macOS capture with ScreenCaptureKit

- [ ] Swift project setup (SPM or Xcode, linking libzigshot.a)
- [ ] ScreenCaptureKit integration — fullscreen capture at native Retina resolution
- [ ] Area selection overlay (semi-transparent, crosshair cursor, pixel coordinates)
- [ ] Window picker (hover to highlight, click to capture)
- [ ] Global hotkey registration (Cmd+Shift+3/4/5)
- [ ] Permission handling (Screen Recording prompt)
- [ ] Capture → pixel buffer handoff to Zig core via C API

## Phase 3: Swift App — Annotation Editor
**Focus:** Interactive Shottr-like annotation experience

- [ ] Editor window (borderless, dark backdrop, captured image at 1:1)
- [ ] Floating toolbar with tool palette
- [ ] Arrow tool — click-drag to draw, anti-aliased
- [ ] Rectangle tool — outline/filled, rounded corners
- [ ] Blur tool — drag region, gaussian blur via Zig core
- [ ] Ruler tool — drag to measure, shows px distance
- [ ] Text tool — click to place, inline editing
- [ ] Highlight tool — semi-transparent overlay
- [ ] Numbering tool — auto-incrementing circles
- [ ] Color picker — preset palette + custom
- [ ] Line width control
- [ ] Undo/Redo stack (Cmd+Z / Cmd+Shift+Z)
- [ ] Zoom & pan in editor

## Phase 4: Swift App — Export & Polish
**Focus:** Format controls, clipboard, daily driver readiness

- [ ] Export dialog — format picker, quality slider, live file size preview
- [ ] Copy to clipboard (PNG, always lossless)
- [ ] Save to file with smart defaults
- [ ] Drag-and-drop from editor to other apps
- [ ] Menu bar app (status icon, recent captures, preferences)
- [ ] Preferences window (save location, default format, hotkeys, startup)
- [ ] Capture sound (optional)
- [ ] App icon and branding
- [ ] DMG distribution packaging
- [ ] Notarization for Gatekeeper

## Phase 5: Advanced Features
**Focus:** Power user features

- [ ] Scrolling capture (auto-scroll + stitch)
- [ ] OCR text extraction (existing Vision framework code)
- [ ] Screen recording (MP4/GIF, existing ScreenCaptureKit code)
- [ ] Pin screenshot (floating always-on-top window)
- [ ] Desktop widget / quick access
- [ ] Annotation templates / presets
- [ ] Batch capture mode

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
- [ ] CI/CD for Linux builds

---

## Timeline Priorities

**Now:** Phase 1 + 2 (get high-quality captures working natively)
**Next:** Phase 3 (annotation editor — the core daily driver feature)
**Then:** Phase 4 (polish to daily driver quality)
**Later:** Phase 5 + 6 (advanced features, Linux)

Each phase is independently shippable. Phase 2 alone gives you a better screenshot tool than the current CLI.
