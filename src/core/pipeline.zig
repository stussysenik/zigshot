//! Image processing pipeline for ZigShot.
//!
//! Composable operations: crop, resize, pad, round corners, overlay.
//! Each operation produces a new Image (functional style).
//!
//! Why functional (new image out) instead of mutating in-place?
//! Same reason Redux uses immutable state: easier to test (compare input vs
//! output), easier to reason about (no spooky action at a distance), and
//! enables undo by keeping the original. The cost is memory — two images
//! alive at once — which is fine for screenshots. Don't prematurely optimize
//! what isn't slow.

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
    // If anything fails AFTER we allocate but BEFORE we return, errdefer
    // frees the memory. Zig's answer to `goto cleanup` in C. Think of it
    // like a `finally` that only runs on exceptions — except Zig errors
    // aren't exceptions, they're values. No stack unwinding, no try/catch.
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
/// Standard Porter-Duff "source over" compositing — same formula your
/// browser uses for CSS `opacity`.
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

            const bg = result.getPixel(ux, uy) orelse continue;
            result.setPixel(ux, uy, Color.blend(fg, bg));
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
            if (color.a == 0) continue;
            const bg = img.getPixel(sx + x, sy + y) orelse continue;
            img.setPixel(sx + x, sy + y, Color.blend(color, bg));
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
///
/// Bresenham's line algorithm (1962). Draws lines using only integer
/// arithmetic — no floating point. Tracks an error term that decides
/// whether to step in Y for each step in X. Every pixel screen since
/// the 1960s has used this. In JS you'd just call `ctx.lineTo()` and
/// the browser does this for you under the hood.
pub fn drawLine(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: Color, width: u32) void {
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

/// Stamps a filled circle at each line point for thick lines.
/// The `r*r` test below is the equation of a circle: x^2 + y^2 <= r^2.
/// Any pixel inside that radius gets colored. Simple brute-force that
/// works perfectly for small radii (line widths of 1-10px).
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

/// Fractional part of a float (used by Wu's algorithm).
fn fpart(x: f64) f64 {
    return x - @floor(x);
}

/// Reverse fractional part: 1 - fpart(x).
fn rfpart(x: f64) f64 {
    return 1.0 - fpart(x);
}

/// Plot a pixel with fractional intensity (alpha modulation).
/// The brightness parameter (0.0-1.0) scales the color's alpha,
/// creating the anti-aliased effect — pixels near the geometric
/// line are brighter, pixels further away are dimmer.
fn plotAA(img: *Image, x: i32, y: i32, color: Color, brightness: f64) void {
    if (x < 0 or y < 0) return;
    const ux: u32 = @intCast(x);
    const uy: u32 = @intCast(y);
    if (ux >= img.width or uy >= img.height) return;

    const clamped = @max(@as(f64, 0), @min(@as(f64, 1), brightness));
    const a: u8 = @intFromFloat(@as(f64, @floatFromInt(color.a)) * clamped);
    if (a == 0) return;
    const fg = Color{ .r = color.r, .g = color.g, .b = color.b, .a = a };
    const bg = img.getPixel(ux, uy) orelse return;
    img.setPixel(ux, uy, Color.blend(fg, bg));
}

/// Absolute value for i32. Avoids @abs which returns u32.
fn absI32(x: i32) i32 {
    return if (x < 0) -x else x;
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

    // 0.866 = cos(30deg), 0.5 = sin(30deg). Arrowhead = two lines rotated
    // +-30deg from the main direction. Same trig as Canvas2D arrow drawing
    // in JS — just inlined instead of calling Math.cos/Math.sin.
    const ax1: i32 = x1 - @as(i32, @intFromFloat(hs * (nx * 0.866 + ny * 0.5)));
    const ay1: i32 = y1 - @as(i32, @intFromFloat(hs * (ny * 0.866 - nx * 0.5)));
    const ax2: i32 = x1 - @as(i32, @intFromFloat(hs * (nx * 0.866 - ny * 0.5)));
    const ay2: i32 = y1 - @as(i32, @intFromFloat(hs * (ny * 0.866 + nx * 0.5)));

    drawLine(img, x1, y1, ax1, ay1, color, line_width);
    drawLine(img, x1, y1, ax2, ay2, color, line_width);
}

/// Draw an anti-aliased line using Wu's algorithm.
///
/// Wu's algorithm (1991) draws lines by plotting TWO pixels per step,
/// each with varying intensity based on sub-pixel position. Where
/// Bresenham's binary on/off produces jagged staircase edges, Wu's
/// smooth gradient edges look natural at any angle.
///
/// For thick lines (width > 2), falls back to Bresenham with dot stamps
/// since thickness already masks aliasing artifacts.
pub fn drawLineAA(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: Color, width: u32) void {
    // Thick lines: AA isn't visible, use fast Bresenham
    if (width > 2) {
        drawLine(img, x0, y0, x1, y1, color, width);
        return;
    }

    // Degenerate case
    if (x0 == x1 and y0 == y1) {
        plotAA(img, x0, y0, color, 1.0);
        return;
    }

    // Determine if line is steep (more vertical than horizontal)
    const steep = absI32(y1 - y0) > absI32(x1 - x0);

    // Transpose coordinates if steep so we always iterate along the longer axis
    var ax0 = if (steep) y0 else x0;
    var ay0 = if (steep) x0 else y0;
    var ax1 = if (steep) y1 else x1;
    var ay1 = if (steep) x1 else y1;

    // Ensure left-to-right
    if (ax0 > ax1) {
        std.mem.swap(i32, &ax0, &ax1);
        std.mem.swap(i32, &ay0, &ay1);
    }

    const dx: f64 = @floatFromInt(ax1 - ax0);
    const dy: f64 = @floatFromInt(ay1 - ay0);
    const gradient: f64 = if (dx == 0) 1.0 else dy / dx;

    // --- First endpoint ---
    var xend: f64 = @round(@as(f64, @floatFromInt(ax0)));
    var yend: f64 = @as(f64, @floatFromInt(ay0)) + gradient * (xend - @as(f64, @floatFromInt(ax0)));
    var xgap: f64 = rfpart(@as(f64, @floatFromInt(ax0)) + 0.5);
    const xpxl1: i32 = @intFromFloat(xend);
    const ypxl1: i32 = @intFromFloat(@floor(yend));

    if (steep) {
        plotAA(img, ypxl1, xpxl1, color, rfpart(yend) * xgap);
        plotAA(img, ypxl1 + 1, xpxl1, color, fpart(yend) * xgap);
    } else {
        plotAA(img, xpxl1, ypxl1, color, rfpart(yend) * xgap);
        plotAA(img, xpxl1, ypxl1 + 1, color, fpart(yend) * xgap);
    }

    var intery: f64 = yend + gradient;

    // --- Second endpoint ---
    xend = @round(@as(f64, @floatFromInt(ax1)));
    yend = @as(f64, @floatFromInt(ay1)) + gradient * (xend - @as(f64, @floatFromInt(ax1)));
    xgap = fpart(@as(f64, @floatFromInt(ax1)) + 0.5);
    const xpxl2: i32 = @intFromFloat(xend);
    const ypxl2: i32 = @intFromFloat(@floor(yend));

    if (steep) {
        plotAA(img, ypxl2, xpxl2, color, rfpart(yend) * xgap);
        plotAA(img, ypxl2 + 1, xpxl2, color, fpart(yend) * xgap);
    } else {
        plotAA(img, xpxl2, ypxl2, color, rfpart(yend) * xgap);
        plotAA(img, xpxl2, ypxl2 + 1, color, fpart(yend) * xgap);
    }

    // --- Main loop ---
    var x = xpxl1 + 1;
    while (x < xpxl2) : (x += 1) {
        const iy: i32 = @intFromFloat(@floor(intery));
        if (steep) {
            plotAA(img, iy, x, color, rfpart(intery));
            plotAA(img, iy + 1, x, color, fpart(intery));
        } else {
            plotAA(img, x, iy, color, rfpart(intery));
            plotAA(img, x, iy + 1, color, fpart(intery));
        }
        intery += gradient;
    }
}

/// Draw an anti-aliased arrow. Same geometry as drawArrow,
/// but uses Wu's algorithm for smooth edges.
pub fn drawArrowAA(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: Color, line_width: u32, head_size: f32) void {
    // Draw the shaft
    drawLineAA(img, x0, y0, x1, y1, color, line_width);

    // Arrowhead geometry (identical to drawArrow)
    const fdx: f64 = @floatFromInt(x1 - x0);
    const fdy: f64 = @floatFromInt(y1 - y0);
    const len = @sqrt(fdx * fdx + fdy * fdy);
    if (len < 1.0) return;

    const nx = fdx / len;
    const ny = fdy / len;
    const hs: f64 = @floatCast(head_size);

    const ax1: i32 = x1 - @as(i32, @intFromFloat(hs * (nx * 0.866 + ny * 0.5)));
    const ay1: i32 = y1 - @as(i32, @intFromFloat(hs * (ny * 0.866 - nx * 0.5)));
    const ax2: i32 = x1 - @as(i32, @intFromFloat(hs * (nx * 0.866 - ny * 0.5)));
    const ay2: i32 = y1 - @as(i32, @intFromFloat(hs * (ny * 0.866 + nx * 0.5)));

    drawLineAA(img, x1, y1, ax1, ay1, color, line_width);
    drawLineAA(img, x1, y1, ax2, ay2, color, line_width);
}

/// Draw a measurement ruler between two points.
/// Renders: main line + perpendicular tick marks at both endpoints.
/// Returns the pixel distance (for the GUI to display as text label).
pub fn drawRuler(img: *Image, x0: i32, y0: i32, x1: i32, y1: i32, color: Color, width: u32, tick_size: u32) void {
    // Main measurement line (anti-aliased)
    drawLineAA(img, x0, y0, x1, y1, color, width);

    // Compute perpendicular direction for tick marks
    const fdx: f64 = @floatFromInt(x1 - x0);
    const fdy: f64 = @floatFromInt(y1 - y0);
    const len = @sqrt(fdx * fdx + fdy * fdy);
    if (len < 1.0) return;

    const px = -fdy / len; // perpendicular x
    const py = fdx / len; // perpendicular y
    const ts: f64 = @floatFromInt(tick_size);

    // Start endpoint tick
    const sx0: i32 = x0 + @as(i32, @intFromFloat(px * ts));
    const sy0: i32 = y0 + @as(i32, @intFromFloat(py * ts));
    const sx1: i32 = x0 - @as(i32, @intFromFloat(px * ts));
    const sy1: i32 = y0 - @as(i32, @intFromFloat(py * ts));
    drawLineAA(img, sx0, sy0, sx1, sy1, color, width);

    // End endpoint tick
    const ex0: i32 = x1 + @as(i32, @intFromFloat(px * ts));
    const ey0: i32 = y1 + @as(i32, @intFromFloat(py * ts));
    const ex1: i32 = x1 - @as(i32, @intFromFloat(px * ts));
    const ey1: i32 = y1 - @as(i32, @intFromFloat(py * ts));
    drawLineAA(img, ex0, ey0, ex1, ey1, color, width);
}

/// Round the corners of an image by setting pixels outside the radius to transparent.
///
/// LEARNING NOTE — distance-based masking:
/// For each corner, we check if a pixel is inside the quarter-circle of the
/// given radius. The check is: (dx*dx + dy*dy) > (r*r). If outside, set
/// alpha to 0. This creates smooth rounded corners without antialiasing.
/// For antialiased edges you'd use sub-pixel coverage, but for screenshot
/// tools crisp edges are fine.
pub fn roundCorners(img: *Image, radius: u32) void {
    if (radius == 0) return;
    const r = @min(radius, @min(img.width / 2, img.height / 2));
    const r_sq = @as(u64, r) * @as(u64, r);

    var y: u32 = 0;
    while (y < r) : (y += 1) {
        var x: u32 = 0;
        while (x < r) : (x += 1) {
            // Distance from corner center
            const dx = r - x;
            const dy = r - y;
            const dist_sq = @as(u64, dx) * @as(u64, dx) + @as(u64, dy) * @as(u64, dy);
            if (dist_sq > r_sq) {
                // Outside radius — make transparent in all four corners
                // Top-left
                img.setPixel(x, y, Color.transparent);
                // Top-right
                img.setPixel(img.width - 1 - x, y, Color.transparent);
                // Bottom-left
                img.setPixel(x, img.height - 1 - y, Color.transparent);
                // Bottom-right
                img.setPixel(img.width - 1 - x, img.height - 1 - y, Color.transparent);
            }
        }
    }
}

/// Add a drop shadow behind an image.
/// Creates a new, larger image with shadow underneath the original.
/// offset_x/y: shadow offset in pixels.
/// blur_radius: how much to blur the shadow.
/// shadow_color: color of the shadow (typically semi-transparent black).
pub fn addDropShadow(allocator: Allocator, src: Image, offset_x: i32, offset_y: i32, blur_radius: u32, shadow_color: Color) !Image {
    const blur = @import("blur.zig");

    // Expand canvas to fit shadow + original
    const expand = blur_radius * 2 + @as(u32, @intCast(@max(@abs(offset_x), @abs(offset_y))));
    const new_w = src.width + expand * 2;
    const new_h = src.height + expand * 2;

    var result = try Image.init(allocator, new_w, new_h);
    errdefer result.deinit();
    result.fill(Color.transparent);

    // Draw shadow silhouette (offset from center)
    const shadow_x: u32 = @intCast(@as(i32, @intCast(expand)) + offset_x);
    const shadow_y: u32 = @intCast(@as(i32, @intCast(expand)) + offset_y);

    var y: u32 = 0;
    while (y < src.height) : (y += 1) {
        var x: u32 = 0;
        while (x < src.width) : (x += 1) {
            const px = src.getPixel(x, y) orelse continue;
            if (px.a > 0) {
                result.setPixel(shadow_x + x, shadow_y + y, shadow_color);
            }
        }
    }

    // Blur the shadow
    if (blur_radius > 0) {
        const shadow_rect = Rect.init(
            @intCast(shadow_x),
            @intCast(shadow_y),
            src.width,
            src.height,
        );
        try blur.blurRegion(&result, shadow_rect, blur_radius);
    }

    // Composite original on top (centered)
    y = 0;
    while (y < src.height) : (y += 1) {
        var x: u32 = 0;
        while (x < src.width) : (x += 1) {
            const px = src.getPixel(x, y) orelse continue;
            if (px.a == 0) continue;
            const bg = result.getPixel(expand + x, expand + y) orelse continue;
            result.setPixel(expand + x, expand + y, Color.blend(px, bg));
        }
    }

    return result;
}

/// Fill an image with a linear gradient between two colors.
/// angle: gradient direction in degrees (0 = left-to-right, 90 = top-to-bottom).
pub fn fillGradient(img: *Image, angle_deg: f64, color1: Color, color2: Color) void {
    const angle = angle_deg * std.math.pi / 180.0;
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);

    // Project each pixel onto the gradient axis
    const fw: f64 = @floatFromInt(img.width);
    const fh: f64 = @floatFromInt(img.height);

    // Compute projection range for normalization
    const corners = [4]f64{
        0.0 * cos_a + 0.0 * sin_a,
        fw * cos_a + 0.0 * sin_a,
        0.0 * cos_a + fh * sin_a,
        fw * cos_a + fh * sin_a,
    };
    var min_proj = corners[0];
    var max_proj = corners[0];
    for (corners[1..]) |c| {
        min_proj = @min(min_proj, c);
        max_proj = @max(max_proj, c);
    }
    const range = max_proj - min_proj;
    if (range < 1.0) return;

    var y: u32 = 0;
    while (y < img.height) : (y += 1) {
        var x: u32 = 0;
        while (x < img.width) : (x += 1) {
            const fx: f64 = @floatFromInt(x);
            const fy: f64 = @floatFromInt(y);
            const proj = (fx * cos_a + fy * sin_a - min_proj) / range;
            const t = @min(@max(proj, 0.0), 1.0);

            // Linear interpolation between color1 and color2
            const r: u8 = @intFromFloat(@as(f64, @floatFromInt(color1.r)) * (1.0 - t) + @as(f64, @floatFromInt(color2.r)) * t);
            const g: u8 = @intFromFloat(@as(f64, @floatFromInt(color1.g)) * (1.0 - t) + @as(f64, @floatFromInt(color2.g)) * t);
            const b: u8 = @intFromFloat(@as(f64, @floatFromInt(color1.b)) * (1.0 - t) + @as(f64, @floatFromInt(color2.b)) * t);
            img.setPixel(x, y, Color{ .r = r, .g = g, .b = b, .a = 255 });
        }
    }
}

