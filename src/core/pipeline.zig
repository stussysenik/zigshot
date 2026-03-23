//! Image processing pipeline for ZigShot.
//!
//! Composable operations: crop, resize, pad, round corners, overlay.
//! Each operation produces a new Image (functional style).
//!
//! LEARNING NOTE — Functional vs. mutating:
//! We chose to produce NEW images rather than mutate in-place.
//! This is easier to test (compare input vs output), easier to
//! reason about (no spooky mutation), and enables undo by keeping
//! the original. The cost is memory (two images alive at once),
//! which is fine for screenshots.

const std = @import("std");
const Allocator = std.mem.Allocator;
const image_mod = @import("image.zig");
const geometry = @import("geometry.zig");
const Image = image_mod.Image;
const Color = image_mod.Color;
const Rect = geometry.Rect;

/// Crop an image to the given rectangle.
/// Returns a new Image containing only the cropped pixels.
pub fn crop(allocator: Allocator, src: Image, region: Rect) !Image {
    const clamped = region.clampTo(src.width, src.height);
    if (clamped.width == 0 or clamped.height == 0) return error.EmptyCrop;

    var result = try Image.init(allocator, clamped.width, clamped.height);
    errdefer result.deinit();

    const sx: u32 = @intCast(clamped.x);
    const sy: u32 = @intCast(clamped.y);

    var y: u32 = 0;
    while (y < clamped.height) : (y += 1) {
        var x: u32 = 0;
        while (x < clamped.width) : (x += 1) {
            const pixel = src.getPixel(sx + x, sy + y) orelse Color.transparent;
            result.setPixel(x, y, pixel);
        }
    }

    return result;
}

/// Add padding around an image.
pub fn addPadding(allocator: Allocator, src: Image, top: u32, right: u32, bottom: u32, left: u32, bg: Color) !Image {
    const new_w = left + src.width + right;
    const new_h = top + src.height + bottom;

    var result = try Image.init(allocator, new_w, new_h);
    errdefer result.deinit();

    // Fill with background color
    result.fill(bg);

    // Copy source image into the padded position
    var y: u32 = 0;
    while (y < src.height) : (y += 1) {
        var x: u32 = 0;
        while (x < src.width) : (x += 1) {
            const pixel = src.getPixel(x, y) orelse continue;
            result.setPixel(left + x, top + y, pixel);
        }
    }

    return result;
}

/// Add uniform padding on all sides.
pub fn addUniformPadding(allocator: Allocator, src: Image, padding: u32, bg: Color) !Image {
    return addPadding(allocator, src, padding, padding, padding, padding, bg);
}

/// Composite (overlay) one image onto another at a given position.
/// Uses simple alpha blending.
pub fn composite(allocator: Allocator, base: Image, overlay_img: Image, at_x: i32, at_y: i32) !Image {
    var result = try Image.init(allocator, base.width, base.height);
    errdefer result.deinit();

    // Copy base
    @memcpy(result.pixels, base.pixels);

    // Blend overlay on top
    var y: u32 = 0;
    while (y < overlay_img.height) : (y += 1) {
        var x: u32 = 0;
        while (x < overlay_img.width) : (x += 1) {
            const dx = at_x + @as(i32, @intCast(x));
            const dy = at_y + @as(i32, @intCast(y));
            if (dx < 0 or dy < 0) continue;
            const ux: u32 = @intCast(dx);
            const uy: u32 = @intCast(dy);
            if (ux >= result.width or uy >= result.height) continue;

            const fg = overlay_img.getPixel(x, y) orelse continue;
            if (fg.a == 0) continue;
            if (fg.a == 255) {
                result.setPixel(ux, uy, fg);
                continue;
            }

            // Alpha blend
            const bg = result.getPixel(ux, uy) orelse continue;
            const alpha: u16 = fg.a;
            const inv_alpha: u16 = 255 - alpha;
            result.setPixel(ux, uy, Color{
                .r = @intCast((@as(u16, fg.r) * alpha + @as(u16, bg.r) * inv_alpha) / 255),
                .g = @intCast((@as(u16, fg.g) * alpha + @as(u16, bg.g) * inv_alpha) / 255),
                .b = @intCast((@as(u16, fg.b) * alpha + @as(u16, bg.b) * inv_alpha) / 255),
                .a = 255,
            });
        }
    }

    return result;
}

