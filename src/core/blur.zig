//! Gaussian blur approximation for ZigShot.
//!
//! Used for blur/redact annotations — blurs a rectangular region
//! of an image to hide sensitive content.
//!
//! Uses a cross-pattern sampling (O(r) per pixel) instead of a full box
//! (O(r^2)). Could be even smoother with a true separable Gaussian, but
//! for redacting a credit card in a screenshot, this runs in milliseconds.
//! Premature optimization is the root of all evil. — Knuth

const std = @import("std");
const image_mod = @import("image.zig");
const geometry = @import("geometry.zig");
const Image = image_mod.Image;
const Color = image_mod.Color;
const Rect = geometry.Rect;

/// Apply blur to a rectangular region of an image (in-place).
/// Uses multiple passes for a smoother result.
pub fn blurRegion(img: *Image, region: Rect, radius: u32) !void {
    if (radius == 0) return;

    const clamped = region.clampTo(img.width, img.height);
    if (clamped.width == 0 or clamped.height == 0) return;

    // Clamp radius to half the region size — a blur radius bigger than the
    // region itself is nonsensical (you'd be averaging pixels that don't exist).
    const r = @min(radius, @min(clamped.width / 2, clamped.height / 2));
    if (r == 0) return;

    // Two passes: first blurs, second blurs the already-blurred.
    // Smoother approximation of a true Gaussian. Like running
    // CSS `blur(5px)` twice — the math converges toward the real thing.
    var pass: u32 = 0;
    while (pass < 2) : (pass += 1) {
        blurPass(img, clamped, r);
    }
}

fn blurPass(img: *Image, region: Rect, radius: u32) void {
    // Ugly but necessary. Zig refuses silent signed/unsigned conversion.
    // Every @intCast is explicit — buffer overflows from careless type
    // mixing become impossible. In C, this would just silently wrap.
    const ox: u32 = @intCast(region.x);
    const oy: u32 = @intCast(region.y);

    var y: u32 = 0;
    while (y < region.height) : (y += 1) {
        var x: u32 = 0;
        while (x < region.width) : (x += 1) {
            var sum_r: u32 = 0;
            var sum_g: u32 = 0;
            var sum_b: u32 = 0;
            var sum_a: u32 = 0;
            var count: u32 = 0;

            // Sample neighbors in a cross pattern (vertical + horizontal).
            // O(r) samples per pixel instead of O(r^2) for a full box.
            // Quality tradeoff invisible for redaction — nobody's inspecting
            // a blurred credit card number for Gaussian accuracy.
            const r_i32: i32 = @intCast(radius);
            var dy: i32 = -r_i32;
            while (dy <= r_i32) : (dy += 1) {
                const sy_i32 = @as(i32, @intCast(y)) + dy;
                if (sy_i32 < 0 or sy_i32 >= @as(i32, @intCast(region.height))) continue;
                const sy: u32 = @intCast(sy_i32);

                const pixel = img.getPixel(ox + x, oy + sy).?;
                sum_r += pixel.r;
                sum_g += pixel.g;
                sum_b += pixel.b;
                sum_a += pixel.a;
                count += 1;
            }
            var dx: i32 = -r_i32;
            while (dx <= r_i32) : (dx += 1) {
                if (dx == 0) continue; // already counted center
                const sx_i32 = @as(i32, @intCast(x)) + dx;
                if (sx_i32 < 0 or sx_i32 >= @as(i32, @intCast(region.width))) continue;
                const sx: u32 = @intCast(sx_i32);

                const pixel = img.getPixel(ox + sx, oy + y).?;
                sum_r += pixel.r;
                sum_g += pixel.g;
                sum_b += pixel.b;
                sum_a += pixel.a;
                count += 1;
            }

            if (count > 0) {
                img.setPixel(ox + x, oy + y, Color{
                    .r = @intCast(sum_r / count),
                    .g = @intCast(sum_g / count),
                    .b = @intCast(sum_b / count),
                    .a = @intCast(sum_a / count),
                });
            }
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "blur: no-op with radius 0" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 10, 10);
    defer img.deinit();
    img.fill(Color.red);

    try blurRegion(&img, Rect.init(0, 0, 10, 10), 0);
    try std.testing.expect(img.getPixel(5, 5).?.eql(Color.red));
}

test "blur: smooths a sharp edge" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 20, 20);
    defer img.deinit();

    // Left half white, right half black
    var y: u32 = 0;
    while (y < 20) : (y += 1) {
        var x: u32 = 0;
        while (x < 20) : (x += 1) {
            if (x < 10) {
                img.setPixel(x, y, Color.white);
            } else {
                img.setPixel(x, y, Color.black);
            }
        }
    }

    try blurRegion(&img, Rect.init(0, 0, 20, 20), 3);

    // After blur, the edge should be smoothed
    const edge_pixel = img.getPixel(10, 10).?;
    try std.testing.expect(edge_pixel.r > 0);
    try std.testing.expect(edge_pixel.r < 255);
}

test "blur: region clamps to image bounds" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 10, 10);
    defer img.deinit();
    img.fill(Color.white);

    // Region extends beyond image — should not crash
    try blurRegion(&img, Rect.init(0, 0, 20, 20), 2);
}
