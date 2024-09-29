// TODO: Factor node_type and poller_type out into a type comming from probably
// root, so that I don't have to switch to go between them

pub fn Node(comptime node_type: enum { client, server }) type {
    const Poller = IPC.Poller(switch (node_type) {
        .server => .server,
        .client => .client,
    });

    return struct {
        process_streamer: Poller,
        out: File,

        pub const MessageStatus = union(enum) {
            streamClosed: void,
            timedOut: void,
            message: Message,
        };

        pub const ReceiveError = error{
            Unexpected,
            OutOfMemory,
            InputOutput,
            AccessDenied,
            BrokenPipe,
            SystemResources,
            OperationAborted,
            WouldBlock,
            ConnectionResetByPeer,
            IsDir,
            ConnectionTimedOut,
            NotOpenForReading,
            SocketNotConnected,
            Canceled,
            Unsupported,
            StreamClosed,
            IncompleteMessage,
            NetworkSubsystemFailed,
        };

        pub const init = switch (node_type) {
            .server => initServer,
            .client => initClient,
        };

        /// Child must have stdout and stderr behavior of Pipe, this ensures that the
        /// stdout and stderr are valid once the child is spawned. The child must also
        /// already be spawned
        fn initServer(alloc: Allocator, child: Child) @This() {
            assert(child.stdin != null);
            assert(child.stdout != null);
            assert(child.stderr != null);

            return .{
                .process_streamer = .init(
                    alloc,
                    child.stdout.?,
                    child.stderr.?,
                ),
                .out = child.stdin.?,
            };
        }

        fn initClient(alloc: Allocator) @This() {
            return .{
                .process_streamer = .init(alloc, std.io.getStdIn()),
                .out = std.io.getStdOut(),
            };
        }

        pub const initManual = switch (node_type) {
            .server => initServerManual,
            .client => initClientManual,
        };

        fn initServerManual(alloc: Allocator, send: File, recv: File, err: File) @This() {
            return .{
                .process_streamer = .init(alloc, recv, err),
                .out = send,
            };
        }

        fn initClientManual(alloc: Allocator, send: File, recv: File) @This() {
            return .{
                .process_streamer = .init(alloc, recv),
                .out = send,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.process_streamer.deinit();
            self.* = undefined;
        }

        pub fn serveMessage(
            self: *@This(),
            header: Message.Header,
            bufs: []const []const u8,
        ) File.WriteError!void {
            assert(bufs.len < 9);
            var iovecs: [10]std.posix.iovec_const = undefined;
            const header_le = bswap(header);

            iovecs[0] = .{
                .base = &Message.ipc_start,
                .len = Message.ipc_start.len,
            };
            iovecs[1] = .{
                .base = @as([*]const u8, @ptrCast(&header_le)),
                .len = @sizeOf(Message.Header),
            };

            for (bufs, iovecs[2 .. bufs.len + 2]) |buf, *iovec| {
                iovec.* = .{
                    .base = buf.ptr,
                    .len = buf.len,
                };
            }

            try self.out.writevAll(iovecs[0 .. bufs.len + 2]);
        }

        pub fn serveExit(server: *@This()) !void {
            const header: Message.Header = .{
                .tag = .exit,
                .bytes_len = 0,
            };

            try server.serveMessage(header, &.{});
        }

        pub fn serveRunTest(server: *@This(), idx: usize) !void {
            const header: Message.Header = .{
                .tag = .runTest,
                .bytes_len = @sizeOf(usize),
            };

            try server.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveStringMessage(
            client: *@This(),
            tag: Message.Tag,
            string: []const u8,
        ) !void {
            const header: Message.Header = .{
                .tag = tag,
                .bytes_len = @intCast(string.len),
            };
            try client.serveMessage(header, &.{
                string,
            });
        }

        pub fn serveTestStart(client: *@This(), idx: usize) !void {
            const header = Message.Header{
                .tag = .testStart,
                .bytes_len = @sizeOf(usize),
            };

            try client.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveTestSuccess(client: *@This(), idx: usize) !void {
            const header = Message.Header{
                .tag = .testSuccess,
                .bytes_len = @sizeOf(usize),
            };

            try client.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveTestFailure(client: *@This(), idx: usize) !void {
            const header = Message.Header{
                .tag = .testFailure,
                .bytes_len = @sizeOf(usize),
            };

            try client.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveTestSkipped(client: *@This(), idx: usize) !void {
            const header = Message.Header{
                .tag = .testSkipped,
                .bytes_len = @sizeOf(usize),
            };

            try client.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveParameterizedStart(client: *@This(), args_str: []const u8) !void {
            const header = Message.Header{
                .tag = .parameterizedStart,
                .bytes_len = @intCast(args_str.len),
            };

            try client.serveMessage(header, &.{
                args_str,
            });
        }

        pub fn serveParameterizedComplete(client: *@This()) !void {
            const header = Message.Header{
                .tag = .parameterizedComplete,
                .bytes_len = 0,
            };

            try client.serveMessage(header, &.{});
        }

        pub fn serveParameterizedSkipped(client: *@This()) !void {
            const header = Message.Header{
                .tag = .parameterizedSkipped,
                .bytes_len = 0,
            };

            try client.serveMessage(header, &.{});
        }

        pub fn serveParameterizedError(client: *@This(), error_name: []const u8) !void {
            const len: usize = @sizeOf(Message.ParameterizedError) + error_name.len;

            const header = Message.Header{
                .tag = .parameterizedError,
                .bytes_len = @intCast(len),
            };

            const message_info = Message.ParameterizedError{
                .error_name_len = @intCast(error_name.len),
            };

            try client.serveMessage(header, &.{
                &std.mem.toBytes(message_info),
                error_name,
            });
        }

        pub fn receiveMessage(self: *@This(), alloc: Allocator) ReceiveError!MessageStatus {
            const array_list = switch (node_type) {
                .server => &self.process_streamer.stdout_content,
                .client => &self.process_streamer.stdin_content,
            };

            const Header = Message.Header;

            const pos = switch (try self.process_streamer.readUntilDelimeter(&Message.ipc_start)) {
                .delimeterFound => |pos| pos,
                .streamClosed => return .streamClosed,
                .timedOut => return .timedOut,
            };
            assert(pos >= Message.ipc_start.len);

            const ipc_msg_start = pos - Message.ipc_start.len;

            var is_last_round = false;
            const header: Header = blk: while (true) {
                switch (try self.process_streamer.read()) {
                    .streamClosed => {
                        if (is_last_round) return .streamClosed;
                        is_last_round = true;
                    },
                    else => {},
                }

                const message_slice = array_list.items[pos..];

                if (message_slice.len < @sizeOf(Header)) continue;

                assert(@sizeOf(Header) == 8);

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
                switch (try self.process_streamer.read()) {
                    .streamClosed => {
                        if (is_last_round) return .streamClosed;
                        is_last_round = true;
                    },
                    else => {},
                }

                const after_slice = array_list.items[bytes_pos..];

                if (after_slice.len < header.bytes_len) continue;

                const bytes = try alloc.alloc(u8, header.bytes_len);
                @memcpy(bytes, after_slice[0..header.bytes_len]);

                std.mem.copyForwards(
                    u8,
                    array_list.items[ipc_msg_start..],
                    after_slice[header.bytes_len..],
                );
                self.process_streamer.delim_checked_ptr = ipc_msg_start -| 1;

                array_list.shrinkRetainingCapacity(ipc_msg_start + after_slice.len - header.bytes_len);

                return .{ .message = Message{ .header = header, .bytes = bytes } };
            }

            return error.IncompleteMessage;
        }
    };
}

pub fn bswap(x: anytype) @TypeOf(x) {
    if (@import("builtin").target.cpu.arch.endian() == .little) return x;

    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .@"enum" => return @as(T, @enumFromInt(@byteSwap(@intFromEnum(x)))),
        .int => return @byteSwap(x),
        .@"struct" => |info| switch (info.layout) {
            .@"extern" => {
                var result: T = undefined;
                inline for (info.fields) |field| {
                    @field(result, field.name) = bswap(@field(x, field.name));
                }
                return result;
            },
            .@"packed" => {
                const I = info.backing_integer.?;
                return @as(T, @bitCast(@byteSwap(@as(I, @bitCast(x)))));
            },
            .auto => @compileError("auto layout struct"),
        },
        else => @compileError("bswap on type " ++ @typeName(T)),
    }
}

const assert = std.debug.assert;

const File = std.fs.File;
const Allocator = std.mem.Allocator;
const Child = std.process.Child;
const Message = IPC.Message;

const std = @import("std");
const IPC = @import("root.zig");
