//! Interactive selection overlay for screen capture.
//!
//! Shows a transparent fullscreen overlay. User drags to select a
//! rectangular area. Returns the selected region or null if cancelled.
//!
//! LEARNING NOTE — C interop with ObjC bridge:
//! The actual GUI code is in vendor/appkit_bridge.m (Objective-C).
//! This Zig module just calls the C functions exported by that file.
//! This pattern lets us use AppKit (ObjC) without contaminating the
//! Zig codebase with ObjC complexity.

const std = @import("std");
const zigshot = @import("zigshot");
const Rect = zigshot.Rect;

const bridge = @cImport({
    @cInclude("appkit_bridge.h");
});

/// Show the interactive selection overlay.
/// Blocks until the user selects an area or presses ESC.
/// Returns the selected Rect, or null if cancelled.
pub fn showSelectionOverlay() ?Rect {
    const result = bridge.appkit_show_selection_overlay();

    if (result.cancelled) return null;
    if (result.width < 2 or result.height < 2) return null;

    return Rect{
        .x = result.x,
        .y = result.y,
        .width = result.width,
        .height = result.height,
    };
}

/// Initialize NSApplication (call once before any GUI operation).
pub fn initApp() void {
    bridge.appkit_init_app();
}

/// Create the menu bar icon and dropdown menu.
/// The callback receives menu action IDs defined in appkit_bridge.h.
pub fn createMenuBar(callback: *const fn (c_int) callconv(.c) void) void {
    bridge.appkit_create_menubar(callback);
}

/// Run the NSApplication event loop (blocks forever).
pub fn runApp() void {
    bridge.appkit_run_app();
}

/// Menu action constants (mirror appkit_bridge.h).
pub const MenuAction = struct {
    pub const capture_fullscreen: c_int = 1;
    pub const capture_area: c_int = 2;
    pub const capture_window: c_int = 3;
    pub const ocr: c_int = 4;
    pub const quit: c_int = 99;
};
