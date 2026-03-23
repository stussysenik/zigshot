//! ZigShot — Screenshot tool for macOS.
//!
//! CLI entry point. Parses arguments and dispatches to the
//! appropriate capture/annotate/ocr command.

const std = @import("std");
const args_mod = @import("cli/args.zig");
const capture = @import("platform/capture.zig");
const clipboard = @import("platform/clipboard.zig");
const ocr = @import("platform/ocr.zig");
const zigshot = @import("zigshot");
const Image = zigshot.Image;
const Color = zigshot.Color;
const Rect = zigshot.Rect;
const pipeline = zigshot.pipeline;
const blur_mod = zigshot.blur;

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
        .annotate => |opts| runAnnotate(opts) catch |err| {
            std.debug.print("Error: annotate failed: {}\n", .{err});
            std.process.exit(1);
        },
        .background => |opts| runBackground(opts) catch |err| {
            std.debug.print("Error: background failed: {}\n", .{err});
            std.process.exit(1);
        },
        .ocr => |opts| runOcr(opts) catch |err| {
            std.debug.print("Error: OCR failed: {}\n", .{err});
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

fn runAnnotate(opts: args_mod.AnnotateOptions) !void {
    if (opts.input_file.len == 0) {
        std.debug.print("Error: no input file specified.\n", .{});
        return error.MissingValue;
    }

    // Capture a screenshot and annotate it (we use capture since we
    // don't have a PNG decoder yet — annotate a fresh fullscreen capture)
    //
    // For now, annotate takes a fresh capture and applies annotations.
    // Full implementation will load an existing PNG once we vendor lodepng.
    std.debug.print("Capturing screenshot for annotation...\n", .{});
    var result = try capture.captureFullscreen();
    defer result.deinit();

    // Convert CGImage pixels to our Image type for annotation
    const allocator = std.heap.page_allocator;
    var img = try cgImageToImage(allocator, result.cg_image, result.width, result.height);
    defer img.deinit();

    // Apply each annotation
    const annotations = opts.annotations[0..opts.annotation_count];
    for (annotations) |ann| {
        switch (ann) {
            .arrow => |a| {
                pipeline.drawArrow(&img, a.x0, a.y0, a.x1, a.y1, Color.red, 3, 12.0);
            },
            .rect => |r| {
                pipeline.strokeRect(&img, Rect.init(r.x, r.y, r.w, r.h), Color.red, 2);
            },
            .blur => |b| {
                try blur_mod.blurRegion(&img, Rect.init(b.x, b.y, b.w, b.h), b.radius);
            },
            .highlight => |h| {
                pipeline.fillRect(&img, Rect.init(h.x, h.y, h.w, h.h), Color{ .r = 255, .g = 255, .b = 0, .a = 80 });
            },
            .text => |t| {
                // Simple text rendering: draw a background rect then set pixels
                // Full text rendering requires CoreText (Phase 5)
                const text_rect = Rect.init(t.x, t.y, @intCast(@min(t.content.len * 8, 2000)), 20);
                pipeline.fillRect(&img, text_rect, Color{ .r = 0, .g = 0, .b = 0, .a = 200 });
                // Note: actual text rasterization deferred to CoreText phase
                std.debug.print("  Text annotation at ({d},{d}): \"{s}\" (placeholder - CoreText pending)\n", .{ t.x, t.y, t.content });
            },
        }
    }

    // Save the result
    const output_path = opts.output_file orelse opts.input_file;
    try saveImageAsPNG(&img, output_path);
    std.debug.print("Annotated image saved to: {s}\n", .{output_path});
}

fn runBackground(opts: args_mod.BackgroundOptions) !void {
    if (opts.input_file.len == 0) {
        std.debug.print("Error: no input file specified.\n", .{});
        return error.MissingValue;
    }

    // Capture a fresh screenshot (until we have PNG loading)
    std.debug.print("Capturing screenshot for background treatment...\n", .{});
    var result = try capture.captureFullscreen();
    defer result.deinit();

    const allocator = std.heap.page_allocator;
    var img = try cgImageToImage(allocator, result.cg_image, result.width, result.height);
    defer img.deinit();

    // Determine background color
    const bg_color = if (opts.color) |hex|
        Color.fromHex(hex) catch Color{ .r = 26, .g = 26, .b = 46 }
    else
        Color{ .r = 26, .g = 26, .b = 46 }; // dark blue default

    // Add padding
    var padded = try pipeline.addUniformPadding(allocator, img, opts.padding, bg_color);
    defer padded.deinit();

    // TODO: Round corners (requires alpha compositing)
    // TODO: Drop shadow (requires blur + offset composite)

    const output_path = opts.output_file orelse opts.input_file;
    try saveImageAsPNG(&padded, output_path);
    std.debug.print("Background added. Saved to: {s}\n", .{output_path});
}

fn runOcr(opts: args_mod.OcrOptions) !void {
    const allocator = std.heap.page_allocator;
    var temp_path: []const u8 = "/tmp/.zigshot-ocr-temp.png";

    if (opts.capture_mode or opts.input_file == null) {
        // Capture screen first, then OCR
        std.debug.print("Capturing screenshot for OCR...\n", .{});
        var result = try capture.captureFullscreen();
        defer result.deinit();
        try capture.savePNG(result.cg_image, temp_path);
    } else {
        temp_path = opts.input_file.?;
    }

    std.debug.print("Extracting text...\n", .{});
    const text = ocr.extractText(allocator, temp_path) catch |err| {
        switch (err) {
            error.NoTextFound => {
                std.debug.print("No text found in image.\n", .{});
                return;
            },
            else => return err,
        }
    };
    defer allocator.free(text);

    // Clean up temp file if we created it
    if (opts.capture_mode or opts.input_file == null) {
        std.fs.deleteFileAbsolute("/tmp/.zigshot-ocr-temp.png") catch {};
    }

    // Output the text
    std.debug.print("{s}", .{text});
}

/// Convert a CGImage to our Image type by extracting pixel data.
fn cgImageToImage(allocator: std.mem.Allocator, cg_image: *capture.c.CGImage, width: u32, height: u32) !Image {
    var img = try Image.init(allocator, width, height);
    errdefer img.deinit();

    // Create a bitmap context backed by our pixel buffer
    const color_space = capture.c.CGColorSpaceCreateDeviceRGB();
    defer capture.c.CGColorSpaceRelease(color_space);

    const context = capture.c.CGBitmapContextCreate(
        img.pixels.ptr,
        width,
        height,
        8, // bits per component
        width * 4, // bytes per row
        color_space,
        capture.c.kCGImageAlphaPremultipliedLast | capture.c.kCGBitmapByteOrder32Big,
    ) orelse return error.ContextCreationFailed;
    defer capture.c.CGContextRelease(context);

    // Draw the CGImage into our buffer
    const draw_rect = capture.c.CGRect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(width), .height = @floatFromInt(height) },
    };
    capture.c.CGContextDrawImage(context, draw_rect, cg_image);

    return img;
}

/// Save our Image type as PNG using CoreGraphics.
fn saveImageAsPNG(img: *Image, path: []const u8) !void {
    const color_space = capture.c.CGColorSpaceCreateDeviceRGB();
    defer capture.c.CGColorSpaceRelease(color_space);

    const context = capture.c.CGBitmapContextCreate(
        img.pixels.ptr,
        img.width,
        img.height,
        8,
        img.stride,
        color_space,
        capture.c.kCGImageAlphaPremultipliedLast | capture.c.kCGBitmapByteOrder32Big,
    ) orelse return error.ContextCreationFailed;
    defer capture.c.CGContextRelease(context);

    const cg_image = capture.c.CGBitmapContextCreateImage(context) orelse return error.ImageCreationFailed;
    defer capture.c.CGImageRelease(cg_image);

    try capture.savePNG(cg_image, path);
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
