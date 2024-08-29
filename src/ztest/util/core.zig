pub const runner_com = @import("runner_communication.zig");
pub const isUsingZtestRunner = runner_com.isUsingZtestRunner();
// FIXME: useless function
pub const setUsingZtest = runner_com.setUsingZtest;
pub const RunnerInfo = runner_com.RunnerInfo;

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
