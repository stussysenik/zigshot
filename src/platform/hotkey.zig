//! Global hotkey registration via macOS CGEventTap.
//!
//! Like `document.addEventListener('keydown')` but for the entire OS,
//! not just your browser window. Every keypress on the Mac goes through
//! our callback before reaching the target app. Powerful, dangerous, and
//! requires "Input Monitoring" permission in System Settings.
//!
//! CGEventTap is a pure C API (not Objective-C), so we can call it
//! directly from Zig via @cImport. The callback uses `callconv(.c)` —
//! the compiler ensures the calling convention matches what CoreGraphics
//! expects. No FFI glue needed.

const std = @import("std");

const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

/// Modifier key flags (matches CGEventFlags bitmask positions).
///
/// Magic numbers below = bit positions for modifier keys in macOS CGEventFlags.
/// Bit 20 = Command, Bit 17 = Shift, Bit 18 = Control, Bit 19 = Option.
/// Hardcoded because @cImport doesn't always translate Apple's #define
/// constants cleanly — some are complex macro expressions that Zig's
/// translate-c chokes on. So we just hardcode the known values.
pub const Modifiers = struct {
    command: bool = false,
    shift: bool = false,
    control: bool = false,
    option: bool = false,

    pub fn matches(self: Modifiers, flags: u64) bool {
        const cmd_flag: u64 = 1 << 20; // kCGEventFlagMaskCommand
        const shift_flag: u64 = 1 << 17; // kCGEventFlagMaskShift
        const ctrl_flag: u64 = 1 << 18; // kCGEventFlagMaskControl
        const opt_flag: u64 = 1 << 19; // kCGEventFlagMaskAlternate

        if (self.command and (flags & cmd_flag == 0)) return false;
        if (self.shift and (flags & shift_flag == 0)) return false;
        if (self.control and (flags & ctrl_flag == 0)) return false;
        if (self.option and (flags & opt_flag == 0)) return false;

        return true;
    }
};

/// An action triggered by a hotkey.
pub const Action = enum {
    capture_fullscreen,
    capture_area,
    capture_window,
    ocr_capture,
};

/// A registered hotkey binding.
pub const Hotkey = struct {
    keycode: u16,
    modifiers: Modifiers,
    action: Action,
};

/// Common macOS keycodes.
pub const Keycode = struct {
    pub const @"1": u16 = 18;
    pub const @"2": u16 = 19;
    pub const @"3": u16 = 20;
    pub const @"4": u16 = 21;
    pub const @"5": u16 = 23;
    pub const @"6": u16 = 22;
    pub const c: u16 = 8;
    pub const s: u16 = 1;
    pub const escape: u16 = 53;
};

// C callbacks can't capture closures. In JS, you'd write
// `tap.onEvent = (e) => myState.handle(e)` and close over `myState`.
// In C, the callback is a bare function pointer — no captured variables
// allowed. So we store state in module-level globals. Ugly, but the
// only option with C callbacks. This is why C code is full of globals.
var registered_hotkeys: [16]Hotkey = undefined;
var hotkey_count: usize = 0;
var last_action: ?Action = null;

/// The C callback invoked by CGEventTap on every keyboard event.
///
/// LEARNING NOTE — callconv(.c):
/// This function is called by CoreGraphics, not by Zig code. The
/// `callconv(.c)` annotation tells the Zig compiler to use the C
/// ABI for this function, matching what CGEventTap expects.
fn eventTapCallback(
    _: c.CGEventTapProxy,
    event_type: c.CGEventType,
    event: c.CGEventRef,
    _: ?*anyopaque,
) callconv(.c) c.CGEventRef {
    // macOS auto-disables your event tap if your callback takes >~1 second.
    // When that happens, it sends this event type as a courtesy notice.
    // A production app would re-enable the tap here (needs the tap reference).
    // For now we just let it pass through — our callback is fast enough.
    if (event_type == c.kCGEventTapDisabledByTimeout or
        event_type == c.kCGEventTapDisabledByUserInput)
    {
        return event;
    }

    if (event_type != c.kCGEventKeyDown) return event;

    const keycode: u16 = @intCast(c.CGEventGetIntegerValueField(event, c.kCGKeyboardEventKeycode));
    const flags: u64 = @intCast(c.CGEventGetFlags(event));

    // Check against registered hotkeys
    var i: usize = 0;
    while (i < hotkey_count) : (i += 1) {
        const hk = registered_hotkeys[i];
        if (hk.keycode == keycode and hk.modifiers.matches(flags)) {
            last_action = hk.action;
            // Stop the run loop to handle the action
            c.CFRunLoopStop(c.CFRunLoopGetCurrent());
            return event;
        }
    }

    return event;
}

