const std = @import("std");

const runner = @import("ztest_runner");

pub const exp = @import("expectations/core.zig");
pub const exp_fn = @import("expectations/functions.zig");

test {
    std.testing.refAllDeclsRecursive(exp);
    std.testing.refAllDeclsRecursive(exp_fn);
}
