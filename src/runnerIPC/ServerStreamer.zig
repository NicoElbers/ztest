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
        .stdout_content = .init(alloc),
        .stderr_content = .init(alloc),
        .output_metadata = .init(alloc),
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

    if (total_len_read == 0 and !should_keep_polling) return .streamClosed;
    if (total_len_read == 0) return .timedOut;

    return .{ .readLen = total_len_read };
}

// FIXME: either use metadata.timestamp or remove it from the struct
pub fn getLogs(self: *const ServerStreamer, alloc: Allocator) ![]const u8 {
    const max_line_width = 80;

    var logs = std.ArrayList(u8).init(alloc);
    const writer = logs.writer().any();

    for (self.output_metadata.items) |metadata| {
        const full_slice = switch (metadata.tag) {
            .stdout => self.stdout_content.items,
            .stderr => self.stderr_content.items,
        };

        const slice = full_slice[metadata.start_idx..(metadata.start_idx + metadata.len)];

        var last_idx: usize = 0;
        var last_space_idx: usize = 0;
        for (slice, 0..) |char, idx| {
            if (char == ' ') last_space_idx = idx;

            const diff = idx - last_idx;

            if (char != '\n' and diff < max_line_width) continue;

            const end_idx = if (last_space_idx > last_idx) last_space_idx else idx;

            const sub_slice = slice[last_idx..end_idx];

            if (sub_slice.len == 0) continue;
            try std.fmt.format(
                writer,
                "{s} | {s}\n",
                .{ @tagName(metadata.tag), sub_slice },
            );

            last_idx = end_idx + 1;
        }
        const sub_slice = slice[last_idx..];

        if (sub_slice.len == 0) continue;
        try std.fmt.format(
            writer,
            "{s} | {s}\n",
            .{ @tagName(metadata.tag), sub_slice },
        );
    }

    return logs.toOwnedSlice();
}

test "longs stderr" {
    std.debug.print("a" ** 100, .{});
}

/// Polls until a delimeter is found, the last poll returned nothing or the stream has ended.
/// If a delimeter is found, returns the index after the delimeter
pub inline fn readUntilDelimeter(self: *ServerStreamer, comptime delimeter: []const u8) Error!DelimeterStatus {
    return try streamerUtils.readUntilDelimeter(
        self,
        delimeter,
        &self.stdout_content,
        &self.delim_checked_ptr,
    );
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).@"fn".return_type.?).error_union.error_set;
}

const ServerStreamer = @This();

const Instant = time.Instant;
const Child = std.process.Child;
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const ReadStatus = streamerUtils.ReadStatus;
const DelimeterStatus = streamerUtils.DelimeterStatus;
const timeout_ns = streamerUtils.timeout_ns;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
const streamerUtils = @import("streamerUtils.zig");
