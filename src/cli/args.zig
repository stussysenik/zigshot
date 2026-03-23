//! Command-line argument parser for ZigShot.
//!
//! LEARNING NOTE — Why not use zig-clap?
//! We're building our own minimal parser to keep zero external
//! dependencies in Phase 1. This teaches Zig's string processing,
//! tagged unions, and iterator patterns. We'll evaluate adding clap
//! later if the CLI gets complex enough to warrant it.
//!
//! LEARNING NOTE — Tagged unions:
//! `Command` is a tagged union — it can be exactly one of its variants
//! at any time. The Zig compiler forces you to handle every variant
//! in a switch statement (exhaustive matching). This is how you model
//! "one of N possibilities" in Zig — much safer than C enums or
//! string-based dispatch.

const std = @import("std");
const zigshot = @import("zigshot");
const Rect = zigshot.Rect;

/// The capture mode — what region of the screen to capture.
pub const CaptureMode = enum {
    fullscreen,
    area,
    window,
};

/// Output destination for captured image.
pub const OutputTarget = union(enum) {
    file: []const u8,
    clipboard,
};

/// Parsed capture command options.
pub const CaptureOptions = struct {
    mode: CaptureMode = .fullscreen,
    area: ?Rect = null,
    window_title: ?[]const u8 = null,
    output: OutputTarget = .clipboard,
    delay_secs: u32 = 0,
    format: ImageFormat = .png,
};

pub const ImageFormat = enum {
    png,
    jpeg,

    pub fn fromExtension(path: []const u8) ImageFormat {
        if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) {
            return .jpeg;
        }
        return .png;
    }
};

/// Parsed annotate command options.
pub const AnnotateOptions = struct {
    input_file: []const u8 = "",
    output_file: ?[]const u8 = null,
    annotations: [16]AnnotateAction = undefined,
    annotation_count: usize = 0,
};

pub const AnnotateAction = union(enum) {
    arrow: struct { x0: i32, y0: i32, x1: i32, y1: i32 },
    rect: struct { x: i32, y: i32, w: u32, h: u32 },
    blur: struct { x: i32, y: i32, w: u32, h: u32, radius: u32 },
    highlight: struct { x: i32, y: i32, w: u32, h: u32 },
    text: struct { x: i32, y: i32, content: []const u8 },
};

/// Parsed background command options.
pub const BackgroundOptions = struct {
    input_file: []const u8 = "",
    output_file: ?[]const u8 = null,
    padding: u32 = 64,
    color: ?[]const u8 = null, // hex color string
    radius: u32 = 0,
    shadow: bool = false,
};

/// Parsed OCR command options.
pub const OcrOptions = struct {
    input_file: ?[]const u8 = null,
    capture_mode: bool = false, // capture screen then OCR
};

/// Top-level command parsed from CLI arguments.
pub const Command = union(enum) {
    capture: CaptureOptions,
    annotate: AnnotateOptions,
    background: BackgroundOptions,
    ocr: OcrOptions,
    help,
    version,
};

pub const ParseError = error{
    UnknownCommand,
    MissingValue,
    InvalidFlag,
    InvalidRect,
};

/// Parse command-line arguments into a Command.
///
/// LEARNING NOTE — Error unions in parsers:
/// Parser functions return `!Command` — either a valid command or
/// a descriptive error. This makes the happy path clean (`try parse(args)`)
/// while still handling every failure mode explicitly.
pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) {
        return Command{ .capture = .{} }; // default: capture fullscreen to clipboard
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "help") or std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "-h")) {
        return .help;
    }

    if (std.mem.eql(u8, subcmd, "version") or std.mem.eql(u8, subcmd, "--version") or std.mem.eql(u8, subcmd, "-V")) {
        return .version;
    }

    if (std.mem.eql(u8, subcmd, "capture")) {
        return Command{ .capture = try parseCaptureArgs(args[1..]) };
    }

    if (std.mem.eql(u8, subcmd, "annotate")) {
        return Command{ .annotate = try parseAnnotateArgs(args[1..]) };
    }

    if (std.mem.eql(u8, subcmd, "bg") or std.mem.eql(u8, subcmd, "background")) {
        return Command{ .background = try parseBackgroundArgs(args[1..]) };
    }

    if (std.mem.eql(u8, subcmd, "ocr")) {
        return Command{ .ocr = parseOcrArgs(args[1..]) };
    }

    // If the first arg looks like a flag, assume implicit "capture" command
    if (subcmd.len > 0 and subcmd[0] == '-') {
        return Command{ .capture = try parseCaptureArgs(args) };
    }

    return ParseError.UnknownCommand;
}

