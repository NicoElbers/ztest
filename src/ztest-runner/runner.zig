const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const io = std.io;
const colors = io.tty;

const Config = std.io.tty.Config;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const BuiltinTestFn = std.builtin.TestFn;

// TODO: Make this more unique with underscores and shit
pub const IsZtestRunner = void;

// ---- Types needed to communicate with test runner ----

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

// TODO: Rename to TestResult
pub const TestRes = struct {
    // TODO: Rename to type?
    typ: TestType,
    // TODO: Rename to smth better
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
    // FIXME: Don't take in TestRunner
    pub fn displayResult(self: TestRes, runner: TestRunner, writer: anytype, config: Config) !void {
        switch (self.typ) {
            .builtin => {
                // Restore saved cursor location
                // FIXME: Factor this out into less magic numbers
                const reset_str = try std.fmt.allocPrint(
                    runner.alloc,
                    "\x1b[{d}F\x1b[u",
                    .{TestRunner.lines_moved},
                );
                defer runner.alloc.free(reset_str);
                try writer.writeAll(reset_str);

                try self.displayReturn(config, writer);

                // FIXME: Factor this out into less magic numbers
                const reset_str = try std.fmt.allocPrint(
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
                // FIXME: Factor this out into less magic numbers
                try writer.writeAll("\x1b[G");
                try writer.writeAll("\x1b[K");
            },
        }
    }
};

// ---- Test runner itself ----

pub const TestRunner = struct {
    // FIXME: Don't use global state
    var lines_moved: u16 = 0;

    // TODO: Create some "output" struct with a writer and color config combined
    output_file: File,
    alloc: Allocator,

    const Self = @This();

    pub fn initDefault() TestRunner {
        const output_file = std.io.getStdOut();
        const alloc = std.testing.allocator;

        return TestRunner{
            .output_file = output_file,
            .alloc = alloc,
            .printer = printer,
        };
    }

    pub fn runTest(self: Self, tst: Test) !void {
        try self.displayName(tst);

        const res = tst.run();
        try self.displayResult(res);

        // Return the error to the party calling the test
        // TODO: Change this into ?ErrorMessage or something
        return res.res;
    }

    pub fn displayName(self: Self, tst: Test) !void {
        const writer = self.output_file.writer();

        try writer.writeAll(tst.name);

        // FIXME: Factor this out into less magic numbers
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

    const runner = TestRunner.initDefault();

    for (builtin.test_functions) |test_fn| {
        runner.runTest(Test.initBuiltin(test_fn)) catch {};
    }
}
