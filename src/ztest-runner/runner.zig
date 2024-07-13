const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const io = std.io;
const colors = io.tty;

const Config = std.io.tty.Config;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const BuiltinTestFn = std.builtin.TestFn;

// ---- Shared state for test to observe ----
pub const IsZtestRunner = void;
pub var clientUsingZtest: bool = false;

pub var current_test_info: Test = undefined;

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

pub const TestType = enum {
    builtin,
    parameterized,
};

pub const Test = struct {
    const Self = @This();

    typ: TestType,
    name: []const u8,
    func: *const fn (*const anyopaque) anyerror!void,
    args: *const anyopaque,

    pub fn initBuiltin(test_fn: BuiltinTestFn) Self {
        const func = struct {
            pub fn wrapper(ptr: *const anyopaque) anyerror!void {
                // TODO: Comptime assert that BuiltinTestFn.func == *const fn() anyerror!void
                const func: *const fn () anyerror!void = @ptrCast(@alignCast(ptr));
                return func();
            }
        }.wrapper;

        return Self{
            .typ = .builtin,
            .name = test_fn.name,
            .func = func,
            .args = test_fn.func,
        };
    }

    pub fn run(self: Self) TestRes {
        const res = self.func(self.args);

        return TestRes{
            .typ = self.typ,
            .res = res,
        };
    }
};

pub const TestRes = struct {
    typ: TestType,
    res: anyerror!void,

    fn displayReturn(self: TestRes, config: Config, writer: anytype) !void {
        if (std.meta.isError(self.res)) {
            try config.setColor(writer, .red);
            try writer.writeAll(" not passed");
            try config.setColor(writer, .reset);
        } else {
            try config.setColor(writer, .bright_green);
            try writer.writeAll(" passed");
            try config.setColor(writer, .reset);
        }
    }

    /// Returns true if we displayed something
    pub fn displayResult(self: TestRes, runner: TestRunner, writer: anytype, config: Config) !void {
        switch (self.typ) {
            .builtin => {
                // Restore saved cursor location
                const reset_str = try std.fmt.allocPrint(
                    runner.alloc,
                    "\x1b[{d}F\x1b[u",
                    .{TestRunner.lines_moved},
                );
                defer runner.alloc.free(reset_str);
                try writer.writeAll(reset_str);

                try self.displayReturn(config, writer);

                const replace_str = try std.fmt.allocPrint(
                    runner.alloc,
                    "\x1b[{d}E",
                    .{TestRunner.lines_moved},
                );
                defer runner.alloc.free(replace_str);
                try writer.writeAll(replace_str);

                TestRunner.lines_moved = 0;
            },
            .parameterized => {
                if (std.meta.isError(self.res)) {
                    // TODO: Display the inputs here
                    try self.displayReturn(config, writer);
                    try writer.writeAll("\n");
                    TestRunner.lines_moved += 1;
                    return;
                }
                // reset line
                try writer.writeAll("\x1b[G");
                try writer.writeAll("\x1b[K");
            },
        }
    }
};

// ---- Test runner itself ----

pub const TestRunner = struct {
    var lines_moved: u16 = 0;

    output_file: File = std.io.getStdOut(),
    alloc: Allocator = std.testing.allocator,

    const Self = @This();

    pub fn runTest(self: Self, tst: Test) !void {
        // Advertise current test
        current_test_info = tst;

        try self.displayName(tst);

        const res = tst.run();
        try self.displayResult(res);

        // Show the error to the party calling the test
        // TODO: Change this into ?ErrorMessage or something
        return res.res;
    }

    pub fn displayName(self: Self, tst: Test) !void {
        const writer = self.output_file.writer();

        try writer.writeAll(tst.name);

        if (tst.typ == .builtin) {
            // Save cursor position
            try writer.writeAll("\x1b[s");
            try writer.writeAll("\n");
            TestRunner.lines_moved = 1;
        }
    }

    pub fn displayResult(self: Self, res: TestRes) !void {
        const config = colors.detectConfig(self.output_file);
        const writer = self.output_file.writer();

        try res.displayResult(self, writer, config);
    }
};

// ---- Bare bones main method ----

pub fn main() !void {
    std.testing.log_level = .warn;

    for (builtin.test_functions) |test_fn| {
        test_runner.runTest(Test.initBuiltin(test_fn)) catch {};
    }
}
