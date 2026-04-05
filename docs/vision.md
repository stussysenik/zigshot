# ZigShot Vision

## What Is ZigShot?

A native screenshot tool that captures, annotates, and exports with the highest possible fidelity. Built for daily use by developers and designers who care about image quality.

## Why?

Every screenshot tool makes trade-offs. Shottr is great but the quality isn't there. CleanShot X is polished but proprietary and subscription-based. Flameshot is powerful but Linux-only and Qt-based. None of them give you:

- **Pixel-perfect captures** at native Retina resolution with correct DPI metadata
- **Flexible format control** — lossless when quality matters, efficiently compressed when size matters, no surprises
- **Native per-platform** — not a cross-platform compromise, but a truly native app on each OS
- **Open source** with a portable core

## Core Beliefs

1. **Quality is non-negotiable.** A screenshot tool that produces blurry output has failed at its one job. Every capture must preserve the exact pixels at the display's native resolution with correct metadata.

2. **Native > cross-platform.** A screenshot tool touches the deepest OS APIs (screen capture, clipboard, global hotkeys, window management). Cross-platform frameworks always compromise here. Build native for each platform, share the compute-heavy core.

3. **Simplicity of use, depth when needed.** Hotkey → capture → annotate → done. But when you need precise format control, quality settings, or measurement tools, they're one click away.

4. **Open and portable.** The image processing core (Zig) compiles anywhere. The GUI is native per platform. No vendor lock-in, no subscriptions.

## The Architecture Bet

**Zig for pixels, native frameworks for UX.**

The Zig core library (`libzigshot`) handles everything that's math: image buffers, annotation rendering, blur, format encoding, quality controls. Zero OS dependencies. Compiles to a static C library.

The GUI layer is native per platform:
- **macOS:** Swift + AppKit + ScreenCaptureKit
- **Linux (future):** GTK4 + xdg-desktop-portal

Same core, different faces. Each platform feels like it belongs.

## Target Users

- Developers who share screenshots in PRs, docs, Slack, Discord
- Designers who need pixel-accurate captures with measurement tools
- Technical writers who annotate screenshots for documentation
- Anyone tired of blurry, poorly compressed screenshot output

## Success Looks Like

You hit a hotkey. The screen dims. You drag to select. The editor opens instantly. You blur a secret, draw an arrow pointing at the bug, add a label. You hit Enter. A pixel-perfect PNG lands in your clipboard and a file on disk. The whole thing takes 3 seconds and the output looks exactly like what was on your screen.