/// Draw a filled rectangle with a solid color (with alpha blending).
pub fn fillRect(img: *Image, rect: Rect, color: Color) void {
    const clamped = rect.clampTo(img.width, img.height);
    const sx: u32 = @intCast(clamped.x);
    const sy: u32 = @intCast(clamped.y);

    var y: u32 = 0;
    while (y < clamped.height) : (y += 1) {
        var x: u32 = 0;
        while (x < clamped.width) : (x += 1) {
            if (color.a == 255) {
                img.setPixel(sx + x, sy + y, color);
            } else if (color.a > 0) {
                // Alpha blend
                const bg = img.getPixel(sx + x, sy + y) orelse continue;
                const alpha: u16 = color.a;
                const inv_alpha: u16 = 255 - alpha;
                img.setPixel(sx + x, sy + y, Color{
                    .r = @intCast((@as(u16, color.r) * alpha + @as(u16, bg.r) * inv_alpha) / 255),
                    .g = @intCast((@as(u16, color.g) * alpha + @as(u16, bg.g) * inv_alpha) / 255),
                    .b = @intCast((@as(u16, color.b) * alpha + @as(u16, bg.b) * inv_alpha) / 255),
                    .a = 255,
                });
            }
        }
    }
}

/// Draw a rectangle outline (not filled).
pub fn strokeRect(img: *Image, rect: Rect, color: Color, width: u32) void {
    const w = @max(width, 1);
    // Top edge
    fillRect(img, Rect.init(rect.x, rect.y, rect.width, w), color);
    // Bottom edge
    fillRect(img, Rect.init(rect.x, rect.bottom() - @as(i32, @intCast(w)), rect.width, w), color);
    // Left edge
    fillRect(img, Rect.init(rect.x, rect.y, w, rect.height), color);
    // Right edge
    fillRect(img, Rect.init(rect.right() - @as(i32, @intCast(w)), rect.y, w, rect.height), color);
}

/// Draw a line between two points using Bresenham's algorithm.
pub fn drawLine(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: Color, width: u32) void {
    // Bresenham's line algorithm
    var cx = x0;
    var cy = y0;
    const dx = @as(i32, if (x1 > x0) 1 else -1);
    const dy = @as(i32, if (y1 > y0) 1 else -1);
    const abs_dx = @as(u32, @intCast(@as(i32, if (x1 >= x0) x1 - x0 else x0 - x1)));
    const abs_dy = @as(u32, @intCast(@as(i32, if (y1 >= y0) y1 - y0 else y0 - y1)));

    if (abs_dx >= abs_dy) {
        var err: i32 = @divTrunc(@as(i32, @intCast(abs_dx)), 2);
        var i: u32 = 0;
        while (i <= abs_dx) : (i += 1) {
            drawDot(img, cx, cy, color, width);
            err -= @as(i32, @intCast(abs_dy));
            if (err < 0) {
                cy += dy;
                err += @as(i32, @intCast(abs_dx));
            }
            cx += dx;
        }
    } else {
        var err: i32 = @divTrunc(@as(i32, @intCast(abs_dy)), 2);
        var i: u32 = 0;
        while (i <= abs_dy) : (i += 1) {
            drawDot(img, cx, cy, color, width);
            err -= @as(i32, @intCast(abs_dx));
            if (err < 0) {
                cx += dx;
                err += @as(i32, @intCast(abs_dy));
            }
            cy += dy;
        }
    }
}

/// Draw a filled circle/dot at a position (used for thick lines).
fn drawDot(img: *Image, cx: i32, cy: i32, color: Color, radius: u32) void {
    if (radius <= 1) {
        if (cx >= 0 and cy >= 0) {
            img.setPixel(@intCast(cx), @intCast(cy), color);
        }
        return;
    }
    const r: i32 = @intCast(radius / 2);
    var dy: i32 = -r;
    while (dy <= r) : (dy += 1) {
        var ddx: i32 = -r;
        while (ddx <= r) : (ddx += 1) {
            if (ddx * ddx + dy * dy <= r * r) {
                const px = cx + ddx;
                const py = cy + dy;
                if (px >= 0 and py >= 0) {
                    img.setPixel(@intCast(px), @intCast(py), color);
                }
            }
        }
    }
}

