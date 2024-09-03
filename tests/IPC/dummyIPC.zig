const gpa = ztest.allocator;

const expect = ztest.expect;

const File = std.fs.File;
const Server = IPC.Server;
const ServerStreamer = IPC.ServerStreamer;
const Client = IPC.Client;
const ClientStreamer = IPC.ClientStreamer;
const Message = IPC.Message;

test "server timeout" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;

    // Wait for one second
    const res = waitForMessageTimeout(server, msg_timeout);

    // try expect(res).isError(@errorCast(error.MessageTookTooLong));
    // https://github.com/ziglang/zig/issues/21222
    _ = res catch |err| switch (err) {
        error.MessageTookTooLong => return,
        else => return err,
    };
    return error.NotAnError;
}

test "client timeout" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const client = &setup.client;

    // Wait for one second
    const res = waitForMessageTimeout(client, msg_timeout);

    // try expect(res).isError(@errorCast(error.MessageTookTooLong));
    // https://github.com/ziglang/zig/issues/21222
    _ = res catch |err| switch (err) {
        error.MessageTookTooLong => return,
        else => return err,
    };
    return error.NotAnError;
}

test "server clean message" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;

    const server_message = "Hello from server";
    try server.serveStringMessage(.runTests, server_message);

    const message = try waitForMessageTimeout(client, msg_timeout);
    defer gpa.free(message.bytes);

    try expect(message).isEqualTo(Message{
        .header = .{ .tag = .runTests, .bytes_len = server_message.len },
        .bytes = server_message,
    });
}

test "client clean message" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;

    const client_message = "Hello from client";
    try client.serveStringMessage(.runTests, client_message);

    const message = try waitForMessageTimeout(server, msg_timeout);
    defer gpa.free(message.bytes);

    try expect(message).isEqualTo(Message{
        .header = .{ .tag = .runTests, .bytes_len = client_message.len },
        .bytes = client_message,
    });
}

test "server noisy message" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;
    const stdin = &setup.stdin.write_file;

    try stdin.writeAll("Noise");

    const server_message = "Hello from server";
    try server.serveStringMessage(.runTests, server_message);

    try stdin.writeAll("Noise");

    const message = try waitForMessageTimeout(client, msg_timeout);
    defer gpa.free(message.bytes);

    try expect(message).isEqualTo(Message{
        .header = .{ .tag = .runTests, .bytes_len = server_message.len },
        .bytes = server_message,
    });
}

test "client noisy message" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;
    const stdout = &setup.stdout.write_file;

    try stdout.writeAll("Noise");

    const client_message = "Hello from client";
    try client.serveStringMessage(.runTests, client_message);

    try stdout.writeAll("Noise");

    const message = try waitForMessageTimeout(server, msg_timeout);
    defer gpa.free(message.bytes);

    try expect(message).isEqualTo(Message{
        .header = .{ .tag = .runTests, .bytes_len = client_message.len },
        .bytes = client_message,
    });
}

test "active communication" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;

    const msg1_expected = "raw string";
    try server.serveStringMessage(.runTests, msg1_expected);

    const msg1 = try waitForMessageTimeout(client, msg_timeout);
    defer gpa.free(msg1.bytes);

    try expect(msg1).isEqualTo(Message{
        .header = .{ .tag = .runTests, .bytes_len = msg1_expected.len },
        .bytes = msg1_expected,
    });

    const msg2_expected = "pram skipped";
    try client.serveStringMessage(.parameterizedSkipped, msg2_expected);

    const msg2 = try waitForMessageTimeout(server, msg_timeout);
    defer gpa.free(msg2.bytes);

    try expect(msg2).isEqualTo(Message{
        .header = .{ .tag = .parameterizedSkipped, .bytes_len = msg2_expected.len },
        .bytes = msg2_expected,
    });

    try server.serveExit();

    const msg3 = try waitForMessageTimeout(client, msg_timeout);
    try expect(msg3).isEqualTo(Message{
        .header = .{ .tag = .exit, .bytes_len = 0 },
        .bytes = &.{},
    });
}

