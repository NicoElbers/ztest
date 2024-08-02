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
    pub fn runTest(self: Self, tst: Test) !void {
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

    pub fn displayResult(self: Self, res: TestRes) !void {
        try res.displayResult(self.printer);
    }
};

// ---- Internal representation for results ----

// TODO: Rename to TestResult
pub const TestRes = struct {
    // TODO: Rename to type?
    typ: TestType,
    // TODO: Rename to smth better
    raw_result: anyerror!void,

    fn displayReturn(self: TestRes, printer: Printer) !void {
        if (std.meta.isError(self.raw_result)) {
            try printer.setColor(.red);
            try printer.writeAll(" not passed");
            try printer.setColor(.reset);
        } else {
            try printer.setColor(.bright_green);
            try printer.writeAll(" passed");
            try printer.setColor(.reset);
        }
    }

    pub fn displayResult(self: TestRes, printer: Printer) !void {
        // FIXME: Don't use global state
        switch (self.typ) {
            .builtin => {
                // Restore saved cursor location
                try printer.moveUpLine(TestRunner.lines_moved);
                try printer.loadCursorPosition();

                try self.displayReturn(printer);

                try printer.moveToStartOfLine();
                try printer.moveDownLine(TestRunner.lines_moved);

                TestRunner.lines_moved = 0;
            },
            // TODO: When a parameterized test passes I want a number after the builtin test name
            .parameterized => {
                if (std.meta.isError(self.raw_result)) {
                    // TODO: Display the inputs here
                    try self.displayReturn(printer);

                    try printer.moveToStartOfLine();
                    try printer.moveDownLine(TestRunner.lines_moved);

                    TestRunner.lines_moved += 1;
                    return;
                }
                try printer.clearLine();
            },
        }
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
