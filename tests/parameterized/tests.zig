const std = @import("std");
const ztest = @import("ztest");
const expect = ztest.expect;
const parameterizedTest = ztest.parameterizedTest;

test {
    const alloc = std.testing.allocator;

    const ptr = try alloc.create(u32);
    defer alloc.destroy(ptr);

    ptr.* = 234;

    try parameterizedTest(runtimeFunc, .{
        .{ptr},
    });

    comptime try parameterizedTest(runtimeFunc, .{
        .{void},
    });
}

fn runtimeFunc(in: anytype) !void {
    try expect(in).isEqualTo(in);
}
