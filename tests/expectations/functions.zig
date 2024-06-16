const ztest = @import("ztest");

const exp = ztest.exp;
const expect = exp.expect;
const expectAll = exp.expectAll;

const utils = @import("../tests.zig").utils;

const exp_fn = ztest.exp_fn;

// pub inline fn isError(expected: anytype) SomeExpectation(@TypeOf(expected)) {
// pub fn expectation(self: *const Self, state: *ExpectationState(T)) !void {

test "isError error union" {
    const Errors = error{ someErr, someOtherErr };

    const input: Errors!u8 = Errors.someErr;

    try expect(input).isError(Errors.someErr);
    try expect(input).isError(error.someErr);
    try expect(input).not().isError(error.someOtherErr);
}

test "isError error set" {
    const Errors = error{ someErr, someOtherErr };

    const input: Errors = Errors.someErr;

    try expect(input).isError(Errors.someErr);
    try expect(input).isError(error.someErr);
    try expect(input).not().isError(Errors.someOtherErr);
}

test "isValue normal value" {
    const input: u8 = 123;

    try expect(input).isValue();
}

test "isValue error set" {
    const Errors = error{ someErr, someOtherErr };

    const input: Errors = Errors.someErr;

    try expect(input).not().isValue();
}

test "isValue Error union error" {
    const Errors = error{ someErr, someOtherErr };

    const input: Errors!u8 = Errors.someErr;

    try expect(input).not().isValue();
}

test "isValue Error union value" {
    const Errors = error{ someErr, someOtherErr };

    const input: Errors!u8 = 123;

    try expect(input).isValue();
}
