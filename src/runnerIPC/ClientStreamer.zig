stdin_content: std.ArrayList(u8),
delim_checked_ptr: usize,
poller: std.io.Poller(PollerEnum),

const PollerEnum = enum { stdin };

pub const Error = error{
    StreamClosed,
} || Allocator.Error || Errors(std.io.Poller(PollerEnum).pollTimeout);

pub fn init(alloc: Allocator, stdin: File) ClientStreamer {
    const poller = std.io.poll(alloc, PollerEnum, .{
        .stdin = stdin,
    });

    return ClientStreamer{
        .stdin_content = std.ArrayList(u8).init(alloc),
        .delim_checked_ptr = 0,
        .poller = poller,
    };
}

pub fn deinit(self: *ClientStreamer) void {
    self.stdin_content.deinit();
    self.poller.deinit();
    self.* = undefined;
}

pub fn read(self: *ClientStreamer) Error!ReadStatus {
    const should_keep_polling = try self.poller.pollTimeout(timeout_ns);

    var total_len_read: usize = 0;
    inline for (comptime std.meta.tags(PollerEnum)) |file| {
        const fifo = self.poller.fifo(file);
        const len = fifo.readableLength();

        if (len != 0) {
            total_len_read += len;

            const slice = fifo.readableSlice(0);

            var array_list = switch (file) {
                .stdin => &self.stdin_content,
            };

            try array_list.appendSlice(slice);

            fifo.discard(len);
        }
    }

    if (total_len_read == 0 and !should_keep_polling) return .StreamClosed;
    if (total_len_read == 0) return .TimedOut;

    return .{ .ReadLen = total_len_read };
}

/// Polls until a delimeter is found, the last poll returned nothing or the stream has ended.
/// If a delimeter is found, returns the index after the delimeter
pub inline fn readUntilDelimeter(self: *ClientStreamer, comptime delimeter: []const u8) Error!ReadStatus {
    return try streamerUtils.readUntilDelimeter(
        self,
        delimeter,
        &self.stdin_content,
        &self.delim_checked_ptr,
    );
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).@"fn".return_type.?).error_union.error_set;
}

fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

const ClientStreamer = @This();

const ReadStatus = streamerUtils.ReadStatus;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const timeout_ns = streamerUtils.timeout_ns;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
const streamerUtils = @import("streamerUtils.zig");
