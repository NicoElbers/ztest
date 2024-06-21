const std = @import("std");
const ztest = @import("ztest");
const expect = ztest.expect;
const parameterizedTest = ztest.parameterizedTest;

test "Comptime" {
    try parameterizedTest(runtimeFunc, .{
        .{void},
    });
}

fn runtimeFunc(in: anytype) !void {
    comptime try expect(in).isEqualTo(in);
}
