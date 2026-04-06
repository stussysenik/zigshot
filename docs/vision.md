# ZigShot Vision

## What Is ZigShot?

A native screenshot tool that captures, annotates, and exports with the highest possible fidelity. Built for daily use by developers and designers who care about image quality.

## Why?

Every screenshot tool makes trade-offs. Shottr is great but the quality isn't there. CleanShot X is polished but proprietary and subscription-based. Flameshot is powerful but Linux-only and Qt-based. None of them give you:

- **Pixel-perfect captures** at native Retina resolution with correct DPI metadata
- **Flexible format control** — PNG, JPEG, PDF with quality settings, no surprises
- **A real annotation editor** — freehand highlights, sticky notes, OCR, rich text, zoom, undo/redo, crop-aware annotations
- **Native per-platform** — not a cross-platform compromise, but a truly native app on each OS
- **Open source** with a portable core

## Core Beliefs

1. **Quality is non-negotiable.** A screenshot tool that produces blurry output has failed at its one job. Every capture must preserve the exact pixels at the display's native resolution with correct metadata.

2. **Native > cross-platform.** A screenshot tool touches the deepest OS APIs (screen capture, clipboard, global hotkeys, window management). Cross-platform frameworks always compromise here. Build native for each platform, share the compute-heavy core.

3. **Simplicity of use, depth when needed.** Hotkey -> capture -> annotate -> done. But when you need precise format control, rich text annotations, measurement tools, or OCR — they're one click away.

4. **Open and portable.** The image processing core (Zig) compiles anywhere. The GUI is native per platform. No vendor lock-in, no subscriptions.

## The Architecture Bet

**Zig for pixels, native frameworks for UX.**

The Zig core library (`libzigshot`) handles everything that's math: image buffers, annotation rendering, blur, format encoding, quality controls. Zero OS dependencies. Compiles to a static C library.

The GUI layer is native per platform:
- **macOS:** Swift + AppKit + ScreenCaptureKit (current)
- **Linux (future):** GTK4 + xdg-desktop-portal

Same core, different faces. Each platform feels like it belongs.

## Current State (April 2026)

ZigShot is a fully functional annotation editor with:
- 12 annotation tools (crop, arrow, rectangle, text, sticky note, highlight brush, blur, line, ruler, numbering, eraser, OCR)
- Rich text with bold/italic/alignment/custom fonts
- Zoom controls (25%-400%), keyboard + toolbar + scroll wheel
- Session persistence and capture history
- PDF/PNG/JPEG export with user-configurable defaults
- Share sheet integration (AirDrop, Messages, Mail, etc.)
- Preferences window with font management
- Crop-aware annotations that survive image transforms
- Full undo/redo with keyboard shortcuts

## Target Users

- Developers who share screenshots in PRs, docs, Slack, Discord
- Designers who need pixel-accurate captures with measurement tools
- Technical writers who annotate screenshots for documentation
- Anyone tired of blurry, poorly compressed screenshot output

## Success Looks Like

You hit a hotkey. The screen dims. You drag to select. The editor opens instantly. You blur a secret, draw an arrow pointing at the bug, add a numbered callout, highlight a line of code with a freehand brush. You hit Enter. A pixel-perfect PNG lands in your clipboard and a file on disk. The whole thing takes 3 seconds and the output looks exactly like what was on your screen.
