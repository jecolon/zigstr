const Build = @import("std").Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Deps
    const ziglyph = b.dependency("ziglyph", .{
        .target = target,
        .optimize = optimize,
    });

    const cow_list = b.dependency("cow_list", .{
        .target = target,
        .optimize = optimize,
    });

    // Module
    const zigstr = b.addModule("zigstr", .{
        .source_file = .{ .path = "src/Zigstr.zig" },
    });
    zigstr.dependencies.put("cow_list", cow_list.module("cow_list")) catch unreachable;
    zigstr.dependencies.put("ziglyph", ziglyph.module("ziglyph")) catch unreachable;

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("cow_list", cow_list.module("cow_list"));
    main_tests.addModule("ziglyph", ziglyph.module("ziglyph"));

    const run_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}
