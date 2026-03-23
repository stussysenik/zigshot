//! macOS clipboard (NSPasteboard) integration via CoreGraphics.
//!
//! LEARNING NOTE — Why not AppKit directly?
//! NSPasteboard is an AppKit class (Objective-C). To call it from Zig
//! without zig-objc, we use a pragmatic workaround: render the image
//! to PNG bytes, then use the `pbcopy` CLI or write to a known temp
//! file. When we add zig-objc in Phase 2, we'll call NSPasteboard directly.
//!
//! For now, we use a shell-out approach via osascript which is reliable
//! and teaches Zig's std.process module.

const std = @import("std");
const capture = @import("capture.zig");

pub const ClipboardError = error{
    WriteFailed,
    ProcessFailed,
    TempFileFailed,
} || capture.CaptureError;

/// Copy a PNG file to the macOS clipboard using osascript.
///
/// LEARNING NOTE — std.process.Child:
/// Zig's child process API is explicit about stdin/stdout/stderr
/// handling. You must configure which streams to capture. This is
/// more verbose than Python's subprocess but gives you full control.
pub fn copyImageFile(png_path: []const u8) ClipboardError!void {
    // Use osascript to set clipboard to image file contents.
    // This is the most reliable cross-version approach without AppKit.
    const allocator = std.heap.page_allocator;

    // Build the AppleScript command
    var script_buf: [512]u8 = undefined;
    const script = std.fmt.bufPrint(&script_buf, "set the clipboard to (read (POSIX file \"{s}\") as «class PNGf»)", .{png_path}) catch return ClipboardError.WriteFailed;

    var child = std.process.Child.init(
        &.{ "osascript", "-e", script },
        allocator,
    );
    child.stderr_behavior = .Ignore;
    child.stdout_behavior = .Ignore;

    _ = child.spawnAndWait() catch return ClipboardError.ProcessFailed;
}

/// Copy a CGImage to the clipboard by saving to temp then copying.
pub fn copyCGImage(cg_image: *capture.c.CGImage) ClipboardError!void {
    const temp_path = "/tmp/.zigshot-clipboard-temp.png";
    try capture.savePNG(cg_image, temp_path);
    try copyImageFile(temp_path);

    // Clean up temp file (best effort)
    std.fs.deleteFileAbsolute(temp_path) catch {};
}
