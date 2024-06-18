const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const io = std.io;
const colors = io.tty;

const File = std.fs.File;

pub const IsZtestRunner = void;

pub fn main() !void {
    std.testing.log_level = .warn;

    const stdout = std.io.getStdOut();

    try runTests(stdout, builtin.test_functions);
}

pub fn runTests(file: File, tests: []const std.builtin.TestFn) !void {
    const config = colors.detectConfig(file);
    const writer = file.writer();

    for (tests) |t| {
        try writer.writeAll(t.name);
        t.func() catch {
            try config.setColor(writer, .red);
            try writer.writeAll(" not passed\n");
            try config.setColor(writer, .reset);
            continue;
        };
        try config.setColor(writer, .bright_green);
        try writer.writeAll(" passed\n");
        try config.setColor(writer, .reset);
    }
}
