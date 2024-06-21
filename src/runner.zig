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


pub const test_runner: TestRunner = TestRunner{};

// ---- Types needed to communicate with test runner ----

pub const TestFn = struct {
    const Self = @This();

    name: []const u8,
    func: *const fn (*const anyopaque) anyerror!void,
    arg: *const anyopaque,

    pub fn run(self: Self) anyerror!void {
        try self.func(self.arg);
    }
};

pub const TestType = union(enum) {
    builtin: BuiltinTestFn,
    testFn: TestFn,

    const Self = @This();

    pub fn run(self: Self) !void {
        return switch (self) {
            .testFn => |tst| tst.run(),
            .builtin => |tst| tst.func(),
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .testFn => |tst| tst.name,
            .builtin => |tst| tst.name,
        };
    }
};

// ---- Test runner itself ----

pub const TestRunner = struct {
    output_file: File = std.io.getStdOut(),

    const Self = @This();

    pub fn runTest(self: Self, test_type: TestType) !void {
        const res = test_type.run();
        const name = test_type.name();

        try self.displayResult(name, res);
    }

    pub fn displayResult(self: Self, name: []const u8, res: anyerror!void) !void {
        const ouput_file = self.output_file;

        const config = colors.detectConfig(ouput_file);
        const writer = ouput_file.writer();

        try writer.writeAll(name);

        if (std.meta.isError(res)) {
            try config.setColor(writer, .red);
            try writer.writeAll(" not passed\n");
            try config.setColor(writer, .reset);
        } else {
            try config.setColor(writer, .bright_green);
            try writer.writeAll(" passed\n");
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
