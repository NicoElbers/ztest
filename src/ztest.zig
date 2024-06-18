const std = @import("std");

const runner = @import("ztest_runner");

pub const exp = @import("expectations/core.zig");
pub const exp_fn = @import("expectations/functions.zig");
pub const exp_meta_fn = @import("expectations/meta_functions.zig");

pub const ExpectationState = exp.ExpectationState;
pub const SomeExpectation = exp_fn.SomeExpectation;

pub const expect = exp.expect;
pub const expectAll = exp.expectAll;

pub const parameterizedTest = @import("parameterized_tests/core.zig").parameterizedTest;

test {
    _ = @import("expectations/core.zig");
    _ = @import("parameterized_tests/core.zig");
}
