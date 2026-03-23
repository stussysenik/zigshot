//! ZigShot — A screenshot tool for macOS, built in Zig.
//!
//! Library root. Re-exports all public modules.

const std = @import("std");

// Core modules (pure Zig, no OS dependencies)
pub const image = @import("core/image.zig");
pub const geometry = @import("core/geometry.zig");
pub const annotation = @import("core/annotation.zig");
pub const blur = @import("core/blur.zig");
pub const pipeline = @import("core/pipeline.zig");

// Re-export main types
pub const Image = image.Image;
pub const Color = image.Color;
pub const Rect = geometry.Rect;
pub const Point = geometry.Point;
pub const Size = geometry.Size;
pub const Annotation = annotation.Annotation;
pub const AnnotationList = annotation.AnnotationList;

test {
    std.testing.refAllDecls(@This());
}
