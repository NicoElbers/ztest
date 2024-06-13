const std = @import("std");
const io = std.io;
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const utils = @import("utils");
const colors = utils.colors;

pub const State = struct {
    ztest_runner: bool = false,
};

pub fn main() !void {
    std.testing.log_level = .warn;

    const stdout = std.io.getStdOut();

    try runTests(stdout, builtin.test_functions);
}

pub fn runTests(writer: anytype, tests: []const std.builtin.TestFn) !void {
    for (tests) |t| {
        try writer.writeAll(t.name);
        t.func() catch {
            // With this line things break, without things are find
            try colors.setColor(writer, .red);
            try writer.writeAll(" not passed\n");
            try colors.setColor(writer, .reset);
            continue;
        };
        try colors.setColor(writer, .bright_green);
        try writer.writeAll(" passed\n");
        try colors.setColor(writer, .reset);
    }
}
