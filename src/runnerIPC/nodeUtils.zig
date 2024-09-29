pub const MessageStatus = union(enum) {
    streamClosed: void,
    timedOut: void,
    message: Message,
};

pub fn serveMessage(
    out: File,
    header: Message.Header,
    bufs: []const []const u8,
) File.WriteError!void {
    assert(bufs.len < 9);
    var iovecs: [10]std.posix.iovec_const = undefined;
    const header_le = bswap(header);

    iovecs[0] = .{
        .base = &Message.ipc_start,
        .len = Message.ipc_start.len,
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

    try out.writevAll(iovecs[0 .. bufs.len + 2]);
}

pub fn receiveMessage(
    alloc: Allocator,
    streamer_ptr: anytype,
    input_list_ptr: anytype,
    checked_ptr: *usize,
) (error{IncompleteMessage} ||
    Allocator.Error || // Allocator.alloc has a generic return type
    Errors(@TypeOf(streamer_ptr), "readUntilDelimeter") ||
    Errors(@TypeOf(streamer_ptr), "read"))!MessageStatus {
    const Header = Message.Header;
    const input_list: *std.ArrayList(u8) = input_list_ptr;

    const pos = switch (try streamer_ptr.readUntilDelimeter(&Message.ipc_start)) {
        .delimeterFound => |pos| pos,
        .streamClosed => return .streamClosed,
        .timedOut => return .timedOut,
    };
    assert(pos >= Message.ipc_start.len);

    const ipc_msg_start = pos - Message.ipc_start.len;

    var is_last_round = false;
    const header: Header = blk: while (true) {
        switch (try streamer_ptr.read()) {
            .streamClosed => {
                if (is_last_round) return .streamClosed;
                is_last_round = true;
            },
            else => {},
        }

        const message_slice = input_list.items[pos..];

        if (message_slice.len < @sizeOf(Header)) continue;

        assert(@sizeOf(Header) == 8);
        // const info = @typeInfo(Header);

        const tag_int = std.mem.readInt(u32, message_slice[0..4], .little);
        const byte_len = std.mem.readInt(u32, message_slice[4..8], .little);

        break :blk Header{
            .tag = @enumFromInt(tag_int),
            .bytes_len = byte_len,
        };
    };

    is_last_round = false;

    const bytes_pos = pos + @sizeOf(Header);
    while (true) {
        switch (try streamer_ptr.read()) {
            .streamClosed => {
                if (is_last_round) return .streamClosed;
                is_last_round = true;
            },
            else => {},
        }

        const after_slice = input_list.items[bytes_pos..];

        if (after_slice.len < header.bytes_len) continue;

        const bytes = try alloc.alloc(u8, header.bytes_len);
        @memcpy(bytes, after_slice[0..header.bytes_len]);

        std.mem.copyForwards(
            u8,
            input_list.items[ipc_msg_start..],
            after_slice[header.bytes_len..],
        );
        checked_ptr.* = ipc_msg_start -| 1;

        input_list.shrinkRetainingCapacity(ipc_msg_start + after_slice.len - header.bytes_len);

        return .{ .message = Message{ .header = header, .bytes = bytes } };
    }

    return error.IncompleteMessage;
}

pub fn bswap(x: anytype) @TypeOf(x) {
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

pub inline fn Errors(comptime T: type, comptime Fn: []const u8) type {
    const info = @typeInfo(T);
    switch (info) {
        .pointer => |ptr| switch (ptr.size) {
            .One => return Errors(ptr.child, Fn),
            else => @compileError("Unsupported for " ++ @tagName(ptr.size) ++ " pointers"),
        },
        .@"struct" => return ErrorsFn(@field(T, Fn)),
        .@"fn" => @compileError("Use ErrorsFn instead"),
        else => @compileError("Unsupported type " ++ @typeName(T)),
    }
}

pub inline fn ErrorsFn(comptime Fn: anytype) type {
    const info = @typeInfo(@TypeOf(Fn));

    comptime assert(info == .@"fn");
    const fn_info = info.@"fn";

    if (fn_info.return_type == null) @compileError("Function return type is generic, cannot infer errors");

    return @typeInfo(fn_info.return_type.?).error_union.error_set;
}

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Message = IPC.Message;
const ServerStreamer = IPC.ServerStreamer;
const File = std.fs.File;

const std = @import("std");
const IPC = @import("root.zig");
const builtin = @import("builtin");
const native_endian = builtin.target.cpu.arch.endian();
const need_bswap = native_endian != .little;
