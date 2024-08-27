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

// fn assertFour(in: u32) !void {
//     try expect(in).isEqualTo(4);
// }

// test "failure" {
//     try parameterizedTest(assertFour, .{
//         .{@as(u32, 5)},
//     });
// }
