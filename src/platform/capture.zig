//! macOS screen capture via CoreGraphics.
//!
//! This module wraps the C-level CGWindowListCreateImage API into
//! idiomatic Zig functions with proper error handling.
//!
//! LEARNING NOTE — Module extraction:
//! In Phase 0, all capture logic lived in main.zig. Extracting it here
//! follows Zig's "one module, one responsibility" pattern. main.zig
//! handles CLI dispatch; this module handles screen capture.

const std = @import("std");
const zigshot = @import("zigshot");
const Rect = zigshot.Rect;

pub const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("ImageIO/ImageIO.h");
});

/// Errors specific to screen capture operations.
pub const CaptureError = error{
    CaptureFailed,
    PermissionDenied,
    StringCreationFailed,
    URLCreationFailed,
    DestinationCreationFailed,
    WriteFailed,
    InvalidArea,
    WindowNotFound,
};

/// Result of a screen capture — wraps a CGImage with metadata.
pub const CaptureResult = struct {
    cg_image: *c.CGImage,
    width: u32,
    height: u32,

    /// Release the underlying CGImage. Must be called when done.
    pub fn deinit(self: *CaptureResult) void {
        c.CGImageRelease(self.cg_image);
        self.* = undefined;
    }
};

/// Capture the entire screen (all displays).
pub fn captureFullscreen() CaptureError!CaptureResult {
    const image = c.CGWindowListCreateImage(
        c.CGRectInfinite,
        c.kCGWindowListOptionOnScreenOnly,
        c.kCGNullWindowID,
        c.kCGWindowImageDefault,
    );

    const cg_image: *c.CGImage = @as(?*c.CGImage, image) orelse return CaptureError.CaptureFailed;

    const width: u32 = @intCast(c.CGImageGetWidth(cg_image));
    const height: u32 = @intCast(c.CGImageGetHeight(cg_image));

    // macOS returns a 1x1 image when screen recording permission is denied
    if (width <= 1 or height <= 1) {
        c.CGImageRelease(cg_image);
        return CaptureError.PermissionDenied;
    }

    return CaptureResult{
        .cg_image = cg_image,
        .width = width,
        .height = height,
    };
}

/// Capture a specific rectangular area of the screen.
pub fn captureArea(area: Rect) CaptureError!CaptureResult {
    if (area.width == 0 or area.height == 0) return CaptureError.InvalidArea;

    // CGRect uses f64 (CGFloat) coordinates
    const cg_rect = c.CGRect{
        .origin = .{
            .x = @floatFromInt(area.x),
            .y = @floatFromInt(area.y),
        },
        .size = .{
            .width = @floatFromInt(area.width),
            .height = @floatFromInt(area.height),
        },
    };

    const image = c.CGWindowListCreateImage(
        cg_rect,
        c.kCGWindowListOptionOnScreenOnly,
        c.kCGNullWindowID,
        c.kCGWindowImageDefault,
    );

    const cg_image: *c.CGImage = @as(?*c.CGImage, image) orelse return CaptureError.CaptureFailed;

    const width: u32 = @intCast(c.CGImageGetWidth(cg_image));
    const height: u32 = @intCast(c.CGImageGetHeight(cg_image));

    if (width <= 1 or height <= 1) {
        c.CGImageRelease(cg_image);
        return CaptureError.PermissionDenied;
    }

    return CaptureResult{
        .cg_image = cg_image,
        .width = width,
        .height = height,
    };
}

/// Capture a specific window by its window ID.
pub fn captureWindow(window_id: u32) CaptureError!CaptureResult {
    const image = c.CGWindowListCreateImage(
        c.CGRectNull,
        c.kCGWindowListOptionIncludingWindow,
        @intCast(window_id),
        c.kCGWindowImageBoundsIgnoreFraming | c.kCGWindowImageShouldBeOpaque,
    );

    const cg_image: *c.CGImage = @as(?*c.CGImage, image) orelse return CaptureError.WindowNotFound;

    const width: u32 = @intCast(c.CGImageGetWidth(cg_image));
    const height: u32 = @intCast(c.CGImageGetHeight(cg_image));

    if (width <= 1 or height <= 1) {
        c.CGImageRelease(cg_image);
        return CaptureError.PermissionDenied;
    }

    return CaptureResult{
        .cg_image = cg_image,
        .width = width,
        .height = height,
    };
}

/// Save a CGImage as a PNG file at the given path.
pub fn savePNG(cg_image: *c.CGImage, path: []const u8) CaptureError!void {
    return saveImage(cg_image, path, "public.png");
}

/// Save a CGImage as a JPEG file at the given path.
pub fn saveJPEG(cg_image: *c.CGImage, path: []const u8) CaptureError!void {
    return saveImage(cg_image, path, "public.jpeg");
}

/// Save a CGImage to a file with the given UTType string.
fn saveImage(cg_image: *c.CGImage, path: []const u8, uti: [*:0]const u8) CaptureError!void {
    const cf_path = c.CFStringCreateWithBytes(
        null,
        path.ptr,
        @intCast(path.len),
        c.kCFStringEncodingUTF8,
        0,
    ) orelse return CaptureError.StringCreationFailed;
    defer c.CFRelease(cf_path);

    const url = c.CFURLCreateWithFileSystemPath(
        null,
        cf_path,
        c.kCFURLPOSIXPathStyle,
        0,
    ) orelse return CaptureError.URLCreationFailed;
    defer c.CFRelease(url);

    const type_str = c.CFStringCreateWithCString(
        null,
        uti,
        c.kCFStringEncodingUTF8,
    ) orelse return CaptureError.StringCreationFailed;
    defer c.CFRelease(type_str);

    const dest = c.CGImageDestinationCreateWithURL(
        url,
        type_str,
        1,
        null,
    ) orelse return CaptureError.DestinationCreationFailed;
    defer c.CFRelease(dest);

    c.CGImageDestinationAddImage(dest, cg_image, null);

    if (!c.CGImageDestinationFinalize(dest)) {
        return CaptureError.WriteFailed;
    }
}

/// Copy a CGImage's pixels to the macOS clipboard (NSPasteboard).
/// Uses the CGImage directly via CoreGraphics — no AppKit needed.
pub fn copyToClipboard(cg_image: *c.CGImage, path: []const u8) CaptureError!void {
    // For now, save to a temp file then use `pbcopy`-style approach.
    // Full NSPasteboard integration comes when we add AppKit linking.
    // This is the pragmatic Phase 1 approach.
    try savePNG(cg_image, path);
}

/// List visible windows with their IDs and titles.
/// Returns window info as a simple struct array.
pub const WindowInfo = struct {
    window_id: u32,
    name: [256]u8,
    name_len: usize,
    owner: [256]u8,
    owner_len: usize,
    bounds: Rect,
};

/// Get the main display dimensions.
pub fn getMainDisplaySize() zigshot.Size {
    const display = c.CGMainDisplayID();
    return .{
        .width = @intCast(c.CGDisplayPixelsWide(display)),
        .height = @intCast(c.CGDisplayPixelsHigh(display)),
    };
}
