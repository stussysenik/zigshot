//! OCR (Optical Character Recognition) via macOS Vision framework.
//!
//! Uses a Swift one-liner to call VNRecognizeTextRequest.
//! All processing happens on-device (no cloud).

const std = @import("std");

pub const OcrError = error{
    ProcessFailed,
    NoTextFound,
};

/// Extract text from a PNG image file using macOS Vision framework.
pub fn extractText(allocator: std.mem.Allocator, image_path: []const u8) ![]u8 {
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

    // collectOutput requires ArrayList pointers
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

    // Copy to owned memory (caller frees)
    const result = try allocator.alloc(u8, stdout_list.items.len);
    @memcpy(result, stdout_list.items);
    return result;
}
