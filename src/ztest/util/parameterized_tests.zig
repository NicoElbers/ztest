// FIXME: Just move this into the main parameterized test folder
const std = @import("std");
const util = @import("../ztest.zig").util;

const runner = util.RunnerInfo;

pub fn runTest(
    name: []const u8,
    comptime func: anytype,
    args: anytype,
) !void {
    std.debug.assert(util.isUsingZtestRunner);

    try runner.test_runner.runTest(runner.Test{
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
    if (info != .Fn)
        @compileError("callAnyFunction takes in a function and argument tuple");

    const RetT = info.Fn.return_type.?;
    switch (@typeInfo(RetT)) {
        .ErrorUnion,
        .ErrorSet,
        => _ = try @call(.auto, func, args),

        else => _ = @call(.auto, func, args),
    }
}
