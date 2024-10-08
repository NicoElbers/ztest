const debug = false;

// Compatibility with std runner
pub fn fuzzInput(arg: anytype) []const u8 {
    _ = arg;

    std.log.err("Fuzzing not supported by ztest yet", .{});
    return "";
}

// TODO: Make this more unique with underscores and shit
pub const IsZtestRunner = void;

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
    for (args[1..]) |arg| {
        const arg_enum = std.meta.stringToEnum(Args, arg) orelse {
            std.log.err("Unknown arg: '{s}'", .{arg});
            continue;
        };

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

        requested_test,

        /// Usize represents the index into builtin.test_functions
        running_test: usize,

        /// Usize represents the index into builtin.test_functions or parent test
        running_parameterized_test: usize,
    };

    const tests = builtin.test_functions;

    const out_file = std.io.getStdOut();

    var res_printer = try ResultPrinter.init(alloc, tests.len, out_file);
    defer res_printer.deinit();

    // We assume that the terminal doesn't resize while tests are being ran.
    const terminal_width = try res_printer.printer.getTerminalWidth() orelse 80;

    var child = std.process.Child.init(&.{ argv0, @tagName(Args.@"--client") }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    errdefer _ = child.kill() catch std.log.err("Couldn't kill child with pgid {?d}", .{child.pgid});

    var server = Node(.server).init(alloc, child);
    defer server.deinit();

    var test_idx: usize = 0;
    var failures: u32 = 0;
    var state: State = .nothing;

    while (test_idx < builtin.test_functions.len) {
        if (state == .nothing) {
            dbg("requesting test {d}", .{test_idx});

            try server.serveRunTest(test_idx);
            state = .requested_test;
        }

        const msg: Message = switch (try server.receiveMessage(alloc)) {
            .streamClosed => unreachable, // Client died unexpectedly
            .timedOut => continue,
            .message => |msg| msg,
        };
        defer alloc.free(msg.bytes);
        dbg("Got message: {any}", .{msg.header});

        switch (msg.header.tag) {
            .testStart => {
                assert(state == .requested_test);

                assert(msg.bytes.len == @sizeOf(usize));
                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);

                res_printer.updateTestStatus(idx, .busy);

                state = .{ .running_test = idx };
            },

            .testSuccess => {
                assert(state == .running_test);

                assert(msg.bytes.len == @sizeOf(usize));
                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);

                res_printer.updateTestStatus(idx, .passed);

                const logs = try server.process_streamer.getRemoveLogs(terminal_width, res_printer.alloc);
                defer res_printer.alloc.free(logs);

                try res_printer.addTestLogs(test_idx, logs);

                test_idx += 1;
                state = .nothing;
            },

            .testSkipped => {
                assert(state == .running_test);

                assert(msg.bytes.len == @sizeOf(usize));
                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);

                res_printer.updateTestStatus(idx, .skipped);

                const logs = try server.process_streamer.getRemoveLogs(terminal_width, res_printer.alloc);
                defer res_printer.alloc.free(logs);

                try res_printer.addTestLogs(idx, logs);

                test_idx += 1;
                state = .nothing;
            },

            .testFailure => {
                const Failure = Message.TestFailure;
                const size = @sizeOf(Failure);

                if (state == .running_parameterized_test) {
                    res_printer.updateLastPtestStatus(
                        state.running_parameterized_test,
                        .{ .failed = error.ParameterizedPanic },
                    );

                    state = .{ .running_test = state.running_parameterized_test };
                }

                assert(state == .running_test);

                assert(msg.bytes.len >= size);
                const failure: Failure = @bitCast(msg.bytes[0..size].*);

                assert(msg.bytes.len == size + failure.error_name_len);
                const error_name = msg.bytes[size..(size + failure.error_name_len)];
                _ = error_name;

                res_printer.updateTestStatus(failure.test_idx, .{ .failed = error.TODO });

                const logs = try server.process_streamer.getRemoveLogs(terminal_width, res_printer.alloc);
                defer res_printer.alloc.free(logs);

                try res_printer.addTestLogs(test_idx, logs);

                failures += 1;
                test_idx += 1;
                state = .nothing;
            },

            .parameterizedStart => {
                const idx: usize = switch (state) {
                    .running_test,
                    .running_parameterized_test,
                    => |idx| idx,
                    else => unreachable,
                };

                const args_fmt = msg.bytes;

                try res_printer.initParameterizedTest(idx, args_fmt);

                state = .{ .running_parameterized_test = idx };
            },

            .parameterizedComplete => {
                assert(state == .running_parameterized_test);

                const idx = state.running_parameterized_test;

                state = .{ .running_test = idx };
            },

            .parameterizedSkipped => {
                assert(state == .running_parameterized_test);

                const idx = state.running_parameterized_test;

                res_printer.updateLastPtestStatus(idx, .skipped);
            },

            .parameterizedError => {
                assert(state == .running_parameterized_test);

                const idx = state.running_parameterized_test;

                res_printer.updateLastPtestStatus(idx, .{ .failed = error.TODO });

                failures += 1;
            },

            .runTest,
            .exit,
            => unreachable, // May only be sent by the server
        }

        if (!debug)
            try res_printer.printResults(tests);
    }

    dbg("Serving exit", .{});
    try server.serveExit();

    const term = try child.wait();
    dbg("Process exit: {any}", .{term});
}

fn clientFn(alloc: Allocator) !void {
    var client = Node(.client).init(alloc);
    defer client.deinit();

    loop: while (true) {
        const msg: Message = switch (try client.receiveMessage(alloc)) {
            .streamClosed => unreachable, // Client should never die before the server
            .timedOut => continue,
            .message => |msg| msg,
        };
        defer alloc.free(msg.bytes);
        assert(msg.bytes.len == msg.header.bytes_len);

        dbg("Client got message: {s}", .{@tagName(msg.header.tag)});

        switch (msg.header.tag) {
            .exit => break :loop,

            .runTest => {
                assert(msg.header.bytes_len == @sizeOf(usize));

                const idx = std.mem.readInt(usize, msg.bytes[0..@sizeOf(usize)], .little);
                assert(idx < builtin.test_functions.len);

                try client.serveTestStart(idx);

                builtin.test_functions[idx].func() catch |err| {
                    switch (err) {
                        error.ZigSkipTest => try client.serveTestSkipped(idx),
                        else => try client.serveTestFailure(idx),
                    }
                    continue;
                };

                try client.serveTestSuccess(idx);
            },

            .parameterizedStart,
            .parameterizedError,
            .parameterizedSkipped,
            .parameterizedComplete,
            .testStart,
            .testSuccess,
            .testSkipped,
            .testFailure,
            => unreachable, // May only be sent by client
        }
    }
}

pub fn dbg(comptime fmt: []const u8, args: anytype) void {
    if (!debug) return;

    std.debug.print(fmt ++ "\n", args);
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
const Node = IPC.Node;
const Message = IPC.Message;

const BuiltinTestFn = std.builtin.TestFn;
