stdout_content: std.ArrayList(u8),
stderr_content: std.ArrayList(u8),
// FIXME: Either do something with the metadata or remove it
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

/// Gets logs aggregated thus far, and clears stdout and stderr content. Will end
/// with a newline unless if stdout/stderr content is empty.
///
/// This may ONLY be done when the client is not actively sending messages,
/// otherwise those might get discarded.
pub fn getRemoveLogs(self: *ServerStreamer, max_width: u16, alloc: Allocator) ![]const u8 {
    var logs = std.ArrayList(u8).init(alloc);
    const writer = logs.writer().any();

    const stdout_prefix = "stdout | ";
    const stderr_prefix = "stderr | ";

    try writeLines(
        writer,
        @max(max_width, stdout_prefix.len + 1),
        stdout_prefix,
        self.stdout_content.items,
    );

    try writeLines(
        writer,
        @max(max_width, stderr_prefix.len + 1),
        stderr_prefix,
        self.stderr_content.items,
    );

    self.delim_checked_ptr = 0;
    self.stdout_content.clearRetainingCapacity();
    self.stderr_content.clearRetainingCapacity();
    self.output_metadata.clearRetainingCapacity();

    return try logs.toOwnedSlice();
}

const breakable_chars = [_]struct { char: u8, skip: bool, force_break: bool }{
    // zig fmt: off
    .{ .char = ' ' , .skip = true , .force_break = false },
    .{ .char = '-' , .skip = false, .force_break = false },
    .{ .char = '"' , .skip = false, .force_break = false },
    .{ .char = '/' , .skip = false, .force_break = false },
    .{ .char = '\'', .skip = false, .force_break = false },
    .{ .char = '\\', .skip = false, .force_break = false },
    .{ .char = '\t', .skip = true , .force_break = false },
    .{ .char = '\n', .skip = true , .force_break = true  },
    // zig fmt: on
};

/// `max_width` must be greater than `prefix.len`
fn writeLines(writer: anytype, max_width: u16, prefix: []const u8, slice: []const u8) !void {
    assert(max_width > prefix.len);

    const max_slice_width: usize = max_width - prefix.len;

    var written_idx: usize = 0;
    var last_breakable = struct {
        skip: bool = false,
        idx: usize = 0,
    }{};

    for (slice, 0..) |char, idx| {
        // Is this character breakable?
        loop: inline for (breakable_chars) |b| {
            if (char == b.char) {
                last_breakable = .{
                    .skip = b.skip,
                    .idx = idx,
                };
                break :loop;
            }
        }

        // Should we break here?
        loop: inline for (breakable_chars) |b| {
            if (b.force_break and char == b.char) 
                break :loop;
        } else {
            if (idx - written_idx < max_slice_width) continue;
        }

        // What slice are we printing
        const sub_slice = if (last_breakable.idx > written_idx) blk: {
            defer written_idx = last_breakable.idx + @intFromBool(last_breakable.skip);
            break :blk slice[written_idx..last_breakable.idx];
        } else blk: {
            defer written_idx = idx;
            break :blk slice[written_idx..idx];
        };

        if (sub_slice.len == 0) continue;

        // Trim because we might have multiple newlines in a row :(
        const trimmed_sub_slice = std.mem.trim(u8, sub_slice, "\n");

        try std.fmt.format(
            writer,
            "{s}{s}\n",
            .{ prefix, trimmed_sub_slice },
        );
    } else {
        const sub_slice = slice[written_idx..];
        if (sub_slice.len == 0) return;

        try std.fmt.format(
            writer,
            "{s}{s}",
            .{ prefix, sub_slice },
        );
    }
}

test "writeLines wrapping string" {
    var buf: [100]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const input = "123456789\n";
    const prefix = "pre | ";
    const max_width = prefix.len + 4;
    const expected =
        \\pre | 1234
        \\pre | 5678
        \\pre | 9
        \\
    ;

    try writeLines(writer, max_width, prefix, input);

    const out = fbs.getWritten();

    try std.testing.expectEqualStrings(expected, out);
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
