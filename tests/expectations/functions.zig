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
}

test "isAnyValue normal value" {
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
}
