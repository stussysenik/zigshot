//! C-callable API surface for libzigshot.
//!
//! This is the contract between the Zig core and platform GUI layers.
//! Swift (macOS) and GTK4 (Linux) call these functions via FFI.
//!
//! Design rules:
//! - All functions use C calling convention (export fn)
//! - Pointers are opaque to callers — never dereference a ZsImage* in C
//! - Colors are packed as 0xRRGGBBAA (big-endian RGBA in a u32)
//! - Memory is managed by the Zig allocator — callers create/destroy, never free

const std = @import("std");
const image_mod = @import("image.zig");
const pipeline = @import("pipeline.zig");
const blur_mod = @import("blur.zig");
const geometry = @import("geometry.zig");
const Image = image_mod.Image;
const Color = image_mod.Color;
const Rect = geometry.Rect;

/// The allocator backing all C API allocations.
/// c_allocator wraps malloc/free — always available on macOS/Linux.
const allocator = std.heap.c_allocator;

// ============================================================================
// Image lifecycle
// ============================================================================

/// Create a new image by copying raw RGBA pixels from an external buffer.
/// The source stride may differ from width*4 (e.g., CVPixelBuffer row alignment).
/// Returns null on allocation failure.
export fn zs_image_create(pixels: [*]const u8, width: u32, height: u32, stride: u32) ?*Image {
    const img_ptr = allocator.create(Image) catch return null;
    img_ptr.* = Image.init(allocator, width, height) catch {
        allocator.destroy(img_ptr);
        return null;
    };

    // Copy pixel data row by row (source stride may differ from dest stride)
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const src_offset = @as(usize, y) * @as(usize, stride);
        const dst_offset = @as(usize, y) * @as(usize, img_ptr.stride);
        const row_bytes = @as(usize, width) * 4;
        @memcpy(
            img_ptr.pixels[dst_offset .. dst_offset + row_bytes],
            pixels[src_offset .. src_offset + row_bytes],
        );
    }

    return img_ptr;
}

/// Create a new empty image (all pixels transparent black).
/// Returns null on allocation failure.
export fn zs_image_create_empty(width: u32, height: u32) ?*Image {
    const img_ptr = allocator.create(Image) catch return null;
    img_ptr.* = Image.init(allocator, width, height) catch {
        allocator.destroy(img_ptr);
        return null;
    };
    return img_ptr;
}

/// Free an image and its pixel buffer.
export fn zs_image_destroy(img: *Image) void {
    img.deinit();
    allocator.destroy(img);
}

// ============================================================================
// Pixel access
// ============================================================================

/// Get a mutable pointer to the raw RGBA pixel buffer.
/// Layout: row-major, 4 bytes per pixel (R, G, B, A).
/// The pointer is valid until zs_image_destroy is called.
export fn zs_image_get_pixels(img: *Image) [*]u8 {
    return img.pixels.ptr;
}

export fn zs_image_get_width(img: *Image) u32 {
    return img.width;
}

export fn zs_image_get_height(img: *Image) u32 {
    return img.height;
}

export fn zs_image_get_stride(img: *Image) u32 {
    return img.stride;
}

// ============================================================================
// Annotations
// ============================================================================

/// Draw an arrow from (x0,y0) to (x1,y1) with anti-aliased rendering.
export fn zs_annotate_arrow(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: u32, width: u32) void {
    pipeline.drawArrowAA(img, x0, y0, x1, y1, unpackColor(color), width, 12.0);
}

/// Draw a rectangle. If filled=true, fills the area; otherwise draws outline.
export fn zs_annotate_rect(img: *Image, x: i32, y: i32, w: u32, h: u32, color: u32, width: u32, filled: bool) void {
    const c = unpackColor(color);
    const rect = Rect.init(x, y, w, h);
    if (filled) {
        pipeline.fillRect(img, rect, c);
    } else {
        pipeline.strokeRect(img, rect, c, width);
    }
}

/// Blur a rectangular region for redaction.
export fn zs_annotate_blur(img: *Image, x: i32, y: i32, w: u32, h: u32, radius: u32) void {
    blur_mod.blurRegion(img, Rect.init(x, y, w, h), radius) catch {};
}

/// Draw a semi-transparent highlight overlay.
export fn zs_annotate_highlight(img: *Image, x: i32, y: i32, w: u32, h: u32, color: u32) void {
    pipeline.fillRect(img, Rect.init(x, y, w, h), unpackColor(color));
}

/// Draw an anti-aliased line.
export fn zs_annotate_line(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: u32, width: u32) void {
    pipeline.drawLineAA(img, x0, y0, x1, y1, unpackColor(color), width);
}

