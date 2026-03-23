//! ZigShot — Screenshot tool for macOS.
//!
//! CLI entry point. Parses arguments and dispatches to the
//! appropriate capture/annotate/ocr command.

const std = @import("std");
const args_mod = @import("cli/args.zig");
const capture = @import("platform/capture.zig");
const clipboard = @import("platform/clipboard.zig");

const version = "0.2.0";

pub fn main() !void {
    // Collect CLI args (skip program name).
    //
    // LEARNING NOTE — std.process.args():
    // Returns an iterator over command-line arguments. On macOS/Linux,
    // these are the classic argv strings. We collect them into a slice
    // for random access during parsing.
    var arg_iter = std.process.args();
    _ = arg_iter.skip(); // skip program name

    // Collect remaining args into a buffer.
    // Using a fixed buffer avoids allocation for typical usage.
    var arg_buf: [64][]const u8 = undefined;
    var arg_count: usize = 0;
    while (arg_iter.next()) |arg| {
        if (arg_count >= arg_buf.len) break;
        arg_buf[arg_count] = arg;
        arg_count += 1;
    }
    const cli_args = arg_buf[0..arg_count];

    const command = args_mod.parse(cli_args) catch |err| {
        switch (err) {
            error.UnknownCommand => std.debug.print("Error: unknown command. Run 'zigshot help' for usage.\n", .{}),
            error.MissingValue => std.debug.print("Error: missing value for flag. Run 'zigshot help' for usage.\n", .{}),
            error.InvalidFlag => std.debug.print("Error: invalid flag. Run 'zigshot help' for usage.\n", .{}),
            error.InvalidRect => std.debug.print("Error: invalid area format. Use: --area X,Y,W,H\n", .{}),
        }
        std.process.exit(1);
    };

    switch (command) {
        .help => args_mod.printHelp(),
        .version => std.debug.print("zigshot {s}\n", .{version}),
        .capture => |opts| runCapture(opts) catch |err| {
            printCaptureError(err);
            std.process.exit(1);
        },
    }
}

fn runCapture(opts: args_mod.CaptureOptions) !void {
    // Handle delay
    if (opts.delay_secs > 0) {
        std.debug.print("Capturing in {d} seconds...\n", .{opts.delay_secs});
        std.Thread.sleep(@as(u64, opts.delay_secs) * std.time.ns_per_s);
    }

    // Perform capture based on mode
    var result = switch (opts.mode) {
        .fullscreen => try capture.captureFullscreen(),
        .area => blk: {
            const area = opts.area orelse {
                std.debug.print("Error: --area requires X,Y,W,H coordinates.\n", .{});
                return error.InvalidArea;
            };
            break :blk try capture.captureArea(area);
        },
        .window => {
            // Window capture by title — for now, show error. Full implementation
            // requires CGWindowListCopyWindowInfo to find window ID by title.
            std.debug.print("Error: --window capture not yet implemented. Use --area or --fullscreen.\n", .{});
            return error.WindowNotFound;
        },
    };
    defer result.deinit();

    std.debug.print("Captured {d}x{d} image\n", .{ result.width, result.height });

    // Output: save to file or clipboard
    switch (opts.output) {
        .file => |path| {
            switch (opts.format) {
                .png => try capture.savePNG(result.cg_image, path),
                .jpeg => try capture.saveJPEG(result.cg_image, path),
            }
            std.debug.print("Saved to: {s}\n", .{path});
        },
        .clipboard => {
            // Save to temp, copy to clipboard, clean up
            const temp_path = "/tmp/.zigshot-clipboard.png";
            try capture.savePNG(result.cg_image, temp_path);
            clipboard.copyImageFile(temp_path) catch {
                std.debug.print("Clipboard copy failed. Image saved to: {s}\n", .{temp_path});
                return;
            };
            std.fs.deleteFileAbsolute(temp_path) catch {};
            std.debug.print("Copied to clipboard\n", .{});
        },
    }
}

fn printCaptureError(err: anyerror) void {
    switch (err) {
        error.CaptureFailed => {
            std.debug.print("Error: Screen capture failed.\n", .{});
        },
        error.PermissionDenied => {
            std.debug.print("Error: Screen recording permission denied.\n", .{});
            std.debug.print("  Go to: System Settings → Privacy & Security → Screen Recording\n", .{});
        },
        error.InvalidArea => {
            std.debug.print("Error: Invalid capture area.\n", .{});
        },
        error.WindowNotFound => {
            std.debug.print("Error: Window not found.\n", .{});
        },
        error.WriteFailed => {
            std.debug.print("Error: Failed to write image file.\n", .{});
        },
        else => {
            std.debug.print("Error: {}\n", .{err});
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "main module imports compile" {
    // Verify all imports resolve. This catches broken module paths.
    _ = args_mod;
    _ = capture;
    _ = clipboard;
}

test {
    // Pull in tests from submodules
    std.testing.refAllDecls(@This());
    _ = @import("cli/args.zig");
}
