pub fn Poller(comptime poller_type: enum { client, server }) type {
    const PollerEnum = switch (poller_type) {
        .server => enum { stdout, stderr },
        .client => enum { stdin },
    };

    // This should be 0 so that the process so that the process doesn't try to wait
    // for data that clearly isn't there. For some reason it will either instantly
    // get data or hang for the entire duration
    const timeout_ns = 0;

    return struct {
        stdout_content: if (poller_type == .server) std.ArrayList(u8) else void,
        stderr_content: if (poller_type == .server) std.ArrayList(u8) else void,
        stdin_content: if (poller_type == .client) std.ArrayList(u8) else void,
        delim_checked_ptr: usize,
        poller: std.io.Poller(PollerEnum),

        pub const Error = error{
            StreamClosed,
        } || Allocator.Error || Errors(std.io.Poller(PollerEnum).pollTimeout);

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

        pub const init = switch (poller_type) {
            .server => initServer,
            .client => initClient,
        };

        fn initServer(alloc: Allocator, stdout: File, stderr: File) @This() {
            comptime assert(poller_type == .server);

            const poller = std.io.poll(alloc, PollerEnum, .{
                .stdout = stdout,
                .stderr = stderr,
            });

            return .{
                .stdout_content = .init(alloc),
                .stderr_content = .init(alloc),
                .stdin_content = undefined,
                .delim_checked_ptr = 0,
                .poller = poller,
            };
        }

        fn initClient(alloc: Allocator, stdin: File) @This() {
            comptime assert(poller_type == .client);

            const poller = std.io.poll(alloc, PollerEnum, .{
                .stdin = stdin,
            });

            return .{
                .stdin_content = .init(alloc),
                .stdout_content = undefined,
                .stderr_content = undefined,
                .delim_checked_ptr = 0,
                .poller = poller,
            };
        }

        pub fn deinit(self: *@This()) void {
            switch (poller_type) {
                .server => {
                    self.stdout_content.deinit();
                    self.stderr_content.deinit();
                },
                .client => self.stdin_content.deinit(),
            }

            self.poller.deinit();
            self.* = undefined;
        }

        pub fn read(self: *@This()) Error!ReadStatus {
            const should_keep_polling = try self.poller.pollTimeout(timeout_ns);

            var total_len_read: usize = 0;
            inline for (comptime std.meta.tags(PollerEnum)) |file| {
                const fifo = self.poller.fifo(file);
                const len = fifo.readableLength();

                if (len != 0) {
                    total_len_read += len;

                    const slice = fifo.readableSlice(0);

                    var array_list = switch (poller_type) {
                        .server => switch (file) {
                            .stdout => &self.stdout_content,
                            .stderr => &self.stderr_content,
                        },
                        .client => &self.stdin_content,
                    };

                    try array_list.appendSlice(slice);

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
        pub fn getRemoveLogs(self: *@This(), max_width: u16, alloc: Allocator) ![]const u8 {
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

            return try logs.toOwnedSlice();
        }

        // zig fmt: off
        const breakable_chars = [_]struct { char: u8, skip: bool, force_break: bool }{
            .{ .char = ' ' , .skip = true , .force_break = false },
            .{ .char = '-' , .skip = false, .force_break = false },
            .{ .char = '"' , .skip = false, .force_break = false },
            .{ .char = '/' , .skip = false, .force_break = false },
            .{ .char = '\'', .skip = false, .force_break = false },
            .{ .char = '\\', .skip = false, .force_break = false },
            .{ .char = '\t', .skip = true , .force_break = false },
            .{ .char = '\n', .skip = true , .force_break = true  },
        };
        // zig fmt: on

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

                // Trim because we might have multiple newlines in a row :(
                const trimmed_sub_slice = std.mem.trim(u8, sub_slice, "\n");

                try std.fmt.format(
                    writer,
                    "{s}{s}",
                    .{ prefix, trimmed_sub_slice },
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
        pub fn readUntilDelimeter(self: *@This(), comptime delimeter: []const u8) Error!DelimeterStatus {
            comptime assert(delimeter.len > 0);

            const array_list = switch (poller_type) {
                .server => &self.stdout_content,
                .client => &self.stdin_content,
            };

            while (true) {
                if (self.delim_checked_ptr >= array_list.items.len -| delimeter.len) {
                    switch (try self.read()) {
                        .readLen => continue,
                        .timedOut => return .timedOut,
                        .streamClosed => return .streamClosed,
                    }
                }

                const unseen_slice = array_list.items[self.delim_checked_ptr..];

                if (std.mem.indexOf(u8, unseen_slice, delimeter)) |pos| {
                    self.delim_checked_ptr += pos + delimeter.len;
                    return .{ .delimeterFound = self.delim_checked_ptr };
                } else {
                    self.delim_checked_ptr += unseen_slice.len - delimeter.len + 1;
                }
            }
            unreachable;
        }
    };
}

pub fn Errors(comptime Fn: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(Fn)).@"fn".return_type.?).error_union.error_set;
}

const Child = std.process.Child;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

const assert = std.debug.assert;
const std = @import("std");
const time = std.time;
