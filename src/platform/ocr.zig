//! OCR (Optical Character Recognition) via macOS Vision framework.
//!
//! Why spawn a Swift subprocess? Because Apple's VNRecognizeTextRequest is
//! a Swift/ObjC-only API with no C bridge. There's no header file to
//! `@cImport`. Rather than writing an Objective-C bridge for a single
//! function call, we shell out to `swift -e` with an inline program.
//!
//! It costs ~500ms of startup overhead (Swift runtime init) but only runs
//! once per OCR request, and the actual ML inference dwarfs the startup
//! cost anyway. All processing happens on-device via Apple's Neural Engine
//! — nothing goes to the cloud. No API keys, no network, no privacy concerns.

const std = @import("std");

pub const OcrError = error{
    ProcessFailed,
    NoTextFound,
};

/// Extract text from a PNG image file using macOS Vision framework.
pub fn extractText(allocator: std.mem.Allocator, image_path: []const u8) ![]u8 {
    // This is a complete Swift program as a Zig string literal. It loads an
    // image, runs Apple's on-device ML text recognizer, and prints each
    // detected line to stdout. We capture that stdout below.
    // Yes, we're embedding one language inside another. It's turtles all the way down.
    var swift_buf: [2048]u8 = undefined;
    const swift_code = std.fmt.bufPrint(&swift_buf,
        \\import Vision
        \\import AppKit
        \\let url = URL(fileURLWithPath: "{s}")
        \\guard let img = NSImage(contentsOf: url), let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {{ exit(1) }}
        \\let req = VNRecognizeTextRequest()
        \\req.recognitionLevel = .accurate
        \\try! VNImageRequestHandler(cgImage: cgImg).perform([req])
        \\for obs in (req.results ?? []) {{ print(obs.topCandidates(1).first?.string ?? "") }}
    , .{image_path}) catch return OcrError.ProcessFailed;

    var child = std.process.Child.init(
        &.{ "swift", "-e", swift_code },
        allocator,
    );
    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    _ = child.spawn() catch return OcrError.ProcessFailed;

    // JS equivalent: `const {stdout} = await exec('swift -e ...')`.
    // Zig's version is more explicit — we allocate buffers for stdout/stderr,
    // the child process fills them, and we own the memory.
    // collectOutput requires ArrayList pointers for the buffers.
    var stdout_list: std.ArrayList(u8) = .empty;
    defer stdout_list.deinit(allocator);
    var stderr_list: std.ArrayList(u8) = .empty;
    defer stderr_list.deinit(allocator);

    child.collectOutput(allocator, &stdout_list, &stderr_list, 1024 * 1024) catch return OcrError.ProcessFailed;
    const term = child.wait() catch return OcrError.ProcessFailed;

    if (term.Exited != 0) {
        return OcrError.NoTextFound;
    }

    if (stdout_list.items.len == 0) {
        return OcrError.NoTextFound;
    }

    // We copy stdout into caller-owned memory. The caller must
    // `allocator.free(result)` when done. In JS, the GC handles this.
    // In Zig, every allocation has an explicit owner — if you allocate it,
    // you document who frees it, or you leak memory forever.
    const result = try allocator.alloc(u8, stdout_list.items.len);
    @memcpy(result, stdout_list.items);
    return result;
}
