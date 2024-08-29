process_streamer: ClientStreamer,
out: File,

/// Child must have stdout and stderr behavior of Pipe, this ensures that the
/// stdout and stderr are valid once the child is spawned. The child must also
/// already be spawned
pub fn init(gpa: Allocator) Client {
    return Client{
        .process_streamer = ClientStreamer.init(gpa, std.io.getStdIn()),
        .out = std.io.getStdOut(),
    };
}

pub fn deinit(self: *Client) void {
    self.process_streamer.deinit();
    self.* = undefined;
}

pub fn serveMessage(
    server: *Client,
    header: Message.Header,
    bufs: []const []const u8,
) !void {
    assert(bufs.len < 9);
    var iovecs: [10]std.posix.iovec_const = undefined;
    const header_le = bswap(header);

    iovecs[0] = .{
        .base = &IPC.special_message_start_key,
        .len = IPC.special_message_start_key.len,
    };
    iovecs[1] = .{
        .base = @as([*]const u8, @ptrCast(&header_le)),
        .len = @sizeOf(Message.Header),
    };

    for (bufs, iovecs[2 .. bufs.len + 2]) |buf, *iovec| {
        iovec.* = .{
            .base = buf.ptr,
            .len = buf.len,
        };
    }
    try server.out.writevAll(iovecs[0 .. bufs.len + 2]);
}

pub fn serveStringMessage(
    server: *Client,
    tag: Message.Tag,
    string: []const u8,
) !void {
    const header: Message.Header = .{
        .tag = tag,
        .bytes_len = @as(u32, @intCast(string.len)),
    };
    try serveMessage(
        server,
        header,
        &.{string},
    );
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
    );
}

fn bswap(x: anytype) @TypeOf(x) {
    if (!need_bswap) return x;

    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .@"enum" => return @as(T, @enumFromInt(@byteSwap(@intFromEnum(x)))),
        .int => return @byteSwap(x),
        .@"struct" => |info| switch (info.layout) {
            .@"extern" => {
                var result: T = undefined;
                inline for (info.fields) |field| {
                    @field(result, field.name) = bswap(@field(x, field.name));
                }
                return result;
            },
            .@"packed" => {
                const I = info.backing_integer.?;
                return @as(T, @bitCast(@byteSwap(@as(I, @bitCast(x)))));
            },
            .auto => @compileError("auto layout struct"),
        },
        else => @compileError("bswap on type " ++ @typeName(T)),
    }
}

const assert = std.debug.assert;

const Client = @This();

const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Child = std.process.Child;
const ClientStreamer = @import("ClientStreamer.zig");
const Message = IPC.Message;
const MessageStatus = nodeUtils.MessageStatus;

const std = @import("std");
const nodeUtils = @import("nodeUtils.zig");
const IPC = @import("root.zig");
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const need_bswap = native_endian != .little;