/// Draw an ellipse outline inside the given rectangle.
/// Uses the midpoint ellipse algorithm — the elliptical cousin of
/// Bresenham's line algorithm. Integer arithmetic only.
pub fn drawEllipse(img: *Image, rect: Rect, color: Color, thickness: u32) void {
    const clamped = rect.clampTo(img.width, img.height);
    if (clamped.width < 3 or clamped.height < 3) return;

    // Center and radii
    const cx: i32 = clamped.x + @as(i32, @intCast(clamped.width / 2));
    const cy: i32 = clamped.y + @as(i32, @intCast(clamped.height / 2));
    const rx: i32 = @intCast(clamped.width / 2);
    const ry: i32 = @intCast(clamped.height / 2);

    // Midpoint ellipse: scan through angles by iterating quadrant pixels
    // Draw by symmetry — compute one quadrant, mirror to all four
    var x: i32 = 0;
    var y: i32 = ry;

    // Region 1: dy/dx > -1 (top of ellipse)
    const rx2: i64 = @as(i64, rx) * @as(i64, rx);
    const ry2: i64 = @as(i64, ry) * @as(i64, ry);
    var px: i64 = 0;
    var py: i64 = 2 * rx2 * @as(i64, y);
    var p: i64 = ry2 - rx2 * @as(i64, ry) + @divTrunc(rx2, 4);

    while (px < py) {
        plotEllipsePoints(img, cx, cy, x, y, color, thickness);
        x += 1;
        px += 2 * ry2;
        if (p < 0) {
            p += ry2 + px;
        } else {
            y -= 1;
            py -= 2 * rx2;
            p += ry2 + px - py;
        }
    }

    // Region 2: dy/dx < -1 (side of ellipse)
    p = ry2 * (@as(i64, x) * @as(i64, x) + @as(i64, x)) + rx2 * (@as(i64, y - 1) * @as(i64, y - 1)) - rx2 * ry2 + @divTrunc(ry2, 4);
    while (y >= 0) {
        plotEllipsePoints(img, cx, cy, x, y, color, thickness);
        y -= 1;
        py -= 2 * rx2;
        if (p > 0) {
            p += rx2 - py;
        } else {
            x += 1;
            px += 2 * ry2;
            p += rx2 - py + px;
        }
    }
}

