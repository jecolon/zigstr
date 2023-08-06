const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Deps
    const ziglyph = b.dependency("ziglyph", .{
        .target = target,
        .optimize = optimize,
    });
    const ziglyph_mod = ziglyph.module("ziglyph");
    const ziglyph_lib = ziglyph.artifact("ziglyph");

    const cow_list = b.dependency("cow_list", .{
        .target = target,
        .optimize = optimize,
    });
    const cow_list_mod = cow_list.module("cow_list");
    const cow_list_lib = cow_list.artifact("cow_list");

    // Module
    _ = b.addModule("zigstr", .{
        .source_file = .{ .path = "src/Zigstr.zig" },
    });

    const lib = b.addStaticLibrary(.{
        .name = "zigstr",
        .root_source_file = .{ .path = "src/Zigstr.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addModule("ziglyph", ziglyph_mod);
    lib.linkLibrary(ziglyph_lib);
    lib.addModule("cow_list", cow_list_mod);
    lib.linkLibrary(cow_list_lib);

    b.installArtifact(lib);

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("cow_list", cow_list_mod);
    main_tests.linkLibrary(cow_list_lib);
    main_tests.addModule("ziglyph", ziglyph_mod);
    main_tests.linkLibrary(ziglyph_lib);

    const run_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
