//! The build script — your `webpack.config.js` + `package.json` combined.
//! Zig's build system is written in Zig itself — no YAML, no JSON, no Makefile.
//! The `build()` function constructs a dependency graph that the build runner
//! executes. This file IS a Zig program that runs at build time.

const std = @import("std");

/// ZigShot build configuration.
pub fn build(b: *std.Build) void {
    // Enables cross-compilation via `zig build -Dtarget=aarch64-macos`.
    // We don't use this today (macOS only) but it's free to include and
    // costs nothing. Like putting `"engines"` in package.json — declares
    // intent without restricting anything.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- Library module (core logic, reusable) ----
    // The library module ("zigshot") contains platform-independent code
    // (Image, Rect, Color, etc.). The executable imports it and adds
    // platform-specific code. This split lets us test core logic without
    // linking macOS frameworks — the library tests run on any platform.
    // Think: your pure utility package vs. your app that depends on it.
    const lib_mod = b.addModule("zigshot", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // ---- CLI executable ----
    const exe = b.addExecutable(.{
        .name = "zigshot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigshot", .module = lib_mod },
            },
        }),
    });

    // macOS system frameworks — think of them as native dependencies that ship
    // with the OS. In JS terms, these are like built-in Node.js modules (`fs`,
    // `crypto`) — always available, no npm install needed.
    //   CoreGraphics = screen capture + drawing API
    //   CoreFoundation = Apple's base C library (strings, URLs, etc.)
    //   ImageIO = PNG/JPEG encode/decode
    //   AppKit/Cocoa = GUI toolkit (menus, windows, overlays)
    exe.root_module.linkFramework("CoreGraphics", .{});
    exe.root_module.linkFramework("CoreFoundation", .{});
    exe.root_module.linkFramework("ImageIO", .{});
    exe.root_module.linkFramework("AppKit", .{});
    exe.root_module.linkFramework("Cocoa", .{});
    exe.root_module.linkFramework("QuartzCore", .{}); // CAMediaTimingFunction (animations)
    exe.root_module.linkFramework("UniformTypeIdentifiers", .{}); // UTType (NSSavePanel)
    exe.root_module.linkFramework("ScreenCaptureKit", .{}); // SCStream (screen recording)
    exe.root_module.linkFramework("AVFoundation", .{}); // AVAssetWriter (MP4 encoding)
    exe.root_module.linkFramework("CoreMedia", .{}); // CMSampleBuffer, CMTime

    // Compile the AppKit ObjC bridge directly into the executable.
    //
    // LEARNING NOTE: Zig can compile Objective-C (.m) files alongside
    // Zig code. The -fobjc-arc flag enables automatic reference counting
    // for ObjC objects. The exported C functions are callable from Zig
    // via @cImport of the header file.
    exe.addCSourceFile(.{
        .file = b.path("vendor/appkit_bridge.m"),
        .flags = &.{ "-fobjc-arc", "-fno-objc-exceptions" },
    });
    exe.root_module.addIncludePath(b.path("vendor"));

    b.installArtifact(exe);

    // ---- Static C library (for Swift/GTK FFI consumers) ----
    // Compiles only the core modules (no platform code, no macOS deps).
    // Produces: zig-out/lib/libzigshot.a
    const c_api_mod = b.createModule(.{
        .root_source_file = b.path("src/core/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const static_lib = b.addLibrary(.{
        .name = "zigshot",
        .root_module = c_api_mod,
        .linkage = .static,
    });
    static_lib.linkLibC();

    // Re-pack the static library with macOS libtool after installation so the
    // ar members are 8-byte aligned. Zig's built-in archiver writes 4-byte-
    // aligned members by default, which Apple's linker (ld) rejects with:
    //   "64-bit mach-o member … not 8-byte aligned"
    // libtool -static regenerates the archive in the format ld expects.
    const lib_out = b.pathJoin(&.{ b.install_path, "lib", "libzigshot.a" });
    const libtool_step = b.addSystemCommand(&.{
        "libtool", "-static", "-o", lib_out, lib_out,
    });
    const install_lib = b.addInstallArtifact(static_lib, .{});
    libtool_step.step.dependOn(&install_lib.step);
    b.getInstallStep().dependOn(&libtool_step.step);

    // Install C header alongside the library
    // Produces: zig-out/include/zigshot.h
    const install_header = b.addInstallFile(b.path("include/zigshot.h"), "include/zigshot.h");
    b.getInstallStep().dependOn(&install_header.step);

    // ---- Run step ----
    const run_step = b.step("run", "Run zigshot");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ---- Tests ----
    // Two separate test suites: library tests (pure Zig, fast, portable) and
    // executable tests (need macOS frameworks linked). `zig build test` runs both.
    // Keeping them split means CI on Linux can still run library tests.
    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
