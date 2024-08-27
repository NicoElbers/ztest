stdout_content: std.ArrayList(u8),
stderr_content: std.ArrayList(u8),
output_metadata: std.ArrayList(SliceMetadata),
delim_checked_ptr: usize,
poller: std.io.Poller(PollerEnum),

const PollerEnum = enum { stdout, stderr };

pub const Error = error{
    StreamClosed,
} || Allocator.Error || Errors(Instant.now) || Errors(std.io.Poller(PollerEnum).pollTimeout);

pub const SliceMetadata = struct {
    tag: PollerEnum,
    timestamp: Instant,
    start_idx: usize,
    len: usize,
};

pub fn init(alloc: Allocator, stdout: File, stderr: File) ServerStreamer {
    const poller = std.io.poll(alloc, PollerEnum, .{
        .stdout = stdout,
        .stderr = stderr,
    });

    return ServerStreamer{
        .stdout_content = std.ArrayList(u8).init(alloc),
        .stderr_content = std.ArrayList(u8).init(alloc),
        .output_metadata = std.ArrayList(SliceMetadata).init(alloc),
        .delim_checked_ptr = 0,
        .poller = poller,
    };
}

pub fn deinit(self: *ServerStreamer) void {
    self.stdout_content.deinit();
    self.stderr_content.deinit();
    self.output_metadata.deinit();
    self.poller.deinit();
    self.* = undefined;
}

pub fn read(self: *ServerStreamer) Error!ReadStatus {
    const should_keep_polling = try self.poller.pollTimeout(timeout_ns);

    var total_len_read: usize = 0;
    inline for (comptime std.meta.tags(PollerEnum)) |file| {
        const fifo = self.poller.fifo(file);
        const len = fifo.readableLength();

        if (len != 0) {
            total_len_read += len;

            const timestamp = try Instant.now();
            const slice = fifo.readableSlice(0);

            var array_list = switch (file) {
                .stdout => &self.stdout_content,
                .stderr => &self.stderr_content,
            };

            const slice_start = array_list.items.len;
            try array_list.appendSlice(slice);

            try self.output_metadata.append(.{
                .tag = file,
                .timestamp = timestamp,
                .start_idx = slice_start,
                .len = slice.len,
            });

            fifo.discard(len);
        }
    }

    if (total_len_read == 0 and !should_keep_polling) return .StreamClosed;
    if (total_len_read == 0) return .TimedOut;

    return .{ .ReadLen = total_len_read };
}

/// Polls until a delimeter is found, the last poll returned nothing or the stream has ended.
/// If a delimeter is found, returns the index after the delimeter
pub inline fn readUntilDelimeter(self: *ServerStreamer, comptime delimeter: []const u8) Error!ReadStatus {
    return try streamerUtils.readUntilDelimeter(
        self,
        delimeter,
        &self.stdout_content,
        &self.delim_checked_ptr,
    );
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).Fn.return_type.?).ErrorUnion.error_set;
}

const ServerStreamer = @This();

const Instant = time.Instant;
const Child = std.process.Child;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const ReadStatus = streamerUtils.ReadStatus;
const timeout_ns = streamerUtils.timeout_ns;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
const streamerUtils = @import("streamerUtils.zig");
