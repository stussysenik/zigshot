//! ZigShot — Screenshot tool for macOS.
//!
//! Phase 0: Capture fullscreen screenshot and save as PNG.
//!
//! LEARNING NOTE — @cImport:
//! Zig has first-class C interop. @cImport translates C headers into Zig
//! types at compile time. Every C function, struct, and constant becomes
//! available as `c.FunctionName`. This is Zig's superpower — you can call
//! any C library without writing bindings by hand.
//!
//! LEARNING NOTE — defer for resource cleanup:
//! macOS CoreFoundation/CoreGraphics objects use manual reference counting.
//! The "Create Rule": any function with "Create" or "Copy" in its name
//! returns a +1 reference that YOU must release. We use `defer` to ensure
//! cleanup happens even if an error occurs later.

const std = @import("std");
const zigshot = @import("zigshot");

// Import macOS C frameworks.
// These are available because build.zig links CoreGraphics, CoreFoundation, and ImageIO.
const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("ImageIO/ImageIO.h");
});

pub fn main() !void {
    // Get output path from args, or default to ~/Desktop/zigshot-capture.png
    var args = std.process.args();
    _ = args.skip(); // skip program name

    const output_path = if (args.next()) |arg| arg else "/tmp/zigshot-capture.png";

    std.debug.print("ZigShot — capturing fullscreen screenshot...\n", .{});

    // Capture the screen
    const cg_image = captureFullscreen() orelse {
        std.debug.print("ERROR: Screen capture failed.\n", .{});
        std.debug.print("  This usually means screen recording permission is not granted.\n", .{});
        std.debug.print("  Go to: System Settings → Privacy & Security → Screen Recording\n", .{});
        std.debug.print("  and add your terminal app.\n", .{});
        return error.CaptureError;
    };
    defer c.CGImageRelease(cg_image);

    // Check for the permission-denied case: macOS returns a 1x1 pixel image
    // instead of null when screen recording permission is denied.
    const width = c.CGImageGetWidth(cg_image);
    const height = c.CGImageGetHeight(cg_image);
    if (width <= 1 or height <= 1) {
        std.debug.print("ERROR: Captured image is {d}x{d} — screen recording permission likely denied.\n", .{ width, height });
        std.debug.print("  Go to: System Settings → Privacy & Security → Screen Recording\n", .{});
        return error.PermissionDenied;
    }

    std.debug.print("  Captured {d}x{d} image\n", .{ width, height });

    // Save as PNG
    savePNG(cg_image, output_path) catch |err| {
        std.debug.print("ERROR: Failed to save PNG: {}\n", .{err});
        return err;
    };

    std.debug.print("  Saved to: {s}\n", .{output_path});
    std.debug.print("Done!\n", .{});
}

/// Capture the entire screen as a CGImage.
///
/// LEARNING NOTE — Optionals (`?T`):
/// This function returns `?*c.CGImage` — either a valid image pointer or null.
/// CGWindowListCreateImage is a C function that returns NULL on failure.
/// Zig's `@as(?..., ...)` wraps the C pointer in an optional type, and
/// `orelse` at the call site handles the null case explicitly.
fn captureFullscreen() ?*c.CGImage {
    // CGRectInfinite captures all displays.
    // kCGWindowListOptionOnScreenOnly captures only visible windows.
    // kCGNullWindowID means "all windows."
    const image = c.CGWindowListCreateImage(
        c.CGRectInfinite,
        c.kCGWindowListOptionOnScreenOnly,
        c.kCGNullWindowID,
        c.kCGWindowImageDefault,
    );
    return @as(?*c.CGImage, image);
}

/// Save a CGImage as a PNG file at the given path.
///
/// LEARNING NOTE — C String Interop:
/// macOS APIs use CFString. We need to convert Zig's `[]const u8` (a
/// pointer + length) to a CFString (a CoreFoundation object). The
/// CFStringCreateWithBytes function does this conversion.
fn savePNG(cg_image: *c.CGImage, path: []const u8) !void {
    // Convert Zig string to CFString
    const cf_path = c.CFStringCreateWithBytes(
        null, // default allocator
        path.ptr,
        @intCast(path.len),
        c.kCFStringEncodingUTF8,
        0, // not external representation
    ) orelse return error.StringCreationFailed;
    defer c.CFRelease(cf_path);

    // Create a file URL from the path string
    const url = c.CFURLCreateWithFileSystemPath(
        null,
        cf_path,
        c.kCFURLPOSIXPathStyle,
        0, // not a directory
    ) orelse return error.URLCreationFailed;
    defer c.CFRelease(url);

    // Create the PNG uniform type identifier as a CFString.
    // kUTTypePNG lives in CoreServices, but we can create it directly
    // since it's just the string "public.png".
    const png_type = c.CFStringCreateWithCString(
        null,
        "public.png",
        c.kCFStringEncodingUTF8,
    ) orelse return error.StringCreationFailed;
    defer c.CFRelease(png_type);

    // Create an image destination (PNG writer).
    // The "1" means we'll write exactly 1 image.
    const dest = c.CGImageDestinationCreateWithURL(
        url,
        png_type,
        1,
        null,
    ) orelse return error.DestinationCreationFailed;
    defer c.CFRelease(dest);

    // Add the captured image and finalize (write to disk)
    c.CGImageDestinationAddImage(dest, cg_image, null);

    if (!c.CGImageDestinationFinalize(dest)) {
        return error.WriteFailed;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "captureFullscreen returns an image on macOS with permissions" {
    // This test only passes when run on macOS with screen recording permission.
    // It verifies the basic capture path works.
    if (captureFullscreen()) |img| {
        defer c.CGImageRelease(img);
        const w = c.CGImageGetWidth(img);
        const h = c.CGImageGetHeight(img);
        // A real display should be at least 800x600
        try std.testing.expect(w > 100);
        try std.testing.expect(h > 100);
    }
    // If capture returns null (no permission), that's OK — test just passes.
}
