const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nvim_c_mod = b.addModule("nvim_c", .{
        .root_source_file = b.path("nvim_c.zig"),
        .link_libc = true,
    });

    _ = b.addModule("znvim", .{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{.{ .name = "nvim_c", .module = nvim_c_mod }},
    });

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    main_tests.root_module.addImport("nvim_c", nvim_c_mod);

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