fn plotEllipsePoints(img: *Image, cx: i32, cy: i32, x: i32, y: i32, color: Color, thickness: u32) void {
    // Draw in all four quadrants with thickness
    drawDot(img, cx + x, cy + y, color, thickness);
    drawDot(img, cx - x, cy + y, color, thickness);
    drawDot(img, cx + x, cy - y, color, thickness);
    drawDot(img, cx - x, cy - y, color, thickness);
}

/// Preset gradient color pairs for background beautification.
pub const GradientPreset = struct {
    name: []const u8,
    color1: Color,
    color2: Color,
    angle: f64,

    pub const ocean = GradientPreset{
        .name = "ocean",
        .color1 = Color{ .r = 0x66, .g = 0x7e, .b = 0xea, .a = 255 },
        .color2 = Color{ .r = 0x76, .g = 0x4b, .b = 0xa2, .a = 255 },
        .angle = 135,
    };
    pub const sunset = GradientPreset{
        .name = "sunset",
        .color1 = Color{ .r = 0xf0, .g = 0x93, .b = 0xfb, .a = 255 },
        .color2 = Color{ .r = 0xf5, .g = 0x57, .b = 0x6c, .a = 255 },
        .angle = 135,
    };
    pub const forest = GradientPreset{
        .name = "forest",
        .color1 = Color{ .r = 0x11, .g = 0x99, .b = 0x8e, .a = 255 },
        .color2 = Color{ .r = 0x38, .g = 0xef, .b = 0x7d, .a = 255 },
        .angle = 135,
    };
    pub const midnight = GradientPreset{
        .name = "midnight",
        .color1 = Color{ .r = 0x0f, .g = 0x0c, .b = 0x29, .a = 255 },
        .color2 = Color{ .r = 0x30, .g = 0x2b, .b = 0x63, .a = 255 },
        .angle = 135,
    };
};

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