/// Draw an arrowhead at the endpoint of a line.
pub fn drawArrow(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: Color, line_width: u32, head_size: f32) void {
    // Draw the line
    drawLine(img, x0, y0, x1, y1, color, line_width);

    // Draw arrowhead
    const fdx: f64 = @floatFromInt(x1 - x0);
    const fdy: f64 = @floatFromInt(y1 - y0);
    const len = @sqrt(fdx * fdx + fdy * fdy);
    if (len < 1.0) return;

    const nx = fdx / len; // normalized direction
    const ny = fdy / len;
    const hs: f64 = @floatCast(head_size);

    // Two points of the arrowhead
    const ax1: i32 = x1 - @as(i32, @intFromFloat(hs * (nx * 0.866 + ny * 0.5)));
    const ay1: i32 = y1 - @as(i32, @intFromFloat(hs * (ny * 0.866 - nx * 0.5)));
    const ax2: i32 = x1 - @as(i32, @intFromFloat(hs * (nx * 0.866 - ny * 0.5)));
    const ay2: i32 = y1 - @as(i32, @intFromFloat(hs * (ny * 0.866 + nx * 0.5)));

    drawLine(img, x1, y1, ax1, ay1, color, line_width);
    drawLine(img, x1, y1, ax2, ay2, color, line_width);
}

// ============================================================================
// Tests
// ============================================================================

test "crop: basic crop" {
    const allocator = std.testing.allocator;
    var src = try Image.init(allocator, 100, 100);
    defer src.deinit();
    src.setPixel(50, 50, Color.red);

    var cropped = try crop(allocator, src, Rect.init(40, 40, 20, 20));
    defer cropped.deinit();

    try std.testing.expectEqual(@as(u32, 20), cropped.width);
    try std.testing.expectEqual(@as(u32, 20), cropped.height);
    // The red pixel at (50,50) should now be at (10,10)
    try std.testing.expect(cropped.getPixel(10, 10).?.eql(Color.red));
}

test "crop: clamps to bounds" {
    const allocator = std.testing.allocator;
    var src = try Image.init(allocator, 50, 50);
    defer src.deinit();

    var cropped = try crop(allocator, src, Rect.init(40, 40, 100, 100));
    defer cropped.deinit();

    try std.testing.expectEqual(@as(u32, 10), cropped.width);
    try std.testing.expectEqual(@as(u32, 10), cropped.height);
}

test "addPadding: expands image" {
    const allocator = std.testing.allocator;
    var src = try Image.init(allocator, 10, 10);
    defer src.deinit();
    src.fill(Color.white);

    var padded = try addUniformPadding(allocator, src, 5, Color.black);
    defer padded.deinit();

    try std.testing.expectEqual(@as(u32, 20), padded.width);
    try std.testing.expectEqual(@as(u32, 20), padded.height);
    // Corner should be black (padding)
    try std.testing.expect(padded.getPixel(0, 0).?.eql(Color.black));
    // Center should be white (original)
    try std.testing.expect(padded.getPixel(10, 10).?.eql(Color.white));
}

test "fillRect: fills region" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 20, 20);
    defer img.deinit();
    img.fill(Color.white);

    fillRect(&img, Rect.init(5, 5, 10, 10), Color.red);

    try std.testing.expect(img.getPixel(0, 0).?.eql(Color.white)); // outside
    try std.testing.expect(img.getPixel(5, 5).?.eql(Color.red)); // inside
    try std.testing.expect(img.getPixel(14, 14).?.eql(Color.red)); // inside
    try std.testing.expect(img.getPixel(15, 15).?.eql(Color.white)); // outside
}

test "strokeRect: draws outline" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 30, 30);
    defer img.deinit();
    img.fill(Color.white);

    strokeRect(&img, Rect.init(5, 5, 20, 20), Color.red, 1);

    // Edge pixels should be red
    try std.testing.expect(img.getPixel(5, 5).?.eql(Color.red));
    try std.testing.expect(img.getPixel(24, 5).?.eql(Color.red));
    // Interior should be white
    try std.testing.expect(img.getPixel(15, 15).?.eql(Color.white));
}

test "drawLine: draws between points" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 20, 20);
    defer img.deinit();

    drawLine(&img, 0, 0, 19, 19, Color.red, 1);

    // Diagonal pixels should be red
    try std.testing.expect(img.getPixel(0, 0).?.eql(Color.red));
    try std.testing.expect(img.getPixel(10, 10).?.eql(Color.red));
    try std.testing.expect(img.getPixel(19, 19).?.eql(Color.red));
    // Off-diagonal should be transparent
    try std.testing.expect(img.getPixel(0, 19).?.eql(Color.transparent));
}

test "drawArrow: does not crash" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 100, 100);
    defer img.deinit();

    drawArrow(&img, 10, 10, 90, 50, Color.red, 2, 12.0);

    // The endpoint should have red pixels nearby
    try std.testing.expect(img.getPixel(90, 50).?.eql(Color.red));
}
