//! The Image type — ZigShot's central nervous system.
//!
//! Every pixel operation in ZigShot flows through this struct. Capture
//! fills it, annotations draw on it, export reads from it. If ZigShot
//! were a web app, this is your `<canvas>` element — the thing everything
//! else exists to serve.
//!
//! LEARNING NOTE — Allocators (the Big One):
//! In JS, you `new` stuff and forget about it. The GC cleans up... eventually,
//! whenever it feels like it, maybe pausing your app for 50ms mid-frame.
//! Zig says: no. Every allocation is explicit. You pass an `Allocator` to
//! functions that need heap memory, and you call `deinit()` when you're done.
//! Feels like busywork at first. Then you realize your screenshot tool uses
//! exactly the memory it needs, frees it the instant it's done, and never
//! stutters. That's the trade.
//!
//! LEARNING NOTE — Error Unions (`!`):
//! The return type `!Image` means "either an Image or an error." Think of it
//! as a `Result<Image, Error>` if you've used Rust, or a Promise that can
//! reject — except it's synchronous and resolved at the call site. `try` is
//! like `await` for errors: unwrap the success or propagate the failure up.
//! No try/catch blocks, no exception stack unwinding, no surprises.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A single RGBA color value.
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };

    /// Parse a hex color string like "#FF0000" or "FF0000".
    ///
    /// Same format as CSS hex colors, parsed the hard way. No `parseInt(str, 16)`
    /// one-liner — we validate length, strip the optional '#', and parse each
    /// channel pair individually. Supports 6-char (RGB) and 8-char (RGBA).
    /// The things you take for granted with `color: #FF0000` in CSS...
    pub fn fromHex(hex: []const u8) !Color {
        const s = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
        if (s.len != 6 and s.len != 8) return error.InvalidHexColor;

        return Color{
            .r = std.fmt.parseInt(u8, s[0..2], 16) catch return error.InvalidHexColor,
            .g = std.fmt.parseInt(u8, s[2..4], 16) catch return error.InvalidHexColor,
            .b = std.fmt.parseInt(u8, s[4..6], 16) catch return error.InvalidHexColor,
            .a = if (s.len == 8) std.fmt.parseInt(u8, s[6..8], 16) catch return error.InvalidHexColor else 255,
        };
    }

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }
};

/// A raw RGBA image buffer.
///
/// LEARNING NOTE — "Allocator-aware init/deinit":
/// This is THE Zig pattern. The struct stores the allocator that created
/// its memory, so `deinit()` can free it without any global state. Always
/// pair `init()` with `defer img.deinit()` at the call site — it's the
/// Zig equivalent of try/finally, except the compiler won't let you forget.
pub const Image = struct {
    /// Raw pixel data: RGBA, 4 bytes per pixel, row-major order.
    /// `pixels[y * stride + x * 4]` is the R component of pixel (x, y).
    ///
    /// Same RGBA layout as Canvas `getImageData().data` — a flat Uint8Array
    /// where every 4 bytes are [R, G, B, A]. If you've ever done
    /// `ctx.getImageData(0, 0, w, h).data[i]`, you already know this format.
    pixels: []u8,
    width: u32,
    height: u32,
    /// Bytes per row. Usually `width * 4`, but may include padding from
    /// the GPU or display framework. Canvas ImageData doesn't have this
    /// concept because it always packs tightly — real graphics APIs do.
    stride: u32,
    /// The allocator that owns `pixels`. Stored so `deinit` works.
    /// Think of this as a handle to the memory manager. Zig doesn't have
    /// a global `free()` — you free through the same allocator that alloc'd.
    allocator: Allocator,

    /// Create a new image filled with transparent black.
    ///
    /// LEARNING NOTE — `try`:
    /// `allocator.alloc()` can fail (out of memory). `try` unwraps the
    /// success value or immediately returns the error to our caller.
    /// It's `await` for errors — one keyword, zero ceremony.
    pub fn init(allocator: Allocator, width: u32, height: u32) !Image {
        const stride = width * 4;
        const size = @as(usize, stride) * @as(usize, height);
        const pixels = try allocator.alloc(u8, size);
        // In JS, `new Uint8Array(n)` is zero-filled automatically.
        // In Zig, allocated memory is undefined — could be anything left
        // over from whoever used this memory last. We explicitly zero it
        // because "transparent black" is all zeros in RGBA.
        @memset(pixels, 0);

        return Image{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = stride,
            .allocator = allocator,
        };
    }

    /// Free the pixel buffer.
    ///
    /// LEARNING NOTE — `defer`:
    /// At the call site, write `defer img.deinit()` right after init. This
    /// guarantees cleanup runs when the scope exits, even on error paths.
    /// It's like `finally` in JS, except scoped to any block, not just
    /// try/catch. Zig also has `errdefer` which ONLY runs if the function
    /// returns an error — perfect for "undo this allocation if something
    /// else fails later."
    pub fn deinit(self: *Image) void {
        self.allocator.free(self.pixels);
        // Poison pill: sets every field to `undefined` (garbage bytes in
        // debug mode). If anything touches this struct after deinit, it
        // crashes immediately instead of silently reading stale data.
        // Imagine if JS's `delete obj` set every property to NaN — that's
        // the energy here. Use-after-free becomes a loud explosion, not a
        // silent data corruption bug you discover three weeks later.
        self.* = undefined;
    }

    /// Get the color at pixel (x, y). Returns null if out of bounds.
    pub fn getPixel(self: Image, x: u32, y: u32) ?Color {
        if (x >= self.width or y >= self.height) return null;
        const offset = @as(usize, y) * @as(usize, self.stride) + @as(usize, x) * 4;
        return Color{
            .r = self.pixels[offset],
            .g = self.pixels[offset + 1],
            .b = self.pixels[offset + 2],
            .a = self.pixels[offset + 3],
        };
    }

    /// Set the color at pixel (x, y). No-op if out of bounds.
    pub fn setPixel(self: *Image, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        const offset = @as(usize, y) * @as(usize, self.stride) + @as(usize, x) * 4;
        self.pixels[offset] = color.r;
        self.pixels[offset + 1] = color.g;
        self.pixels[offset + 2] = color.b;
        self.pixels[offset + 3] = color.a;
    }

    /// Fill the entire image with a single color.
    pub fn fill(self: *Image, color: Color) void {
        var y: u32 = 0;
        while (y < self.height) : (y += 1) {
            var x: u32 = 0;
            while (x < self.width) : (x += 1) {
                self.setPixel(x, y, color);
            }
        }
    }

    /// Return the total number of pixels.
    pub fn pixelCount(self: Image) usize {
        return @as(usize, self.width) * @as(usize, self.height);
    }

    /// Return the raw byte size of the pixel buffer.
    pub fn byteSize(self: Image) usize {
        return self.pixels.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Image: create and destroy without leaks" {
    // LEARNING NOTE — std.testing.allocator:
    // This is your memory cop. It wraps the general-purpose allocator with
    // leak detection cranked to max. Forget to free even one byte? Test
    // fails. In JS, leaked memory is a slow performance death you notice
    // months later. In Zig tests, it's a red X right now. Use this
    // allocator in every single test.
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 100, 50);
    defer img.deinit();

    try std.testing.expectEqual(@as(u32, 100), img.width);
    try std.testing.expectEqual(@as(u32, 50), img.height);
    try std.testing.expectEqual(@as(u32, 400), img.stride);
    try std.testing.expectEqual(@as(usize, 20000), img.byteSize());
}