test "roundCorners: makes corner pixels transparent" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 40, 40);
    defer img.deinit();
    img.fill(Color.white);

    roundCorners(&img, 10);

    // Top-left corner (0,0) should be transparent (outside radius)
    try std.testing.expect(img.getPixel(0, 0).?.eql(Color.transparent));
    // Center should remain white
    try std.testing.expect(img.getPixel(20, 20).?.eql(Color.white));
    // Just inside the radius should remain white
    try std.testing.expect(img.getPixel(10, 10).?.eql(Color.white));
}

test "fillGradient: produces different colors at endpoints" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 100, 10);
    defer img.deinit();

    fillGradient(&img, 0, Color.red, Color{ .r = 0, .g = 0, .b = 255, .a = 255 });

    // Left side should be reddish
    const left = img.getPixel(0, 5).?;
    try std.testing.expect(left.r > 200);
    // Right side should be bluish
    const right = img.getPixel(99, 5).?;
    try std.testing.expect(right.b > 200);
}

test "drawEllipse: draws pixels" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 60, 40);
    defer img.deinit();
    img.fill(Color.transparent);

    drawEllipse(&img, Rect.init(5, 5, 50, 30), Color.red, 1);

    // Top center of ellipse should have red pixels
    try std.testing.expect(img.getPixel(30, 5).?.eql(Color.red));
    // Center should remain transparent (outline only)
    try std.testing.expect(img.getPixel(30, 20).?.eql(Color.transparent));
}

