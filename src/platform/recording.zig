//! Screen recording via ScreenCaptureKit + AVFoundation.
//!
//! Records a screen area to MP4 (H.264) or GIF. Requires macOS 12.3+.
//! The actual recording happens in the ObjC bridge — ScreenCaptureKit is
//! an ObjC-only API with no C equivalent.
//!
//! LEARNING NOTE — ScreenCaptureKit vs CGWindowListCreateImage:
//! CGWindowListCreateImage captures a single frame (screenshot).
//! ScreenCaptureKit (SCStream) captures a continuous stream of frames —
//! essentially a live video feed of a screen region. Frames arrive as
//! CMSampleBuffers via a callback, which we pipe into AVAssetWriter (MP4)
//! or accumulate as CGImages (GIF).

const std = @import("std");

const bridge = @cImport({
    @cInclude("appkit_bridge.h");
});

/// Recording status constants (mirror appkit_bridge.h).
pub const Status = struct {
    pub const started: c_int = 1;
    pub const stopped: c_int = 2;
    pub const err: c_int = 3;
};

/// Start recording a screen area.
pub fn startRecording(
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    output_path: [*c]const u8,
    format: [*c]const u8,
    fps: u32,
    callback: *const fn (c_int, [*c]const u8) callconv(.c) void,
) void {
    bridge.appkit_start_recording(x, y, width, height, output_path, format, fps, callback);
}

/// Stop the current recording.
pub fn stopRecording() void {
    bridge.appkit_stop_recording();
}

/// Check if currently recording.
pub fn isRecording() bool {
    return bridge.appkit_is_recording();
}