test "server message with multithreaded noise" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;

    var wg = WaitGroup{};
    wg.start();

    const thread = try Thread.spawn(.{}, noiseMaker, .{ &wg, server.out });

    const msg_string = "Hello from server";
    for (0..100) |_| {
        try server.serveStringMessage(.runTests, msg_string);

        const msg = try waitForMessageTimeout(client, msg_timeout);
        defer gpa.free(msg.bytes);

        try expect(msg).isEqualTo(.{
            .header = .{ .tag = .runTests, .bytes_len = msg_string.len },
            .bytes = msg_string,
        });
    }

    wg.finish();
    thread.join();
}

test "client message with multithreaded noise" {
    var setup = IPCSetup.setup();
    defer setup.cleanup();

    const server = &setup.server;
    const client = &setup.client;

    var wg = WaitGroup{};
    wg.start();

    const thread = try Thread.spawn(.{}, noiseMaker, .{ &wg, client.out });

    const msg_string = "Hello from client";
    for (0..100) |_| {
        try client.serveStringMessage(.runTests, msg_string);

        const msg = try waitForMessageTimeout(server, msg_timeout);
        defer gpa.free(msg.bytes);

        try expect(msg).isEqualTo(.{
            .header = .{ .tag = .runTests, .bytes_len = msg_string.len },
            .bytes = msg_string,
        });
    }

    wg.finish();
    thread.join();
}

fn noiseMaker(wg: *WaitGroup, file: File) !void {
    while (!wg.isDone()) {
        try file.writeAll("Noise");
        try Thread.yield();
    }
}

pub const Pipe = struct {
    read_file: File,
    write_file: File,

    pub fn createPipe() !Pipe {
        if (os == .windows) unreachable;

        const fds = try posix.pipe2(.{ .CLOEXEC = true });
        return .{
            .read_file = .{ .handle = fds[0] },
            .write_file = .{ .handle = fds[1] },
        };
    }

    pub fn destroy(self: Pipe) void {
        if (os == .windows) unreachable;

        if (self.read_file.handle != -1) std.posix.close(self.read_file.handle);
        if (self.read_file.handle != self.write_file.handle) std.posix.close(self.write_file.handle);
    }
};

pub fn makeDummyServer(child_stdin: File, child_stdout: File, child_stderr: File) Server {
    return Server{
        .process_streamer = ServerStreamer.init(
            gpa,
            child_stdout,
            child_stderr,
        ),
        .out = child_stdin,
    };
}

pub fn makeDummyClient(child_stdin: File, child_stdout: File) Client {
    return Client{
        .process_streamer = ClientStreamer.init(
            gpa,
            child_stdin,
        ),
        .out = child_stdout,
    };
}

pub fn waitForMessageTimeout(node: anytype, timeout_ns: u64) !Message {
    const Instant = std.time.Instant;
    const timer = try Instant.now();
    while ((try Instant.now()).since(timer) <= timeout_ns) {
        switch (try node.receiveMessage(gpa)) {
            .StreamClosed => return error.StreamClosed,
            .TimedOut => continue,
            .Message => |msg| return msg,
        }
    }
    return error.MessageTookTooLong;
}

const msg_timeout = std.time.ns_per_ms * 50;

pub const IPCSetup = struct {
    stdin: Pipe,
    stdout: Pipe,
    stderr: Pipe,

    server: Server,
    client: Client,

    pub fn setup() IPCSetup {
        const stdin = Pipe.createPipe() catch @panic("setup panic");
        errdefer stdin.destroy();

        const stdout = Pipe.createPipe() catch @panic("setup panic");
        errdefer stdout.destroy();

        const stderr = Pipe.createPipe() catch @panic("setup panic");
        errdefer stderr.destroy();

        var server = makeDummyServer(
            stdin.write_file,
            stdout.read_file,
            stderr.read_file,
        );
        errdefer server.deinit();

        var client = makeDummyClient(
            stdin.read_file,
            stdout.write_file,
        );
        errdefer client.deinit();

        return IPCSetup{
            .stdin = stdin,
            .stdout = stdout,
            .stderr = stderr,

            .server = server,
            .client = client,
        };
    }

    pub fn cleanup(self: *IPCSetup) void {
        self.stdin.destroy();
        self.stdout.destroy();
        self.stderr.destroy();

        self.server.deinit();
        self.client.deinit();
    }
};

const std = @import("std");
const ztest = @import("ztest");
const IPC = @import("IPC");
const builtin = @import("builtin");

const Thread = std.Thread;
const WaitGroup = Thread.WaitGroup;

const os = builtin.os.tag;
const windows = std.os.windows;
const posix = std.posix;
