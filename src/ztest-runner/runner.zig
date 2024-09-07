// TODO: Structure this file out over multiple files so that everything is more ledgeable

const std = @import("std");
const IPC = @import("runnerIPC/root.zig");
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

// Compatibility with std runner

pub fn fuzzInput(arg: anytype) []const u8 {
    _ = arg;

    std.log.err("Fuzzing not supported by ztest yet", .{});
    return "";
}

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
        comptime assert(test_fn_info == .pointer);
        comptime assert(test_fn_info.pointer.is_const);
        comptime assert(test_fn_info.pointer.child == fn () anyerror!void);

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

    pub const TestReturn = struct { err: ?anyerror };

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

    pub fn runTest(self: *Self, tst: Test) !TestReturn {
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

        if (res.raw_result) {
            return .{ .err = null };
        } else |err| {
            return .{ .err = err };
        }
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

const Args = enum {
    @"--client",
};

const ProcessFunction = enum(u1) { server, client };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    std.testing.log_level = .warn;

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var process_state: ProcessFunction = .server;
    for (args) |arg| {
        const arg_enum = std.meta.stringToEnum(Args, arg) orelse continue;

        switch (arg_enum) {
            .@"--client" => process_state = .client,
        }
    }

    switch (process_state) {
        .server => return serverFn(args[0], alloc),
        .client => return clientFn(alloc),
    }
}

fn serverFn(argv0: [:0]const u8, alloc: Allocator) !void {
    var child = std.process.Child.init(&.{ argv0, @tagName(Args.@"--client") }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    errdefer _ = child.kill() catch std.log.err("Couldn't kill child with pgid {?d}", .{child.pgid});

    var server = IPC.Server.init(alloc, child);
    defer server.deinit();

    const tests = builtin.test_functions;
    try server.serveRunTest(0, tests.len);

    const State = enum { nothing, in_test, in_parameterized_test };

    var tests_to_see: usize = tests.len;
    var failures: usize = 0;
    var state: State = .nothing;
    while (tests_to_see > 0) {
        std.debug.print("Waiting for message\n", .{});
        const msg: IPC.Message = switch (try server.receiveMessage(alloc)) {
            .streamClosed => unreachable, // Client died unexpectedly
            .timedOut => continue,
            .message => |msg| msg,
        };
        defer alloc.free(msg.bytes);

        std.debug.print("Got message: {s}\n", .{@tagName(msg.header.tag)});

        switch (msg.header.tag) {
            .testStart => {
                assert(state == .nothing);
                state = .in_test;
            },

            .testSuccess => {
                assert(state == .in_test);
                tests_to_see -= 1;
                state = .nothing;
            },

            .testFailure => {
                assert(state == .in_test);
                failures += 1;
                tests_to_see -= 1;
                state = .nothing;
            },

            .parameterizedStart => {
                assert(state == .in_test);
                state = .in_parameterized_test;
            },

            .parameterizedSuccess => {
                assert(state == .in_parameterized_test);
                state = .in_test;
            },
            .parameterizedSkipped => {
                assert(state == .in_parameterized_test);
                state = .in_test;
            },

            .parameterizedError => {
                assert(state == .in_parameterized_test);
                failures += 1;
                state = .in_test;
            },

            .runTests,
            .exit,
            => unreachable, // May only be sent by the server
        }
    }

    try server.serveExit();
    const term = try child.wait();
    std.debug.print("Process exit: {any}\n", .{term});
}

fn clientFn(alloc: Allocator) !void {
    var client = IPC.Client.init(alloc);
    defer client.deinit();

    var runner = TestRunner.initDefault();
    defer runner.deinit();

    loop: while (true) {
        const msg: IPC.Message = switch (try client.receiveMessage(alloc)) {
            .streamClosed => unreachable, // Client should never die before the server
            .timedOut => continue,
            .message => |msg| msg,
        };
        defer alloc.free(msg.bytes);
        assert(msg.bytes.len == msg.header.bytes_len);

        switch (msg.header.tag) {
            .exit => break :loop,

            .runTests => {
                assert(msg.header.bytes_len == @sizeOf(usize) * 2);

                const start_idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);
                const end_idx = std.mem.readInt(usize, msg.bytes[@sizeOf(usize)..(@sizeOf(usize) * 2)], .little);

                for (builtin.test_functions[start_idx..end_idx], start_idx..end_idx) |test_fn, idx| {
                    try client.serveTestStart(idx);

                    const res = runner.runTest(Test.initBuiltin(test_fn)) catch
                        @panic("Internal server error");

                    if (res.err) |_| {
                        // FIXME: Actually send over the error
                        try client.serveTestFailure(idx);
                    } else {
                        try client.serveTestSuccess(idx);
                    }
                }

                try runner.printer.printResults();
            },

            .parameterizedStart,
            .parameterizedError,
            .parameterizedSkipped,
            .parameterizedSuccess,
            .testStart,
            .testSuccess,
            .testFailure,
            => unreachable, // May only be sent by client
        }
    }
}

test {
    _ = @import("Printer.zig");
    _ = @import("ResultPrinter.zig");
}
