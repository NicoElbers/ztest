const std = @import("std");
const IPC = @import("src/runnerIPC/root.zig");

const Server = IPC.Server;
const Client = IPC.Client;
const Child = std.process.Child;
const Allocator = std.mem.Allocator;

fn print(comptime msg: []const u8) void {
    printf(msg, .{});
}

fn printf(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len == 1) {
        return parentFn(args[0], alloc);
    } else {
        return childFn(alloc);
    }
}

pub fn childFn(gpa: Allocator) !void {
    var client = Client.init(gpa);
    defer client.deinit();
    defer print("Client shutting down");

    print("serving msg");
    try client.serveStringMessage(.rawString, "Hello from client!");
    print("Done serving msg");

    while (true) {
        const message = switch (try client.receiveMessage(gpa)) {
            .Message => |msg| msg,
            .TimedOut => {
                continue;
            },
            .StreamClosed => {
                print("Stream closed");
                printf("stdin: {s}", .{client.process_streamer.stdin_content.items});
                return;
            },
        };
        defer gpa.free(message.bytes);

        printf("Got message: {any}", .{message});

        switch (message.header.tag) {
            .rawString => printf("{s}", .{message.bytes}),
            .exit => return,
            else => unreachable,
        }
    }
}

pub fn parentFn(arg0: [:0]const u8, gpa: Allocator) !void {
    var child = Child.init(&.{ arg0, "asdf" }, gpa);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.stdin_behavior = .Pipe;

    try child.spawn();
    // errdefer _ = child.kill() catch @panic(":(");

    var server = Server.init(gpa, child);
    defer server.deinit();

    while (true) {
        const message = switch (try server.receiveMessage(gpa)) {
            .Message => |msg| msg,
            .TimedOut => continue,
            .StreamClosed => unreachable,
        };
        defer gpa.free(message.bytes);

        switch (message.header.tag) {
            .rawString => printf("received: {s}", .{message.bytes}),
            else => unreachable,
        }

        break;
    }

    print("Sending string");
    try server.serveStringMessage(.rawString, "Hello from server!");
    print("serving exit");
    try server.serveExit();

    const timer = try std.time.Instant.now();
    while ((try std.time.Instant.now()).since(timer) < std.time.ns_per_s * 30) {
        switch (try server.receiveMessage(gpa)) {
            .Message => |thing| printf("got: {any}", .{thing}),
            .TimedOut => continue,
            .StreamClosed => break,
        }
    }

    _ = try child.kill();

    for (server.process_streamer.output_metadata.items) |item| {
        const array_list = switch (item.tag) {
            .stdout => server.process_streamer.stdout_content,
            .stderr => server.process_streamer.stderr_content,
        };

        const full_slice = array_list.items[item.start_idx..(item.start_idx + item.len)];

        var last_idx: usize = 0;
        for (full_slice, 0..) |char, idx| {
            if (char != '\n') continue;

            printf("{s} | {s}", .{
                @tagName(item.tag),
                full_slice[last_idx..idx],
            });

            last_idx = idx + 1;
        }
        if (last_idx != full_slice.len) {
            printf("{s} | {s}", .{
                @tagName(item.tag),
                full_slice[last_idx..],
            });
        }
    }
}
