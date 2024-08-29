pub const MessageStatus = union(enum) {
    Message: Message,
    StreamClosed: void,
    TimedOut: void,
};

pub fn receiveMessage(
    alloc: Allocator,
    streamer_ptr: anytype,
    input_list_ptr: anytype,
) (error{IncompleteMessage} ||
    Allocator.Error ||
    Errors(@TypeOf(streamer_ptr), "readUntilDelimeter") ||
    Errors(@TypeOf(streamer_ptr), "read"))!MessageStatus {
    const Header = Message.Header;

    const pos = switch (try streamer_ptr.readUntilDelimeter(&IPC.special_message_start_key)) {
        .DelimeterEnd => |pos| pos,
        .StreamClosed => return .StreamClosed,
        else => return .TimedOut,
    };

    var is_last_round = false;
    const header: Header = blk: while (true) {
        switch (try streamer_ptr.read()) {
            .StreamClosed => {
                if (is_last_round) return .StreamClosed;
                is_last_round = true;
            },
            else => {},
        }

        const message_slice = input_list_ptr.items[pos..];

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
            .StreamClosed => {
                if (is_last_round) return .StreamClosed;
                is_last_round = true;
            },
            else => {},
        }

        const after_slice = input_list_ptr.items[bytes_pos..];

        if (after_slice.len < header.bytes_len) continue;

        const bytes = try alloc.alloc(u8, header.bytes_len);
        @memcpy(bytes, after_slice[0..header.bytes_len]);

        return .{ .Message = Message{ .header = header, .bytes = bytes } };
    }

    return error.IncompleteMessage;
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

    if (fn_info.return_type == null) @compileError("return type null :(");

    return @typeInfo(fn_info.return_type.?).error_union.error_set;
}

const std = @import("std");
const IPC = @import("root.zig");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;
const Message = IPC.Message;
const ServerStreamer = IPC.ServerStreamer;
