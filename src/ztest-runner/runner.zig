// TODO: Structure this file out over multiple files so that everything is more ledgeable

const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const io = std.io;
const colors = io.tty;
const windows = std.os.windows;

const Printer = @import("Printer.zig");
const Color = std.io.tty.Color;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

const BuiltinTestFn = std.builtin.TestFn;

// TODO: Make this more unique with underscores and shit
pub const IsZtestRunner = void;

// ---- Types exposed to ztest ----

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
            .raw_result = res,
        };
    }
};

pub const TestRunner = struct {
    // FIXME: Don't use global state
    var lines_moved: u15 = 0;

    alloc: Allocator,
    printer: Printer,
    error_count: usize = 0,

    const Self = @This();

    pub fn initDefault() TestRunner {
        const output_file = std.io.getStdOut();
        const alloc = std.testing.allocator;
        const printer = Printer.init(output_file, alloc);

        return TestRunner{
            .alloc = alloc,
            .printer = printer,
        };
    }

    // FIXME: These 3 functions are a mess, make it better
    pub fn runTest(self: *Self, tst: Test) !void {
        try self.displayName(tst);

        const res = tst.run();
        try self.displayResult(res);

        // Return the error to the party calling the test
        // TODO: Change this into ?ErrorMessage or something
        // FIXME: Make it more obvious that this is the test result and not an error.
        return res.raw_result;
    }

    pub fn displayName(self: Self, tst: Test) !void {
        try self.printer.writeAll(tst.name);

        if (tst.typ == .builtin) {
            try self.printer.saveCursorPosition();
            try self.printer.moveDownLine(1);
            TestRunner.lines_moved = 1;
        }
    }

    pub fn displayResult(self: *Self, res: TestRes) !void {
        switch (res.typ) {
            .builtin => {
                // Restore saved cursor location
                try self.printer.moveUpLine(TestRunner.lines_moved);
                try self.printer.loadCursorPosition();

                try self.displayReturn(res);

                try self.printer.moveToStartOfLine();
                try self.printer.moveDownLine(TestRunner.lines_moved);

                TestRunner.lines_moved = 0;
            },
            // TODO: When a parameterized test passes I want a number after the builtin test name
            .parameterized => {
                if (std.meta.isError(res.raw_result)) {
                    // TODO: Display the inputs here
                    try self.displayReturn(res);

                    try self.printer.moveToStartOfLine();
                    try self.printer.moveDownLine(TestRunner.lines_moved);

                    TestRunner.lines_moved += 1;
                    return;
                }
                try self.printer.clearLine();
            },
        }
    }

    fn displayReturn(self: *Self, res: TestRes) !void {
        if (std.meta.isError(res.raw_result)) {
            self.error_count += 1;
            try self.printer.setColor(.red);
            try self.printer.writeAll(" not passed");
            try self.printer.setColor(.reset);
        } else {
            try self.printer.setColor(.bright_green);
            try self.printer.writeAll(" passed");
            try self.printer.setColor(.reset);
        }
    }

    pub fn displayErrorCount(self: Self) !void {
        if (self.error_count == 0) return;
        try self.printer.writeAll("Failed ");
        try self.printer.setColor(.red);
        try self.printer.printFmt("{d}", .{self.error_count});
        try self.printer.setColor(.reset);
        try self.printer.writeAll(" tests\n");
    }
};

// ---- Internal representation for results ----

// TODO: Rename to TestResult
pub const TestRes = struct {
    // TODO: Rename to type?
    typ: TestType,
    // TODO: Rename to smth better
    raw_result: anyerror!void,
};

// ---- Bare bones main method ----

pub fn main() !void {
    std.testing.log_level = .warn;

    var runner = TestRunner.initDefault();

    for (builtin.test_functions) |test_fn| {
        runner.runTest(Test.initBuiltin(test_fn)) catch {};
    }

    try runner.displayErrorCount();
}
