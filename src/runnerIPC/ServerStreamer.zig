stdout_content: std.ArrayList(u8),
stderr_content: std.ArrayList(u8),
output_metadata: std.ArrayList(SliceMetadata),
stdout_checked_ptr: usize,
poller: std.io.Poller(PollerEnum),

pub const timeout_ns = time.ns_per_ms * 5;

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

pub const ReadStatus = union(enum) {
    StreamClosed: void,
    TimedOut: void,
    ReadLen: usize,
    DelimeterEnd: usize,
};

pub fn init(alloc: Allocator, child: Child) ProcesStreamer {
    assert(child.stdout != null);
    assert(child.stderr != null);

    const poller = std.io.poll(alloc, PollerEnum, .{
        .stdout = child.stdout.?,
        .stderr = child.stderr.?,
    });

    return ProcesStreamer{
        .stdout_content = std.ArrayList(u8).init(alloc),
        .stderr_content = std.ArrayList(u8).init(alloc),
        .output_metadata = std.ArrayList(SliceMetadata).init(alloc),
        .stdout_checked_ptr = 0,
        .poller = poller,
    };
}

pub fn deinit(self: *ProcesStreamer) void {
    self.stdout_content.deinit();
    self.stderr_content.deinit();
    self.output_metadata.deinit();
    self.poller.deinit();
    self.* = undefined;
}

pub fn read(self: *ProcesStreamer) Error!ReadStatus {
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
pub fn readUntilDelimeter(self: *ProcesStreamer, comptime delimeter: []const u8) Error!ReadStatus {
    comptime assert(delimeter.len > 0);

    var total_len_read: usize = 0;
    while (true) {
        switch (try self.read()) {
            .ReadLen => |len| total_len_read += len,
            .TimedOut => if (total_len_read == 0) {
                return .TimedOut;
            } else {
                return .{ .ReadLen = total_len_read };
            },
            else => |status| return status,
        }

        const unseen_slice = self.stdout_content.items[self.stdout_checked_ptr..];

        if (unseen_slice.len < delimeter.len) continue;

        inner: for (0..(unseen_slice.len - delimeter.len + 1)) |start_ptr| {
            const check_slice = unseen_slice[start_ptr..(start_ptr + delimeter.len)];
            assert(check_slice.len == delimeter.len);

            // TODO: Be a little bit smarter, and move up stdout_checked_ptr while
            // looping
            for (check_slice, delimeter) |check_item, delim_item| {
                if (check_item != delim_item) continue :inner;
            }

            self.stdout_checked_ptr += start_ptr + delimeter.len;
            return .{ .DelimeterEnd = self.stdout_checked_ptr };
        }

        self.stdout_checked_ptr += unseen_slice.len - delimeter.len + 1;
    }
    unreachable;
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).Fn.return_type.?).ErrorUnion.error_set;
}

const ProcesStreamer = @This();

const Instant = time.Instant;
const Child = std.process.Child;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
