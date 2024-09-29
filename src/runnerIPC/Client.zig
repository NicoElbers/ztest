process_streamer: Poller,
out: File,

/// Child must have stdout and stderr behavior of Pipe, this ensures that the
/// stdout and stderr are valid once the child is spawned. The child must also
/// already be spawned
pub fn init(gpa: Allocator) Client {
    return Client{
        .process_streamer = .init(gpa, std.io.getStdIn()),
        .out = std.io.getStdOut(),
    };
}

/// Create a client that is only allowed to send, recieving anything will
/// most likely segfault
pub fn initSender() Client {
    return Client{
        .process_streamer = undefined,
        .out = std.io.getStdOut(),
    };
}

pub fn deinit(self: *Client) void {
    self.process_streamer.deinit();
    self.* = undefined;
}

pub fn serveMessage(
    client: *Client,
    header: Message.Header,
    bufs: []const []const u8,
) File.WriteError!void {
    try nodeUtils.serveMessage(
        client.out,
        header,
        bufs,
    );
}

pub fn serveStringMessage(
    client: *Client,
    tag: Message.Tag,
    string: []const u8,
) !void {
    const header: Message.Header = .{
        .tag = tag,
        .bytes_len = @intCast(string.len),
    };
    try client.serveMessage(header, &.{
        string,
    });
}

pub fn serveTestStart(client: *Client, idx: usize) !void {
    const header = Message.Header{
        .tag = .testStart,
        .bytes_len = @sizeOf(usize),
    };

    try client.serveMessage(header, &.{
        std.mem.asBytes(&idx),
    });
}

pub fn serveTestSuccess(client: *Client, idx: usize) !void {
    const header = Message.Header{
        .tag = .testSuccess,
        .bytes_len = @sizeOf(usize),
    };

    try client.serveMessage(header, &.{
        std.mem.asBytes(&idx),
    });
}

pub fn serveTestFailure(client: *Client, idx: usize) !void {
    const header = Message.Header{
        .tag = .testFailure,
        .bytes_len = @sizeOf(usize),
    };

    try client.serveMessage(header, &.{
        std.mem.asBytes(&idx),
    });
}

pub fn serveTestSkipped(client: *Client, idx: usize) !void {
    const header = Message.Header{
        .tag = .testSkipped,
        .bytes_len = @sizeOf(usize),
    };

    try client.serveMessage(header, &.{
        std.mem.asBytes(&idx),
    });
}

pub fn serveParameterizedStart(client: *Client, args_str: []const u8) !void {
    const header = Message.Header{
        .tag = .parameterizedStart,
        .bytes_len = @intCast(args_str.len),
    };

    try client.serveMessage(header, &.{
        args_str,
    });
}

pub fn serveParameterizedComplete(client: *Client) !void {
    const header = Message.Header{
        .tag = .parameterizedComplete,
        .bytes_len = 0,
    };

    try client.serveMessage(header, &.{});
}

pub fn serveParameterizedSkipped(client: *Client) !void {
    const header = Message.Header{
        .tag = .parameterizedSkipped,
        .bytes_len = 0,
    };

    try client.serveMessage(header, &.{});
}

pub fn serveParameterizedError(client: *Client, error_name: []const u8) !void {
    const len: usize = @sizeOf(Message.ParameterizedError) + error_name.len;

    const header = Message.Header{
        .tag = .parameterizedError,
        .bytes_len = @intCast(len),
    };

    const message_info = Message.ParameterizedError{
        .error_name_len = @intCast(error_name.len),
    };

    try client.serveMessage(header, &.{
        &std.mem.toBytes(message_info),
        error_name,
    });
}

pub const ReceiveError = error{
    Unexpected,
    OutOfMemory,
    InputOutput,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    WouldBlock,
    ConnectionResetByPeer,
    IsDir,
    ConnectionTimedOut,
    NotOpenForReading,
    SocketNotConnected,
    Canceled,
    StreamClosed,
    IncompleteMessage,
    NetworkSubsystemFailed,
};

pub fn receiveMessage(self: *Client, alloc: Allocator) ReceiveError!MessageStatus {
    return try nodeUtils.receiveMessage(
        alloc,
        &self.process_streamer,
        &self.process_streamer.stdin_content,
        &self.process_streamer.delim_checked_ptr,
    );
}

const assert = std.debug.assert;

const Client = @This();

const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Child = std.process.Child;
const Poller = IPC.Poller(.client);
const Message = IPC.Message;
const MessageStatus = nodeUtils.MessageStatus;

const std = @import("std");
const nodeUtils = @import("nodeUtils.zig");
const IPC = @import("root.zig");
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const need_bswap = native_endian != .little;
