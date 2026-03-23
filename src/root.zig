//! ZigShot — A screenshot tool for macOS, built in Zig.
//!
//! This is the library root. It re-exports all public modules so that
//! consumers (the CLI, tests, and eventually the GUI) can import them
//! with a single `@import("zigshot")`.

const std = @import("std");
pub const image = @import("core/image.zig");

// Re-export the main types for convenience
pub const Image = image.Image;
pub const Color = image.Color;

test {
    // Pull in all nested test blocks so `zig build test` runs them.
    std.testing.refAllDecls(@This());
}
