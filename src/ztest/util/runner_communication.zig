const std = @import("std");
const root = @import("root");
const util = @import("../ztest.zig").util;

pub inline fn isUsingZtestRunner() bool {
    return comptime blk: {
        const root_decls = @typeInfo(root).Struct.decls;
        for (root_decls) |decl| {
            if (std.mem.eql(u8, "IsZtestRunner", decl.name)) {
                break :blk true;
            }
        }
        break :blk false;
    };
}

pub fn setUsingZtest() void {
    std.debug.assert(isUsingZtestRunner());

    root.clientUsingZtest = true;
}

pub const RunnerInfo = blk: {
    if (!util.isUsingZtestRunner)
        break :blk struct {};

    break :blk struct {
        pub const TestFn = root.TestFn;
        pub const BuiltinTestFn = root.BuiltinTestFn;
        pub const TestType = root.TestType;
        pub const TestRunner = root.TestRunner;

        pub const test_runner = root.test_runner;
    };
};