/// Start listening for global hotkeys with default bindings.
/// Returns the triggered action when a hotkey is pressed.
///
/// macOS event pump. `CFRunLoopRun()` blocks the thread, processing
/// events forever. Our callback calls `CFRunLoopStop()` when a matching
/// hotkey fires, which unblocks this call. Think of it as
/// `await new Promise(resolve => { onHotkey = resolve })` in JS —
/// except the "event loop" is macOS's, not Node's.
pub fn waitForHotkey(hotkeys: []const Hotkey) !Action {
    // Register hotkeys
    hotkey_count = @min(hotkeys.len, 16);
    for (hotkeys[0..hotkey_count], 0..) |hk, i| {
        registered_hotkeys[i] = hk;
    }
    last_action = null;

    // Create event tap for key-down events
    const event_mask: u64 = (@as(u64, 1) << @intCast(c.kCGEventKeyDown));

    const tap = c.CGEventTapCreate(
        c.kCGSessionEventTap,
        c.kCGHeadInsertEventTap,
        c.kCGEventTapOptionDefault,
        event_mask,
        &eventTapCallback,
        null,
    );

    if (tap == null) {
        std.debug.print("Error: Could not create event tap.\n", .{});
        std.debug.print("  Enable Input Monitoring in System Settings → Privacy & Security.\n", .{});
        return error.PermissionDenied;
    }

    const run_loop_source = c.CFMachPortCreateRunLoopSource(null, tap, 0);
    if (run_loop_source == null) {
        return error.PermissionDenied;
    }
    defer c.CFRelease(run_loop_source);

    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), run_loop_source, c.kCFRunLoopCommonModes);
    c.CGEventTapEnable(tap, true);

    // Block until a hotkey fires (callback calls CFRunLoopStop)
    c.CFRunLoopRun();

    // Clean up
    c.CGEventTapEnable(tap, false);
    c.CFRunLoopRemoveSource(c.CFRunLoopGetCurrent(), run_loop_source, c.kCFRunLoopCommonModes);

    return last_action orelse error.PermissionDenied;
}

/// Get the default hotkey bindings.
pub fn defaultHotkeys() [4]Hotkey {
    return .{
        .{ .keycode = Keycode.@"3", .modifiers = .{ .command = true, .shift = true }, .action = .capture_fullscreen },
        .{ .keycode = Keycode.@"4", .modifiers = .{ .command = true, .shift = true }, .action = .capture_area },
        .{ .keycode = Keycode.@"5", .modifiers = .{ .command = true, .shift = true }, .action = .capture_window },
        .{ .keycode = Keycode.@"2", .modifiers = .{ .command = true, .shift = true }, .action = .ocr_capture },
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Modifiers: matches flags correctly" {
    const cmd_shift = Modifiers{ .command = true, .shift = true };
    // Command + Shift flags
    const flags: u64 = (1 << 20) | (1 << 17);
    try std.testing.expect(cmd_shift.matches(flags));

    // Missing shift
    const cmd_only: u64 = (1 << 20);
    try std.testing.expect(!cmd_shift.matches(cmd_only));
}

test "Modifiers: empty matches everything" {
    const none = Modifiers{};
    try std.testing.expect(none.matches(0));
    try std.testing.expect(none.matches(0xFFFFFFFF));
}

test "defaultHotkeys: returns 4 bindings" {
    const hk = defaultHotkeys();
    try std.testing.expectEqual(@as(usize, 4), hk.len);
    try std.testing.expectEqual(Action.capture_fullscreen, hk[0].action);
    try std.testing.expectEqual(Action.capture_area, hk[1].action);
}
