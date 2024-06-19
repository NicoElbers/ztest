const ztest = @import("ztest");

const exp = ztest.exp;
const expect = exp.expect;
const expectAll = exp.expectAll;
const parameterizedTest = ztest.parameterizedTest;

const utils = @import("../tests.zig").utils;

const exp_fn = ztest.exp_fn;

// pub inline fn isError(expected: anytype) SomeExpectation(@TypeOf(expected)) {
// pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {

test "isError" {
    const Errors = error{ someErr, someOtherErr };

    const inner = struct {
        pub fn exect(in: anytype) !void {
            try expect(in).isError(Errors.someErr);
            try expect(in).isError(error.someErr);
            try expect(in).not().isError(error.someOtherErr);
        }
    };

    try parameterizedTest(inner.exect, .{
        .{@as(Errors, Errors.someErr)},
        .{@as(Errors!u8, Errors.someErr)},
    });

    comptime try parameterizedTest(inner.exect, .{
        .{@as(Errors, Errors.someErr)},
        .{@as(Errors!u8, Errors.someErr)},
    });
}

test "isAnyValue" {
    const Errors = error{ someErr, someOtherErr };

    const inner = struct {
        pub fn isVal(in: anytype) !void {
            try expect(in).isAnyValue();
        }
        pub fn isNotVal(in: anytype) !void {
            try expect(in).not().isAnyValue();
        }
    };

    try parameterizedTest(inner.isVal, .{
        .{@as(u8, 43)},
        .{@as(Errors!u8, 12)},
    });

    try parameterizedTest(inner.isNotVal, .{
        .{Errors.someErr},
        .{@as(Errors!u8, Errors.someErr)},
    });

    comptime try parameterizedTest(inner.isVal, .{
        .{@as(u8, 43)},
        .{@as(Errors!u8, 12)},
    });

    comptime try parameterizedTest(inner.isNotVal, .{
        .{Errors.someErr},
        .{@as(Errors!u8, Errors.someErr)},
    });
}

test "isEqualTo equal" {
    const equality = struct {
        pub fn inner(input: anytype, expected: @TypeOf(input)) !void {
            try expect(input).isEqualTo(expected);
        }
    }.inner;

    const alloc = ztest.allocator;
    const first = try alloc.create(u8);
    defer alloc.destroy(first);
    first.* = 123;

    const second = try alloc.create(u8);
    defer alloc.destroy(second);
    second.* = 123;

    try expect(@intFromPtr(first)).not().isEqualTo(@intFromPtr(second));

    try parameterizedTest(equality, .{
        .{ true, true },
        .{ @as(u8, 123), @as(u8, 123) },
        .{ @as(f32, 123.456), @as(f32, 123.456) },
        .{ first, second },
    });

    comptime try parameterizedTest(equality, .{
        .{ true, true },
        .{ @as(u8, 123), @as(u8, 123) },
        .{ @as(f32, 123.456), @as(f32, 123.456) },
        // .{ first, second },
    });
}
