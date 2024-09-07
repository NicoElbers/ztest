const debug = false;

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
    const State = union(enum) {
        nothing,

        /// Usize represents the index into builtin.test_functions
        in_test: usize,

        /// Usize represents the index into builtin.test_functions or parent test
        in_parameterized_test: usize,
    };

    const tests = builtin.test_functions;

    const out_file = std.io.getStdOut();

    var res_printer = try ResultPrinter.init(alloc, tests.len, out_file);
    defer res_printer.deinit();

    var child = std.process.Child.init(&.{ argv0, @tagName(Args.@"--client") }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    errdefer _ = child.kill() catch std.log.err("Couldn't kill child with pgid {?d}", .{child.pgid});

    var server = IPC.Server.init(alloc, child);
    defer server.deinit();

    try server.serveRunTest(0, tests.len);

    var tests_to_see: usize = tests.len;
    var failures: usize = 0;
    var state: State = .nothing;

    while (tests_to_see > 0) {
        const msg: IPC.Message = switch (try server.receiveMessage(alloc)) {
            .streamClosed => unreachable, // Client died unexpectedly
            .timedOut => continue,
            .message => |msg| msg,
        };
        defer alloc.free(msg.bytes);

        if (debug)
            std.debug.print("Got {s}\n", .{@tagName(msg.header.tag)});

        switch (msg.header.tag) {
            .testStart => {
                assert(state == .nothing);

                assert(msg.bytes.len == @sizeOf(usize));
                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);

                res_printer.initTest(idx);

                state = .{ .in_test = idx };
            },

            .testSuccess => {
                assert(state == .in_test);

                assert(msg.bytes.len == @sizeOf(usize));
                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);

                res_printer.updateTest(idx, .passed);

                tests_to_see -= 1;
                state = .nothing;
            },

            .testSkipped => {
                assert(state == .in_test);

                assert(msg.bytes.len == @sizeOf(usize));
                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);

                res_printer.updateTest(idx, .skipped);

                tests_to_see -= 1;
                state = .nothing;
            },

            .testFailure => {
                const Failure = Message.TestFailure;
                const size = @sizeOf(Failure);

                assert(state == .in_test);

                assert(msg.bytes.len >= size);
                const failure: Failure = @bitCast(msg.bytes[0..size].*);

                assert(msg.bytes.len == size + failure.error_name_len);
                const error_name = msg.bytes[size..(size + failure.error_name_len)];
                _ = error_name;

                res_printer.updateTest(failure.test_idx, .{ .failed = error.TODO });

                failures += 1;
                tests_to_see -= 1;
                state = .nothing;
            },

            .parameterizedStart => {
                assert(state == .in_test);

                const idx = state.in_test;

                const args_fmt = msg.bytes;

                try res_printer.initParameterizedTest(idx, args_fmt);

                state = .{ .in_parameterized_test = idx };
            },

            .parameterizedSuccess => {
                assert(state == .in_parameterized_test);

                const idx = state.in_parameterized_test;

                res_printer.updateLastPtest(idx, .passed);

                state = .{ .in_test = idx };
            },
            .parameterizedSkipped => {
                assert(state == .in_parameterized_test);

                const idx = state.in_parameterized_test;

                res_printer.updateLastPtest(idx, .skipped);

                state = .{ .in_test = idx };
            },

            .parameterizedError => {
                assert(state == .in_parameterized_test);

                const idx = state.in_parameterized_test;

                res_printer.updateLastPtest(idx, .{ .failed = error.TODO });

                failures += 1;
                state = .{ .in_test = idx };
            },

            .runTests,
            .exit,
            => unreachable, // May only be sent by the server
        }

        if (!debug)
            try res_printer.printResults(tests);
    }

    try server.serveExit();
    const term = try child.wait();
    std.debug.print("Process exit: {any}\n", .{term});
}

fn clientFn(alloc: Allocator) !void {
    var client = IPC.Client.init(alloc);
    defer client.deinit();

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

                    test_fn.func() catch |err| {
                        switch (err) {
                            error.ZigSkipTest => try client.serveTestSkipped(idx),
                            else => try client.serveTestFailure(idx),
                        }
                        continue;
                    };

                    try client.serveTestSuccess(idx);
                }
            },

            .parameterizedStart,
            .parameterizedError,
            .parameterizedSkipped,
            .parameterizedSuccess,
            .testStart,
            .testSuccess,
            .testSkipped,
            .testFailure,
            => unreachable, // May only be sent by client
        }
    }
}

test {
    _ = @import("Printer.zig");
    _ = @import("ResultPrinter.zig");
}

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
const Message = IPC.Message;

const BuiltinTestFn = std.builtin.TestFn;
