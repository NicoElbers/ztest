stdin_content: std.ArrayList(u8),
delim_checked_ptr: usize,
poller: std.io.Poller(PollerEnum),

pub const timeout_ns = time.ns_per_ms * 5;

const PollerEnum = enum { stdin };

pub const Error = error{
    StreamClosed,
} || Allocator.Error || Errors(std.io.Poller(PollerEnum).pollTimeout);

pub const ReadStatus = union(enum) {
    StreamClosed: void,
    TimedOut: void,
    ReadLen: usize,
    DelimeterEnd: usize,
};

pub fn init(alloc: Allocator) ClientStreamer {
    const poller = std.io.poll(alloc, PollerEnum, .{
        .stdin = std.io.getStdIn(),
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
pub fn readUntilDelimeter(self: *ClientStreamer, comptime delimeter: []const u8) Error!ReadStatus {
    comptime assert(delimeter.len > 0);

    var total_len_read: usize = 0;
    while (true) {
        if (self.delim_checked_ptr >= self.stdin_content.items.len -| delimeter.len) {
            switch (try self.read()) {
                .ReadLen => |len| total_len_read += len,
                .TimedOut => if (total_len_read == 0) {
                    return .TimedOut;
                } else {
                    return .{ .ReadLen = total_len_read };
                },
                else => |status| return status,
            }
        }

        const unseen_slice = self.stdin_content.items[self.delim_checked_ptr..];

        print("Found unseen: {s}", .{unseen_slice});

        if (unseen_slice.len < delimeter.len) continue;

        inner: for (0..(unseen_slice.len - delimeter.len + 1)) |start_ptr| {
            const check_slice = unseen_slice[start_ptr..(start_ptr + delimeter.len)];
            assert(check_slice.len == delimeter.len);

            // TODO: Be a little bit smarter, and move up delim_checked_ptr while
            // looping
            for (check_slice, delimeter) |check_item, delim_item| {
                if (check_item != delim_item) continue :inner;
            }

            self.delim_checked_ptr += start_ptr + delimeter.len;
            return .{ .DelimeterEnd = self.delim_checked_ptr };
        }

        self.delim_checked_ptr += unseen_slice.len - delimeter.len + 1;
    }
    unreachable;
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).Fn.return_type.?).ErrorUnion.error_set;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

const ClientStreamer = @This();

const Allocator = std.mem.Allocator;
const File = std.fs.File;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
