// TODO: When compile error tests are implemented go through the entire codebase
// again to make comments

// TODO: Expose common functions like "expectEqual"

const std = @import("std");

// FIXME: These all have shitty names tbh
pub const util = @import("util/core.zig");
pub const exp = @import("expectations/core.zig");
pub const exp_fn = @import("expectations/functions.zig");
pub const exp_meta_fn = @import("expectations/meta_functions.zig");

pub const ExpectationState = exp.ExpectationState;
pub const SomeExpectation = exp_fn.SomeExpectation;

pub const expect = exp.expect;

// TODO: Decide if I'm removing expectAll
pub const expectAll = exp.expectAll;

const parameterizedTests = @import("parameterized_tests/core.zig");

pub const parameterizedTest = parameterizedTests.parameterizedTest;

// TODO: Decide if I really need this
pub const allocator = std.testing.allocator;

test {
    _ = @import("expectations/core.zig");
    _ = @import("parameterized_tests/core.zig");
}
