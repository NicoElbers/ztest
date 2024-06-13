// TODO: Rename Expectation maybe to state or smth

const std = @import("std");

const runner = @import("ztest_runner");

pub const exp = @import("expectations/core.zig");
pub const exp_fn = @import("expectations/functions.zig");
pub const exp_meta_fn = @import("expectations/meta_functions.zig");

pub const Expectation = exp.Expectation;
pub const SomeExpectation = exp_fn.SomeExpectation;

// NOTE: This is explicitly inlined to be able to return a pointer to the stack
pub inline fn expect(val: anytype) *Expectation(@TypeOf(val)) {
    var instance: Expectation(@TypeOf(val)) = Expectation(@TypeOf(val)){
        .val = val,
    };

    return &instance;
}

test expect {
    comptime try expect(123).isEqualTo(123);
    try expect(@as(u32, 123)).isEqualTo(123);
}

pub fn expectAll(val: anytype, expectations: []const SomeExpectation(@TypeOf(val))) !void {
    const expecta = expect(val);

    for (expectations) |expec| {
        expec.expect(expecta) catch |err| {
            return expecta.handleError(err);
        };
    }
}

test expectAll {
    try expectAll(@as(u32, 64), &.{
        exp_fn.isEqualTo(@as(u32, 64)),
        exp_fn.isValue(u32),
        exp_meta_fn.not(u32, exp_fn.isEqualTo(@as(u32, 123))),
    });
}

test {
    std.testing.refAllDeclsRecursive(exp);
    std.testing.refAllDeclsRecursive(exp_fn);
}