/// Draw a measurement ruler with tick marks. Returns the pixel distance.
export fn zs_annotate_ruler(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: u32, width: u32) f64 {
    pipeline.drawRuler(img, x0, y0, x1, y1, unpackColor(color), width, 6);
    const dx: f64 = @floatFromInt(x1 - x0);
    const dy: f64 = @floatFromInt(y1 - y0);
    return @sqrt(dx * dx + dy * dy);
}

/// Draw an ellipse outline inside the given rectangle.
export fn zs_annotate_ellipse(img: *Image, x: i32, y: i32, w: u32, h: u32, color: u32, width: u32) void {
    pipeline.drawEllipse(img, Rect.init(x, y, w, h), unpackColor(color), width);
}

// ============================================================================
// Internals
// ============================================================================

/// Unpack 0xRRGGBBAA into a Color struct.
fn unpackColor(rgba: u32) Color {
    return Color{
        .r = @intCast((rgba >> 24) & 0xFF),
        .g = @intCast((rgba >> 16) & 0xFF),
        .b = @intCast((rgba >> 8) & 0xFF),
        .a = @intCast(rgba & 0xFF),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "c_api: image create empty and destroy" {
    const img = zs_image_create_empty(100, 50);
    try std.testing.expect(img != null);
    defer zs_image_destroy(img.?);

    try std.testing.expectEqual(@as(u32, 100), zs_image_get_width(img.?));
    try std.testing.expectEqual(@as(u32, 50), zs_image_get_height(img.?));
    try std.testing.expectEqual(@as(u32, 400), zs_image_get_stride(img.?));
}

test "c_api: image create from pixels copies data" {
    // Create a 2x2 red image
    var pixels = [_]u8{
        255, 0, 0, 255, 0, 255, 0, 255, // row 0: red, green
        0, 0, 255, 255, 255, 255, 255, 255, // row 1: blue, white
    };
    const img = zs_image_create(&pixels, 2, 2, 8);
    try std.testing.expect(img != null);
    defer zs_image_destroy(img.?);

    const out = zs_image_get_pixels(img.?);
    // Pixel (0,0) should be red
    try std.testing.expectEqual(@as(u8, 255), out[0]); // R
    try std.testing.expectEqual(@as(u8, 0), out[1]); // G
    try std.testing.expectEqual(@as(u8, 0), out[2]); // B
    try std.testing.expectEqual(@as(u8, 255), out[3]); // A
}

test "c_api: annotate arrow draws pixels" {
    const img = zs_image_create_empty(100, 100);
    try std.testing.expect(img != null);
    defer zs_image_destroy(img.?);

    // Draw red arrow (0xFF0000FF = red, fully opaque)
    zs_annotate_arrow(img.?, 10, 10, 90, 50, 0xFF0000FF, 2);

    // Endpoint should have non-zero pixels
    const out = zs_image_get_pixels(img.?);
    const stride = zs_image_get_stride(img.?);
    const offset = @as(usize, 50) * @as(usize, stride) + @as(usize, 90) * 4;
    try std.testing.expect(out[offset] > 0);
}

test "c_api: annotate blur modifies pixels" {
    const img = zs_image_create_empty(20, 20);
    try std.testing.expect(img != null);
    defer zs_image_destroy(img.?);

    // Set a single bright pixel
    const pixels = zs_image_get_pixels(img.?);
    const stride = zs_image_get_stride(img.?);
    const center = @as(usize, 10) * @as(usize, stride) + @as(usize, 10) * 4;
    pixels[center] = 255; // R
    pixels[center + 3] = 255; // A

    // Blur the region
    zs_annotate_blur(img.?, 0, 0, 20, 20, 3);

    // The bright pixel should have spread — neighbors should be non-zero
    const neighbor = @as(usize, 10) * @as(usize, stride) + @as(usize, 11) * 4;
    try std.testing.expect(pixels[neighbor] > 0);
}

test "c_api: ruler returns distance" {
    const img = zs_image_create_empty(200, 100);
    try std.testing.expect(img != null);
    defer zs_image_destroy(img.?);

    const dist = zs_annotate_ruler(img.?, 0, 0, 100, 0, 0x00C8FFFF, 1);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), dist, 0.001);
}

test "unpackColor: RGBA packing" {
    const c = unpackColor(0xFF8040C0);
    try std.testing.expectEqual(@as(u8, 0xFF), c.r);
    try std.testing.expectEqual(@as(u8, 0x80), c.g);
    try std.testing.expectEqual(@as(u8, 0x40), c.b);
    try std.testing.expectEqual(@as(u8, 0xC0), c.a);
}
