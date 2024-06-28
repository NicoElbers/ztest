const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const io = std.io;
const colors = io.tty;

const File = std.fs.File;
const BuiltinTestFn = std.builtin.TestFn;

// ---- Shared state for test to observe ----
pub const IsZtestRunner = void;
pub var clientUsingZtest: bool = false;

pub var current_test_info: TestType = undefined;

pub const test_runner: TestRunner = TestRunner{};

// ---- Types needed to communicate with test runner ----

pub const TestFn = struct {
    const Self = @This();

    name: []const u8,
    wrapped_func: *const fn (*const anyopaque) anyerror!void,
    arg: *const anyopaque,

    pub fn run(self: Self) anyerror!void {
        try self.wrapped_func(self.arg);
    }
};

pub const TestType = union(enum) {
    builtin: BuiltinTestFn,
    parameterized: TestFn,

    const Self = @This();

    pub fn run(self: Self) !void {
        return switch (self) {
            .parameterized => |tst| tst.run(),
            .builtin => |tst| tst.func(),
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .parameterized => |tst| tst.name,
            .builtin => |tst| tst.name,
        };
    }
};

// ---- Test runner itself ----

pub const TestRunner = struct {
    output_file: File = std.io.getStdOut(),

    const Self = @This();

    pub fn runTest(self: Self, test_type: TestType) !void {
        // Advertise current test
        current_test_info = test_type;

        const name = test_type.name();
        try self.displayName(name);

        const res = test_type.run();
        try self.displayResult(res);
    }

    pub fn displayName(self: Self, name: []const u8) !void {
        const ouput_file = self.output_file;

        const writer = ouput_file.writer();

        try writer.writeAll("\n");
        try writer.writeAll(name);
    }

    pub fn displayResult(self: Self, res: anyerror!void) !void {
        const ouput_file = self.output_file;

        const config = colors.detectConfig(ouput_file);
        const writer = ouput_file.writer();

        if (std.meta.isError(res)) {
            try config.setColor(writer, .red);
            try writer.writeAll(" not passed");
            try config.setColor(writer, .reset);
        } else {
            try config.setColor(writer, .bright_green);
            try writer.writeAll(" passed");
            try config.setColor(writer, .reset);
        }
    }
};

// ---- Bare bones main method ----

pub fn main() !void {
    std.testing.log_level = .warn;

    for (builtin.test_functions) |test_fn| {
        try test_runner.runTest(TestType{ .builtin = test_fn });
    }
}