test "addDropShadow: creates larger image" {
    const allocator = std.testing.allocator;
    var src = try Image.init(allocator, 20, 20);
    defer src.deinit();
    src.fill(Color.white);

    var result = try addDropShadow(allocator, src, 4, 4, 3, Color{ .r = 0, .g = 0, .b = 0, .a = 128 });
    defer result.deinit();

    // Result should be larger than source
    try std.testing.expect(result.width > src.width);
    try std.testing.expect(result.height > src.height);
}

test "drawLineAA: anti-aliased diagonal has intermediate alpha" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 20, 20);
    defer img.deinit();
    img.fill(Color.white);

    drawLineAA(&img, 0, 0, 19, 10, Color.red, 1);

    // Anti-aliased line should have pixels with intermediate colors
    // (blended between red and white) — not just pure red or pure white.
    // When red (r=255, g=0, b=0) blends over white (r=255, g=255, b=255),
    // the green channel falls to an intermediate value (0 < g < 255).
    var found_intermediate = false;
    var y: u32 = 0;
    while (y < 20) : (y += 1) {
        var x: u32 = 0;
        while (x < 20) : (x += 1) {
            const px = img.getPixel(x, y).?;
            if (px.r == 255 and px.g > 0 and px.g < 255) {
                found_intermediate = true;
            }
        }
    }
    try std.testing.expect(found_intermediate);
}

test "drawArrowAA: draws anti-aliased arrow" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 100, 100);
    defer img.deinit();
    img.fill(Color.white);

    drawArrowAA(&img, 10, 10, 90, 50, Color.red, 2, 12.0);

    // Endpoint should have red pixels
    const px = img.getPixel(90, 50).?;
    try std.testing.expect(px.r > 200);
}

test "drawRuler: renders measurement line with ticks" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 200, 100);
    defer img.deinit();

    drawRuler(&img, 20, 50, 180, 50, Color{ .r = 0, .g = 200, .b = 255, .a = 255 }, 1, 6);

    // Midpoint of ruler line should have cyan pixels
    const mid = img.getPixel(100, 50).?;
    try std.testing.expect(mid.b > 200);

    // Tick marks are perpendicular — for a horizontal line, ticks are vertical
    // Check tick at start point (x=20, y=44 and y=56 for tick_size=6)
    const tick_above = img.getPixel(20, 44).?;
    const tick_below = img.getPixel(20, 56).?;
    try std.testing.expect(tick_above.b > 100 or tick_below.b > 100);
}
