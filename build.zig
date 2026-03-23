const std = @import("std");

/// ZigShot build configuration.
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

    // Link macOS frameworks
    exe.root_module.linkFramework("CoreGraphics", .{});
    exe.root_module.linkFramework("CoreFoundation", .{});
    exe.root_module.linkFramework("ImageIO", .{});
    exe.root_module.linkFramework("AppKit", .{});
    exe.root_module.linkFramework("Cocoa", .{});

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

    // ---- Run step ----
    const run_step = b.step("run", "Run zigshot");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ---- Tests ----
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
