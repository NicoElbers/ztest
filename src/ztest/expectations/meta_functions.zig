// fn Template(comptime T: type) type {
//     return struct {
//         const Self = @This();
//
//      pub inline fn bind(to_mutate: SomeExpectation(T)) SomeExpectation(RetT) {
//             return SomeExpectation(T).init(&Self{});
//         }
//
//         pub fn expect(self: *const Self, state: *ExpectationState(T)) !void {
//
//         }
//
//         pub fn make(self: *const Self) SomeExpectation(T) {
//             return SomeExpectation(T).init(self);
//         }
//     };
// }

//switch (@typeInfo(T)) {
//     .Type,
//     .Void,
//     .Bool,
//     .NoReturn,
//     .Int,
//     .Float,
//     .Pointer,
//     .Array,
//     .Struct,
//     .ComptimeFloat,
//     .ComptimeInt,
//     .Undefined,
//     .Null,
//     .Optional,
//     .ErrorUnion,
//     .ErrorSet,
//     .Enum,
//     .Union,
//     .Fn,
//     .Opaque,
//     .Frame,
//     .AnyFrame,
//     .Vector,
//     .EnumLiteral,
//      => {},
// }

const std = @import("std");

const exp = @import("core.zig");
const exp_fn = @import("functions.zig");

const ExpectationState = exp.ExpectationState;
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
