const ztest = @import("ztest");

const exp = ztest.exp;
const expect = exp.expect;
const expectAll = exp.expectAll;
const parameterizedTest = ztest.parameterizedTest;

const utils = @import("../tests.zig").utils;

const exp_fn = ztest.exp_fn;

const Errors = error{ someErr, someOtherErr };
const OtherErrors = error{ someErr, someOtherErr };

test "isError" {
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

    try parameterizedTest(inner.exect, .{
        .{@as(Errors, Errors.someErr)},
        .{@as(Errors!u8, Errors.someErr)},
    });
}

test "isAnyValue" {
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

    try parameterizedTest(inner.isVal, .{
        .{@as(u8, 43)},
        .{@as(Errors!u8, 12)},
    });

    try parameterizedTest(inner.isNotVal, .{
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

    // TODO: Annotate and verify the types I'm testing
    try parameterizedTest(equality, .{
        .{ @as(Errors, Errors.someErr), @as(Errors, Errors.someErr) },
        .{ @as(Errors, Errors.someErr), @as(OtherErrors, OtherErrors.someErr) },
        .{ true, true },
        .{ @as(u8, 123), @as(u8, 123) },
        .{ @as(f32, 123.456), @as(f32, 123.456) },
        .{ first, second },
        .{ @constCast(@as(*const u32, &123)), @constCast(@as(*const u32, &123)) },
    });
}

test "isEqualTo equal comptime" {
    const equality = struct {
        pub fn inner(comptime input: anytype, comptime expected: @TypeOf(input)) !void {
            comptime try expect(input).isEqualTo(expected);
        }
    }.inner;

    // TODO: Annotate and verify the types I'm testing
    try parameterizedTest(equality, .{
        .{ void, void },
        .{ noreturn, noreturn },
        .{ null, null },
        .{ undefined, undefined },
        .{ @as(Errors, Errors.someErr), @as(Errors, Errors.someErr) },
        .{ @as(Errors, Errors.someErr), @as(OtherErrors, OtherErrors.someErr) },
        .{ true, true },
        .{ @as(u8, 123), @as(u8, 123) },
        .{ @as(f32, 123.456), @as(f32, 123.456) },
        .{ .someLiteral, .someLiteral },
    });
}

test "isEqualTo not equal" {
    const equality = struct {
        pub fn inner(input: anytype, expected: @TypeOf(input)) !void {
            try expect(input).not().isEqualTo(expected);
        }
    }.inner;

    // TODO: Annotate and verify the types I'm testing
    try parameterizedTest(equality, .{
        // .{ Errors, OtherErrors },
        .{ true, false },
        .{ @as(u8, 123), @as(u8, 13) },
        .{ @as(f32, 123.456), @as(f32, 123.653) },
        .{ @as(*const u32, &123), @as(*const u32, &456) },
    });
}

test "isEqualTo not equal comptime" {
    const equality = struct {
        pub fn inner(comptime input: anytype, comptime expected: @TypeOf(input)) !void {
            comptime try expect(input).not().isEqualTo(expected);
        }
    }.inner;

    // TODO: Annotate and verify the types I'm testing
    try parameterizedTest(equality, .{
        .{ @as(Errors, Errors.someErr), @as(Errors, Errors.someOtherErr) },
        .{ true, false },
        .{ @as(u8, 123), @as(u8, 124) },
        .{ @as(f32, 431.456), @as(f32, 123.456) },
        .{ @as(type, u8), @as(type, u9) },
        .{ .someLiteral, .someOtherLiteral },
    });
}
