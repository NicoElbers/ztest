// TODO: Structure this file out over multiple files so that everything is more ledgeable

const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

const assert = std.debug.assert;

const io = std.io;
const colors = io.tty;
const windows = std.os.windows;

const ResultPrinter = @import("ResultPrinter.zig");
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
        const test_fn_info = @typeInfo(@TypeOf(test_fn.func));
        comptime assert(test_fn_info == .Pointer);
        comptime assert(test_fn_info.Pointer.is_const);
        comptime assert(test_fn_info.Pointer.child == fn () anyerror!void);

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
    alloc: Allocator,
    printer: ResultPrinter,
    error_count: usize = 0,

    const Self = @This();

    pub fn initDefault() TestRunner {
        const output_file = std.io.getStdOut();
        const alloc = std.testing.allocator;
        const printer = ResultPrinter.init(alloc, output_file);

        return TestRunner{
            .alloc = alloc,
            .printer = printer,
        };
    }

    pub fn deinit(self: *TestRunner) void {
        self.printer.deinit();
    }

    pub fn runTest(self: *Self, tst: Test) !void {
        self.printer.initTest(tst.name, null);

        // FIXME: I'm not using test res anymore, simplify
        const res = tst.run();

        const status: ResultPrinter.TestInformation.Status = blk: {
            res.raw_result catch |err| switch (err) {
                error.SkipZigTest => break :blk .skipped,
                else => break :blk .{ .failed = err },
            };
            break :blk .passed;
        };

        self.printer.updateTest(tst.name, status);

        // Return the error to the party calling the test
        // TODO: Change this into ?ErrorMessage or something
        // FIXME: Make it more obvious that this is the test result and not an error.
        return res.raw_result;
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
    defer runner.deinit();

    for (builtin.test_functions) |test_fn| {
        runner.runTest(Test.initBuiltin(test_fn)) catch {};
    }

    try runner.printer.printResults();
    // try runner.displayErrorCount();
}

test {
    _ = @import("Printer.zig");
    _ = @import("ResultPrinter.zig");
}
