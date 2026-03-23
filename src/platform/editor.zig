//! Annotation Editor — interactive canvas for drawing on screenshots.
//!
//! Manages the editor state (image, undo stack, active tool) and bridges
//! between the ObjC GUI and the Zig annotation pipeline. The ObjC side
//! handles mouse events and rubber-band previews. When the user finishes
//! drawing (mouseUp), ObjC calls back to Zig with coordinates. Zig
//! applies the annotation via pipeline.zig (same code as CLI) and pushes
//! the updated pixels back to ObjC for display.
//!
//! LEARNING NOTE — Zig global state:
//! Zig doesn't have global mutable variables by default (for good reason).
//! But the editor callback is a C function pointer with no user_data param,
//! so we need file-level (`var`) state. This is the Zig equivalent of a
//! static mutable in C. We use a single EditorState struct to keep it tidy.

const std = @import("std");
const zigshot = @import("zigshot");
const Image = zigshot.Image;
const Color = zigshot.Color;
const Rect = zigshot.Rect;
const pipeline = zigshot.pipeline;
const blur_mod = zigshot.blur;
const capture = @import("capture.zig");
const clipboard = @import("clipboard.zig");

const bridge = @cImport({
    @cInclude("appkit_bridge.h");
});

/// Maximum undo depth. Each undo entry stores a full RGBA pixel buffer.
/// At 1920x1080 that's ~8MB per entry, so 20 entries = ~160MB worst case.
const MAX_UNDO: usize = 20;

/// Editor action IDs from the ObjC bridge.
const EditorAction = struct {
    const copy: c_int = 1;
    const save: c_int = 2;
    const undo: c_int = 3;
    const redo: c_int = 4;
    const close: c_int = 5;
};

/// File-level editor state. Only one editor can be open at a time.
/// This is set by `openEditor` and read by the C callbacks.
var g_state: ?EditorState = null;

pub const EditorState = struct {
    image: Image,
    undo_stack: [MAX_UNDO]?[]u8,
    undo_count: usize,
    redo_stack: [MAX_UNDO]?[]u8,
    redo_count: usize,
    handle: ?*anyopaque,
    allocator: std.mem.Allocator,

    /// Create editor state from an existing image.
    /// Takes ownership of the image — caller must not deinit it.
    pub fn init(allocator: std.mem.Allocator, image: Image) EditorState {
        return .{
            .image = image,
            .undo_stack = [_]?[]u8{null} ** MAX_UNDO,
            .undo_count = 0,
            .redo_stack = [_]?[]u8{null} ** MAX_UNDO,
            .redo_count = 0,
            .handle = null,
            .allocator = allocator,
        };
    }

    /// Push current pixels onto the undo stack before modifying.
    pub fn pushUndo(self: *EditorState) void {
        if (self.undo_count >= MAX_UNDO) {
            if (self.undo_stack[0]) |old| {
                self.allocator.free(old);
            }
            var i: usize = 0;
            while (i < MAX_UNDO - 1) : (i += 1) {
                self.undo_stack[i] = self.undo_stack[i + 1];
            }
            self.undo_stack[MAX_UNDO - 1] = null;
            self.undo_count -= 1;
        }

        const copy = self.allocator.dupe(u8, self.image.pixels) catch return;
        self.undo_stack[self.undo_count] = copy;
        self.undo_count += 1;
    }

    /// Pop the last undo entry, restoring pixels. Pushes current to redo stack.
    pub fn popUndo(self: *EditorState) bool {
        if (self.undo_count == 0) return false;

        // Save current state to redo stack before restoring
        self.pushRedo();

        self.undo_count -= 1;
        if (self.undo_stack[self.undo_count]) |saved| {
            @memcpy(self.image.pixels, saved);
            self.allocator.free(saved);
            self.undo_stack[self.undo_count] = null;
            return true;
        }
        return false;
    }

    /// Push current pixels onto the redo stack.
    fn pushRedo(self: *EditorState) void {
        if (self.redo_count >= MAX_UNDO) {
            if (self.redo_stack[0]) |old| {
                self.allocator.free(old);
            }
            var i: usize = 0;
            while (i < MAX_UNDO - 1) : (i += 1) {
                self.redo_stack[i] = self.redo_stack[i + 1];
            }
            self.redo_stack[MAX_UNDO - 1] = null;
            self.redo_count -= 1;
        }

        const copy = self.allocator.dupe(u8, self.image.pixels) catch return;
        self.redo_stack[self.redo_count] = copy;
        self.redo_count += 1;
    }

    /// Pop the last redo entry, restoring pixels.
    pub fn popRedo(self: *EditorState) bool {
        if (self.redo_count == 0) return false;

        // Save current to undo stack (so we can undo the redo)
        const copy = self.allocator.dupe(u8, self.image.pixels) catch return false;
        self.undo_stack[self.undo_count] = copy;
        self.undo_count += 1;

        self.redo_count -= 1;
        if (self.redo_stack[self.redo_count]) |saved| {
            @memcpy(self.image.pixels, saved);
            self.allocator.free(saved);
            self.redo_stack[self.redo_count] = null;
            return true;
        }
        return false;
    }

    /// Clear redo stack (called when a new edit is made).
    pub fn clearRedo(self: *EditorState) void {
        for (&self.redo_stack) |*entry| {
            if (entry.*) |buf| {
                self.allocator.free(buf);
                entry.* = null;
            }
        }
        self.redo_count = 0;
    }

    /// Clean up all undo and redo entries.
    pub fn deinit(self: *EditorState) void {
        for (&self.undo_stack) |*entry| {
            if (entry.*) |buf| {
                self.allocator.free(buf);
                entry.* = null;
            }
        }
        for (&self.redo_stack) |*entry| {
            if (entry.*) |buf| {
                self.allocator.free(buf);
                entry.* = null;
            }
        }
        self.image.deinit();
    }
};

