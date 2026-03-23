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
const geometry = @import("../core/geometry.zig");
const Rect = geometry.Rect;

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

/// Top-level command parsed from CLI arguments.
pub const Command = union(enum) {
    capture: CaptureOptions,
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

/// Print usage/help text.
pub fn printHelp() void {
    const help =
        \\ZigShot — Screenshot tool for macOS
        \\
        \\USAGE:
        \\  zigshot [capture] [OPTIONS]
        \\
        \\COMMANDS:
        \\  capture     Take a screenshot (default command)
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
        \\EXAMPLES:
        \\  zigshot capture --fullscreen -o ~/Desktop/shot.png
        \\  zigshot capture --area 100,200,800,600 -o area.png
        \\  zigshot --fullscreen --clipboard
        \\  zigshot capture --delay 3 -o delayed.png
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
