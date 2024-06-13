const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/util/util.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ztest_runner_mod = b.addModule("ztest_runner", .{
        .root_source_file = b.path("src/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    ztest_runner_mod.addImport("utils", utils_mod);

    const ztest_mod = b.addModule("ztest", .{
        .root_source_file = b.path("src/ztest.zig"),
        .target = target,
        .optimize = optimize,
    });
    ztest_mod.addImport("utils", utils_mod);
    ztest_mod.addImport("ztest_runner", ztest_runner_mod);

    const ztest_runner_unit_tests = b.addTest(.{
        .name = "ztest runner unit tests",
        .root_source_file = b.path("src/runner.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    ztest_runner_unit_tests.root_module.addImport("utils", utils_mod);
    const run_ztest_runner_unit_tests = b.addRunArtifact(ztest_runner_unit_tests);

    const ztest_unit_tests = b.addTest(.{
        .name = "ztest main unit tests",
        .root_source_file = b.path("src/ztest.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    ztest_unit_tests.root_module.addImport("utils", utils_mod);
    ztest_unit_tests.root_module.addImport("ztest_runner", ztest_runner_mod);
    const run_ztest_unit_tests = b.addRunArtifact(ztest_unit_tests);

    const unit_with_runner_tests = b.addTest(.{
        .name = "Unit tests under ztest runner",
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    unit_with_runner_tests.root_module.addImport("utils", utils_mod);
    unit_with_runner_tests.root_module.addImport("ztest", ztest_mod);
    const run_unit_with_runner = b.addRunArtifact(unit_with_runner_tests);

    const unit_without_runner_tests = b.addTest(.{
        .name = "Unit tests under default runner",
        .root_source_file = b.path("tests/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_without_runner_tests.root_module.addImport("utils", utils_mod);
    unit_without_runner_tests.root_module.addImport("ztest", ztest_mod);
    const run_unit_without_runner = b.addRunArtifact(unit_without_runner_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_ztest_runner_unit_tests.step);
    test_step.dependOn(&run_ztest_unit_tests.step);
    test_step.dependOn(&run_unit_with_runner.step);
    test_step.dependOn(&run_unit_without_runner.step);
}