/// Open the annotation editor with the given image.
/// Takes ownership of the image.
pub fn openEditor(allocator: std.mem.Allocator, image: Image) void {
    // Clean up previous state if any
    if (g_state) |*s| {
        if (s.handle) |h| bridge.appkit_editor_close(h);
        s.deinit();
    }

    g_state = EditorState.init(allocator, image);
    var state = &g_state.?;

    state.handle = bridge.appkit_open_editor(
        state.image.pixels.ptr,
        state.image.width,
        state.image.height,
        &toolCallback,
        &actionCallback,
    );
}

/// C-calling-convention callback: ObjC calls this when user finishes drawing.
fn toolCallback(tool: c_int, x0: i32, y0: i32, x1: i32, y1: i32) callconv(.c) void {
    var state = &(g_state orelse return);

    // Save current state for undo, clear redo (new edit invalidates redo)
    state.pushUndo();
    state.clearRedo();

    // Apply the annotation using the same pipeline functions as the CLI
    switch (tool) {
        bridge.EDITOR_TOOL_ARROW => {
            pipeline.drawArrow(&state.image, x0, y0, x1, y1, Color.red, 3, 12.0);
        },
        bridge.EDITOR_TOOL_RECT => {
            const x = @min(x0, x1);
            const y = @min(y0, y1);
            const w: u32 = @intCast(@as(i32, @intCast(@abs(x1 - x0))));
            const h: u32 = @intCast(@as(i32, @intCast(@abs(y1 - y0))));
            if (w > 1 and h > 1) {
                pipeline.strokeRect(&state.image, Rect.init(x, y, w, h), Color.red, 2);
            }
        },
        bridge.EDITOR_TOOL_BLUR => {
            const x = @min(x0, x1);
            const y = @min(y0, y1);
            const w: u32 = @intCast(@as(i32, @intCast(@abs(x1 - x0))));
            const h: u32 = @intCast(@as(i32, @intCast(@abs(y1 - y0))));
            if (w > 2 and h > 2) {
                blur_mod.blurRegion(&state.image, Rect.init(x, y, w, h), 8) catch {};
            }
        },
        bridge.EDITOR_TOOL_HIGHLIGHT => {
            const x = @min(x0, x1);
            const y = @min(y0, y1);
            const w: u32 = @intCast(@as(i32, @intCast(@abs(x1 - x0))));
            const h: u32 = @intCast(@as(i32, @intCast(@abs(y1 - y0))));
            if (w > 1 and h > 1) {
                pipeline.fillRect(&state.image, Rect.init(x, y, w, h), Color{ .r = 255, .g = 255, .b = 0, .a = 80 });
            }
        },
        // Ellipse draws an outline inside the bounding rect
        6 => { // EDITOR_TOOL_NUMBERING — repurpose as ellipse for now
            const x = @min(x0, x1);
            const y = @min(y0, y1);
            const w: u32 = @intCast(@as(i32, @intCast(@abs(x1 - x0))));
            const h: u32 = @intCast(@as(i32, @intCast(@abs(y1 - y0))));
            if (w > 3 and h > 3) {
                pipeline.drawEllipse(&state.image, Rect.init(x, y, w, h), Color.red, 2);
            }
        },
        else => {
            // Text, Numbering — TODO: Phase C
            std.debug.print("Editor tool {d} not yet implemented\n", .{tool});
        },
    }

    // Push updated pixels to the ObjC view
    if (state.handle) |h| {
        bridge.appkit_editor_update_image(h, state.image.pixels.ptr, state.image.width, state.image.height);
    }
}

