//! The "I can't believe this works" module.
//!
//! macOS clipboard integration for images. The "clean" API for this is
//! NSPasteboard — an Objective-C class. Calling Objective-C from Zig
//! is possible (via zig-objc), but overkill for a single clipboard write.
//! So we shell out to `osascript` (Apple's command-line AppleScript runner)
//! and let a one-line AppleScript do the dirty work.
//!
//! It's absurd. It works. Ship it.

const std = @import("std");
const capture = @import("capture.zig");

pub const ClipboardError = error{
    WriteFailed,
    ProcessFailed,
    TempFileFailed,
} || capture.CaptureError;

/// Copy a PNG file to the macOS clipboard using osascript.
///
/// It's absurd that shelling out to AppleScript is the cleanest way to
/// copy an image to the clipboard from C-level code. But here we are.
/// This is what happens when the clean API (NSPasteboard) is Objective-C
/// only and you're writing in a language that speaks C, not ObjC.
pub fn copyImageFile(png_path: []const u8) ClipboardError!void {
    const allocator = std.heap.page_allocator;

    // This one-liner tells AppleScript: "read this file as PNG data, put it
    // on the clipboard." The «class PNGf» is AppleScript's way of saying
    // "PNG format" — yes, those are actual guillemet characters in source code.
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
///
/// The clipboard pipeline: CGImage -> temp PNG file -> osascript reads it
/// -> delete temp file. Three syscalls for what `navigator.clipboard.write()`
/// does in one line of JS. Welcome to systems programming.
pub fn copyCGImage(cg_image: *capture.c.CGImage) ClipboardError!void {
    const temp_path = "/tmp/.zigshot-clipboard-temp.png";
    try capture.savePNG(cg_image, temp_path);
    try copyImageFile(temp_path);

    // Clean up temp file (best effort — `catch {}` silently ignores errors,
    // like an empty catch block in JS. Fine for cleanup, never for real work.)
    std.fs.deleteFileAbsolute(temp_path) catch {};
}
