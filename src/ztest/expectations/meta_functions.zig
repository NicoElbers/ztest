// TODO: Am I gonna create more of these? Otherwise refactor
const std = @import("std");

const exp = @import("core.zig");
const exp_fn = @import("functions.zig");

const ExpectationState = exp.ExpectationState;
const ExpectationError = exp.ExpectationError;
const SomeExpectation = exp_fn.SomeExpectation;

// FIXME: This never worked, remove
fn isExpectationError(err: anyerror) bool {
    const expectation_info = @typeInfo(ExpectationError);
    const errors: []const std.builtin.Type.Error = expectation_info.error_set.?;

    for (errors) |expectationError| {
        if (std.meta.eql(@errorName(err), expectationError.name)) return true;
    }
    return false;
}

// FIXME: Make more usable or remove
// I would want:
//  try expect(foo).not(expectation(bar));
// or
//  try expect(foo).not().expectation(bar);
pub inline fn not(comptime T: type, to_mutate: SomeExpectation(T)) SomeExpectation(T) {
    return Not(T).bind(to_mutate);
}
pub fn Not(comptime T: type) type {
    switch (T) {
        else => {},
    }

    return struct {
        const Self = @This();

        some_expectation: SomeExpectation(T),

        pub inline fn bind(to_mutate: SomeExpectation(T)) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .some_expectation = to_mutate,
            });
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }

        pub fn expectation(self: *const Self, expec: *ExpectationState(T)) !void {
            expec.negative_expectation = !expec.negative_expectation;
            return self.some_expectation.expectation(expec);
        }
    };
}
