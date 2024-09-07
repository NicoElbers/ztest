pub const timeout_ns = time.ns_per_ms * 5;

pub const ReadStatus = union(enum) {
    streamClosed: void,
    timedOut: void,
    readLen: usize,
};

pub const DelimeterStatus = union(enum) {
    streamClosed: void,
    timedOut: void,
    delimeterFound: usize,
};

/// Shared delim reader for both the client and the server.
/// streamer must be a function called read, that updates the to_check array.
/// checked_ptr is the location inside the to_check array which has already been
/// checked for delimeters.
pub fn readUntilDelimeter(
    streamer: anytype,
    comptime delimeter: []const u8,
    to_check: *std.ArrayList(u8),
    checked_ptr: *usize,
) !DelimeterStatus {
    comptime assert(delimeter.len > 0);

    while (true) {
        if (checked_ptr.* >= to_check.items.len -| delimeter.len) {
            switch (try streamer.read()) {
                .readLen => continue,
                .timedOut => return .timedOut,
                .streamClosed => return .streamClosed,
            }
        }

        const unseen_slice = to_check.items[streamer.delim_checked_ptr..];

        if (unseen_slice.len < delimeter.len) continue;

        inner: for (0..(unseen_slice.len - delimeter.len + 1)) |start_ptr| {
            const check_slice = unseen_slice[start_ptr..(start_ptr + delimeter.len)];
            assert(check_slice.len == delimeter.len);

            for (check_slice, delimeter) |check_item, delim_item| {
                if (check_item != delim_item) continue :inner;
            }

            checked_ptr.* += start_ptr + delimeter.len;
            return .{ .delimeterFound = checked_ptr.* };
        }

        checked_ptr.* += unseen_slice.len - delimeter.len + 1;
    }
    unreachable;
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).@"fn".return_type.?).error_union.error_set;
}

const Allocator = std.mem.Allocator;
const File = std.fs.File;
const Poller = std.io.Poller;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