fn parseCaptureArgs(args: []const []const u8) ParseError!CaptureOptions {
    var opts = CaptureOptions{};
    var i: usize = 0;

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--fullscreen") or std.mem.eql(u8, arg, "-f")) {
            opts.mode = .fullscreen;
        } else if (std.mem.eql(u8, arg, "--area") or std.mem.eql(u8, arg, "-a")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.mode = .area;
            opts.area = Rect.parse(args[i]) catch return ParseError.InvalidRect;
        } else if (std.mem.eql(u8, arg, "--window") or std.mem.eql(u8, arg, "-w")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.mode = .window;
            opts.window_title = args[i];
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const path = args[i];
            opts.output = .{ .file = path };
            opts.format = ImageFormat.fromExtension(path);
        } else if (std.mem.eql(u8, arg, "--clipboard") or std.mem.eql(u8, arg, "-c")) {
            opts.output = .clipboard;
        } else if (std.mem.eql(u8, arg, "--delay") or std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.delay_secs = std.fmt.parseInt(u32, args[i], 10) catch return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            if (std.mem.eql(u8, args[i], "jpeg") or std.mem.eql(u8, args[i], "jpg")) {
                opts.format = .jpeg;
            } else if (std.mem.eql(u8, args[i], "png")) {
                opts.format = .png;
            } else {
                return ParseError.InvalidFlag;
            }
        } else {
            return ParseError.InvalidFlag;
        }

        i += 1;
    }

    return opts;
}

fn parseAnnotateArgs(args: []const []const u8) ParseError!AnnotateOptions {
    var opts = AnnotateOptions{};
    var i: usize = 0;

    // First positional arg is the input file
    if (args.len > 0 and args[0].len > 0 and args[0][0] != '-') {
        opts.input_file = args[0];
        i = 1;
    } else {
        return ParseError.MissingValue;
    }

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.output_file = args[i];
        } else if (std.mem.eql(u8, arg, "--arrow")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const coords = parseFourInts(args[i]) orelse return ParseError.InvalidRect;
            if (opts.annotation_count < 16) {
                opts.annotations[opts.annotation_count] = .{ .arrow = .{
                    .x0 = coords[0],
                    .y0 = coords[1],
                    .x1 = coords[2],
                    .y1 = coords[3],
                } };
                opts.annotation_count += 1;
            }
        } else if (std.mem.eql(u8, arg, "--rect")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const r = Rect.parse(args[i]) catch return ParseError.InvalidRect;
            if (opts.annotation_count < 16) {
                opts.annotations[opts.annotation_count] = .{ .rect = .{
                    .x = r.x, .y = r.y, .w = r.width, .h = r.height,
                } };
                opts.annotation_count += 1;
            }
        } else if (std.mem.eql(u8, arg, "--blur")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const r = Rect.parse(args[i]) catch return ParseError.InvalidRect;
            if (opts.annotation_count < 16) {
                opts.annotations[opts.annotation_count] = .{ .blur = .{
                    .x = r.x, .y = r.y, .w = r.width, .h = r.height, .radius = 10,
                } };
                opts.annotation_count += 1;
            }
        } else if (std.mem.eql(u8, arg, "--highlight")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const r = Rect.parse(args[i]) catch return ParseError.InvalidRect;
            if (opts.annotation_count < 16) {
                opts.annotations[opts.annotation_count] = .{ .highlight = .{
                    .x = r.x, .y = r.y, .w = r.width, .h = r.height,
                } };
                opts.annotation_count += 1;
            }
        } else if (std.mem.eql(u8, arg, "--text")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const coords_str = args[i];
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            const content = args[i];
            // Parse "x,y" from coords_str
            var iter = std.mem.splitScalar(u8, coords_str, ',');
            const x_str = iter.next() orelse return ParseError.InvalidRect;
            const y_str = iter.next() orelse return ParseError.InvalidRect;
            const x = std.fmt.parseInt(i32, std.mem.trim(u8, x_str, " "), 10) catch return ParseError.InvalidRect;
            const y = std.fmt.parseInt(i32, std.mem.trim(u8, y_str, " "), 10) catch return ParseError.InvalidRect;
            if (opts.annotation_count < 16) {
                opts.annotations[opts.annotation_count] = .{ .text = .{
                    .x = x, .y = y, .content = content,
                } };
                opts.annotation_count += 1;
            }
        } else {
            return ParseError.InvalidFlag;
        }

        i += 1;
    }

    return opts;
}

