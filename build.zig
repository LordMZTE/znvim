const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nvim_c_mod = b.addModule("nvim_c", .{
        .source_file = .{ .path = "nvim_c.zig" },
    });

    _ = b.addModule("znvim", .{
        .source_file = .{ .path = "src/main.zig" },
        .dependencies = &.{.{ .name = "nvim_c", .module = nvim_c_mod }},
    });

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main_tests.addModule("nvim_c", nvim_c_mod);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
