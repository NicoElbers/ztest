process_streamer: ServerStreamer,
out: File,

/// Child must have stdout and stderr behavior of Pipe, this ensures that the
/// stdout and stderr are valid once the child is spawned. The child must also
/// already be spawned
pub fn init(gpa: Allocator, child: Child) Server {
    assert(child.stdin != null);
    assert(child.stdout != null);
    assert(child.stderr != null);

    return Server{
        .process_streamer = ServerStreamer.init(
            gpa,
            child.stdout.?,
            child.stderr.?,
        ),
        .out = child.stdin.?,
    };
}

pub fn deinit(self: *Server) void {
    self.process_streamer.deinit();
    self.* = undefined;
}

pub fn serveMessage(
    server: *Server,
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

pub fn serveExit(server: *Server) !void {
    const header: Message.Header = .{
        .tag = .exit,
        .bytes_len = 0,
    };

    try server.serveMessage(header, &.{});
}

pub fn serveStringMessage(
    server: *Server,
    tag: Message.Tag,
    string: []const u8,
) !void {
    const header: Message.Header = .{
        .tag = tag,
        .bytes_len = @as(u32, @intCast(string.len)),
    };
    try server.serveMessage(
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
    Unsupported,
    StreamClosed,
    IncompleteMessage,
    NetworkSubsystemFailed,
};

pub fn receiveMessage(self: *Server, alloc: Allocator) ReceiveError!MessageStatus {
    return try nodeUtils.receiveMessage(
        alloc,
        &self.process_streamer,
        &self.process_streamer.stdout_content,
    );
}

fn bswap(x: anytype) @TypeOf(x) {
    if (!need_bswap) return x;

    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .Enum => return @as(T, @enumFromInt(@byteSwap(@intFromEnum(x)))),
        .Int => return @byteSwap(x),
        .Struct => |info| switch (info.layout) {
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
const Server = @This();

const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Child = std.process.Child;
const ServerStreamer = @import("ServerStreamer.zig");
const Message = IPC.Message;
const MessageStatus = nodeUtils.MessageStatus;

const nodeUtils = @import("nodeUtils.zig");
const std = @import("std");
const IPC = @import("root.zig");
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const need_bswap = native_endian != .little;