/// C-calling-convention callback: ObjC calls this for Copy/Save/Undo actions.
fn actionCallback(action: c_int, path: [*c]const u8) callconv(.c) void {
    var state = &(g_state orelse return);

    switch (action) {
        EditorAction.copy => {
            // Save to temp file then copy to clipboard
            const temp = "/tmp/.zigshot-editor-out.png";
            saveEditorImage(state, temp);
            clipboard.copyImageFile(temp) catch {};
            std.debug.print("Editor: copied to clipboard\n", .{});
        },
        EditorAction.save => {
            const save_path = std.mem.span(path);
            if (save_path.len > 0) {
                // Save to the path provided by NSSavePanel
                saveEditorImage(state, save_path);
                std.debug.print("Editor: saved to {s}\n", .{save_path});
            } else {
                // Cmd+S with no path: save to temp + copy to clipboard
                const temp = "/tmp/.zigshot-editor-out.png";
                saveEditorImage(state, temp);
                clipboard.copyImageFile(temp) catch {};
                std.debug.print("Editor: saved to clipboard (Cmd+S)\n", .{});
            }
        },
        EditorAction.undo => {
            if (state.popUndo()) {
                if (state.handle) |h| {
                    bridge.appkit_editor_update_image(h, state.image.pixels.ptr, state.image.width, state.image.height);
                }
                std.debug.print("Editor: undo\n", .{});
            } else {
                std.debug.print("Editor: nothing to undo\n", .{});
            }
        },
        EditorAction.redo => {
            if (state.popRedo()) {
                if (state.handle) |h| {
                    bridge.appkit_editor_update_image(h, state.image.pixels.ptr, state.image.width, state.image.height);
                }
                std.debug.print("Editor: redo\n", .{});
            } else {
                std.debug.print("Editor: nothing to redo\n", .{});
            }
        },
        EditorAction.close => {
            std.debug.print("Editor: closing\n", .{});
            if (state.handle) |h| {
                bridge.appkit_editor_close(h);
                state.handle = null;
            }
        },
        else => {},
    }
}

/// Helper: save the current editor image as PNG.
fn saveEditorImage(state: *EditorState, path: []const u8) void {
    const color_space = capture.c.CGColorSpaceCreateDeviceRGB();
    defer capture.c.CGColorSpaceRelease(color_space);

    const context = capture.c.CGBitmapContextCreate(
        state.image.pixels.ptr,
        state.image.width,
        state.image.height,
        8,
        state.image.stride,
        color_space,
        capture.c.kCGImageAlphaPremultipliedLast | capture.c.kCGBitmapByteOrder32Big,
    ) orelse return;
    defer capture.c.CGContextRelease(context);

    const cg_image = capture.c.CGBitmapContextCreateImage(context) orelse return;
    defer capture.c.CGImageRelease(cg_image);

    capture.savePNG(cg_image, path) catch {};
}