fn parseBackgroundArgs(args: []const []const u8) ParseError!BackgroundOptions {
    var opts = BackgroundOptions{};
    var i: usize = 0;

    // First positional arg is the input file
    if (args.len > 0 and args[0].len > 0 and args[0][0] != '-') {
        opts.input_file = args[0];
        i = 1;
    } else {
        return ParseError.MissingValue;
    }

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.output_file = args[i];
        } else if (std.mem.eql(u8, arg, "--padding") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.padding = std.fmt.parseInt(u32, args[i], 10) catch return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "--color")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.color = args[i];
        } else if (std.mem.eql(u8, arg, "--radius") or std.mem.eql(u8, arg, "-r")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.radius = std.fmt.parseInt(u32, args[i], 10) catch return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "--shadow")) {
            opts.shadow = true;
        } else {
            return ParseError.InvalidFlag;
        }

        i += 1;
    }

    return opts;
}

fn parseOcrArgs(args: []const []const u8) OcrOptions {
    var opts = OcrOptions{};
    var i: usize = 0;

    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--capture")) {
            opts.capture_mode = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            opts.input_file = arg;
        }
        i += 1;
    }

    return opts;
}

/// Parse "a,b,c,d" into four i32 values.
fn parseFourInts(s: []const u8) ?[4]i32 {
    var iter = std.mem.splitScalar(u8, s, ',');
    var result: [4]i32 = undefined;
    var idx: usize = 0;
    while (iter.next()) |part| {
        if (idx >= 4) return null;
        result[idx] = std.fmt.parseInt(i32, std.mem.trim(u8, part, " "), 10) catch return null;
        idx += 1;
    }
    if (idx != 4) return null;
    return result;
}

