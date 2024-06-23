const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ztest_runner_mod = b.addModule("ztest_runner", .{
        .root_source_file = b.path("src/ztest-runner/runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ztest_mod = b.addModule("ztest", .{
        .root_source_file = b.path("src/ztest/ztest.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ztest_runner_unit_tests = b.addTest(.{
        .name = "ztest runner unit tests",
        .root_source_file = b.path("src/ztest-runner/runner.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    const run_ztest_runner_unit_tests = b.addRunArtifact(ztest_runner_unit_tests);

    const ztest_unit_tests = b.addTest(.{
        .name = "ztest main unit tests",
        .root_source_file = b.path("src/ztest/ztest.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    const run_ztest_unit_tests = b.addRunArtifact(ztest_unit_tests);

    const unit_with_runner_tests = b.addTest(.{
        .name = "Unit tests under ztest runner",
        .root_source_file = b.path("tests/ztest/tests.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    unit_with_runner_tests.root_module.addImport("ztest", ztest_mod);
    const run_unit_with_runner = b.addRunArtifact(unit_with_runner_tests);

    const unit_without_runner_tests = b.addTest(.{
        .name = "Unit tests under default runner",
        .root_source_file = b.path("tests/ztest/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_without_runner_tests.root_module.addImport("ztest", ztest_mod);
    const run_unit_without_runner = b.addRunArtifact(unit_without_runner_tests);

    const readme_with_runner = b.addTest(.{
        .name = "README code with runner",
        .root_source_file = b.path("tests/readme/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    readme_with_runner.root_module.addImport("ztest", ztest_mod);
    const run_readme_with_runner = b.addRunArtifact(readme_with_runner);

    const readme_without_runner = b.addTest(.{
        .name = "README code without runner",
        .root_source_file = b.path("tests/readme/tests.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = ztest_runner_mod.root_source_file,
    });
    readme_without_runner.root_module.addImport("ztest", ztest_mod);
    const run_readme_without_runner = b.addRunArtifact(readme_without_runner);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_ztest_runner_unit_tests.step);
    test_step.dependOn(&run_ztest_unit_tests.step);

    test_step.dependOn(&run_unit_with_runner.step);
    test_step.dependOn(&run_unit_without_runner.step);

    test_step.dependOn(&run_readme_with_runner.step);
    test_step.dependOn(&run_readme_without_runner.step);
}
