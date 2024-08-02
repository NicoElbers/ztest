// FIXME: Just move this into the main parameterized test folder
const std = @import("std");
const util = @import("../ztest.zig").util;

const runner = util.RunnerInfo;

// TODO: Change this to take in multiple tests, and run them all under the same runner
// or maybe easier, take in a list of args and run a test for each on the same runner
pub fn runTest(
    name: []const u8,
    comptime func: anytype,
    args: anytype,
) !void {
    std.debug.assert(util.isUsingZtestRunner);

    var our_runner = runner.TestRunner.initDefault();

    try our_runner.runTest(runner.Test{
        .typ = .parameterized,
        .name = name,
        .func = wrap(func, @TypeOf(args)),
        .args = &args,
    });
}

pub fn wrap(comptime func: anytype, comptime ArgsT: type) *const fn (*const anyopaque) anyerror!void {
    return struct {
        pub fn wrapper(args_ptr: *const anyopaque) !void {
            const args: *const ArgsT = @ptrCast(@alignCast(args_ptr));
            try callAnyFunction(func, args.*);
        }
    }.wrapper;
}

// TODO: Put this in an actual util module? file? idk.
pub fn callAnyFunction(comptime func: anytype, args: anytype) !void {
    const info = @typeInfo(@TypeOf(func));
    if (info != .@"fn")
        @compileError("callAnyFunction takes in a function and argument tuple");

    const RetT = info.@"fn".return_type.?;
    switch (@typeInfo(RetT)) {
        .error_union,
        .error_set,
        => _ = try @call(.auto, func, args),

        else => _ = @call(.auto, func, args),
    }
}
