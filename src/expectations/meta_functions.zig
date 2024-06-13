const std = @import("std");

const exp = @import("core.zig");
const exp_fn = @import("functions.zig");

const Expectation = exp.ExpectationState;
const ExpectationError = exp.ExpectationError;
const SomeExpectation = exp_fn.SomeExpectation;

fn isExpectationError(err: anyerror) bool {
    const expectation_info = @typeInfo(ExpectationError);
    const errors: []const std.builtin.Type.Error = expectation_info.ErrorSet.?;

    for (errors) |expectationError| {
        if (std.meta.eql(@errorName(err), expectationError.name)) return true;
    }
    return false;
}

pub inline fn not(comptime T: type, to_mutate: SomeExpectation(T)) SomeExpectation(T) {
    return Not(T).bind(to_mutate);
}
pub fn Not(comptime T: type) type {
    return struct {
        const Self = @This();

        someExpectation: SomeExpectation(T),

        pub inline fn bind(to_mutate: SomeExpectation(T)) SomeExpectation(T) {
            return SomeExpectation(T).init(&Self{
                .someExpectation = to_mutate,
            });
        }

        pub fn make(self: *const Self) SomeExpectation(T) {
            return SomeExpectation(T).init(self);
        }

        pub fn expect(self: *const Self, expec: *Expectation(T)) !void {
            expec.negative_expectation = !expec.negative_expectation;
            self.someExpectation.expect(expec) catch |err| {
                if (isExpectationError(err)) {
                    expec.err = null;
                    return;
                }

                return err;
            };

            return ExpectationError.Failed;
        }
    };
}
