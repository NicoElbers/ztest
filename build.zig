const std = @import("std");

const Build = std.Build;
const Step = Build.Step;
const Module = Build.Module;
const LazyPath = Build.LazyPath;
const TestOptions = Build.TestOptions;

const NamedModule = struct {
    name: []const u8,
    module: *Module,
};

fn makeModule(b: *Build, name: []const u8, options: Module.CreateOptions) NamedModule {
    const mod = b.addModule(name, options);
    return .{
        .name = name,
        .module = mod,
    };
}

fn runnerPath(b: *Build) LazyPath {
    return b.path("src/ztest-runner/runner.zig");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ztest_mod = makeModule(b, "ztest", .{
        .root_source_file = b.path("src/ztest/ztest.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");

    addMultiTest(b, test_step, &.{}, .{
        .name = "ztest runner core unit tests",
        .root_source_file = b.path("src/ztest-runner/runner.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = runnerPath(b),
    });

    addMultiTest(b, test_step, &.{}, .{
        .name = "ztest core unit tests",
        .root_source_file = b.path("src/ztest/ztest.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = runnerPath(b),
    });

    addMultiTest(b, test_step, &.{ztest_mod}, .{
        .name = "Ztest unit tests",
        .root_source_file = b.path("tests/ztest/tests.zig"),
        .target = target,
        .optimize = optimize,
        .test_runner = runnerPath(b),
    });

    addMultiTest(b, test_step, &.{ztest_mod}, .{
        .name = "README code",
        .root_source_file = b.path("tests/readme/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
}

fn addMultiTest(b: *Build, test_step: *Step, deps: []const NamedModule, options: TestOptions) void {
    // ----------- With runner --------------------
    const options_with_runner = blk: {
        var opt: TestOptions = options;
        opt.test_runner = runnerPath(b);
        break :blk opt;
    };
    const with_runner = b.addTest(options_with_runner);
    for (deps) |dep| {
        with_runner.root_module.addImport(dep.name, dep.module);
    }
    const run_with_runner = b.addRunArtifact(with_runner);
    test_step.dependOn(&run_with_runner.step);

    // ------------- Without runner -------------
    const options_without_runner = blk: {
        var opt: TestOptions = options;
        opt.test_runner = null;
        break :blk opt;
    };
    const without_runner = b.addTest(options_without_runner);
    for (deps) |dep| {
        without_runner.root_module.addImport(dep.name, dep.module);
    }
    const run_without_runner = b.addRunArtifact(without_runner);
    test_step.dependOn(&run_without_runner.step);
}