/// Print usage/help text.
pub fn printHelp() void {
    const help =
        \\ZigShot — Screenshot tool for macOS
        \\
        \\USAGE:
        \\  zigshot <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\  capture     Take a screenshot (default command)
        \\  annotate    Add annotations to an image
        \\  bg          Add background, padding, rounded corners
        \\  help        Show this help message
        \\  version     Show version
        \\
        \\CAPTURE OPTIONS:
        \\  --fullscreen, -f    Capture entire screen (default)
        \\  --area, -a X,Y,W,H  Capture specific region
        \\  --window, -w TITLE  Capture window by title
        \\  --output, -o PATH   Save to file (default: clipboard)
        \\  --clipboard, -c     Copy to clipboard (default)
        \\  --delay, -d SECS    Wait before capturing
        \\  --format png|jpeg   Image format (auto-detected from -o extension)
        \\
        \\ANNOTATE OPTIONS:
        \\  zigshot annotate <FILE> [OPTIONS]
        \\  --arrow X0,Y0,X1,Y1  Draw an arrow
        \\  --rect X,Y,W,H       Draw a rectangle outline
        \\  --blur X,Y,W,H       Blur a region
        \\  --highlight X,Y,W,H  Highlight a region (yellow overlay)
        \\  --text X,Y "TEXT"     Add text at position
        \\  --output, -o PATH     Save result (default: overwrite input)
        \\
        \\BACKGROUND OPTIONS:
        \\  zigshot bg <FILE> [OPTIONS]
        \\  --padding, -p N     Padding in pixels (default: 64)
        \\  --color HEX         Background color (e.g. "#1a1a2e")
        \\  --radius, -r N      Corner radius
        \\  --shadow            Add drop shadow
        \\  --output, -o PATH   Save result
        \\
        \\EXAMPLES:
        \\  zigshot capture --fullscreen -o ~/Desktop/shot.png
        \\  zigshot capture --area 100,200,800,600 -o area.png
        \\  zigshot annotate shot.png --arrow 10,10,200,200 --blur 300,100,150,80
        \\  zigshot bg shot.png --padding 64 --color "#1a1a2e" --radius 12
        \\
    ;
    std.debug.print("{s}", .{help});
}

// ============================================================================
// Tests
// ============================================================================

test "parse: no args → default capture fullscreen to clipboard" {
    const cmd = try parse(&.{});
    switch (cmd) {
        .capture => |opts| {
            try std.testing.expectEqual(CaptureMode.fullscreen, opts.mode);
            try std.testing.expectEqual(OutputTarget.clipboard, opts.output);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse: capture --fullscreen -o path" {
    const cmd = try parse(&.{ "capture", "--fullscreen", "-o", "/tmp/test.png" });
    switch (cmd) {
        .capture => |opts| {
            try std.testing.expectEqual(CaptureMode.fullscreen, opts.mode);
            switch (opts.output) {
                .file => |path| try std.testing.expectEqualStrings("/tmp/test.png", path),
                .clipboard => return error.TestUnexpectedResult,
            }
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse: capture --area with rect" {
    const cmd = try parse(&.{ "capture", "--area", "100,200,800,600" });
    switch (cmd) {
        .capture => |opts| {
            try std.testing.expectEqual(CaptureMode.area, opts.mode);
            try std.testing.expect(opts.area.?.eql(Rect.init(100, 200, 800, 600)));
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse: implicit capture with flags" {
    const cmd = try parse(&.{ "--fullscreen", "-o", "/tmp/x.png" });
    switch (cmd) {
        .capture => |opts| {
            try std.testing.expectEqual(CaptureMode.fullscreen, opts.mode);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse: help and version" {
    const h = try parse(&.{"--help"});
    try std.testing.expectEqual(Command.help, h);

    const v = try parse(&.{"--version"});
    try std.testing.expectEqual(Command.version, v);
}

test "parse: delay flag" {
    const cmd = try parse(&.{ "capture", "--delay", "3", "--fullscreen" });
    switch (cmd) {
        .capture => |opts| {
            try std.testing.expectEqual(@as(u32, 3), opts.delay_secs);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse: format auto-detect from extension" {
    const cmd = try parse(&.{ "capture", "-o", "test.jpg" });
    switch (cmd) {
        .capture => |opts| {
            try std.testing.expectEqual(ImageFormat.jpeg, opts.format);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse: unknown command → error" {
    try std.testing.expectError(ParseError.UnknownCommand, parse(&.{"foobar"}));
}

test "parse: missing value → error" {
    try std.testing.expectError(ParseError.MissingValue, parse(&.{ "capture", "--area" }));
    try std.testing.expectError(ParseError.MissingValue, parse(&.{ "capture", "-o" }));
}
