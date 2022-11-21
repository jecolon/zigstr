const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zigstr", "src/Zigstr.zig");
    lib.setBuildMode(mode);
    lib.addPackagePath("ziglyph", "libs/ziglyph/src/ziglyph.zig");
    lib.addPackagePath("cow_list", "libs/cow_list/src/main.zig");
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.addPackagePath("ziglyph", "libs/ziglyph/src/ziglyph.zig");
    main_tests.addPackagePath("cow_list", "libs/cow_list/src/main.zig");

    var zs_tests = b.addTest("src/Zigstr.zig");
    zs_tests.setBuildMode(mode);
    zs_tests.addPackagePath("ziglyph", "libs/ziglyph/src/ziglyph.zig");
    zs_tests.addPackagePath("cow_list", "libs/cow_list/src/main.zig");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&zs_tests.step);
}
