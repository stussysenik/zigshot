//! ZigShot — A screenshot tool for macOS, built in Zig.
//!
//! Library root. This is your `index.js` barrel file.
//!
//! Architecture — three layers, data flows down and back up:
//!
//!   ┌─────────────────────────────────────────┐
//!   │  CLI (src/cli/)                         │
//!   │  Parses args, orchestrates commands      │
//!   └──────────────┬──────────────────────────┘
//!                  │ calls
//!   ┌──────────────▼──────────────────────────┐
//!   │  Platform (src/platform/)               │
//!   │  macOS screen capture, clipboard, OCR   │
//!   └──────────────┬──────────────────────────┘
//!                  │ produces/consumes
//!   ┌──────────────▼──────────────────────────┐
//!   │  Core (src/core/)                       │
//!   │  Image, Geometry, Annotation, Blur      │
//!   │  Pure Zig — no OS deps, fully testable  │
//!   └─────────────────────────────────────────┘
//!
//! Zig only compiles what's reachable from here or main.zig — dead code
//! is truly dead. If a module isn't imported (directly or transitively),
//! it doesn't exist in the binary. No tree-shaking pass needed.

const std = @import("std");

// Core modules (pure Zig, no OS dependencies)
pub const image = @import("core/image.zig");
pub const geometry = @import("core/geometry.zig");
pub const annotation = @import("core/annotation.zig");
pub const blur = @import("core/blur.zig");
pub const pipeline = @import("core/pipeline.zig");
pub const quality = @import("core/quality.zig");
pub const c_api = @import("core/c_api.zig");

// Re-export main types for convenience.
// `pub const Image = image.Image` is Zig's version of:
//   export { Image } from './core/image'
// Consumers can write `const zigshot = @import("root.zig")` and use
// `zigshot.Image` directly instead of reaching into submodules.
pub const Image = image.Image;
pub const Color = image.Color;
pub const Rect = geometry.Rect;
pub const Point = geometry.Point;
pub const Size = geometry.Size;
pub const Annotation = annotation.Annotation;
pub const AnnotationList = annotation.AnnotationList;
pub const ExportConfig = quality.ExportConfig;
pub const Format = quality.Format;

test {
    // Forces the compiler to semantically analyze every declaration in
    // every imported module — catches broken imports, type errors, and
    // invalid module paths without actually running any test logic.
    // It's a compile-time smoke test: "can this code at least parse?"
    std.testing.refAllDecls(@This());
}
