// This should be 0 so that the process so that the process doesn't try to wait
// for data that clearly isn't there. For some reason it will either instantly
// get data or hang for the entire duration
//
// TODO: Remove this constant from here when the client/server merge happens and
// then make sure to yield the thread when we timed out, so that (presumably) the
// client server counterpart can do their thing
pub const timeout_ns = 0;

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

        const unseen_slice = to_check.items[checked_ptr.*..];

        if (std.mem.indexOf(u8, unseen_slice, delimeter)) |pos| {
            checked_ptr.* += pos + delimeter.len;
            return .{ .delimeterFound = checked_ptr.* };
        } else {
            checked_ptr.* += unseen_slice.len - delimeter.len + 1;
        }
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
