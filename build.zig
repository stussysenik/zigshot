const std = @import("std");

/// ZigShot build configuration.
///
/// LEARNING NOTE: build.zig is just a Zig program that runs at build time.
/// `zig build` executes THIS file, which describes what to compile and how.
/// The build graph is lazy — only steps you actually invoke get executed.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- Library module (core logic, reusable) ----
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

    // Link macOS frameworks for screen capture and image I/O.
    //
    // LEARNING NOTE: Zig can link against C libraries and system frameworks
    // directly. No Xcode project needed — the Zig build system handles
    // finding and linking these frameworks from the macOS SDK.
    exe.root_module.linkFramework("CoreGraphics", .{});
    exe.root_module.linkFramework("CoreFoundation", .{});
    exe.root_module.linkFramework("ImageIO", .{});

    b.installArtifact(exe);

    // ---- Run step ----
    const run_step = b.step("run", "Run zigshot");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ---- Tests ----
    // Library tests (core logic — pure Zig, testable anywhere)
    const lib_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    // Executable tests (includes macOS framework tests)
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