test "Image: pixels start as transparent black" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 10, 10);
    defer img.deinit();

    const pixel = img.getPixel(5, 5).?;
    try std.testing.expect(pixel.eql(Color.transparent));
}

test "Image: setPixel and getPixel roundtrip" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 10, 10);
    defer img.deinit();

    img.setPixel(3, 7, Color.red);
    const pixel = img.getPixel(3, 7).?;
    try std.testing.expect(pixel.eql(Color.red));

    // Neighboring pixel should still be transparent
    const neighbor = img.getPixel(4, 7).?;
    try std.testing.expect(neighbor.eql(Color.transparent));
}

test "Image: out-of-bounds returns null / no-op" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 10, 10);
    defer img.deinit();

    // getPixel out of bounds returns null
    try std.testing.expectEqual(img.getPixel(10, 0), null);
    try std.testing.expectEqual(img.getPixel(0, 10), null);
    try std.testing.expectEqual(img.getPixel(100, 100), null);

    // setPixel out of bounds is a no-op (no crash)
    img.setPixel(10, 0, Color.red);
    img.setPixel(0, 10, Color.red);
}

test "Image: fill sets all pixels" {
    const allocator = std.testing.allocator;
    var img = try Image.init(allocator, 4, 4);
    defer img.deinit();

    img.fill(Color.white);

    // Check a few pixels
    try std.testing.expect(img.getPixel(0, 0).?.eql(Color.white));
    try std.testing.expect(img.getPixel(3, 3).?.eql(Color.white));
    try std.testing.expect(img.getPixel(2, 1).?.eql(Color.white));
}

test "Color: fromHex parses valid colors" {
    const red = try Color.fromHex("#FF0000");
    try std.testing.expect(red.eql(Color.red));

    const white = try Color.fromHex("FFFFFF");
    try std.testing.expect(white.eql(Color.white));

    // With alpha
    const semi = try Color.fromHex("#FF000080");
    try std.testing.expectEqual(@as(u8, 255), semi.r);
    try std.testing.expectEqual(@as(u8, 0), semi.g);
    try std.testing.expectEqual(@as(u8, 128), semi.a);
}

test "Color: fromHex rejects invalid input" {
    try std.testing.expectError(error.InvalidHexColor, Color.fromHex("GG0000"));
    try std.testing.expectError(error.InvalidHexColor, Color.fromHex("#FFF"));
    try std.testing.expectError(error.InvalidHexColor, Color.fromHex(""));
}
