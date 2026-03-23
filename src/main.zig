//! ZigShot — Screenshot tool for macOS.
//!
//! Entry point. Follows a simple pipeline: parse args → dispatch to command
//! handler → capture/load image → process → save/clipboard. Every command
//! handler follows the same shape: validate inputs, do the work, handle errors,
//! print status. Think of this as your `index.js` — it wires everything
//! together but contains minimal business logic itself.

const std = @import("std");
const args_mod = @import("cli/args.zig");
const capture = @import("platform/capture.zig");
const clipboard = @import("platform/clipboard.zig");
const ocr = @import("platform/ocr.zig");
const hotkey = @import("platform/hotkey.zig");
const overlay = @import("platform/overlay.zig");
const quick_overlay = @import("platform/quick_overlay.zig");
const editor = @import("platform/editor.zig");
const recording = @import("platform/recording.zig");
const zigshot = @import("zigshot");
const Image = zigshot.Image;
const Color = zigshot.Color;
const Rect = zigshot.Rect;
const pipeline = zigshot.pipeline;
const blur_mod = zigshot.blur;

const version = "0.2.0";

/// `pub fn main() !void` — the `!` means this function returns an error union
/// with void. In JS terms, this is `async function main()` where any `await`
/// can throw. The `!void` tells the compiler "this can fail with any error
/// type" — and if it does, Zig prints a stack trace and exits. Clean and honest.
pub fn main() !void {
    // Collect CLI args (skip program name).
    //
    // LEARNING NOTE — std.process.args():
    // Returns an iterator over command-line arguments. On macOS/Linux,
    // these are the classic argv strings. We collect them into a slice
    // for random access during parsing.
    var arg_iter = std.process.args();
    _ = arg_iter.skip(); // skip program name

    // 64-slot stack-allocated array. No heap needed — screenshot tools won't
    // have 64+ arguments. Common Zig pattern: use a fixed buffer when you know
    // the upper bound. JS devs: this is like `const args = new Array(64)` but
    // lives on the stack, not the heap — zero allocator overhead, gone when
    // the function returns.
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

    // Exhaustive switch on Command variants. Add a new command to the enum?
    // The compiler forces you to handle it here. TypeScript's `assertNever(cmd)`
    // pattern, but enforced at compile time — you literally can't forget a case.
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
        .record => |opts| runRecord(opts),
        .listen => runListen() catch |err| {
            std.debug.print("Error: listen failed: {}\n", .{err});
            std.process.exit(1);
        },
        .gui => runGui(),
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
        .window => blk2: {
            const title = opts.window_title orelse {
                std.debug.print("Error: --window requires a window title.\n", .{});
                return error.WindowNotFound;
            };
            const window_id = capture.findWindowByTitle(title) catch {
                std.debug.print("Error: no window found matching \"{s}\"\n", .{title});
                return error.WindowNotFound;
            };
            std.debug.print("Found window ID {d} for \"{s}\"\n", .{ window_id, title });
            break :blk2 try capture.captureWindow(window_id);
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

    // Load the input file via CGImageSource (handles PNG, JPEG, etc.)
    var result = capture.loadImageFile(opts.input_file) catch |err| {
        switch (err) {
            error.FileNotFound => std.debug.print("Error: file not found: {s}\n", .{opts.input_file}),
            error.ImageDecodeFailed => std.debug.print("Error: could not decode image: {s}\n", .{opts.input_file}),
            else => std.debug.print("Error loading image: {}\n", .{err}),
        }
        return err;
    };
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
                // Render text via CoreText (ObjC bridge)
                const text_bridge = @cImport({
                    @cInclude("appkit_bridge.h");
                });
                var tw: u32 = 0;
                var th: u32 = 0;
                const buf = text_bridge.appkit_render_text(
                    t.content.ptr,
                    16.0, // font size
                    0xFFFFFFFF, // white text
                    &tw,
                    &th,
                );
                if (buf) |text_pixels| {
                    // Composite the rendered text onto the image
                    var ty: u32 = 0;
                    while (ty < th) : (ty += 1) {
                        var tx: u32 = 0;
                        while (tx < tw) : (tx += 1) {
                            const idx = (ty * tw + tx) * 4;
                            const a = text_pixels[idx + 3];
                            if (a == 0) continue;
                            const dest_x = @as(i32, t.x) + @as(i32, @intCast(tx));
                            const dest_y = @as(i32, t.y) + @as(i32, @intCast(ty));
                            if (dest_x < 0 or dest_y < 0) continue;
                            const ux: u32 = @intCast(dest_x);
                            const uy: u32 = @intCast(dest_y);
                            if (ux >= img.width or uy >= img.height) continue;

                            if (a == 255) {
                                img.setPixel(ux, uy, Color{
                                    .r = text_pixels[idx],
                                    .g = text_pixels[idx + 1],
                                    .b = text_pixels[idx + 2],
                                    .a = 255,
                                });
                            } else {
                                const bg_px = img.getPixel(ux, uy) orelse continue;
                                const alpha: u16 = a;
                                const inv: u16 = 255 - alpha;
                                img.setPixel(ux, uy, Color{
                                    .r = @intCast((@as(u16, text_pixels[idx]) * alpha + @as(u16, bg_px.r) * inv) / 255),
                                    .g = @intCast((@as(u16, text_pixels[idx + 1]) * alpha + @as(u16, bg_px.g) * inv) / 255),
                                    .b = @intCast((@as(u16, text_pixels[idx + 2]) * alpha + @as(u16, bg_px.b) * inv) / 255),
                                    .a = 255,
                                });
                            }
                        }
                    }
                    text_bridge.appkit_free_text_buffer(buf);
                    std.debug.print("  Text annotation at ({d},{d}): \"{s}\"\n", .{ t.x, t.y, t.content });
                } else {
                    std.debug.print("  Text rendering failed for: \"{s}\"\n", .{t.content});
                }
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

    // Load the input file
    var result = capture.loadImageFile(opts.input_file) catch |err| {
        switch (err) {
            error.FileNotFound => std.debug.print("Error: file not found: {s}\n", .{opts.input_file}),
            error.ImageDecodeFailed => std.debug.print("Error: could not decode image: {s}\n", .{opts.input_file}),
            else => std.debug.print("Error loading image: {}\n", .{err}),
        }
        return err;
    };
    defer result.deinit();

    const allocator = std.heap.page_allocator;
    var img = try cgImageToImage(allocator, result.cg_image, result.width, result.height);
    defer img.deinit();

    // Determine background color
    const bg_color = if (opts.color) |hex|
        Color.fromHex(hex) catch Color{ .r = 26, .g = 26, .b = 46 }
    else
        Color{ .r = 26, .g = 26, .b = 46 }; // dark blue default

    // Round corners before adding padding (applies to the screenshot itself)
    if (opts.radius > 0) {
        pipeline.roundCorners(&img, opts.radius);
    }

    // Determine the image to pad (with or without shadow)
    var work_img: Image = undefined;
    var owns_work_img = false;

    if (opts.shadow) {
        const shadow_color = Color{ .r = 0, .g = 0, .b = 0, .a = 100 };
        work_img = try pipeline.addDropShadow(allocator, img, 6, 6, 8, shadow_color);
        owns_work_img = true;
    } else {
        work_img = img;
    }
    defer if (owns_work_img) work_img.deinit();

    // Add padding
    var padded = try pipeline.addUniformPadding(allocator, work_img, opts.padding, bg_color);
    defer padded.deinit();

    // Apply gradient background if requested (fills the padding area with gradient)
    if (opts.gradient) |preset_name| {
        const preset = getGradientPreset(preset_name);
        pipeline.fillGradient(&padded, preset.angle, preset.color1, preset.color2);
        // Re-composite the image on top of the gradient
        const cx = opts.padding;
        const cy = opts.padding;
        var y: u32 = 0;
        while (y < work_img.height) : (y += 1) {
            var x: u32 = 0;
            while (x < work_img.width) : (x += 1) {
                const px = work_img.getPixel(x, y) orelse continue;
                if (px.a == 255) {
                    padded.setPixel(cx + x, cy + y, px);
                } else if (px.a > 0) {
                    const bg = padded.getPixel(cx + x, cy + y) orelse continue;
                    const alpha: u16 = px.a;
                    const inv: u16 = 255 - alpha;
                    padded.setPixel(cx + x, cy + y, Color{
                        .r = @intCast((@as(u16, px.r) * alpha + @as(u16, bg.r) * inv) / 255),
                        .g = @intCast((@as(u16, px.g) * alpha + @as(u16, bg.g) * inv) / 255),
                        .b = @intCast((@as(u16, px.b) * alpha + @as(u16, bg.b) * inv) / 255),
                        .a = 255,
                    });
                }
            }
        }
    }

    const output_path = opts.output_file orelse opts.input_file;
    try saveImageAsPNG(&padded, output_path);
    std.debug.print("Background added. Saved to: {s}\n", .{output_path});
}

fn runGui() void {
    std.debug.print("ZigShot — menu bar mode\n", .{});
    overlay.initApp();
    overlay.createMenuBar(&menuBarCallback);
    std.debug.print("Menu bar icon active. Use the camera icon or hotkeys.\n", .{});
    overlay.runApp(); // blocks forever
}

fn menuBarCallback(action_id: c_int) callconv(.c) void {
    switch (action_id) {
        overlay.MenuAction.capture_fullscreen => {
            std.debug.print("→ Capturing fullscreen...\n", .{});
            var result = capture.captureFullscreen() catch return;
            defer result.deinit();
            const temp = "/tmp/.zigshot-latest.png";
            capture.savePNG(result.cg_image, temp) catch return;
            // Show quick access overlay instead of direct clipboard copy.
            // The overlay lets the user choose: Copy, Save, Annotate, Pin.
            quick_overlay.showQuickOverlay(temp, result.width, result.height, &quickOverlayCallback);
            std.debug.print("  Captured {d}x{d} — overlay shown\n", .{ result.width, result.height });
        },
        overlay.MenuAction.capture_area => {
            std.debug.print("→ Capture area...\n", .{});
            const rect = overlay.showSelectionOverlay() orelse {
                std.debug.print("  Selection cancelled\n", .{});
                return;
            };
            var result = capture.captureArea(rect) catch |err| {
                std.debug.print("  Capture failed: {}\n", .{err});
                return;
            };
            defer result.deinit();
            const temp = "/tmp/.zigshot-latest.png";
            capture.savePNG(result.cg_image, temp) catch return;
            quick_overlay.showQuickOverlay(temp, result.width, result.height, &quickOverlayCallback);
            std.debug.print("  Captured {d}x{d} — overlay shown\n", .{ result.width, result.height });
        },
        overlay.MenuAction.capture_window => {
            std.debug.print("→ Window capture (TODO: window picker)\n", .{});
        },
        overlay.MenuAction.ocr => {
            std.debug.print("→ OCR capture...\n", .{});
            var result = capture.captureFullscreen() catch return;
            defer result.deinit();
            const temp_path = "/tmp/.zigshot-ocr-temp.png";
            capture.savePNG(result.cg_image, temp_path) catch return;
            const allocator = std.heap.page_allocator;
            const text = ocr.extractText(allocator, temp_path) catch {
                std.debug.print("  OCR failed\n", .{});
                return;
            };
            defer allocator.free(text);
            std.fs.deleteFileAbsolute(temp_path) catch {};
            std.debug.print("  Extracted text:\n{s}\n", .{text});
        },
        overlay.MenuAction.quit => {
            std.debug.print("Quitting ZigShot.\n", .{});
        },
        else => {
            std.debug.print("→ Action {d} (TODO)\n", .{action_id});
        },
    }
}

/// Callback for the quick access overlay action buttons.
/// Runs on the main thread (called from AppKit).
fn quickOverlayCallback(action_id: c_int, path: [*c]const u8) callconv(.c) void {
    switch (action_id) {
        quick_overlay.QuickAction.copy => {
            std.debug.print("  → Copied to clipboard\n", .{});
            clipboard.copyImageFile(std.mem.span(path)) catch {
                std.debug.print("  Clipboard copy failed\n", .{});
            };
        },
        quick_overlay.QuickAction.save => {
            // Save was handled by NSSavePanel in ObjC. The path is the dest.
            std.debug.print("  → Saved to: {s}\n", .{std.mem.span(path)});
        },
        quick_overlay.QuickAction.annotate => {
            std.debug.print("  → Opening annotation editor...\n", .{});
            // Load the captured image into a Zig Image, then open the editor
            const img_path = std.mem.span(path);
            var result = capture.loadImageFile(img_path) catch {
                std.debug.print("  Failed to load image for editor\n", .{});
                return;
            };
            defer result.deinit();
            const allocator = std.heap.page_allocator;
            const img = cgImageToImage(allocator, result.cg_image, result.width, result.height) catch {
                std.debug.print("  Failed to convert image for editor\n", .{});
                return;
            };
            // Editor takes ownership of the image — don't deinit here
            editor.openEditor(allocator, img);
            // Dismiss the quick overlay after opening editor
            quick_overlay.dismissQuickOverlay();
        },
        quick_overlay.QuickAction.pin => {
            std.debug.print("  → Pinned to screen\n", .{});
            // Read dimensions from the captured image to pass to pin
            var result = capture.loadImageFile(std.mem.span(path)) catch {
                std.debug.print("  Failed to load image for pin\n", .{});
                return;
            };
            defer result.deinit();
            quick_overlay.pinScreenshot(path, result.width, result.height);
        },
        quick_overlay.QuickAction.close => {
            std.debug.print("  → Overlay dismissed\n", .{});
        },
        else => {},
    }
}

fn runRecord(opts: args_mod.RecordOptions) void {
    // Determine recording area
    var x: i32 = 0;
    var y: i32 = 0;
    var width: u32 = 1920;
    var height: u32 = 1080;

    if (opts.has_area) {
        x = opts.area_x;
        y = opts.area_y;
        width = opts.area_w;
        height = opts.area_h;
    } else if (!opts.fullscreen) {
        // Interactive selection
        const rect = overlay.showSelectionOverlay() orelse {
            std.debug.print("Selection cancelled.\n", .{});
            return;
        };
        x = rect.x;
        y = rect.y;
        width = rect.width;
        height = rect.height;
    }

    const format_str: [*c]const u8 = switch (opts.format) {
        .mp4 => "mp4",
        .gif => "gif",
    };

    std.debug.print("Recording {d}x{d} at ({d},{d}) to {s}...\n", .{ width, height, x, y, opts.output_file });
    std.debug.print("Press Ctrl+C to stop recording.\n", .{});

    recording.startRecording(x, y, width, height, opts.output_file.ptr, format_str, opts.fps, &recordingCallback);

    // Wait for duration or until interrupted
    if (opts.duration > 0) {
        std.Thread.sleep(@as(u64, opts.duration) * std.time.ns_per_s);
        recording.stopRecording();
    } else {
        // Block forever — user stops with Ctrl+C
        // Use a signal handler or just sleep indefinitely
        while (recording.isRecording()) {
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }
}

fn recordingCallback(status: c_int, info: [*c]const u8) callconv(.c) void {
    const msg = std.mem.span(info);
    switch (status) {
        recording.Status.started => std.debug.print("Recording started: {s}\n", .{msg}),
        recording.Status.stopped => std.debug.print("Recording saved: {s}\n", .{msg}),
        recording.Status.err => std.debug.print("Recording error: {s}\n", .{msg}),
        else => {},
    }
}

/// Block forever, waiting for hotkeys. Each iteration: wait for hotkey press →
/// handle action → loop. `continue` on error keeps listening instead of
/// crashing — resilience over correctness for a background daemon.
/// In Node.js terms, this is your event loop — except it's explicit.
fn runListen() !void {
    std.debug.print("ZigShot listening for hotkeys...\n", .{});
    std.debug.print("  Cmd+Shift+3: Capture fullscreen\n", .{});
    std.debug.print("  Cmd+Shift+4: Capture area\n", .{});
    std.debug.print("  Cmd+Shift+5: Capture window\n", .{});
    std.debug.print("  Cmd+Shift+2: OCR capture\n", .{});
    std.debug.print("Press Ctrl+C to quit.\n\n", .{});

    const hk = hotkey.defaultHotkeys();

    while (true) {
        const action = hotkey.waitForHotkey(&hk) catch |err| {
            std.debug.print("Hotkey error: {}\n", .{err});
            return err;
        };

        switch (action) {
            .capture_fullscreen => {
                std.debug.print("→ Capturing fullscreen...\n", .{});
                var result = capture.captureFullscreen() catch |err| {
                    std.debug.print("  Capture failed: {}\n", .{err});
                    continue;
                };
                defer result.deinit();
                const temp_path = "/tmp/.zigshot-clipboard.png";
                capture.savePNG(result.cg_image, temp_path) catch continue;
                clipboard.copyImageFile(temp_path) catch {};
                std.fs.deleteFileAbsolute(temp_path) catch {};
                std.debug.print("  Copied {d}x{d} to clipboard\n", .{ result.width, result.height });
            },
            .capture_area => {
                std.debug.print("→ Area capture (TODO: interactive overlay)\n", .{});
                // TODO: Phase 4 — show selection overlay
            },
            .capture_window => {
                std.debug.print("→ Window capture (TODO: window picker)\n", .{});
            },
            .ocr_capture => {
                std.debug.print("→ OCR capture...\n", .{});
                var result = capture.captureFullscreen() catch continue;
                defer result.deinit();
                const temp_path = "/tmp/.zigshot-ocr-temp.png";
                capture.savePNG(result.cg_image, temp_path) catch continue;
                const allocator = std.heap.page_allocator;
                const text = ocr.extractText(allocator, temp_path) catch {
                    std.debug.print("  OCR failed\n", .{});
                    continue;
                };
                defer allocator.free(text);
                std.fs.deleteFileAbsolute(temp_path) catch {};
                std.debug.print("  Extracted text:\n{s}\n", .{text});
            },
        }
    }
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

/// Bridge function: converts Apple's opaque CGImage into our owned pixel buffer.
///
/// Strategy: create a CGBitmapContext backed by our Image's pixel array, then
/// "draw" the CGImage into it. CoreGraphics copies the pixel data for us.
/// This is Apple's sanctioned way to extract raw pixels — there is no direct
/// accessor for CGImage pixel data. Yes, really. You ask CG to "draw" into
/// a buffer you own, and that's how you get the bytes out. Feels roundabout,
/// but it handles color space conversion, byte ordering, and alpha
/// premultiplication in one shot.
fn cgImageToImage(allocator: std.mem.Allocator, cg_image: *capture.c.CGImage, width: u32, height: u32) !Image {
    var img = try Image.init(allocator, width, height);
    errdefer img.deinit();

    const color_space = capture.c.CGColorSpaceCreateDeviceRGB();
    defer capture.c.CGColorSpaceRelease(color_space);

    // CGBitmapContextCreate parameters explained:
    //   img.pixels.ptr — destination buffer (we own it, CG writes into it)
    //   8 = bits per component (each R, G, B, A channel is 8 bits)
    //   width * 4 = bytes per row (4 bytes per RGBA pixel)
    //   kCGImageAlphaPremultipliedLast = alpha channel is the last byte (RGBA
    //     order), with premultiplied alpha
    //   kCGBitmapByteOrder32Big = big-endian byte order within each 32-bit pixel
    const context = capture.c.CGBitmapContextCreate(
        img.pixels.ptr,
        width,
        height,
        8,
        width * 4,
        color_space,
        capture.c.kCGImageAlphaPremultipliedLast | capture.c.kCGBitmapByteOrder32Big,
    ) orelse return error.ContextCreationFailed;
    defer capture.c.CGContextRelease(context);

    // "Draw" the CGImage into our buffer — this is the actual pixel extraction.
    const draw_rect = capture.c.CGRect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(width), .height = @floatFromInt(height) },
    };
    capture.c.CGContextDrawImage(context, draw_rect, cg_image);

    return img;
}

/// Reverse of cgImageToImage: wrap our raw pixel buffer in a CGBitmapContext,
/// extract a CGImage from it, then save via ImageIO.
/// The round-trip: CGImage → our pixels → CGImage → file. Apple makes you go
/// through their types to hit the disk — no raw PNG encoder here.
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

/// Look up a gradient preset by name.
fn getGradientPreset(name: []const u8) pipeline.GradientPreset {
    if (std.mem.eql(u8, name, "ocean")) return pipeline.GradientPreset.ocean;
    if (std.mem.eql(u8, name, "sunset")) return pipeline.GradientPreset.sunset;
    if (std.mem.eql(u8, name, "forest")) return pipeline.GradientPreset.forest;
    if (std.mem.eql(u8, name, "midnight")) return pipeline.GradientPreset.midnight;
    // Default to ocean for unknown names
    std.debug.print("Unknown gradient preset \"{s}\", using ocean\n", .{name});
    return pipeline.GradientPreset.ocean;
}

fn printCaptureError(err: anyerror) void {
    switch (err) {
        error.CaptureFailed => {
            std.debug.print("Error: Screen capture failed.\n", .{});
        },
        // The most common error users will hit. macOS requires explicit Screen
        // Recording permission, and the error message from the OS isn't obvious —
        // it just silently returns a blank image or fails. We catch it here and
        // tell the user exactly where to click.
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
