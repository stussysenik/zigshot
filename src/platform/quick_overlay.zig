//! Quick Access Overlay — floating thumbnail after capture.
//!
//! Shows a small floating panel with a thumbnail of the captured image
//! and action buttons: Copy, Save, Annotate, Pin, Close.
//! Auto-dismisses after 5 seconds (auto-copies to clipboard).
//!
//! LEARNING NOTE — NSPanel vs NSWindow:
//! NSPanel is a subclass of NSWindow designed for utility windows.
//! It supports floating behavior, doesn't appear in the Dock, and
//! has special key focus handling (becomesKeyOnlyIfNeeded).
//! Perfect for ephemeral UI like this overlay.

const bridge = @cImport({
    @cInclude("appkit_bridge.h");
});

/// Quick overlay action constants (mirror appkit_bridge.h).
pub const QuickAction = struct {
    pub const copy: c_int = 10;
    pub const save: c_int = 11;
    pub const annotate: c_int = 12;
    pub const pin: c_int = 13;
    pub const close: c_int = 14;
};

/// Show the quick access overlay with a thumbnail of the captured image.
/// callback receives action_id and the image path.
///
/// LEARNING NOTE — [*c]const u8 vs [*:0]const u8:
/// @cImport translates C's `const char*` as `[*c]const u8` — a C-compatible
/// pointer that may be null. We use this type in the callback signature to
/// match what the C bridge expects. `[*:0]const u8` (null-terminated) won't
/// implicitly convert because [*c] might be null.
pub fn showQuickOverlay(
    image_path: [*c]const u8,
    width: u32,
    height: u32,
    callback: *const fn (c_int, [*c]const u8) callconv(.c) void,
) void {
    bridge.appkit_show_quick_overlay(image_path, width, height, callback);
}

/// Dismiss the quick overlay if visible.
pub fn dismissQuickOverlay() void {
    bridge.appkit_dismiss_quick_overlay();
}

/// Pin a screenshot as an always-on-top floating window.
pub fn pinScreenshot(image_path: [*c]const u8, width: u32, height: u32) void {
    bridge.appkit_pin_screenshot(image_path, width, height);
}

/// Dismiss the pinned screenshot window.
pub fn unpinScreenshot() void {
    bridge.appkit_unpin_screenshot();
}
